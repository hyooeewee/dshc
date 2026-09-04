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

# Sandbox readiness check — use main package's launcherPath logic (handles missing optional deps)
LANDLOCK=$(node -e "
  const { createRequire } = require('node:module');
  const { dirname, join } = require('node:path');
  const { fileURLToPath } = require('node:url');
  const require = createRequire(import.meta.url);
  try {
    // Resolve main package, then use its launcherPath logic
    const mainPkg = require.resolve('@deepseek-ai/node-addon-landlock-run/package.json');
    const mainDir = dirname(mainPkg);
    // Dynamically import the launcherPath function from the main package
    const { launcherPath } = require(mainDir + '/lib/index.js');
    console.log(launcherPath());
  } catch (e) {
    console.log(''); // Not found
  }
" 2>/dev/null)

if [ -n "$LANDLOCK" ] && [ -x "$LANDLOCK" ]; then
  if "$LANDLOCK" --probe >/dev/null 2>&1; then
    echo "[dshc] sandbox: Landlock available"
  else
    echo "[dshc] sandbox: landlock probe failed (kernel/seccomp)"
  fi
else
  echo "[dshc] sandbox: landlock not available (optional dependency)"
fi

# Install wslpath to user-writable location
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/wslpath" <<'EOF'
#!/usr/bin/env node
const p = process.argv[2] || "";
if (/^\/mnt\/([a-z])\/(.*)$/.test(p)) {
  const [, drive, rest] = p.match(/^\/mnt\/([a-z])\/(.*)$/);
  console.log(drive.toUpperCase() + ":\\" + rest.replace(/\//g, "\\"));
} else if (/^\/home\/(.*)$/.test(p)) {
  console.log("C:\\home\\" + p.slice(6).replace(/\//g, "\\"));
} else if (/^\/root\/(.*)$/.test(p)) {
  console.log("C:\\root\\" + p.slice(6).replace(/\//g, "\\"));
} else {
  console.log("C:\\" + p.slice(1).replace(/\//g, "\\"));
}
EOF
chmod +x "$HOME/.local/bin/wslpath"
export PATH="$HOME/.local/bin:$PATH"

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