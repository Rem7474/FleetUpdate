from fastapi import FastAPI, Header, HTTPException, Request, Depends, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from fastapi import WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
import os
from sqlmodel import Session, select
from .config import settings
from .utils.hmac import verify_signature
from .db.session import engine, init_db
from .db.models import Agent, Command
from .schemas.protocol import HeartbeatPayload, CommandResult, CommandChunk
from .core.security import create_access_token, decode_token, verify_password
import json
from datetime import datetime
import asyncio
import uuid


app = FastAPI(title="FleetUpdate Server", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"]
)

# Serve built UI (single-port) if available
ui_dist_path = os.path.join(os.path.dirname(__file__), "..", "..", "ui", "dist")
ui_dist_path = os.path.abspath(ui_dist_path)
if os.path.isdir(ui_dist_path):
    app.mount("/", StaticFiles(directory=ui_dist_path, html=True), name="ui")


@app.on_event("startup")
def _startup():
    init_db()


@app.get("/api/health")
def api_health():
    return {"status": "ok", "time": datetime.utcnow().isoformat()}


# --------- Auth (UI) ---------

def require_user(authorization: str | None = Header(default=None, alias="Authorization"), token: str | None = Query(default=None)):
    tok: str | None = None
    if authorization and authorization.lower().startswith("bearer "):
        tok = authorization.split(" ", 1)[1].strip()
    elif token:
        tok = token
    if not tok:
        raise HTTPException(status_code=401, detail="Missing token")
    try:
        data = decode_token(tok)
        if not data or data.get("sub") != settings.ui_user:
            raise HTTPException(status_code=401, detail="Invalid token")
        return settings.ui_user
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")


@app.post("/api/auth/login")
async def auth_login(payload: dict):
    username = payload.get("username")
    password = payload.get("password")
    if username != settings.ui_user:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if settings.ui_password_hash:
        ok = verify_password(password or "", settings.ui_password_hash, True)
    else:
        ok = verify_password(password or "", settings.ui_password, False)
    if not ok:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    token = create_access_token(subject=settings.ui_user)
    return {"token": token}


# --------- Metrics ---------

@app.get("/api/metrics")
def metrics(user: str = Depends(require_user)):
    now = datetime.utcnow()
    with Session(engine) as session:
        agents = session.exec(select(Agent)).all()
        total = len(agents)
        online = sum(1 for a in agents if a.status == "online")
        uptime_seconds = {a.id: max(0, int((now - a.last_seen).total_seconds())) for a in agents}
        # simple command success rate last 100
        total_cmd = session.exec(select(Command).order_by(Command.created_at.desc())).all()
        last = total_cmd[:100]
        succ = sum(1 for c in last if c.status == "success")
        rate = (succ / len(last)) if last else None
        return {
            "agents_total": total,
            "agents_online": online,
            "uptime_seconds": uptime_seconds,
            "command_success_rate_last100": rate,
            "app_drift": 0,
        }


@app.get("/api/agents")
def list_agents(user: str = Depends(require_user)):
    with Session(engine) as session:
        agents = session.exec(select(Agent)).all()
        return [
            {
                "id": a.id,
                "last_seen": a.last_seen.isoformat(),
                "status": a.status,
                "apps_state": json.loads(a.apps_state) if a.apps_state else None,
                "os_update": json.loads(a.os_update) if a.os_update else None,
                "uptime_seconds": max(0, int((datetime.utcnow() - a.last_seen).total_seconds())),
                "outdated": (json.loads(a.os_update)["upgrades"] > 0) if a.os_update else False,
            }
            for a in agents
        ]


@app.get("/api/agents/{agent_id}")
def get_agent(agent_id: str, user: str = Depends(require_user)):
    with Session(engine) as session:
        agent = session.get(Agent, agent_id)
        if not agent:
            raise HTTPException(status_code=404, detail="Agent not found")
        return {
            "id": agent.id,
            "last_seen": agent.last_seen.isoformat(),
            "status": agent.status,
            "apps_state": json.loads(agent.apps_state) if agent.apps_state else None,
            "os_update": json.loads(agent.os_update) if agent.os_update else None,
        }


@app.post("/api/heartbeat")
async def heartbeat(
    request: Request,
    x_agent_id: str | None = Header(default=None, alias="X-Agent-Id"),
    x_signature: str | None = Header(default=None, alias="X-Signature"),
):
    raw = await request.body()
    if not x_agent_id or not x_signature:
        raise HTTPException(status_code=400, detail="Missing authentication headers")

    if not verify_signature(x_signature, raw, settings.server_psk):
        raise HTTPException(status_code=401, detail="Invalid signature")

    try:
        payload = HeartbeatPayload.model_validate_json(raw)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid payload")

    if payload.agent_id != x_agent_id:
        raise HTTPException(status_code=400, detail="Agent ID mismatch")

    with Session(engine) as session:
        agent = session.get(Agent, payload.agent_id)
        if not agent:
            agent = Agent(id=payload.agent_id)
        agent.last_seen = datetime.utcnow()
        agent.status = "online"
        agent.apps_state = json.dumps({k: v.model_dump() for k, v in payload.apps.items()})
        # optionally parse os_update if the client sent it
        try:
            body = json.loads(raw)
            if "os_update" in body:
                agent.os_update = json.dumps(body["os_update"]) if body["os_update"] is not None else None
        except Exception:
            pass
        session.add(agent)
        session.commit()
    # broadcast agent update over WebSocket
    await ws_broadcast({
        "type": "agent_update",
        "agent": {
            "id": payload.agent_id,
            "last_seen": datetime.utcnow().isoformat(),
            "status": "online",
            "apps_state": {k: v.model_dump() for k, v in payload.apps.items()},
            "os_update": json.loads(agent.os_update) if agent.os_update else None,
        }
    })
    return {"status": "ok"}


