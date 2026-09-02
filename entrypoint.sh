#!/usr/bin/env bash
set -euo pipefail

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

# Sandbox readiness check
case "$(uname -m)" in
  x86_64) L_ARCH="x64" ;;
  aarch64|arm64) L_ARCH="arm64" ;;
  *) L_ARCH="x64" ;;
esac
LANDLOCK="/app/dsh/node_modules/@deepseek-ai/node-addon-landlock-run-linux-$L_ARCH/bin/landlock-run"
if [ -x "$LANDLOCK" ]; then
  if "$LANDLOCK" --probe >/dev/null 2>&1; then
    echo "[dshc] sandbox: Landlock available (fallback chain bwrap->landlock)"
  else
    echo "[dshc] sandbox: landlock probe failed — check host kernel (CONFIG_SECURITY_LANDLOCK) / seccomp"
  fi
else
  echo "[dshc] sandbox: launcher not found at $LANDLOCK"
fi

wslpath() {
  node -e '
    const p = process.argv[1];
    // /mnt/c/... -> C:\...
    if (/^\/mnt\/([a-z])\/(.*)$/.test(p)) {
      const [, drive, rest] = p.match(/^\/mnt\/([a-z])\/(.*)$/);
      console.log(drive.toUpperCase() + ":\\" + rest.replace(/\//g, "\\"));
    }
    // /home/... -> C:\home\... (WSL2 默认挂载点)
    else if (/^\/home\/(.*)$/.test(p)) {
      console.log("C:\\home\\" + p.slice(6).replace(/\//g, "\\"));
    }
    // /root/... -> C:\root\...
    else if (/^\/root\/(.*)$/.test(p)) {
      console.log("C:\\root\\" + p.slice(6).replace(/\//g, "\\"));
    }
    // 其他按 /mnt/c 默认
    else {
      console.log("C:\\" + p.slice(1).replace(/\//g, "\\"));
    }
  ' "$1"
}
export -f wslpath

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

exec node --expose-internals /app/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js --profile web --patch "$OVERLAY" $TRUSTED_ARGS "$@" 2>&1 \
 | stdbuf -oL tee >(stdbuf -oL grep -oE 'token=[A-Za-z0-9_\-]+' | head -1 > "$AUTH_FILE")