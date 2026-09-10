# syntax=docker/dockerfile:1
# Multi-arch (amd64/arm64) hardened image for DSH.
ARG APT_MIRROR=deb.debian.org
ARG NPM_REGISTRY=https://registry.npmjs.org
ARG DIST_HASH=unknown
ARG DSH_TAG=unknown

# ---- builder: resolve the packed closure ----
FROM node:24-bookworm-slim AS builder
ARG APT_MIRROR
ARG NPM_REGISTRY
ENV DEBIAN_FRONTEND=noninteractive npm_config_registry=$NPM_REGISTRY

RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked --mount=type=cache,target=/var/cache/apt,sharing=locked \
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do [ -f "$f" ] && sed -i "s|deb.debian.org|$APT_MIRROR|g" "$f"; done \
  && apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ cmake ca-certificates

WORKDIR /buildspace
COPY package.json ./
COPY pnpm-lock.yaml ./
COPY dist/ ./dist/

RUN corepack enable \
  && pnpm clean --lockfile \
  && pnpm install --prod --ignore-scripts --update-checksums \
  && pnpm store prune

# ---- runtime: minimal hardened image ----
FROM node:24-bookworm-slim AS runtime
ARG APT_MIRROR
ARG DSH_TAG
ENV DEBIAN_FRONTEND=noninteractive \
    DSHC_BASE_VERSION=${DSH_TAG#dsh-v}

RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked --mount=type=cache,target=/var/cache/apt,sharing=locked \
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do [ -f "$f" ] && sed -i "s|deb.debian.org|$APT_MIRROR|g" "$f"; done \
  && apt-get update \
  && apt-get install -y --no-install-recommends tini ca-certificates util-linux \
  && useradd --create-home --uid 10001 dsh \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /buildspace/node_modules ./dsh/node_modules
COPY overlay/ ./overlay/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN mkdir -p /home/dsh/.dsh /home/dsh/workspace && \
    chown -R dsh:dsh /home/dsh/.dsh /home/dsh/workspace

ENV PATH="/app/dsh/node_modules/.bin:$PATH" \
    PNPM_HOME="/home/dsh/.dsh/pnpm" \
    PNPM_STORE_PATH="/home/dsh/.dsh/pnpm-store"

STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3080/').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

EXPOSE 3080
VOLUME ["/home/dsh/.dsh", "/home/dsh/workspace"]
WORKDIR /home/dsh/workspace

ENTRYPOINT ["tini", "-g", "--", "/entrypoint.sh"]