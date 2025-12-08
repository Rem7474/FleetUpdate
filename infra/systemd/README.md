# Systemd Services (Linux)

This directory contains example systemd unit files to run the server and agent as services.

Services:
- `orchestrator-server.service`: FastAPI server that also serves the built UI (single port)
- `orchestrator-agent.service`: Agent daemon

## 1) Create a dedicated user
```bash
sudo useradd --system --create-home --home-dir /opt/orchestrator --shell /usr/sbin/nologin orchestrator || true
```

## 2) Deploy the repository
Use the installer scripts (recommended) to deploy and configure services:
```bash
curl -fsSL https://raw.githubusercontent.com/Rem7474/FleetUpdate/main/scripts/install-server.sh -o install-server.sh
chmod +x install-server.sh
sudo ./install-server.sh
```

## 3) Agent configuration
```bash
sudo mkdir -p /etc/orchestrator-agent
sudo cp /opt/orchestrator/agent/config.example.yaml /etc/orchestrator-agent/config.yaml
sudo chown -R orchestrator:orchestrator /etc/orchestrator-agent
```

## 4) Install services
Installer copies units automatically. If doing it manually:
```bash
cd /opt/orchestrator/infra/systemd
sudo cp orchestrator-server.service orchestrator-agent.service /etc/systemd/system/
sudo systemctl daemon-reload
```

## 5) Environment variables (optional)
Set a strong PSK for the server before enabling. Prefer `/opt/orchestrator/.env` via `EnvironmentFile`:
```bash
sudo tee /opt/orchestrator/.env > /dev/null <<'EOF'
SERVER_PSK=replace-with-strong-secret
UI_USER=admin
UI_PASSWORD=changeme
JWT_SECRET=$(openssl rand -hex 32)
HOST=0.0.0.0
EOF
sudo chown orchestrator:orchestrator /opt/orchestrator/.env
```

## 6) Enable and start (single port)
```bash
sudo systemctl daemon-reload
sudo systemctl enable orchestrator-server orchestrator-agent
sudo systemctl start  orchestrator-server  orchestrator-agent
```
Pour le développement local, utilisez `scripts/run-stack.sh` au lieu de systemd.

## 7) Verify
```bash
systemctl status orchestrator-server
systemctl status orchestrator-agent
journalctl -u orchestrator-server -f
```

Notes:
- In production, run `npm run build` in `ui/`; the server serves `ui/dist` on the same port as the API.
- The installer builds the UI automatically and configures `EnvironmentFile=/opt/orchestrator/.env` for server secrets.
- Set `SERVER_PSK` on the server and the same `psk` in the agent config.
