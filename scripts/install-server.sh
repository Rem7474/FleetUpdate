#!/usr/bin/env bash
set -euo pipefail

# Server installer (server + UI on single port) for Debian/Ubuntu-like systems.
# - Creates service user and deploys repo to /opt/orchestrator
# - Installs prerequisites (python3-venv, nodejs, npm, git)
# - Writes /opt/orchestrator/.env with a strong SERVER_PSK if missing
# - Prompts for UI credentials (username/password)
# - Builds UI and installs/starts orchestrator-server systemd unit

# Standalone installer: fetch repo directly to /opt/orchestrator using git
REPO_URL="${REPO_URL_OVERRIDE:-https://github.com/Rem7474/FleetUpdate.git}"
APP_USER="orchestrator"
APP_GROUP="orchestrator"
APP_HOME="/opt/orchestrator"
SYSTEMD_DIR="/etc/systemd/system"
NO_PROMPT="${NO_PROMPT:-0}"

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

clean_app_home() {
  echo "Cleaning directory: $APP_HOME"
  if [ -d "$APP_HOME" ]; then
    find "$APP_HOME" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
  fi
}

deploy_repo() {
  echo "Deploying repository from $REPO_URL to $APP_HOME ..."
  mkdir -p "$APP_HOME"
  # Updates must be done via git only
  if [ -d "$APP_HOME/.git" ]; then
    echo "Repo exists in $APP_HOME, ensuring correct remote and pulling latest..."
    # Configure safe.directory for the service user to avoid 'dubious ownership' errors
    sudo -u "$APP_USER" bash -lc "git config --global --add safe.directory '$APP_HOME'" || true
    sudo -u "$APP_USER" bash -lc "git -C '$APP_HOME' remote set-url origin '$REPO_URL'" || true
    if ! sudo -u "$APP_USER" bash -lc "git -C '$APP_HOME' fetch --prune --tags"; then
      echo "Warning: git fetch failed; attempting full reclone..." >&2
      clean_app_home
      sudo -u "$APP_USER" bash -lc "git clone --depth=1 '$REPO_URL' '$APP_HOME'" >/dev/null 2>&1 || { echo "Error: git clone failed" >&2; exit 1; }
    else
      DEFAULT_BRANCH=$(sudo -u "$APP_USER" bash -lc "git -C '$APP_HOME' remote show origin" 2>/dev/null | awk '/HEAD branch/ {print $NF}')
      DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
      if ! sudo -u "$APP_USER" bash -lc "git -C '$APP_HOME' rev-parse --verify '$DEFAULT_BRANCH'" >/dev/null 2>&1; then
        sudo -u "$APP_USER" bash -lc "git -C '$APP_HOME' checkout -b '$DEFAULT_BRANCH' 'origin/$DEFAULT_BRANCH'" >/dev/null 2>&1 || true
      else
        sudo -u "$APP_USER" bash -lc "git -C '$APP_HOME' checkout '$DEFAULT_BRANCH'" >/dev/null 2>&1 || true
      fi
      sudo -u "$APP_USER" bash -lc "git -C '$APP_HOME' reset --hard 'origin/$DEFAULT_BRANCH'" >/dev/null 2>&1 || \
      sudo -u "$APP_USER" bash -lc "git -C '$APP_HOME' pull --ff-only origin '$DEFAULT_BRANCH'" >/dev/null 2>&1 || {
        echo "Warning: git reset/pull failed; attempting reclone..." >&2
        clean_app_home
        sudo -u "$APP_USER" bash -lc "git clone --depth=1 '$REPO_URL' '$APP_HOME'" >/dev/null 2>&1 || { echo "Error: git clone failed" >&2; exit 1; }
      }
    fi
  else
    if [ -n "$(ls -A "$APP_HOME" 2>/dev/null || true)" ]; then
      echo "Non-git contents detected in $APP_HOME; cleaning before clone..."
      clean_app_home
    fi
    sudo -u "$APP_USER" bash -lc "git config --global --add safe.directory '$APP_HOME'" || true
    sudo -u "$APP_USER" bash -lc "git clone --depth=1 '$REPO_URL' '$APP_HOME'" >/dev/null 2>&1 || { echo "Error: git clone failed" >&2; exit 1; }
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
    echo "A base config was created at $env_file"
  else
    echo "$env_file already exists; leaving as-is."
  fi
}

