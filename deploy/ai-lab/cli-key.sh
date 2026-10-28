#!/usr/bin/env bash
# Mint a personal API key against the self-hosted Executor instance as the
# bootstrap admin without a browser, and write it to ~/.config/executor-selfhost/cli-key.
# Secrets are read only into process memory and temp files (0600); never printed or passed on argv.
set -euo pipefail
umask 077

ENV_FILE="${EXECUTOR_ENV_FILE:-$HOME/.config/executor-selfhost/env}"
OUT_FILE="${EXECUTOR_CLI_KEY_FILE:-$HOME/.config/executor-selfhost/cli-key}"
HOST="${EXECUTOR_HOST:-http://127.0.0.1:4788}"
KEY_NAME="${EXECUTOR_CLI_KEY_NAME:-ai-lab-cli}"

if [ -f "$ENV_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ""|\#*) continue ;;
      *=*)
        var="${line%%=*}"
        val="${line#*=}"
        if [[ "$val" == \"*\" && "$val" == *\" ]]; then
          val="${val:1:${#val}-2}"
        elif [[ "$val" == \'*\' && "$val" == *\' ]]; then
          val="${val:1:${#val}-2}"
        fi
        case "$var" in
          EXECUTOR_BOOTSTRAP_ADMIN_EMAIL|EXECUTOR_BOOTSTRAP_ADMIN_PASSWORD|EXECUTOR_WEB_BASE_URL)
            if [ -z "${!var:-}" ]; then
              export "$var=$val"
            fi
            ;;
        esac
        ;;
    esac
  done < "$ENV_FILE"
fi

if [ -z "${EXECUTOR_BOOTSTRAP_ADMIN_EMAIL:-}" ] || [ -z "${EXECUTOR_BOOTSTRAP_ADMIN_PASSWORD:-}" ]; then
  echo "missing EXECUTOR_BOOTSTRAP_ADMIN_EMAIL or EXECUTOR_BOOTSTRAP_ADMIN_PASSWORD (checked env and $ENV_FILE)" >&2
  exit 78
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# 1. Sign in as the seeded bootstrap admin (apps/host-selfhost/src/auth/better-auth.ts:137,171).
#    Credentials are read from jq's environment (never argv) and piped to curl stdin.
jq -n '{
  email: env.EXECUTOR_BOOTSTRAP_ADMIN_EMAIL,
  password: env.EXECUTOR_BOOTSTRAP_ADMIN_PASSWORD
}' | curl -fsS \
  -D "$tmpdir/headers" \
  -o "$tmpdir/signin.json" \
  -X POST \
  -H "Content-Type: application/json" \
  --data-binary @- \
  "${HOST%/}/api/auth/sign-in/email"

AUTH_TOKEN="$(awk 'tolower($1) == "set-auth-token:" { sub(/^[^:]+:[[:space:]]*/, ""); sub(/\r$/, ""); print; exit }' "$tmpdir/headers")"
if [ -z "$AUTH_TOKEN" ]; then
  AUTH_TOKEN="$(jq -r '.token // empty' "$tmpdir/signin.json")"
fi
if [ -z "$AUTH_TOKEN" ]; then
  echo "sign-in succeeded but no session token was returned" >&2
  exit 1
fi

# 2. Mint a personal API key via /api/account/api-keys
#    (apps/host-selfhost/src/account/better-auth-account-provider.ts:89-102).
printf 'header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n' "$AUTH_TOKEN" > "$tmpdir/curl.cfg"
unset AUTH_TOKEN

jq -n --arg name "$KEY_NAME" '{name: $name}' | curl -fsS \
  --config "$tmpdir/curl.cfg" \
  -o "$tmpdir/key.json" \
  -X POST \
  --data-binary @- \
  "${HOST%/}/api/account/api-keys"

mkdir -p "$(dirname "$OUT_FILE")"
jq -er '.value // .key' "$tmpdir/key.json" > "$tmpdir/cli-key"
if [ ! -s "$tmpdir/cli-key" ]; then
  echo "API key response did not contain a key value" >&2
  exit 1
fi

chmod 0600 "$tmpdir/cli-key"
mv -f "$tmpdir/cli-key" "$OUT_FILE"
chmod 0600 "$OUT_FILE"
