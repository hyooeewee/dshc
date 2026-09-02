# syntax=docker/dockerfile:1
# Multi-arch (amd64/arm64) hardened image for DSH.
ARG APT_MIRROR=deb.debian.org
ARG NPM_REGISTRY=https://registry.npmjs.org

# ---- builder: resolve the packed closure ----
FROM node:24-bookworm-slim AS builder
ARG APT_MIRROR
ARG NPM_REGISTRY
ENV DEBIAN_FRONTEND=noninteractive npm_config_registry=$NPM_REGISTRY

RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked --mount=type=cache,target=/var/cache/apt,sharing=locked \
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do [ -f "$f" ] && sed -i "s|deb.debian.org|$APT_MIRROR|g" "$f"; done \
  && apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ cmake ca-certificates

WORKDIR /opt/install
COPY install/ ./
COPY dist/npm /opt/dist/npm
COPY dist/npm-vendor /opt/dist/npm-vendor
COPY dist/npm-landlock /opt/dist/npm-landlock

RUN npm ci --omit=dev --no-audit --no-fund \
  && npm cache clean --force

# ---- runtime: minimal hardened image ----
FROM node:24-bookworm-slim AS runtime
ARG APT_MIRROR
ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked --mount=type=cache,target=/var/cache/apt,sharing=locked \
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do [ -f "$f" ] && sed -i "s|deb.debian.org|$APT_MIRROR|g" "$f"; done \
  && apt-get update \
  && apt-get install -y --no-install-recommends tini ca-certificates \
  && useradd --create-home --uid 10001 dsh \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /opt/install/node_modules ./dsh/node_modules
COPY overlay/ ./overlay/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN mkdir -p /home/dsh/.dsh /home/dsh/workspace && chown dsh:dsh /home/dsh/.dsh /home/dsh/workspace
VOLUME ["/home/dsh/.dsh"]
WORKDIR /home/dsh/workspace
USER dsh

ENV PATH="/app/dsh/node_modules/.bin:$PATH" \
    npm_config_store_dir=/home/dsh/.dsh/pnpm-store

EXPOSE 3080
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3080/').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]