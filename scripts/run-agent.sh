#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PY=python3
if [ ! -d agent/.venv ]; then
  $PY -m venv agent/.venv
fi

source agent/.venv/bin/activate
pip install --upgrade pip >/dev/null
pip install -r agent/requirements.txt

exec python agent/main.py
