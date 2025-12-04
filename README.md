# FleetUpdate — Orchestrateur GitOps Multi-VM (MVP)

Outil centralisé, modulaire et sécurisé pour superviser et automatiser des déploiements applicatifs sur un parc de VMs via une architecture pull-only, sans ports entrants.

## Monorepo
- `server/`: API FastAPI + SQLite (control plane)
- `agent/`: Agent Python (heartbeat + exécution commandes basique)
- `ui/`: Dashboard React (Vite)
- `shared/`: Utilitaires HMAC et schémas de protocole
- `infra/`: Scripts/dev compose (optionnel)
- `docs/`: Architecture, sécurité

## Démarrage rapide (Linux / macOS)

Prérequis: Python 3.11+, Node 18+

- Debian/Ubuntu (prérequis rapides):
```bash
sudo apt update
# venv pour Python (selon version installée)
sudo apt install -y python3-venv
# ou si votre Python est 3.12: sudo apt install -y python3.12-venv
# Node.js + npm (paquets distro; pour LTS récent, voir NodeSource)
sudo apt install -y nodejs npm
```

- Lancer le Stack (Server + UI ensemble):
```bash
chmod +x scripts/run-stack.sh
scripts/run-stack.sh
```
- Lancer l'agent (utilise `agent/config.example.yaml`):
```bash
chmod +x scripts/run-agent.sh
scripts/run-agent.sh
```

Alternative automatisée (recommandé pour la prod ou plusieurs hôtes): voir la section « Installateurs (one-shot) » ci‑dessous pour utiliser `scripts/install-server.sh` (serveur+UI) et `scripts/install-agent.sh` (agent sur chaque VM).

Accès UI: `http://localhost:5173` (proxy `/api` → `http://localhost:8000`).

## Sécurité (MVP)
- Auth Agent↔Serveur: HMAC-SHA256 via `PSK` partagé (en-têtes `X-Agent-Id` et `X-Signature`).
- Auth UI (serveur): JWT avec utilisateur unique (env `UI_USER`/`UI_PASSWORD` ou `UI_PASSWORD_HASH` + `JWT_SECRET`).
- PSK de dev: `changeme` (remplacez via `SERVER_PSK`).
- TLS/mTLS non activé dans l'exemple (prévoir reverse-proxy en prod).

Exemple variables d'environnement (serveur):
```bash
export SERVER_PSK="remplacez-par-un-secret-fort"
export UI_USER="admin"
export UI_PASSWORD="motdepasse"   # ou UI_PASSWORD_HASH=bcrypt:$2b$...
export JWT_SECRET="jeton-secret"
```

Sudoers pour upgrade OS sur agents (exemple):
```
orchestrator ALL=(root) NOPASSWD:/usr/bin/apt
```

## Fonctionnalités clés (implémentées)
- Dashboard: statut OS (nombre de MAJ), badge sudo, filtres Tous/Obsolètes, recherche, actions Sudo check/Upgrade.
- VM détail: terminal temps réel (SSE) pour upgrade + alerte sudoers.
- Temps réel: WebSocket `/api/ws` pour mises à jour agents (réduction du polling).
- Commandes: file d'attente + streaming logs (SSE) + résultats.
- Métriques (MVP): `/api/metrics` (uptime, taux succès commandes 100 dernières, drift=0 placeholder).

Consultez `docs/ARCHITECTURE.md` et `docs/SECURITY.md` pour les détails.

## Installateurs (one-shot)

Pour automatiser l’installation, deux scripts sont fournis:
- Serveur + UI (sur la machine serveur):
```bash
curl -fsSL https://raw.githubusercontent.com/Rem7474/FleetUpdate/main/scripts/install-server.sh -o install-server.sh
chmod +x install-server.sh
sudo ./install-server.sh
```
- Agent seul (à lancer sur chaque VM agent):
```bash
curl -fsSL https://raw.githubusercontent.com/Rem7474/FleetUpdate/main/scripts/install-agent.sh -o install-agent.sh
chmod +x install-agent.sh
# Variables optionnelles pour personnaliser la config agent
export AGENT_ID=vm-01
export SERVER_URL=http://<ip-serveur>:8000
export AGENT_PSK=<psk-identique-au-serveur>
sudo ./install-agent.sh
```
Les installateurs créent l’utilisateur `orchestrator`, déploient le code sous `/opt/orchestrator`, installent les prérequis, configurent systemd et démarrent les services.

