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

- Lancer l'agent (utilise `agent/config.example.yaml`):
```bash
chmod +x scripts/run-agent.sh
scripts/run-agent.sh
```

Alternative automatisée (recommandé pour la prod ou plusieurs hôtes): voir la section « Installateurs (one-shot) » ci‑dessous pour utiliser `scripts/install-server.sh` (serveur+UI) et `scripts/install-agent.sh` (agent sur chaque VM).


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

Pour créer une règle dédiée avec `visudo` (recommandé):

```bash
sudo visudo -f /etc/sudoers.d/orchestrator
```

Puis ajoutez la ligne suivante dans l'éditeur qui s'ouvre:

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

Pour automatiser l’installation, deux scripts sont fournis (avec prompts interactifs):
- Serveur + UI (sur la machine serveur):
```bash
curl -fsSL https://raw.github.com/Rem7474/FleetUpdate/main/scripts/install-server.sh -o install-server.sh
chmod +x install-server.sh
sudo ./install-server.sh
```
- Agent seul (à lancer sur chaque VM agent):
```bash
curl -fsSL https://raw.github.com/Rem7474/FleetUpdate/main/scripts/install-agent.sh -o install-agent.sh
chmod +x install-agent.sh
# Prompts: AGENT_ID, SERVER_URL et PSK (doit correspondre au SERVER_PSK du serveur)
sudo ./install-agent.sh
```
Les installateurs créent l’utilisateur `orchestrator`, déploient le code sous `/opt/orchestrator`, installent les prérequis, configurent systemd et démarrent les services.

### Ce que font précisément les installateurs
- Arrêt des services systemd avant mise à jour: `orchestrator-stack`, `orchestrator-server`, `orchestrator-ui`, `orchestrator-agent` (selon le script)
- Dépendances (Debian/Ubuntu): n’installent que les paquets manquants via `apt`.
	- Serveur: `python3-venv`, `nodejs`, `npm`, `git`, `ca-certificates`
	- Agent: `python3-venv`, `git`, `ca-certificates`
- Déploiement du code: mise à jour Git sur `/opt/orchestrator`
	- Si un repo existe: `git remote set-url origin`, `git fetch --prune --tags`, détection branche par défaut (`main`/`master`), `git checkout`, `git reset --hard origin/<branch>` ou `git pull --ff-only`
	- En cas d’erreur Git: nettoyage complet du répertoire (y compris fichiers cachés) puis `git clone --depth=1`
- Configuration serveur: création de `/opt/orchestrator/.env` si absent, avec un `SERVER_PSK` fort et variables UI à compléter
- Systemd: copie des unités, `daemon-reload`, `enable`, puis `restart`

### Ce qu’il faut configurer (obligatoire)
- Côté serveur (`/opt/orchestrator/.env`):
	- `SERVER_PSK`: secret partagé avec les agents (fort et privé)
	- `UI_USER`: identifiant de connexion UI (demandé pendant l’install)
	- `UI_PASSWORD` ou `UI_PASSWORD_HASH` (bcrypt) pour l’UI (demandé pendant l’install)
	- `JWT_SECRET`: secret de signature des JWT (généré si absent)
	- Exemple:
		```bash
		SERVER_PSK=remplacez-par-un-secret-fort
		UI_USER=admin
		UI_PASSWORD=motdepasse
		JWT_SECRET=$(openssl rand -hex 32)
		HOST=0.0.0.0
		```
	- Les unités systemd du serveur lisent automatiquement ce fichier via `EnvironmentFile=/opt/orchestrator/.env`.
- Côté agent (`/etc/orchestrator-agent/config.yaml`):
	- `agent.id`: identifiant unique de la VM (demandé pendant l’install si non fourni)
	- `agent.server_url`: URL du serveur (demandé pendant l’install si non fournie)
	- `agent.psk`: DOIT être identique à `SERVER_PSK` côté serveur (demandé pendant l’install)
	- Pré-remplissage non interactif possible via variables avant `install-agent.sh`:
		```bash
		export AGENT_ID=vm-01
		export SERVER_URL=http://<ip-serveur>:8000
		export AGENT_PSK=<même secret que SERVER_PSK>
		NO_PROMPT=1 sudo ./install-agent.sh
		```

### Démarrage et vérifications
```bash
sudo systemctl restart orchestrator-server orchestrator-agent || true

systemctl status orchestrator-server
systemctl status orchestrator-agent
journalctl -u orchestrator-server -f
```

### Déploiement (Production)
Construisez la UI (`npm run build`) et servez `ui/dist` via le serveur FastAPI sur un seul port. Placez un reverse-proxy (Nginx/Caddy) en frontal si nécessaire et routez `/api/ws` avec les en-têtes WebSocket.

Exemple Nginx (production, serveur unique UI+API+WS sur 8000):
```
server {
	server_name erpnext.remcorp.fr;
	listen 443 ssl;
	# ssl certs...

	# Route tout le trafic (UI + API + WebSocket /ws) vers le serveur FastAPI
	location / {
		proxy_pass http://<server-ip>:8000;
		proxy_set_header Host $host;
		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_http_version 1.1;
		# Autoriser l'upgrade WebSocket sans bloc dédié
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection $connection_upgrade;
	}
}
```

Notes:
- En production, ne servez pas le bundle UI directement depuis Nginx; laissez le serveur FastAPI monter `ui/dist` et gérez un seul port.

