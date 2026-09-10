#!/usr/bin/env bash
set -euo pipefail

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# DSH resolves its home from $DSH_HOME, else $HOME/.dsh. setpriv does not reset
# these (unlike runuser), so pin both to the dsh user's home explicitly.
export HOME=/home/dsh
export DSH_HOME=/home/dsh/.dsh

chown -R "${PUID}:${PGID}" /home/dsh 2>/dev/null || true

# First-boot preference seed
SETTINGS=/home/dsh/.dsh/settings.yaml
if [ ! -f "$SETTINGS" ]; then
  mkdir -p "${SETTINGS%/*}"
  touch "$SETTINGS"
  case "${DSHC_LOCALE:-}" in
    zh|en) printf 'locale:\n  preference: %s\n' "$DSHC_LOCALE" >> "$SETTINGS" ;;
  esac
  case "${DSHC_THEME:-}" in
    light|dark|system) printf 'ui-theme:\n  preference: %s\n' "$DSHC_THEME" >> "$SETTINGS" ;;
  esac
fi

OVERLAY=/app/overlay/webstartup.yml
[ -f "$OVERLAY" ] || { echo "[dshc] ERROR: overlay missing" >&2; exit 1; }

TRUSTED_HOSTS="${DSHC_TRUSTED_HOSTS:-}"
TRUSTED_ARGS=""
if [ -n "$TRUSTED_HOSTS" ]; then
  for host in $(echo "$TRUSTED_HOSTS" | tr ',' ' '); do
    TRUSTED_ARGS="$TRUSTED_ARGS --trusted-host $host"
  done
fi

echo "[dshc] applying overlay: bind 0.0.0.0:3080 via --patch $OVERLAY"
echo "[dshc] starting: node --expose-internals dsh bin.js --profile web --patch $OVERLAY"

AUTH_FILE="/home/dsh/.dsh/.web-auth"
# Pre-create the auth token file owned by PUID/PGID so the unprivileged DSH/GUI
# process can read it back for auto-login (root still writes the token below).
touch "$AUTH_FILE"
chown "${PUID}:${PGID}" "$AUTH_FILE" 2>/dev/null || true

# Run the main process as PUID/PGID. setpriv uses numeric IDs directly, so no
# /etc/passwd entry is required for the target user.
exec setpriv --reuid "$PUID" --regid "$PGID" --clear-groups node --expose-internals /app/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js --profile web --patch "$OVERLAY" $TRUSTED_ARGS "$@" 2>&1 \
  | stdbuf -oL tee >(stdbuf -oL grep -oE 'token=[A-Za-z0-9_\-]+' | head -1 > "$AUTH_FILE")