prompt_server_config() {
  if [ "$NO_PROMPT" = "1" ]; then
    echo "NO_PROMPT=1 set; skipping interactive server config prompts."; return 0;
  fi
  local env_file="$APP_HOME/.env"
  [ -f "$env_file" ] || { echo "Missing $env_file" >&2; return 1; }

  # Read existing values
  local cur_user="$(grep -E '^UI_USER=' "$env_file" | sed 's/^UI_USER=//')"
  local cur_pass="$(grep -E '^UI_PASSWORD=' "$env_file" | sed 's/^UI_PASSWORD=//')"
  local cur_jwt="$(grep -E '^JWT_SECRET=' "$env_file" | sed 's/^JWT_SECRET=//')"

  # Prompt username
  local input_user
  read -r -p "UI username [${cur_user:-admin}]: " input_user || true
  input_user=${input_user:-${cur_user:-admin}}

  # Prompt password (silent)
  local input_pass
  if [ -z "$cur_pass" ]; then
    printf "UI password: "
    stty -echo; read -r input_pass; stty echo; printf "\n"
  else
    read -r -p "UI password [kept existing]: " _ignore || true
    input_pass="$cur_pass"
  fi

  # JWT secret (generate if empty)
  local input_jwt="$cur_jwt"
  if [ -z "$input_jwt" ]; then
    if have_cmd openssl; then input_jwt="$(openssl rand -hex 32)"; else input_jwt="jwt-$(date +%s)"; fi
  fi

  # Apply changes (escape sed special chars minimally)
  sed -i "s/^UI_USER=.*/UI_USER=${input_user}/" "$env_file" || true
  sed -i "s/^UI_PASSWORD=.*/UI_PASSWORD=${input_pass}/" "$env_file" || true
  if grep -qE '^JWT_SECRET=' "$env_file"; then
    sed -i "s/^JWT_SECRET=.*/JWT_SECRET=${input_jwt}/" "$env_file" || true
  else
    echo "JWT_SECRET=${input_jwt}" >> "$env_file"
  fi

  echo "Configured UI credentials in $env_file"
}

install_services() {
  echo "Installing systemd units ..."
  # Force update unit files
  cp -f "$APP_HOME/infra/systemd/orchestrator-server.service" "$SYSTEMD_DIR/" >/dev/null 2>&1 || true

  # Ensure server unit can load environment
  mkdir -p "$SYSTEMD_DIR/orchestrator-server.service.d"
  cat > "$SYSTEMD_DIR/orchestrator-server.service.d/override.conf" <<EOF
[Service]
EnvironmentFile=$APP_HOME/.env
EOF

  systemctl daemon-reload >/dev/null 2>&1 || systemctl daemon-reload
  # Ensure updated units are enabled
  systemctl enable orchestrator-server >/dev/null 2>&1 || true
}

enable_and_start() {
  echo "Enabling and starting server ..."
  # Restart to pick up unit changes
  systemctl restart orchestrator-server >/dev/null 2>&1 || systemctl start orchestrator-server >/dev/null 2>&1
}

print_summary() {
  printf "\nServer installation complete. Summary:\n"
  printf "  App home:        %s\n" "$APP_HOME"
  printf "  Service user:    %s\n" "$APP_USER"
  printf "  Server .env:     %s/.env\n" "$APP_HOME"
  printf "  Service:         orchestrator-server (serves UI + API)\n\n"
  printf "Check status/logs:\n"
  printf "  systemctl status orchestrator-server\n"
  printf "  journalctl -u orchestrator-server -f\n"
}

main() {
  need_root
  # Stop services before updating files
  systemctl stop orchestrator-server >/dev/null 2>&1 || true
  install_prereqs
  ensure_user
  deploy_repo
  # Build UI for single-port serving
  echo "Building UI production bundle ..."
  sudo -u "$APP_USER" bash -lc "cd '$APP_HOME/ui' && npm install && npm run build" || {
    echo "Error: UI build failed" >&2; exit 1; }
  write_env
  prompt_server_config
  install_services
  enable_and_start
  print_summary
}

main "$@"