## Déploiement via systemd (Linux)

Des unités prêtes à l’emploi sont fournies dans `infra/systemd/`:
- `orchestrator-stack.service` (stack dev: Server + UI)
- `orchestrator-server.service`, `orchestrator-ui.service`, `orchestrator-agent.service`

1) Prérequis (Debian/Ubuntu)
```bash
sudo apt update
sudo apt install -y python3-venv
# si Python 3.12: sudo apt install -y python3.12-venv
sudo apt install -y nodejs npm
```

2) Créer l’utilisateur et déployer le code
```bash
sudo useradd --system --create-home --home-dir /opt/orchestrator --shell /usr/sbin/nologin orchestrator || true
sudo mkdir -p /opt/orchestrator
sudo rsync -a --delete . /opt/orchestrator/
sudo chown -R orchestrator:orchestrator /opt/orchestrator
```

3) Configurer l’agent
```bash
sudo mkdir -p /etc/orchestrator-agent
sudo cp /opt/orchestrator/agent/config.example.yaml /etc/orchestrator-agent/config.yaml
sudo chown -R orchestrator:orchestrator /etc/orchestrator-agent
# Éditez /etc/orchestrator-agent/config.yaml:
# - agent.id: identifiant unique de la VM
# - agent.server_url: URL du serveur (ex: http://<IP>:8000)
# - agent.psk: DOIT correspondre à SERVER_PSK côté serveur
```

4) Installer les services
```bash
cd /opt/orchestrator/infra/systemd
sudo cp orchestrator-*.service /etc/systemd/system/
# Ajustez WorkingDirectory= si votre chemin diffère
```

5) Variables d’environnement serveur (sécurité)
```bash
sudo systemctl edit orchestrator-server.service
# Ajoutez sous [Service] (une ligne par variable):
# Environment=SERVER_PSK=remplacez-par-un-secret-fort
# Environment=UI_USER=admin
# Environment=UI_PASSWORD=motdepasse
# Environment=JWT_SECRET=un-jeton-secret
```

6) Démarrer
- Option A (stack + agent):
```bash
sudo systemctl daemon-reload
sudo systemctl enable orchestrator-stack orchestrator-agent
sudo systemctl start  orchestrator-stack  orchestrator-agent
```
- Option B (services séparés):
```bash
sudo systemctl daemon-reload
sudo systemctl enable orchestrator-server orchestrator-ui orchestrator-agent
sudo systemctl start  orchestrator-server  orchestrator-ui  orchestrator-agent
```

7) Vérifier
```bash
systemctl status orchestrator-server
systemctl status orchestrator-ui
systemctl status orchestrator-agent
journalctl -u orchestrator-server -f
```

Notes:
- Les scripts `scripts/run-*.sh` créent/réparent automatiquement les venvs et `node_modules` au premier démarrage.
- Pour la prod UI, préférez `npm run build` et servez `ui/dist` via un reverse-proxy (Nginx/Caddy) plutôt que le serveur Vite de dev.
- Ouvrez/routez les ports nécessaires (API `8000`, UI dev `5173`) ou placez un reverse-proxy en frontal.

## Variables d’environnement

Fichier `.env` (chargé par les scripts) côté serveur:
```
SERVER_PSK=secret-partagé-entre-serveur-et-agents
UI_USER=admin
UI_PASSWORD=motdepasse
JWT_SECRET=jeton-secret
HOST=0.0.0.0
```
Copiez `/.env.example` vers `/.env` puis adaptez.

Overrides côté agent (avant `install-agent.sh`):
```
AGENT_ID=vm-01
SERVER_URL=http://<ip-serveur>:8000
AGENT_PSK=<même PSK que le serveur>
```