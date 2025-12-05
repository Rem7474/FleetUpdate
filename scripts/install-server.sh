#!/usr/bin/env bash
set -euo pipefail

# Server installer (server + UI) for Debian/Ubuntu-like systems.
# - Creates service user and deploys repo to /opt/orchestrator
# - Installs prerequisites (python3-venv, nodejs, npm, git)
# - Writes /opt/orchestrator/.env with a strong SERVER_PSK if missing
# - Installs systemd services and starts orchestrator-stack

# Standalone installer: fetch repo directly to /opt/orchestrator using git
REPO_URL="${REPO_URL_OVERRIDE:-https://github.com/Rem7474/FleetUpdate.git}"
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
  if have_cmd apt; then
    echo "Installing prerequisites with apt (only missing ones)..."
    apt update -y >/dev/null 2>&1 || apt update -y
    # Build list of missing packages
    pkgs=()
    have_cmd python3 || pkgs+=(python3)
    python3 -c 'import ensurepip' >/dev/null 2>&1 || pkgs+=(python3-venv)
    have_cmd node || have_cmd nodejs || pkgs+=(nodejs)
    have_cmd npm || pkgs+=(npm)
    have_cmd git || pkgs+=(git)
    pkgs+=(ca-certificates)
    if [ ${#pkgs[@]} -gt 0 ]; then
      DEBIAN_FRONTEND=noninteractive apt install -y -qq "${pkgs[@]}" >/dev/null 2>&1 || \
      DEBIAN_FRONTEND=noninteractive apt install -y "${pkgs[@]}"
    fi
    # If Python is 3.12 and ensurepip missing, try python3.12-venv
    if have_cmd python3 && ! python3 -c 'import ensurepip' >/dev/null 2>&1; then
      DEBIAN_FRONTEND=noninteractive apt install -y -qq python3.12-venv >/dev/null 2>&1 || apt install -y python3.12-venv || true
    fi
  else
    echo "apt not found; please install Python venv, Node.js, npm, git and curl manually." >&2
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
  # Updates must be done via git only
  if [ -d "$APP_HOME/.git" ]; then
    echo "Repo exists in $APP_HOME, pulling latest..."
    if ! git -C "$APP_HOME" fetch --all --quiet >/dev/null 2>&1; then
      echo "Warning: git fetch failed; attempting full reclone..." >&2
      rm -rf "$APP_HOME"/* "$APP_HOME"/.git >/dev/null 2>&1 || true
      git clone --depth=1 "$REPO_URL" "$APP_HOME" >/dev/null 2>&1 || { echo "Error: git clone failed" >&2; exit 1; }
    else
      DEFAULT_BRANCH=$(git -C "$APP_HOME" remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}')
      DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
      if ! git -C "$APP_HOME" rev-parse --verify "$DEFAULT_BRANCH" >/dev/null 2>&1; then
        git -C "$APP_HOME" checkout -b "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" >/dev/null 2>&1 || true
      else
        git -C "$APP_HOME" checkout "$DEFAULT_BRANCH" >/dev/null 2>&1 || true
      fi
      git -C "$APP_HOME" reset --hard "origin/$DEFAULT_BRANCH" >/dev/null 2>&1 || \
      git -C "$APP_HOME" pull --ff-only origin "$DEFAULT_BRANCH" >/devnull 2>&1 || {
        echo "Warning: git reset/pull failed; attempting reclone..." >&2
        rm -rf "$APP_HOME"/* "$APP_HOME"/.git >/dev/null 2>&1 || true
        git clone --depth=1 "$REPO_URL" "$APP_HOME" >/dev/null 2>&1 || { echo "Error: git clone failed" >&2; exit 1; }
      }
    fi
  else
    rm -rf "$APP_HOME"/* "$APP_HOME"/.git >/dev/null 2>&1 || true
    git clone --depth=1 "$REPO_URL" "$APP_HOME" >/dev/null 2>&1 || { echo "Error: git clone failed" >&2; exit 1; }
  fi
  chown -R "$APP_USER:$APP_GROUP" "$APP_HOME" >/dev/null 2>&1 || true
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
    chown "$APP_USER:$APP_GROUP" "$env_file" >/dev/null 2>&1 || true
    chmod 600 "$env_file" >/dev/null 2>&1 || true
    echo "Edit $env_file to set UI_USER/UI_PASSWORD before exposing the UI."
  else
    echo "$env_file already exists; leaving as-is."
  fi
}

install_services() {
  echo "Installing systemd units ..."
  # Force update unit files
  cp -f "$APP_HOME/infra/systemd/orchestrator-"*.service "$SYSTEMD_DIR/" >/dev/null 2>&1

  # Ensure server unit can load environment
  mkdir -p "$SYSTEMD_DIR/orchestrator-server.service.d"
  cat > "$SYSTEMD_DIR/orchestrator-server.service.d/override.conf" <<EOF
[Service]
EnvironmentFile=$APP_HOME/.env
EOF

  systemctl daemon-reload >/dev/null 2>&1 || systemctl daemon-reload
  # Ensure updated units are enabled
  systemctl enable orchestrator-stack >/dev/null 2>&1 || true
  systemctl enable orchestrator-server >/dev/null 2>&1 || true
  systemctl enable orchestrator-ui >/dev/null 2>&1 || true
}

enable_and_start() {
  echo "Enabling and starting server stack ..."
  # Restart to pick up unit changes
  systemctl restart orchestrator-stack >/dev/null 2>&1 || systemctl start orchestrator-stack >/dev/null 2>&1
}

print_summary() {
  printf "\nServer installation complete. Summary:\n"
  printf "  App home:        %s\n" "$APP_HOME"
  printf "  Service user:    %s\n" "$APP_USER"
  printf "  Server .env:     %s/.env\n" "$APP_HOME"
  printf "  Service:         orchestrator-stack (server + UI)\n\n"
  printf "Check status/logs:\n"
  printf "  systemctl status orchestrator-stack\n"
  printf "  journalctl -u orchestrator-server -f\n"
}

main() {
  need_root
  # Stop services before updating files
  systemctl stop orchestrator-stack >/dev/null 2>&1 || true
  systemctl stop orchestrator-ui >/dev/null 2>&1 || true
  systemctl stop orchestrator-server >/dev/null 2>&1 || true
  install_prereqs
  ensure_user
  deploy_repo
  write_env
  install_services
  enable_and_start
  print_summary
}

main "$@"
