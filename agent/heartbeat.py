from typing import Dict
import subprocess


def collect_apps_state(config_apps: list[dict]) -> Dict[str, dict]:
    state: Dict[str, dict] = {}
    for app in config_apps:
        name = app.get("name") or "app"
        state[name] = {
            "type": app.get("type"),
            "status": "unknown",
            "health": "unknown",
        }
    return state


def collect_os_update_status() -> dict:
    try:
        # Count upgradable packages (Debian/Ubuntu)
        p = subprocess.run("bash -lc 'apt list --upgradable 2>/dev/null'", shell=True, capture_output=True, text=True, timeout=30)
        lines = [ln for ln in p.stdout.splitlines() if ln.strip()]
        # First line may be a header; count rest
        count = max(0, len(lines) - 1) if lines else 0
        # Check sudoers allows apt without password
        sp = subprocess.run("bash -lc 'sudo -n apt -v >/dev/null 2>&1'", shell=True)
        sudo_ok = (sp.returncode == 0)
        return {
            "pkg_manager": "apt",
            "upgrades": count,
            "status": ("outdated" if count > 0 else "up_to_date"),
            "sudo_apt_ok": sudo_ok,
        }
    except Exception:
        return {"pkg_manager": "apt", "upgrades": -1, "status": "unknown", "sudo_apt_ok": False}
