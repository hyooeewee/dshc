#!/usr/bin/env bash
# Container entrypoint (tini is PID 1; this exec-replaces into DSH).
#
# No profile provisioning happens here: on first boot DSH auto-initializes its
# built-in web profile (manifest + user patch layer + pnpm workspace) under
# ~/.dsh/profiles/web and heals the module-fallback symlink closure from the
# installation at /app/dsh/node_modules (verified against deepseek-harness
# app-boot sources, dshc#11). The state volume only needs to be writable.
set -euo pipefail

# First-boot preference seed. DSH has no env var or CLI flag for UI
# preferences; they persist in the Host settings document instead. Seed it
# only when absent — afterwards the file belongs to the user's GUI edits and
# must never be rewritten here.
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

# Informational sandbox readiness check. The launcher lives in the platform
# package (node-addon-landlock-run-linux-{x64,arm64}/bin), not the umbrella pkg.
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

# DSH rejects --host 0.0.0.0 by design; the loader patch overrides the
# webserver row instead, binding 0.0.0.0 so `docker -p` can reach the GUI.
OVERLAY=/app/overlay/webstartup.yml
[ -f "$OVERLAY" ] || { echo "[dshc] ERROR: overlay missing" >&2; exit 1; }
echo "[dshc] applying overlay: bind 0.0.0.0:3080 via --patch $OVERLAY"

# DSH needs node --expose-internals (cordis-plugin-hmr/loader read the internal
# loader; NODE_OPTIONS forbids the flag, so it must be passed as execArgv).
echo "[dshc] starting: node --expose-internals dsh bin.js --profile web --patch $OVERLAY"
exec node --expose-internals /app/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js --profile web --patch "$OVERLAY" "$@"