@app.post("/api/command-result")
async def command_result(
    result: CommandResult,
    x_agent_id: str | None = Header(default=None, alias="X-Agent-Id"),
    x_signature: str | None = Header(default=None, alias="X-Signature"),
    request: Request = None,
):
    raw = await request.body()
    if not x_agent_id or not x_signature:
        raise HTTPException(status_code=400, detail="Missing authentication headers")
    if not verify_signature(x_signature, raw, settings.server_psk):
        raise HTTPException(status_code=401, detail="Invalid signature")
    # TODO: persist deployment result
    return {"ack": True}


@app.post("/api/agents/{agent_id}/commands")
def enqueue_command(agent_id: str, body: dict, user: str = Depends(require_user)):
    cmd_id = body.get("command_id") or f"{uuid.uuid4()}"
    payload = json.dumps(body)
    with Session(engine) as session:
        cmd = Command(command_id=cmd_id, agent_id=agent_id, payload=payload, status="pending")
        session.add(cmd)
        session.commit()
    # initialize broadcaster queue
    _get_broadcaster(cmd_id)  # ensure exists
    return {"queued": True, "agent_id": agent_id, "command_id": cmd_id}


@app.post("/api/agents/{agent_id}/sudo-check")
def sudo_check(agent_id: str, user: str = Depends(require_user)):
    body = {"command": "sudo_check", "commands": []}
    return enqueue_command(agent_id, body, user)


@app.get("/api/agents/{agent_id}/next-command")
def next_command(agent_id: str, x_agent_id: str | None = Header(default=None, alias="X-Agent-Id"), x_signature: str | None = Header(default=None, alias="X-Signature")):
    # Optional HMAC: verify empty body signature
    if x_agent_id != agent_id:
        raise HTTPException(status_code=400, detail="Agent ID mismatch")
    with Session(engine) as session:
        cmd = session.exec(
            select(Command).where(Command.agent_id == agent_id, Command.status == "pending").order_by(Command.created_at)
        ).first()
        if not cmd:
            return {"command": None}
        cmd.status = "running"
        cmd.updated_at = datetime.utcnow()
        session.add(cmd)
        session.commit()
        return {"command": json.loads(cmd.payload)}


@app.post("/api/command-chunk")
async def command_chunk(chunk: CommandChunk, request: Request, x_agent_id: str | None = Header(default=None, alias="X-Agent-Id"), x_signature: str | None = Header(default=None, alias="X-Signature")):
    raw = await request.body()
    if not x_agent_id or not x_signature or not verify_signature(x_signature, raw, settings.server_psk):
        raise HTTPException(status_code=401, detail="Invalid signature")
    # Append to DB output and broadcast to SSE subscribers
    with Session(engine) as session:
        cmd = session.exec(select(Command).where(Command.command_id == chunk.command_id)).first()
        if cmd:
            existing = cmd.output or ""
            cmd.output = existing + chunk.chunk
            cmd.updated_at = datetime.utcnow()
            session.add(cmd)
            session.commit()
    # Broadcast
    queue = _get_broadcaster(chunk.command_id)
    await queue.put(chunk.chunk)
    return {"ok": True}


# SSE broadcaster storage
_broadcast_queues: dict[str, asyncio.Queue[str]] = {}


def _get_broadcaster(command_id: str) -> asyncio.Queue:
    if command_id not in _broadcast_queues:
        _broadcast_queues[command_id] = asyncio.Queue()
    return _broadcast_queues[command_id]


@app.get("/api/commands/{command_id}/stream")
async def stream_command(command_id: str, user: str = Depends(require_user)):
    queue = _get_broadcaster(command_id)

    async def event_gen():
        # send existing output first
        with Session(engine) as session:
            cmd = session.exec(select(Command).where(Command.command_id == command_id)).first()
            if cmd and cmd.output:
                for line in cmd.output.splitlines(True):
                    yield f"data: {line}\n\n"
        # then live chunks
        while True:
            chunk = await queue.get()
            yield f"data: {chunk}\n\n"

    return StreamingResponse(event_gen(), media_type="text/event-stream")


# --------- WebSocket push ---------
_ws_clients: set[WebSocket] = set()


@app.websocket("/api/ws")
async def websocket_endpoint(ws: WebSocket):
    # Simple token via query param ?token=
    token = ws.query_params.get("token")
    try:
        data = decode_token(token) if token else None
        if not data or data.get("sub") != settings.ui_user:
            await ws.close(code=4401)
            return
    except Exception:
        await ws.close(code=4401)
        return
    await ws.accept()
    _ws_clients.add(ws)
    try:
        while True:
            await ws.receive_text()  # no-op; keepalive if needed
    except WebSocketDisconnect:
        pass
    finally:
        _ws_clients.discard(ws)


async def ws_broadcast(message: dict):
    if not _ws_clients:
        return
    dead: list[WebSocket] = []
    text = json.dumps(message)
    for ws in list(_ws_clients):
        try:
            await ws.send_text(text)
        except Exception:
            dead.append(ws)
    for ws in dead:
        _ws_clients.discard(ws)
