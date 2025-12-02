#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PY=python3
if [ ! -d server/.venv ]; then
  $PY -m venv server/.venv
fi

source server/.venv/bin/activate
pip install --upgrade pip >/dev/null
pip install -r server/requirements.txt

export PYTHONPATH=server
exec uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
