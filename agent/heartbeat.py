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
        # Try to collect OS version (Debian/Ubuntu)
        osv = ""
        try:
            pv = subprocess.run("bash -lc 'lsb_release -ds 2>/dev/null'", shell=True, capture_output=True, text=True, timeout=10)
            osv = (pv.stdout or "").strip().strip('"')
            if not osv:
                pv2 = subprocess.run("bash -lc 'cat /etc/os-release 2>/dev/null'", shell=True, capture_output=True, text=True, timeout=10)
                for ln in pv2.stdout.splitlines():
                    if ln.startswith("PRETTY_NAME="):
                        osv = ln.split("=",1)[1].strip().strip('"')
                        break
        except Exception:
            pass
        # Collect additional OS metadata
        arch = ""
        kernel = ""
        hostname = ""
        uptime_seconds = 0
        try:
            arch = subprocess.run("bash -lc 'uname -m'", shell=True, capture_output=True, text=True, timeout=5).stdout.strip()
            kernel = subprocess.run("bash -lc 'uname -r'", shell=True, capture_output=True, text=True, timeout=5).stdout.strip()
            hostname = subprocess.run("bash -lc 'hostname'", shell=True, capture_output=True, text=True, timeout=5).stdout.strip()
            up = subprocess.run("bash -lc 'cat /proc/uptime 2>/dev/null'", shell=True, capture_output=True, text=True, timeout=5).stdout.strip()
            if up:
                uptime_seconds = int(float(up.split()[0]))
        except Exception:
            pass
        # Check sudoers allows apt without password
        sp = subprocess.run("bash -lc 'sudo -n apt -v >/dev/null 2>&1'", shell=True)
        sudo_ok = (sp.returncode == 0)
        return {
            "pkg_manager": "apt",
            "upgrades": count,
            "status": ("outdated" if count > 0 else "up_to_date"),
            "sudo_apt_ok": sudo_ok,
            "os_version": osv,
            "arch": arch,
            "kernel": kernel,
            "hostname": hostname,
            "uptime_seconds": uptime_seconds,
        }
    except Exception:
        return {"pkg_manager": "apt", "upgrades": -1, "status": "unknown", "sudo_apt_ok": False, "os_version": "", "arch": "", "kernel": "", "hostname": "", "uptime_seconds": 0}
