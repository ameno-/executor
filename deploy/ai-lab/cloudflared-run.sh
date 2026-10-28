#!/usr/bin/env bash
# Start the Executor Cloudflare Tunnel. Token: op reference first, then 0600 file.
# Refuses to start if neither exists. The token is never printed.
set -euo pipefail
OP_REF="${EXECUTOR_TUNNEL_OP_REF:-op://ai-dev-secrets/cloudflare-tunnel-executor/token}"
FILE="${EXECUTOR_TUNNEL_TOKEN_FILE:-$HOME/.config/executor-selfhost/cloudflared.token}"
tok=""
if command -v op >/dev/null 2>&1; then tok="$(op read "$OP_REF" 2>/dev/null || true)"; fi
if [ -z "$tok" ] && [ -s "$FILE" ]; then tok="$(tr -d '[:space:]' < "$FILE")"; fi
if [ -z "$tok" ]; then
  echo "no tunnel token: neither $OP_REF nor $FILE is available" >&2
  exit 78
fi
export TUNNEL_TOKEN="$tok"
exec /usr/bin/cloudflared tunnel --no-autoupdate run
