# FleetUpdate Architecture (MVP)

- Server (FastAPI): Control plane, SQLite (SQLModel), HMAC verification, JWT pour UI.
- Agent (Python): Heartbeat + exécution de commandes + upgrade OS + sudo check.
- UI (Vite React): Dashboard, VM detail avec terminal temps réel.

## Lancement
Le serveur et l'UI sont lancés ensemble par défaut via `scripts/run-stack.sh` ou `infra/systemd/orchestrator-stack.service`. Les agents se connectent en pull-only.

## Communication
- Agent → Serveur: Heartbeat + résultats de commandes signés HMAC (PSK)
- Serveur → Agent: Polling `next-command` (pull) pour récupérer la prochaine commande
- Logs temps réel: SSE `/api/commands/{cid}/stream` (agent pousse des chunks via `POST /api/command-chunk`)
- UI push: WebSocket `/api/ws` (broadcast `agent_update`)

## Authentification
- Agents: PSK/HMAC sur chaque payload
- UI: JWT (utilisateur unique serveur) via `/api/auth/login`, token dans `Authorization: Bearer` (et `?token=` pour SSE/WS)

## Endpoints (MVP)
- `GET /api/health`
- `GET /api/agents` (JWT)
- `GET /api/agents/{id}` (JWT)
- `POST /api/heartbeat` (HMAC)
- `POST /api/command-result` (HMAC)
- `POST /api/agents/{id}/commands` (JWT)
- `GET /api/agents/{id}/next-command` (HMAC)
- `POST /api/command-chunk` (HMAC)
- `GET /api/commands/{cid}/stream` (JWT)
- `GET /api/ws?token=...` (JWT)
- `GET /api/metrics` (JWT) — uptime, taux succès commandes (100 dernières), drift=0
- `POST /api/agents/{id}/sudo-check` (JWT)

## Flow
1. Agent charge YAML, collecte état apps + os_update (sudo_apt_ok), envoie heartbeat signé.
2. Serveur vérifie HMAC, upsert Agent, stocke état + os_update et broadcast WebSocket.
3. UI consomme WebSocket pour mises à jour live et utilise SSE pour logs de commandes.

## Extensibilité
- Desired state (Git), drift réel, rollback.
- RBAC, audit log, mTLS derrière reverse-proxy.