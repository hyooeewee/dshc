# syntax=docker/dockerfile:1
# Multi-arch (amd64/arm64) hardened build. Decisions tracked in the wayfinder
# map (hyooeewee/dshc#1): Landlock works under default seccomp so no privileged
# flags are added (#2); --prod --frozen-lockfile over the pinned closure keeps
# the image reproducible (#3); /app read-only, /data = DSH_HOME state volume,
# /workspace isolated (#4).
ARG NODE_VERSION=22
ARG PNPM_VERSION=11.22.0
# apt mirror (default upstream keeps the public repo clean; for throttled CN
# networks pass --build-arg APT_MIRROR=mirrors.aliyun.com)
ARG APT_MIRROR=deb.debian.org
# npm registry (default upstream; for slow CN networks pass
# --build-arg NPM_REGISTRY=https://registry.npmmirror.com)
ARG NPM_REGISTRY=https://registry.npmjs.org

FROM node:${NODE_VERSION}-bookworm-slim AS builder
ARG APT_MIRROR=deb.debian.org
ARG NPM_REGISTRY=https://registry.npmjs.org
ENV DEBIAN_FRONTEND=noninteractive npm_config_registry=$NPM_REGISTRY
# build toolchain so native modules (node-pty etc.) compile when a prebuild is
# unavailable under buildx/QEMU for arm64
RUN for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do [ -f "$f" ] && sed -i "s|deb.debian.org|$APT_MIRROR|g" "$f"; done \
 && apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN npm install -g pnpm@${PNPM_VERSION}
WORKDIR /opt/dsh-tpl
COPY template/profile/ ./
# The profile's own pnpm-workspace sets minimumReleaseAge:0 so the frozen
# install never trips on freshly-published DSH releases.
RUN pnpm install --prod --frozen-lockfile \
 && pnpm store prune

FROM node:${NODE_VERSION}-bookworm-slim AS runtime
ARG APT_MIRROR=deb.debian.org
ENV DEBIAN_FRONTEND=noninteractive
# bash for the DSH bash tool; bwrap as an opt-in sandbox fallback; curl for
# HEALTHCHECK; tini handles signals/reaping as PID 1; passwd provides useradd
# (UID 1000 is already `node` in this image, so use 10001 for the dsh user)
RUN for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do [ -f "$f" ] && sed -i "s|deb.debian.org|$APT_MIRROR|g" "$f"; done \
 && apt-get update \
 && apt-get install -y --no-install-recommends bash bubblewrap ca-certificates curl tini passwd \
 && rm -rf /var/lib/apt/lists/* \
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
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS -o /dev/null http://127.0.0.1:3080/ || exit 1

ENTRYPOINT ["tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]
