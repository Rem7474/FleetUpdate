# FleetUpdate Security (MVP)

- Identity: `agent_id` per VM.
- Authentication: HMAC-SHA256 with PSK per agent (development uses a single PSK – replace with per-agent PSKs in production).
- Transport: Use TLS termination at reverse proxy; mTLS recommended for production.
- Principle of least privilege: run agent under a dedicated non-admin account; restrict shell environment.
- Audit: store deployment events, inputs, and outputs; immutable logs (future work).
 - UI Auth: JWT for UI endpoints with a single server-side user.

## HMAC
- Server expects headers: `X-Agent-Id`, `X-Signature` (hex of HMAC_SHA256(PSK, body)).
- Body is raw JSON bytes without whitespace changes.
- Server rejects if signature invalid or Agent ID mismatch.

## UI Authentication (JWT)
- Configure env on server:
	- `UI_USER` (default `admin`)
	- `UI_PASSWORD` (plaintext dev) or `UI_PASSWORD_HASH` (bcrypt) pour la prod
	- `JWT_SECRET` (secret pour signer les tokens)
- Login: `POST /api/auth/login` → `{ token }`
- Usage: `Authorization: Bearer <token>` pour toutes les routes UI
- SSE/WS: ajouter `?token=<token>` aux URLs `/api/commands/{cid}/stream` et `/api/ws`

## Sudoers (agents)
- Pour permettre les upgrades sans mot de passe, ajouter par exemple:
```
orchestrator ALL=(root) NOPASSWD:/usr/bin/apt
```
- L’agent vérifie `sudo -n apt -v` et remonte `sudo_apt_ok` dans le heartbeat.
