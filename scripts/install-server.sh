#!/usr/bin/env bash
set -euo pipefail

# Server installer (server + UI) for Debian/Ubuntu-like systems.
# - Creates service user and deploys repo to /opt/orchestrator
# - Installs prerequisites (python3-venv, nodejs, npm, rsync)
# - Writes /opt/orchestrator/.env with a strong SERVER_PSK if missing
# - Installs systemd services and starts orchestrator-stack

# Use the directory from which the script is launched as the repo root.
# You can override via REPO_DIR_OVERRIDE=/path/to/repo
REPO_DIR="${REPO_DIR_OVERRIDE:-$(pwd -P)}"
APP_USER="orchestrator"
APP_GROUP="orchestrator"
APP_HOME="/opt/orchestrator"
SYSTEMD_DIR="/etc/systemd/system"

need_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "This script must be run as root (sudo)." >&2
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

install_prereqs() {
  if have_cmd apt-get; then
    echo "Installing prerequisites with apt-get..."
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3-venv nodejs npm rsync
    # If Python is 3.12 and ensurepip missing, try python3.12-venv
    if have_cmd python3 && ! python3 -c 'import ensurepip' >/dev/null 2>&1; then
      apt-get install -y python3.12-venv || true
    fi
  else
    echo "apt-get not found; please install Python venv, Node.js, npm, and rsync manually." >&2
  fi
}

ensure_user() {
  if ! id -u "$APP_USER" >/dev/null 2>&1; then
    useradd --system --create-home --home-dir "$APP_HOME" --shell /usr/sbin/nologin "$APP_USER"
  fi
  mkdir -p "$APP_HOME"
  chown -R "$APP_USER:$APP_GROUP" "$APP_HOME" || true
}

deploy_repo() {
  echo "Deploying repository from $REPO_DIR to $APP_HOME ..."
  mkdir -p "$APP_HOME"
  # Safety checks to avoid syncing from '/'
  if [ -z "$REPO_DIR" ] || [ "$REPO_DIR" = "/" ]; then
    echo "Safety check failed: REPO_DIR='$REPO_DIR' looks invalid. Run this script from your repo root." >&2
    exit 1
  fi
  if [ ! -d "$REPO_DIR/scripts" ] || [ ! -f "$REPO_DIR/README.md" ]; then
    echo "REPO_DIR '$REPO_DIR' doesn't look like the FleetUpdate repo (missing scripts/ or README.md)." >&2
    echo "Run the installer from the repo root, or set REPO_DIR_OVERRIDE to the repo path." >&2
    exit 1
  fi
  rsync -a --delete \
    --exclude ".git/" \
    --exclude "server/.venv/" \
    --exclude "agent/.venv/" \
    --exclude "ui/node_modules/" \
    --exclude "ui/dist/" \
    "$REPO_DIR/" "$APP_HOME/"
  chown -R "$APP_USER:$APP_GROUP" "$APP_HOME"
}

write_env() {
  local env_file="$APP_HOME/.env"
  if [ ! -f "$env_file" ]; then
    echo "Creating $env_file ..."
    local psk
    if have_cmd openssl; then
      psk=$(openssl rand -hex 32)
    elif have_cmd python3; then
      psk=$(python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
)
    else
      psk="changeme-$(date +%s)"
    fi
    cat > "$env_file" <<EOF
SERVER_PSK=$psk
UI_USER=
UI_PASSWORD=
JWT_SECRET=$(date +%s)-devsecret
HOST=0.0.0.0
EOF
    chown "$APP_USER:$APP_GROUP" "$env_file"
    chmod 600 "$env_file"
    echo "Edit $env_file to set UI_USER/UI_PASSWORD before exposing the UI."
  else
    echo "$env_file already exists; leaving as-is."
  fi
}

install_services() {
  echo "Installing systemd units ..."
  cp "$APP_HOME/infra/systemd/orchestrator-"*.service "$SYSTEMD_DIR/"

  # Ensure server unit can load environment
  mkdir -p "$SYSTEMD_DIR/orchestrator-server.service.d"
  cat > "$SYSTEMD_DIR/orchestrator-server.service.d/override.conf" <<EOF
[Service]
EnvironmentFile=$APP_HOME/.env
EOF

  systemctl daemon-reload
}

enable_and_start() {
  echo "Enabling and starting server stack ..."
  systemctl enable orchestrator-stack || true
  systemctl restart orchestrator-stack || systemctl start orchestrator-stack
}

print_summary() {
  echo "\nServer installation complete. Summary:"
  echo "  App home:        $APP_HOME"
  echo "  Service user:    $APP_USER"
  echo "  Server .env:     $APP_HOME/.env"
  echo "  Service:         orchestrator-stack (server + UI)"
  echo
  echo "Check status/logs:"
  echo "  systemctl status orchestrator-stack"
  echo "  journalctl -u orchestrator-server -f"
}

main() {
  need_root
  install_prereqs
  ensure_user
  deploy_repo
  write_env
  install_services
  enable_and_start
  print_summary
}

main "$@"
