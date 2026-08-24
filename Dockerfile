# syntax=docker/dockerfile:1
# Multi-arch (amd64/arm64) hardened image for DSH. Decisions live in the
# wayfinder map hyooeewee/dshc#1.
#
# Build-knob panel — every ARG and its default lives here, once (network
# knobs are overridable via compose build.args / .env). Stages re-declare a
# bare `ARG <name>` to import; without that line a global ARG is empty inside
# the stage. Only NODE_VERSION feeds FROM directly.
# Toolchain pins live in install/package.json instead: `packageManager` pins
# pnpm (corepack reads it), `engines.node` fails the install on drift —
# NODE_VERSION stays an ARG only because FROM cannot read manifests.
ARG NODE_VERSION=22
ARG APT_MIRROR=deb.debian.org
ARG NPM_REGISTRY=https://registry.npmjs.org

# ---- builder: resolve the frozen dependency closure ----
FROM node:${NODE_VERSION}-bookworm-slim AS builder
ARG APT_MIRROR
ARG NPM_REGISTRY
# COREPACK_NPM_REGISTRY routes the pnpm CLI download through the same mirror;
# DOWNLOAD_PROMPT=0 keeps the first fetch non-interactive.
ENV DEBIAN_FRONTEND=noninteractive npm_config_registry=$NPM_REGISTRY \
    COREPACK_NPM_REGISTRY=$NPM_REGISTRY COREPACK_ENABLE_DOWNLOAD_PROMPT=0

# node-pty ships no prebuild -> node-gyp compiles it; git stays out because
# every dependency resolves from registry tarballs. Cache mounts make the apt
# metadata fetch one-time across builds (sharing=locked serializes stages).
RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked --mount=type=cache,target=/var/cache/apt,sharing=locked \
 for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do [ -f "$f" ] && sed -i "s|deb.debian.org|$APT_MIRROR|g" "$f"; done \
 && apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ ca-certificates
# corepack picks the pnpm version from install/package.json's packageManager.
RUN corepack enable

# The minimal manifest declares only @deepseek-ai/dsh: the frozen closure IS
# the installation; no out-of-tree plugins ship (#11).
WORKDIR /opt/install
COPY install/ ./
# minimumReleaseAge:0 keeps the install off freshly-published DSH releases.
RUN pnpm install --prod --frozen-lockfile \
 && pnpm store prune

# ---- runtime: hardened minimal image ----
FROM node:${NODE_VERSION}-bookworm-slim AS runtime
ARG APT_MIRROR
ENV DEBIAN_FRONTEND=noninteractive
# tini as PID 1 for signals/zombies; no bubblewrap — Landlock runs under
# default seccomp without privileges (#2). dsh takes uid 10001: uid 1000 is
# already `node` in the base image.
RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked --mount=type=cache,target=/var/cache/apt,sharing=locked \
 for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do [ -f "$f" ] && sed -i "s|deb.debian.org|$APT_MIRROR|g" "$f"; done \
 && apt-get update \
 && apt-get install -y --no-install-recommends tini ca-certificates \
 && useradd --create-home --uid 10001 dsh

WORKDIR /app
# Only the closure ships; manifests stay behind — DSH writes its own profile
# files into the state volume at runtime (#11).
COPY --from=builder /opt/install/node_modules ./dsh/node_modules
COPY overlay/ ./overlay/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# The harness state lives at the upstream-default ~/.dsh; compose mounts the
# named volume exactly there, and the workspace bind at ~/workspace. Both sit
# inside $HOME so every home-rooted UI surface sees them.
RUN mkdir -p /home/dsh/.dsh /home/dsh/workspace && chown dsh:dsh /home/dsh/.dsh /home/dsh/workspace
VOLUME ["/home/dsh/.dsh"]
WORKDIR /home/dsh/workspace
USER dsh
# HOME stays the image default (/home/dsh) — no override. Two mechanical
# additions only: PATH exposes the closure's binaries image-wide;
# npm_config_store_dir gives runtime pnpm runs (profile self-heal, plugin
# installs) a writable store on the state volume instead of the read-only
# rootfs default ~/.local/share/pnpm.
ENV PATH="/app/dsh/node_modules/.bin:$PATH" \
    npm_config_store_dir=/home/dsh/.dsh/pnpm-store

EXPOSE 3080
STOPSIGNAL SIGTERM
# GUI answers HTTP 200 once up; node's bundled fetch replaces curl.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3080/').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]
