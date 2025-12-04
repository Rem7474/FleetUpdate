#!/usr/bin/env bash
set -euo pipefail

# Agent-only installer for Debian/Ubuntu-like systems.
# - Creates service user and deploys repo to /opt/orchestrator
# - Installs prerequisites (python3-venv, rsync, git)
# - Creates /etc/orchestrator-agent/config.yaml (can patch via env vars)
# - Installs systemd agent service and starts it

# Use the directory from which the script is launched as the repo root.
# Standalone installer: fetch repo directly to /opt/orchestrator using git
REPO_URL="${REPO_URL_OVERRIDE:-https://github.com/Rem7474/FleetUpdate.git}"
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
    apt-get update -y >/dev/null 2>&1 || apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv rsync git ca-certificates >/dev/null 2>&1 || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3-venv rsync git ca-certificates
    # If Python is 3.12 and ensurepip missing, try python3.12-venv
    if have_cmd python3 && ! python3 -c 'import ensurepip' >/dev/null 2>&1; then
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3.12-venv >/dev/null 2>&1 || apt-get install -y python3.12-venv || true
    fi
  else
    echo "apt-get not found; please install Python venv, rsync, and git manually." >&2
  fi
}

ensure_user() {
  if ! id -u "$APP_USER" >/dev/null 2>&1; then
    useradd --system --create-home --home-dir "$APP_HOME" --shell /usr/sbin/nologin "$APP_USER" >/dev/null 2>&1 || true
  fi
  mkdir -p "$APP_HOME"
  chown -R "$APP_USER:$APP_GROUP" "$APP_HOME" >/dev/null 2>&1 || true
}

deploy_repo() {
  echo "Deploying repository from $REPO_URL to $APP_HOME ..."
  mkdir -p "$APP_HOME"
  if [ -d "$APP_HOME/.git" ]; then
    echo "Repo exists in $APP_HOME, pulling latest..."
    if ! git -C "$APP_HOME" fetch --all --quiet >/dev/null 2>&1; then
      echo "Warning: git fetch failed; attempting full reclone..." >&2
      rm -rf "$APP_HOME"/* "$APP_HOME"/.git >/dev/null 2>&1 || true
      git clone --depth=1 "$REPO_URL" "$APP_HOME" >/dev/null 2>&1 || {
        echo "Error: git clone failed" >&2; exit 1; }
    else
      DEFAULT_BRANCH=$(git -C "$APP_HOME" remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}')
      DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
      if ! git -C "$APP_HOME" rev-parse --verify "$DEFAULT_BRANCH" >/dev/null 2>&1; then
        git -C "$APP_HOME" checkout -b "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" >/dev/null 2>&1 || true
      else
        git -C "$APP_HOME" checkout "$DEFAULT_BRANCH" >/dev/null 2>&1 || true
      fi
      git -C "$APP_HOME" reset --hard "origin/$DEFAULT_BRANCH" >/dev/null 2>&1 || \
      git -C "$APP_HOME" pull --ff-only origin "$DEFAULT_BRANCH" >/dev/null 2>&1 || {
        echo "Warning: git reset/pull failed; attempting reclone..." >&2
        rm -rf "$APP_HOME"/* "$APP_HOME"/.git >/dev/null 2>&1 || true
        git clone --depth=1 "$REPO_URL" "$APP_HOME" >/dev/null 2>&1 || {
          echo "Error: git clone failed" >&2; exit 1; }
      }
    fi
  else
    rm -rf "$APP_HOME"/* "$APP_HOME"/.git >/dev/null 2>&1 || true
    git clone --depth=1 "$REPO_URL" "$APP_HOME" >/dev/null 2>&1
  fi
  chown -R "$APP_USER:$APP_GROUP" "$APP_HOME" >/dev/null 2>&1 || true
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
  chown -R "$APP_USER:$APP_GROUP" "$AGENT_CONF_DIR" >/dev/null 2>&1 || true
}

install_services() {
  echo "Installing systemd unit for agent ..."
  cp -f "$APP_HOME/infra/systemd/orchestrator-agent.service" "$SYSTEMD_DIR/" >/dev/null 2>&1
  systemctl daemon-reload >/dev/null 2>&1 || systemctl daemon-reload
  systemctl enable orchestrator-agent >/dev/null 2>&1 || true
}

enable_and_start() {
  echo "Enabling and starting agent ..."
  systemctl restart orchestrator-agent >/dev/null 2>&1 || systemctl start orchestrator-agent >/dev/null 2>&1
}

print_summary() {
  printf "\nAgent installation complete. Summary:\n"
  printf "  App home:        %s\n" "$APP_HOME"
  printf "  Service user:    %s\n" "$APP_USER"
  printf "  Agent config:    %s\n" "$AGENT_CONF_PATH"
  printf "  Service:         orchestrator-agent\n\n"
  printf "Check status/logs:\n"
  printf "  systemctl status orchestrator-agent\n"
  printf "  journalctl -u orchestrator-agent -f\n"
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
