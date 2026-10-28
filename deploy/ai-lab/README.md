# Executor Self-Host (`ai-lab`)

Self-hosted Executor deployment listening on `127.0.0.1:4788` (`container_name: executor-selfhost`, built from `apps/host-selfhost/Dockerfile`).

## Files

- `docker-compose.yml` — runs `executor-selfhost` bound to `127.0.0.1:4788` with secrets in `~/.config/executor-selfhost/env` (`0600`) and SQLite/blob storage in `~/.local/share/executor-selfhost` (`0700`).
- `.env.sample` — required variable names for `~/.config/executor-selfhost/env` (never commit secret values).
- `cli-key.sh` — headless bootstrap script that signs in as the seeded bootstrap admin (`POST /api/auth/sign-in/email`), mints a personal API key (`POST /api/account/api-keys`), and writes it to `~/.config/executor-selfhost/cli-key` (`0600`, `umask 077`) without printing or passing secrets on `argv`.
- `cloudflared-run.sh` & `executor-cloudflared.service` — user systemd unit for the Cloudflare Tunnel (`op://ai-dev-secrets/cloudflare-tunnel-executor/token` or `~/.config/executor-selfhost/cloudflared.token`).

## Minting a CLI / MCP API key without a browser

```bash
./deploy/ai-lab/cli-key.sh
```

The minted key is written to `~/.config/executor-selfhost/cli-key` (`0600`) and authenticates both `/api/*` and `/mcp` via `Authorization: Bearer <key>` (or `x-api-key: <key>`).

- Repo v1 CLI (`apps/cli`):
  ```bash
  EXECUTOR_API_KEY="$(cat ~/.config/executor-selfhost/cli-key)" \
    bun run --cwd apps/cli src/main.ts --base-url http://127.0.0.1:4788 sources
  ```
- Global v2 CLI (`executor@2.0.0-beta.27`): `executor apps` targets the Executor v2 app-management API (`/api/apps` with `EXECUTOR_API_KEY` on loopback, or `/api/organizations/<org>/apps` with `EXECUTOR_ACCESS_TOKEN` and `--organization`), which is served by v2 (`apps/hosted/self-host` / `apps/local/server` on the `v2` branch), not by the v1 `apps/host-selfhost` image on `main`.

## Reaching internal Docker services (`http://nasir-live-gateway-1:6580`)

Outbound tool fetches run inside the `executor-selfhost` container's `bun` process (`packages/core/sdk/src/hosted-http-client.ts`). Non-TLS `http://` URLs are allowed on self-host, but single-label hostnames and RFC 1918 / Docker bridge IPs are blocked by default unless `EXECUTOR_ALLOW_LOCAL_NETWORK=true` is set in `~/.config/executor-selfhost/env` in addition to attaching `executor-selfhost` to the shared Docker network.

## MCP for Claude Code

`executor-selfhost` serves Streamable HTTP MCP at `http://127.0.0.1:4788/mcp` (and org-prefixed `http://127.0.0.1:4788/default/mcp` or `<EXECUTOR_WEB_BASE_URL>/mcp`), accepting either `Authorization: Bearer <api-key>` (from `~/.config/executor-selfhost/cli-key`) or interactive MCP OAuth 2.1 (`/.well-known/oauth-protected-resource`).
