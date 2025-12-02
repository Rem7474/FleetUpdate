#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../ui"

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

exec npm run dev