Exemple Caddy (production, serveur unique UI+API+WS sur 8000):
```
erpnext.remcorp.fr {
	reverse_proxy 127.0.0.1:8000 {
		header_up Host {host}
		header_up X-Real-IP {remote}
		header_up X-Forwarded-For {remote}
		# Upgrade WebSocket automatiquement
		header_up Connection {header.Connection}
		header_up Upgrade {header.Upgrade}
	}
}
```

### Problèmes fréquents et correctifs
- Login UI impossible:
	- Vérifiez `UI_USER`, `UI_PASSWORD`/`UI_PASSWORD_HASH` et `JWT_SECRET` dans `/opt/orchestrator/.env`, puis `sudo systemctl restart orchestrator-server`.
	- UI dev: si vous accédez via un hôte différent, ajoutez `ALLOWED_HOSTS` dans `ui/.env` et redémarrez `npm run dev`.
- Agent 401 sur `/api/heartbeat`:
	- PSK non aligné: `agent.psk` doit être égal à `SERVER_PSK`. Redémarrez serveur+agent.
	- Vérifiez l’URL d’API (`agent.server_url`) atteignable depuis la VM.
	- Logs utiles:
		```bash
		sudo cat /etc/orchestrator-agent/config.yaml
		sudo cat /opt/orchestrator/.env
		journalctl -u orchestrator-server -n 200 -f
		```
- Mise à jour Git échoue:
	- Les installateurs assurent `origin` → `REPO_URL`, font `fetch --prune --tags`, détectent la branche par défaut et `reset/pull`.
	- En cas d’échec, le répertoire est intégralement nettoyé puis recloné.
	- Pour diagnostiquer côté agent: `sudo VERBOSE=1 ./scripts/install-agent.sh 2>&1 | tee /tmp/agent-install.log`

### Variables utiles (récap)
- Serveur (`/opt/orchestrator/.env`): `SERVER_PSK`, `UI_USER`, `UI_PASSWORD` ou `UI_PASSWORD_HASH`, `JWT_SECRET`, `HOST`
- Agent (avant install): `AGENT_ID`, `SERVER_URL`, `AGENT_PSK`

## Déploiement via systemd (Linux)

Des unités prêtes à l’emploi sont fournies dans `infra/systemd/`:
- `orchestrator-server.service` (serve UI + API sur le même port)
- `orchestrator-agent.service`

1) Prérequis (Debian/Ubuntu)
```bash
sudo apt update
sudo apt install -y python3-venv
# si Python 3.12: sudo apt install -y python3.12-venv
sudo apt install -y nodejs npm
sudo apt install -y git ca-certificates
```

2) Créer l’utilisateur et déployer le code (via Git)
```bash
sudo useradd --system --create-home --home-dir /opt/orchestrator --shell /usr/sbin/nologin orchestrator || true
sudo mkdir -p /opt/orchestrator
sudo chown -R orchestrator:orchestrator /opt/orchestrator
sudo -u orchestrator git config --global --add safe.directory /opt/orchestrator || true
sudo -u orchestrator bash -lc '
	REPO_URL="https://github.com/Rem7474/FleetUpdate.git";
	if [ -d /opt/orchestrator/.git ]; then
		git -C /opt/orchestrator remote set-url origin "$REPO_URL";
		git -C /opt/orchestrator fetch --prune --tags;
		BR=$(git -C /opt/orchestrator remote show origin | awk "/HEAD branch/ {print \$NF}");
		git -C /opt/orchestrator checkout "$BR";
		git -C /opt/orchestrator reset --hard "origin/$BR";
	else
		rm -rf /opt/orchestrator/* /opt/orchestrator/.[!.]* /opt/orchestrator/..?* 2>/dev/null || true;
		git clone --depth=1 "$REPO_URL" /opt/orchestrator;
	fi
'
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
sudo tee /opt/orchestrator/.env > /dev/null <<'EOF'
SERVER_PSK=remplacez-par-un-secret-fort
UI_USER=admin
UI_PASSWORD=motdepasse
JWT_SECRET=$(openssl rand -hex 32)
HOST=0.0.0.0
EOF
sudo chown orchestrator:orchestrator /opt/orchestrator/.env
```
Les unités `orchestrator-server.service` lisent automatiquement ce fichier via `EnvironmentFile=/opt/orchestrator/.env`.

6) Construire la UI (production) et démarrer
```bash
cd /opt/orchestrator/ui; sudo -u orchestrator bash -lc 'npm ci || npm install; npm run build'
sudo systemctl daemon-reload
sudo systemctl enable orchestrator-server orchestrator-agent
sudo systemctl start  orchestrator-server  orchestrator-agent
```

Astuce: en mode non interactif, préparez vos variables avant l’install serveur pour éviter les prompts:
```bash
export UI_USER=admin
export UI_PASSWORD=motdepasse
export SERVER_PSK=$(openssl rand -hex 32)
export JWT_SECRET=$(openssl rand -hex 32)
NO_PROMPT=1 sudo ./install-server.sh
```

7) Vérifier
```bash
systemctl status orchestrator-server
systemctl status orchestrator-agent
journalctl -u orchestrator-server -f
```

Notes:
- Les scripts `scripts/run-*.sh` créent/réparent automatiquement les venvs et `node_modules` au premier démarrage.
- En production, l’UI est servie par le serveur FastAPI (bundle `ui/dist`) sur le même port que l’API.
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