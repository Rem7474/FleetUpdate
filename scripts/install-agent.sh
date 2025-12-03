#!/usr/bin/env bash
set -euo pipefail

# Agent-only installer for Debian/Ubuntu-like systems.
# - Creates service user and deploys repo to /opt/orchestrator
# - Installs prerequisites (python3-venv, rsync)
# - Creates /etc/orchestrator-agent/config.yaml (can patch via env vars)
# - Installs systemd agent service and starts it

# Use the directory from which the script is launched as the repo root.
# You can override via REPO_DIR_OVERRIDE=/path/to/repo
REPO_DIR="${REPO_DIR_OVERRIDE:-$(pwd -P)}"
APP_USER="orchestrator"
APP_GROUP="orchestrator"
APP_HOME="/opt/orchestrator"
AGENT_CONF_DIR="/etc/orchestrator-agent"
AGENT_CONF_PATH="$AGENT_CONF_DIR/config.yaml"
SYSTEMD_DIR="/etc/systemd/system"

# Optional env overrides for config templating
AGENT_ID_DEFAULT="${AGENT_ID:-}"
SERVER_URL_DEFAULT="${SERVER_URL:-}"
AGENT_PSK_DEFAULT="${AGENT_PSK:-}"

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
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3-venv rsync
    # If Python is 3.12 and ensurepip missing, try python3.12-venv
    if have_cmd python3 && ! python3 -c 'import ensurepip' >/dev/null 2>&1; then
      apt-get install -y python3.12-venv || true
    fi
  else
    echo "apt-get not found; please install Python venv and rsync manually." >&2
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

setup_agent_config() {
  echo "Ensuring agent config at $AGENT_CONF_PATH ..."
  mkdir -p "$AGENT_CONF_DIR"
  if [ ! -f "$AGENT_CONF_PATH" ]; then
    cp "$APP_HOME/agent/config.example.yaml" "$AGENT_CONF_PATH"
  fi
  # Patch config if env vars provided
  if [ -n "$AGENT_ID_DEFAULT" ]; then
    sed -i "s/^\s*id: .*/  id: \"$AGENT_ID_DEFAULT\"/" "$AGENT_CONF_PATH" || true
  fi
  if [ -n "$SERVER_URL_DEFAULT" ]; then
    sed -i "s|^\s*server_url: .*|  server_url: \"$SERVER_URL_DEFAULT\"|" "$AGENT_CONF_PATH" || true
  fi
  if [ -n "$AGENT_PSK_DEFAULT" ]; then
    sed -i "s/^\s*psk: .*/  psk: \"$AGENT_PSK_DEFAULT\"/" "$AGENT_CONF_PATH" || true
  fi
  chown -R "$APP_USER:$APP_GROUP" "$AGENT_CONF_DIR"
}

install_services() {
  echo "Installing systemd unit for agent ..."
  cp "$APP_HOME/infra/systemd/orchestrator-agent.service" "$SYSTEMD_DIR/"
  systemctl daemon-reload
}

enable_and_start() {
  echo "Enabling and starting agent ..."
  systemctl enable orchestrator-agent || true
  systemctl restart orchestrator-agent || systemctl start orchestrator-agent
}

print_summary() {
  echo "\nAgent installation complete. Summary:"
  echo "  App home:        $APP_HOME"
  echo "  Service user:    $APP_USER"
  echo "  Agent config:    $AGENT_CONF_PATH"
  echo "  Service:         orchestrator-agent"
  echo
  echo "Check status/logs:"
  echo "  systemctl status orchestrator-agent"
  echo "  journalctl -u orchestrator-agent -f"
}

main() {
  need_root
  install_prereqs
  ensure_user
  deploy_repo
  setup_agent_config
  install_services
  enable_and_start
  print_summary
}

main "$@"
