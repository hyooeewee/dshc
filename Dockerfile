# syntax=docker/dockerfile:1
# Multi-arch (amd64/arm64) hardened build. Decisions tracked in the wayfinder
# map (hyooeewee/dshc#1): Landlock works under default seccomp so no privileged
# flags are added (#2); --prod --frozen-lockfile over the pinned closure keeps
# the image reproducible (#3); /app read-only, /data = DSH_HOME state volume,
# /workspace isolated (#4).
# Only NODE_VERSION is consumed by FROM, so it must stay global; every other
# ARG is used inside stages, where Docker only sees a value after an in-stage
# ARG declaration (a pre-FROM ARG is empty there, and PNPM_VERSION had to move
# in to actually pin the pnpm version).
ARG NODE_VERSION=22

FROM node:${NODE_VERSION}-bookworm-slim AS builder
ARG PNPM_VERSION=11.22.0
# apt mirror (default upstream; pass --build-arg APT_MIRROR=mirrors.aliyun.com
# for throttled networks)
ARG APT_MIRROR=deb.debian.org
# npm registry (default upstream; pass
# --build-arg NPM_REGISTRY=https://registry.npmmirror.com for slow networks)
ARG NPM_REGISTRY=https://registry.npmjs.org
ENV DEBIAN_FRONTEND=noninteractive npm_config_registry=$NPM_REGISTRY
# node-pty ships no prebuild (its tarball has no prebuilds/ dir and the prebuild
# fetch is unreliable), so node-gyp compiles it: python3/make/g++ are required.
# git stays out — the frozen install needs no git (dsh-browser is a recorded
# codeload tarball). ca-certificates guards the cloudflared postinstall.
# The apt cache mount keeps the 8MB metadata fetch one-time across builds;
# sharing=locked serializes the two parallel stages against the shared cache.
RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked --mount=type=cache,target=/var/cache/apt,sharing=locked \
 for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do [ -f "$f" ] && sed -i "s|deb.debian.org|$APT_MIRROR|g" "$f"; done \
 && apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ ca-certificates
RUN corepack enable && corepack prepare pnpm@${PNPM_VERSION} --activate
WORKDIR /opt/dsh-tpl
COPY template/profile/ ./
# minimumReleaseAge:0 in the workspace keeps the frozen install from tripping
# on freshly-published DSH releases.
RUN pnpm install --prod --frozen-lockfile \
 && pnpm store prune

FROM node:${NODE_VERSION}-bookworm-slim AS runtime
ARG APT_MIRROR=deb.debian.org
ENV DEBIAN_FRONTEND=noninteractive
# tini as PID 1 for signal/zombie handling; bash and useradd already ship in
# the base image. Node brings its own CA bundle; system ca-certificates is kept
# for non-node TLS consumers. bubblewrap is not installed: the sandbox runs on
# Landlock under default seccomp, and bwrap would need privileges anyway (#2).
RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked --mount=type=cache,target=/var/cache/apt,sharing=locked \
 for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do [ -f "$f" ] && sed -i "s|deb.debian.org|$APT_MIRROR|g" "$f"; done \
 && apt-get update \
 && apt-get install -y --no-install-recommends tini ca-certificates \
 && useradd --create-home --uid 10001 dsh

WORKDIR /app
COPY --from=builder /opt/dsh-tpl ./template-profile
COPY overlay/ ./overlay/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# state volume (DSH_HOME) + isolated workspace; mounted/composed at runtime
RUN mkdir -p /data /workspace && chown dsh:dsh /data /workspace
VOLUME ["/data", "/workspace"]
WORKDIR /data

# non-root; HOME under the state volume so dotfile-style writes survive
USER dsh
ENV DSH_HOME=/data \
    DSH_AGENTS_HOME=/data/agents \
    DSH_PERMISSION_MODE=workspace-write \
    DSH_TELEMETRY_DISABLED=1 \
    HOME=/data \
    PATH="/app/template-profile/node_modules/.bin:$PATH"
EXPOSE 3080

STOPSIGNAL SIGTERM
# node's built-in fetch (bundled CA) replaces curl; the GUI returns 200 once up
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3080/').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]