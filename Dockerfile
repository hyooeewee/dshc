# dshc — Dockerfile（多阶段，linux/amd64 + linux/arm64，默认硬化）
# 决策依据：wayfinder 地图 hyooeewee/dshc#1 ——
#   #2  seccomp：默认 seccomp 下 Landlock 沙箱可用（零额外权限），bwrap 需特权；保持默认硬化
#   #3  最小安装集：profile 三件套 + `pnpm install --prod --frozen-lockfile` 即可复现闭包（glibc→bookworm-slim）
#   #4  布局：/app 只读 · /data=DSH_HOME 状态卷 · /workspace 隔离工作区 · /tmp 可写；非 root uid1000 跑 `exec dsh --profile web`
# 模板 profile 已内部自洽：pnpm-workspace.yaml 设 minimumReleaseAge:0（容器自带策略，不追上游发版）

ARG NODE_VERSION=22
ARG PNPM_VERSION=11.22.0
# apt 镜像（默认 deb.debian.org 保公共仓库纯净；中国区本地构建可传 mirrors.aliyun.com / mirrors.tuna.tsinghua.edu.cn 等）
ARG APT_MIRROR=deb.debian.org

# ================= 阶段一：builder —— 构造锁定的依赖闭包 =================
FROM node:${NODE_VERSION}-bookworm-slim AS builder
ARG APT_MIRROR=deb.debian.org
# 原生模块(node-pty 等)在 multi-arch(QEMU) 下若预编译不可用则需本地编译
RUN for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do [ -f "$f" ] && sed -i "s|deb.debian.org|$APT_MIRROR|g" "$f"; done \
 && apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN npm install -g pnpm@${PNPM_VERSION}
WORKDIR /opt/dsh-tpl
COPY template/profile/ ./
# --prod：只装生产依赖；--frozen-lockfile：严格按锁文件，保证可复现
RUN pnpm install --prod --frozen-lockfile \
 && pnpm store prune

# ================= 阶段二：runtime —— 只读 + 非 root + 硬化 =================
FROM node:${NODE_VERSION}-bookworm-slim AS runtime
ARG APT_MIRROR=deb.debian.org
# 系统依赖：bash（DSH Linux bash 工具）· bubblewrap（备用/高级沙箱）·
# ca-certificates（HTTPS 出站到 api.deepseek.com 等）· curl（healthcheck）· tini（PID1 信号/优雅退出）
RUN for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do [ -f "$f" ] && sed -i "s|deb.debian.org|$APT_MIRROR|g" "$f"; done \
 && apt-get update \
 && apt-get install -y --no-install-recommends bash bubblewrap ca-certificates curl tini \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 1000 dsh

# 只读代码区（rootfs 交给 compose `read_only: true`）
WORKDIR /app
COPY --from=builder /opt/dsh-tpl ./template-profile
COPY overlay/ ./overlay/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 状态卷（数据根）与默认隔离工作区（compose/运行时挂载）
RUN mkdir -p /data /workspace && chown dsh:dsh /data /workspace
VOLUME ["/data", "/workspace"]
WORKDIR /data

# 非 root 用户；根文件系统只读的唯一可写点是 /data、/workspace、/tmp(tmpfs)
USER dsh
ENV DSH_HOME=/data \
    DSH_AGENTS_HOME=/data/agents \
    DSH_PERMISSION_MODE=workspace-write \
    DSH_TELEMETRY_DISABLED=1 \
    HOME=/data \
    PATH="/app/template-profile/node_modules/.bin:$PATH"
EXPOSE 3080

# 优雅退出 + 健康检查（DSH 进程自身处理 SIGTERM 5s 宽限）
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS -o /dev/null http://127.0.0.1:3080/ || exit 1

ENTRYPOINT ["tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]