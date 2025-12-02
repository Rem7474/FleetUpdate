# Systemd Services (Linux)

This directory contains example systemd unit files to run the server, agent, and UI as services.

Services:
- `orchestrator-stack.service`: Server + UI (dev stack in one service)
- `orchestrator-server.service`: FastAPI server (uvicorn)
- `orchestrator-agent.service`: Agent daemon
- `orchestrator-ui.service`: UI dev/preview server (for production, serve built static files)

## 1) Create a dedicated user
```bash
sudo useradd --system --create-home --home-dir /opt/orchestrator --shell /usr/sbin/nologin orchestrator || true
```

## 2) Deploy the repository
```bash
sudo mkdir -p /opt/orchestrator
sudo rsync -a --delete . /opt/orchestrator/
sudo chown -R orchestrator:orchestrator /opt/orchestrator
```

## 3) Agent configuration
```bash
sudo mkdir -p /etc/orchestrator-agent
sudo cp /opt/orchestrator/agent/config.example.yaml /etc/orchestrator-agent/config.yaml
sudo chown -R orchestrator:orchestrator /etc/orchestrator-agent
```

## 4) Install services
Edit service files if needed (WorkingDirectory path, SERVER_PSK):
```bash
cd /opt/orchestrator/infra/systemd
sudo cp orchestrator-*.service /etc/systemd/system/
```

## 5) Environment variables (optional)
Set a strong PSK for the server before enabling:
```bash
sudo systemctl edit orchestrator-server.service
# Add under [Service]:
# Environment=SERVER_PSK=replace-with-strong-secret
```

## 6) Enable and start
Option A: one service for dev (server + UI)
```bash
sudo systemctl daemon-reload
sudo systemctl enable orchestrator-stack orchestrator-agent
sudo systemctl start  orchestrator-stack  orchestrator-agent
```

Option B: separate services
```bash
sudo systemctl daemon-reload
sudo systemctl enable orchestrator-server orchestrator-ui orchestrator-agent
sudo systemctl start  orchestrator-server  orchestrator-ui  orchestrator-agent
```

## 7) Verify
```bash
systemctl status orchestrator-server
systemctl status orchestrator-ui
systemctl status orchestrator-agent
journalctl -u orchestrator-server -f
```

Notes:
- The UI unit uses Vite dev server for convenience; for production, run `npm run build` and serve `ui/dist` via Nginx or `vite preview` in a separate service.
- The scripts handle venv/node_modules creation on first start.
- Set `SERVER_PSK` on the server and the same `psk` in the agent config.
