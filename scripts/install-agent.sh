#!/usr/bin/env bash
set -euo pipefail

# Set VERBOSE=1 to enable shell tracing
VERBOSE="${VERBOSE:-0}"
[ "$VERBOSE" = "1" ] && set -x

# Agent-only installer for Debian/Ubuntu-like systems.
# - Creates service user and deploys repo to /opt/orchestrator
# - Installs prerequisites (python3-venv, git)
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
NO_PROMPT="${NO_PROMPT:-0}"

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
  if have_cmd apt; then
    echo "Installing prerequisites with apt (only missing ones)..."
    apt update -y >/dev/null 2>&1 || apt update -y
    pkgs=()
    have_cmd python3 || pkgs+=(python3)
    python3 -c 'import ensurepip' >/dev/null 2>&1 || pkgs+=(python3-venv)
    have_cmd git || pkgs+=(git)
    pkgs+=(ca-certificates)
    if [ ${#pkgs[@]} -gt 0 ]; then
      DEBIAN_FRONTEND=noninteractive apt install -y -qq "${pkgs[@]}" >/dev/null 2>&1 || \
      DEBIAN_FRONTEND=noninteractive apt install -y "${pkgs[@]}"
    fi
    if have_cmd python3 && ! python3 -c 'import ensurepip' >/dev/null 2>&1; then
      DEBIAN_FRONTEND=noninteractive apt install -y -qq python3.12-venv >/dev/null 2>&1 || apt install -y python3.12-venv || true
    fi
  else
    echo "apt not found; please install Python venv and git manually." >&2
  fi
}

ensure_user() {
  if ! id -u "$APP_USER" >/dev/null 2>&1; then
    useradd --system --create-home --home-dir "$APP_HOME" --shell /usr/sbin/nologin "$APP_USER" >/dev/null 2>&1 || true
  fi
  mkdir -p "$APP_HOME"
  chown -R "$APP_USER:$APP_GROUP" "$APP_HOME" >/dev/null 2>&1 || true
}

clean_app_home() {
  echo "Cleaning directory: $APP_HOME"
  if [ -d "$APP_HOME" ]; then
    # Remove all contents including dotfiles but keep the directory
    find "$APP_HOME" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
  fi
}

deploy_repo() {
  echo "Deploying repository from $REPO_URL to $APP_HOME ..."
  mkdir -p "$APP_HOME"
  if [ -d "$APP_HOME/.git" ]; then
    echo "Repo exists in $APP_HOME, ensuring correct remote and pulling latest..."
    echo "Running: git -C '$APP_HOME' remote set-url origin '$REPO_URL'"
    git -C "$APP_HOME" remote set-url origin "$REPO_URL" || true
    echo "Running: git -C '$APP_HOME' fetch --prune --tags"
    if ! git -C "$APP_HOME" fetch --prune --tags; then
      echo "Warning: git fetch failed; attempting full reclone..." >&2
      git --version || true
      echo "Remote URL: $REPO_URL" >&2
      echo "Testing connectivity with: git ls-remote $REPO_URL" >&2
      GIT_TRACE=1 GIT_CURL_VERBOSE=1 git ls-remote "$REPO_URL" || true
      echo "Directory perms:" >&2; ls -ld "$APP_HOME" || true
      echo "Disk space:" >&2; df -h "$APP_HOME" || true
      clean_app_home
      echo "Running: git clone --depth=1 '$REPO_URL' '$APP_HOME'"
      git clone --depth=1 "$REPO_URL" "$APP_HOME" || { echo "Error: git clone failed" >&2; exit 1; }
    else
      DEFAULT_BRANCH=$(git -C "$APP_HOME" remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}')
      DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
      if ! git -C "$APP_HOME" rev-parse --verify "$DEFAULT_BRANCH" >/dev/null 2>&1; then
        echo "Running: git -C '$APP_HOME' checkout -b '$DEFAULT_BRANCH' 'origin/$DEFAULT_BRANCH'"
        git -C "$APP_HOME" checkout -b "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" >/dev/null 2>&1 || true
      else
        echo "Running: git -C '$APP_HOME' checkout '$DEFAULT_BRANCH'"
        git -C "$APP_HOME" checkout "$DEFAULT_BRANCH" >/dev/null 2>&1 || true
      fi
      echo "Running: git -C '$APP_HOME' reset --hard 'origin/$DEFAULT_BRANCH' || git -C '$APP_HOME' pull --ff-only origin '$DEFAULT_BRANCH'"
      git -C "$APP_HOME" reset --hard "origin/$DEFAULT_BRANCH" >/dev/null 2>&1 || \
      git -C "$APP_HOME" pull --ff-only origin "$DEFAULT_BRANCH" >/dev/null 2>&1 || {
        echo "Warning: git reset/pull failed; attempting reclone..." >&2
        clean_app_home
        echo "Running: git clone --depth=1 '$REPO_URL' '$APP_HOME'"
        git clone --depth=1 "$REPO_URL" "$APP_HOME" || { echo "Error: git clone failed" >&2; exit 1; }
      }
    fi
  else
    if [ -n "$(ls -A "$APP_HOME" 2>/dev/null || true)" ]; then
      echo "Non-git contents detected in $APP_HOME; cleaning before clone..."
      clean_app_home
    fi
    echo "Running: git clone --depth=1 '$REPO_URL' '$APP_HOME'"
    git clone --depth=1 "$REPO_URL" "$APP_HOME" || { echo "Error: git clone failed" >&2; exit 1; }
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

prompt_agent_config() {
  if [ "$NO_PROMPT" = "1" ]; then
    echo "NO_PROMPT=1 set; skipping interactive agent config prompts."; return 0;
  fi
  # Ask interactively when not supplied via env
  if [ -z "$AGENT_ID_DEFAULT" ]; then
    read -r -p "Agent ID (e.g., vm-01): " AGENT_ID_DEFAULT || true
  fi
  if [ -z "$SERVER_URL_DEFAULT" ]; then
    read -r -p "Server URL (default http://<ip>:8000): " SERVER_URL_DEFAULT || true
  fi
  if [ -z "$AGENT_PSK_DEFAULT" ]; then
    printf "Agent PSK (must match server SERVER_PSK): "
    stty -echo; read -r AGENT_PSK_DEFAULT; stty echo; printf "\n"
  fi
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
  # Stop agent service before updating files
  systemctl stop orchestrator-agent >/dev/null 2>&1 || true
  install_prereqs
  ensure_user
  deploy_repo
  prompt_agent_config
  setup_agent_config
  install_services
  enable_and_start
  print_summary
}

main "$@"
