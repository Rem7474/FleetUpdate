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