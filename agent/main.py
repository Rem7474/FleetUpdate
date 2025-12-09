import os
import json
import asyncio
from typing import Any
import httpx
import yaml
from pydantic import BaseModel
from heartbeat import collect_apps_state, collect_os_update_status
from crypto_hmac import sign_bytes


class AgentSettings(BaseModel):
    id: str
    server_url: str
    poll_interval: int = 30
    psk: str


def load_config(path: str) -> tuple[AgentSettings, list[dict]]:
    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)
    a = data.get("agent", {})
    apps = data.get("apps", [])
    settings = AgentSettings(id=a["id"], server_url=a["server_url"], poll_interval=a.get("poll_interval", 30), psk=a["psk"])
    return settings, apps


async def send_heartbeat(client: httpx.AsyncClient, settings: AgentSettings, apps_cfg: list[dict]) -> None:
    payload: dict[str, Any] = {
        "agent_id": settings.id,
        "apps": collect_apps_state(apps_cfg),
        "logs": [],
    }
    # Agent software version (prefer env override, else module/package version)
    agent_version = os.environ.get("AGENT_VERSION") or "1.0.0"
    payload["agent_version"] = agent_version
    payload["os_update"] = collect_os_update_status()
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    sig = sign_bytes(body, settings.psk)
    headers = {"X-Agent-Id": settings.id, "X-Signature": sig, "Content-Type": "application/json"}
    url = settings.server_url.rstrip("/") + "/api/heartbeat"
    r = await client.post(url, content=body, headers=headers, timeout=20)
    r.raise_for_status()


async def main():
    cfg_path = os.environ.get("AGENT_CONFIG", os.path.join(os.path.dirname(__file__), "config.example.yaml"))
    settings, apps_cfg = load_config(cfg_path)
    async with httpx.AsyncClient() as client:
        while True:
            try:
                await send_heartbeat(client, settings, apps_cfg)
            except Exception as e:
                print(f"heartbeat error: {e}")
            # poll for command
            try:
                url = settings.server_url.rstrip("/") + f"/api/agents/{settings.id}/next-command"
                sig = sign_bytes(b"{}", settings.psk)
                r = await client.get(url, headers={"X-Agent-Id": settings.id, "X-Signature": sig}, timeout=20)
                r.raise_for_status()
                data = r.json()
                cmd = data.get("command")
                if cmd:
                    await execute_command(client, settings, cmd)
            except Exception as e:
                print(f"command poll error: {e}")
            await asyncio.sleep(settings.poll_interval)


 


async def execute_command(client: httpx.AsyncClient, settings: AgentSettings, cmd: dict):
    from executor import stream_command
    command_id = cmd.get("command_id") or "unknown"
    commands = cmd.get("commands") or []
    # If no commands provided but a known command type exists
    if not commands and cmd.get("command") == "apt_upgrade":
        commands = [
            "sudo apt update",
            "sudo DEBIAN_FRONTEND=noninteractive apt -y upgrade",
        ]
    elif not commands and cmd.get("command") == "sudo_check":
        commands = [
            "sudo -n apt -v || true",
        ]
    start = asyncio.get_event_loop().time()
    outputs: list[str] = []
    status = "success"
    for c in commands:
        try:
            async def post_chunk(text: str):
                payload = {"command_id": command_id, "chunk": text}
                body = json.dumps(payload).encode("utf-8")
                s = sign_bytes(body, settings.psk)
                await client.post(settings.server_url.rstrip("/") + "/api/command-chunk", content=body, headers={"Content-Type":"application/json","X-Agent-Id": settings.id, "X-Signature": s}, timeout=30)

            await post_chunk(f"$ {c}\n")
            for line in stream_command(c):
                outputs.append(line)
                await post_chunk(line)
        except Exception as e:
            status = "failed"
            err = f"[ERROR] {e}\n"
            outputs.append(err)
            body = json.dumps({"command_id": command_id, "chunk": err}).encode("utf-8")
            s = sign_bytes(body, settings.psk)
            await client.post(settings.server_url.rstrip("/") + "/api/command-chunk", content=body, headers={"Content-Type":"application/json","X-Agent-Id": settings.id, "X-Signature": s}, timeout=30)
            break

    duration = int(asyncio.get_event_loop().time() - start)
    result_payload = {
        "command_id": command_id,
        "status": status,
        "output": outputs,
        "duration": duration,
        "logs": "".join(outputs)[-4000:],
    }
    body = json.dumps(result_payload).encode("utf-8")
    s = sign_bytes(body, settings.psk)
    await client.post(settings.server_url.rstrip("/") + "/api/command-result", content=body, headers={"Content-Type":"application/json","X-Agent-Id": settings.id, "X-Signature": s}, timeout=60)

if __name__ == "__main__":
    asyncio.run(main())
