#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f ./.env ]; then set -a; . ./.env; set +a; fi

if command -v python3 >/dev/null 2>&1; then PY=python3; elif command -v python >/dev/null 2>&1; then PY=python; else echo "Python not found in PATH" >&2; exit 1; fi

# Check Python version (warn if < 3.11)
if ! $PY -c 'import sys; import sys as s; raise SystemExit(0 if s.version_info[:2] >= (3,11) else 1)'; then
  echo "Warning: Python 3.11+ is recommended. Current: $($PY -c 'import sys; print(sys.version.split()[0])')" >&2
fi

# Warn if SERVER_PSK is unset or weak
if [ "${SERVER_PSK:-}" = "" ] || [ "${SERVER_PSK:-}" = "changeme" ]; then
  echo "Warning: SERVER_PSK is unset or 'changeme'. Set a strong secret in .env or environment." >&2
fi

# Recreate venv if missing or incomplete
if [ ! -f server/.venv/bin/activate ]; then
  rm -rf server/.venv 2>/dev/null || true
  # Check venv support (ensurepip)
  if ! $PY -c "import ensurepip" >/dev/null 2>&1; then
    echo "Python venv support is missing. On Debian/Ubuntu install it with:" >&2
    echo "  sudo apt update; sudo apt install -y python3-venv" >&2
    echo "If you're on Python 3.12, the package may be 'python3.12-venv'." >&2
    exit 1
  fi
  $PY -m venv server/.venv
fi

source server/.venv/bin/activate
pip install --upgrade pip >/dev/null
pip install -r server/requirements.txt

export PYTHONPATH=server
exec uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
