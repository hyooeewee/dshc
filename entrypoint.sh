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
  x86_64) L_PLATFORM="linux-x64" ;;
  aarch64|arm64) L_PLATFORM="linux-arm64" ;;
  *) L_PLATFORM="linux-x64" ;;
esac

# Try to find landlock-run via the package's launcherPath logic
LANDLOCK_PKG="/app/dsh/node_modules/@deepseek-ai/node-addon-landlock-run"
LANDLOCK=""
if [ -d "$LANDLOCK_PKG" ]; then
  # Use node to resolve the platform package path (same logic as landlock package)
  LANDLOCK=$(node -e "
    const { createRequire } = require('node:module');
    const { dirname, join } = require('node:path');
    const { fileURLToPath } = require('node:url');
    const require = createRequire(import.meta.url);
    try {
      const platformPackage = '@deepseek-ai/node-addon-landlock-run-${L_PLATFORM}';
      const pkgPath = require.resolve(platformPackage + '/package.json');
      console.log(join(dirname(pkgPath), 'bin', 'landlock-run'));
    } catch {
      console.log(fileURLToPath(new URL('../node_modules/@deepseek-ai/node-addon-landlock-run-'${L_PLATFORM}'/bin/landlock-run', import.meta.url)));
    }
  " 2>/dev/null)
fi

if [ -n "$LANDLOCK" ] && [ -x "$LANDLOCK" ]; then
  if "$LANDLOCK" --probe >/dev/null 2>&1; then
    echo "[dshc] sandbox: Landlock available (fallback chain bwrap->landlock)"
  else
    echo "[dshc] sandbox: landlock probe failed — check host kernel (CONFIG_SECURITY_LANDLOCK) / seccomp"
  fi
else
  echo "[dshc] sandbox: landlock launcher not found — skipping probe (optional dependency)"
fi

# Install wslpath as executable in PATH (for Node.js spawn)
cat > /usr/local/bin/wslpath <<'EOF'
#!/usr/bin/env node
const p = process.argv[2] || "";
// /mnt/c/... -> C:\...
if (/^\/mnt\/([a-z])\/(.*)$/.test(p)) {
  const [, drive, rest] = p.match(/^\/mnt\/([a-z])\/(.*)$/);
  console.log(drive.toUpperCase() + ":\\" + rest.replace(/\//g, "\\"));
}
// /home/... -> C:\home\... (WSL2 default mount point)
else if (/^\/home\/(.*)$/.test(p)) {
  console.log("C:\\home\\" + p.slice(6).replace(/\//g, "\\"));
}
// /root/... -> C:\root\...
else if (/^\/root\/(.*)$/.test(p)) {
  console.log("C:\\root\\" + p.slice(6).replace(/\//g, "\\"));
}
// default: treat as /mnt/c
else {
  console.log("C:\\" + p.slice(1).replace(/\//g, "\\"));
}
EOF
chmod +x /usr/local/bin/wslpath

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