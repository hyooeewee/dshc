#!/usr/bin/env bash
# Container entrypoint (tini is PID 1; this exec-replaces into DSH).
set -euo pipefail

# dsh CLI lives under node_modules/.bin, which is not on the slim-image PATH.
export PATH="/app/template-profile/node_modules/.bin:$PATH"

mkdir -p /data/agents

PROFILE_WEB="/data/profiles/web"
TPL="/app/template-profile"

if [ ! -f "$PROFILE_WEB/package.json" ]; then
  echo "[dshc] first boot: provisioning web profile from read-only template"
  mkdir -p "$PROFILE_WEB"
  # Copy the manifest set incl. the frozen lockfile so later `dsh plugin`
  # installs stay on the image's pinned closure; node_modules stays read-only
  # unless the user opts into a writable copy (DSH_ALLOW_PLUGIN_INSTALL=1).
  cp -a \
    "$TPL/package.json" "$TPL/pnpm-workspace.yaml" "$TPL/pnpm-lock.yaml" \
    "$TPL/cordis.yml" "$TPL/cordis.patch.yml" \
    "$PROFILE_WEB/"

  if [ "${DSH_ALLOW_PLUGIN_INSTALL:-0}" = "1" ]; then
    echo "[dshc] DSH_ALLOW_PLUGIN_INSTALL=1 -> copying node_modules into state volume (~380MB)"
    cp -a "$TPL/node_modules" "$PROFILE_WEB/node_modules"
  else
    # read-only symlink: the image closure IS the version; no runtime plugin install
    ln -s "$TPL/node_modules" "$PROFILE_WEB/node_modules"
  fi
else
  echo "[dshc] profile already present in state volume; reusing"
  # Re-add the symlink idempotently for read-only runs. DSH_ALLOW_PLUGIN_INSTALL
  # applies only on first boot; changing it later needs a /data volume reset.
  [ -d "$PROFILE_WEB" ] && [ ! -e "$PROFILE_WEB/node_modules" ] && ln -s "$TPL/node_modules" "$PROFILE_WEB/node_modules" || true
fi

# Informational sandbox readiness check. The launcher lives in the platform
# package (node-addon-landlock-run-linux-{x64,arm64}/bin), not the umbrella pkg.
case "$(uname -m)" in
  x86_64) L_ARCH="x64" ;;
  aarch64|arm64) L_ARCH="arm64" ;;
  *) L_ARCH="x64" ;;
esac
LANDLOCK="$PROFILE_WEB/node_modules/@deepseek-ai/node-addon-landlock-run-linux-$L_ARCH/bin/landlock-run"
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
exec node --expose-internals /app/template-profile/node_modules/@deepseek-ai/dsh/lib/bin.js --profile web --patch "$OVERLAY" "$@"
