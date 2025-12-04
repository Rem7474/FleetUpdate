#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f ./.env ]; then set -a; . ./.env; set +a; fi

# Prevent port conflicts: stop any running systemd services for UI/Server
if command -v systemctl >/dev/null 2>&1; then
  systemctl stop orchestrator-ui >/dev/null 2>&1 || true
  systemctl stop orchestrator-server >/dev/null 2>&1 || true
fi

pids=()

cleanup() {
  trap - INT TERM EXIT
  for pid in "${pids[@]:-}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  wait || true
}
trap cleanup INT TERM EXIT

/bin/bash scripts/run-server.sh &
pids+=($!)
/bin/bash scripts/run-ui.sh &
pids+=($!)

# Wait until one exits, then cleanup
wait -n || true
exit 0
