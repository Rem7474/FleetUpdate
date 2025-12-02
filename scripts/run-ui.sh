#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../ui"

if [ -f ../.env ]; then set -a; . ../.env; set +a; fi

if ! command -v node >/dev/null 2>&1; then
  echo "node not found. Please install Node.js 18+ and npm." >&2
  echo "Debian/Ubuntu quick fix:" >&2
  echo "  sudo apt update; sudo apt install -y nodejs npm" >&2
  echo "Or NodeSource LTS: https://github.com/nodesource/distributions" >&2
  exit 1
fi

if ! node -e 'process.exit(process.versions.node.split(".")[0] >= 18 ? 0 : 1)'; then
  echo "Node.js 18+ required. Current: $(node -v)" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm not found. Please install Node.js 18+ and npm." >&2
  echo "Debian/Ubuntu quick fix:" >&2
  echo "  sudo apt update; sudo apt install -y nodejs npm" >&2
  echo "Or use NodeSource for a newer LTS: https://github.com/nodesource/distributions" >&2
  exit 1
}

if [ ! -d node_modules ]; then
  npm install
fi

export HOST="${HOST:-0.0.0.0}"
exec npm run dev
