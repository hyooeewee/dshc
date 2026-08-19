#!/usr/bin/env bash
# dshc — 容器入口（tini 为 PID1，本脚本经 exec 变为 PID2 的 DSH 进程）
set -euo pipefail

# ---------- 状态卷就绪 ----------
mkdir -p /data/agents

# ---------- 首启：初始化 web profile（模板 → 状态卷） ----------
PROFILE_WEB="/data/profiles/web"
TPL="/app/template-profile"

if [ ! -f "$PROFILE_WEB/package.json" ]; then
  echo "[dshc] first boot: provisioning web profile from read-only template"
  mkdir -p "$PROFILE_WEB"
  # 清单文件复制进状态卷（可被 DSH 热写：cordis.patch.yml、package.json、HMR）
  cp -a "$TPL/package.json" "$TPL/pnpm-workspace.yaml" "$TPL/cordis.yml" "$TPL/cordis.patch.yml" "$PROFILE_WEB/"

  if [ "${DSH_ALLOW_PLUGIN_INSTALL:-0}" = "1" ]; then
    echo "[dshc] DSH_ALLOW_PLUGIN_INSTALL=1 -> copying node_modules into state volume (writable, ~380MB)"
    cp -a "$TPL/node_modules" "$PROFILE_WEB/node_modules"
  else
    # 默认：node_modules 只读符号链接指向镜像内闭包 → 镜像即版本、不可运行时装插件
    ln -s "$TPL/node_modules" "$PROFILE_WEB/node_modules"
  fi
  # 已随包安装的皮肤配置由镜像提供；真实用户配置留在状态卷（.credentials.yaml 等）
else
  echo "[dshc] profile already present in state volume; reusing"
  # 若用户此前以只读模式启动，状态卷里没有 node_modules —— 补一个符号链接（幂等）
  [ -d "$PROFILE_WEB" ] && [ ! -e "$PROFILE_WEB/node_modules" ] && ln -s "$TPL/node_modules" "$PROFILE_WEB/node_modules" || true
fi

# ---------- 沙箱就绪自检（信息性；#2：默认 seccomp 下 Landlock 可用） ----------
if [ -x "$PROFILE_WEB/node_modules/@deepseek-ai/node-addon-landlock-run/bin/landlock-run" ]; then
  "$PROFILE_WEB/node_modules/@deepseek-ai/node-addon-landlock-run/bin/landlock-run" --probe >/dev/null 2>&1 && \
    echo "[dshc] sandbox: Landlock available (fallback chain bwrap→landlock)" || \
    echo "[dshc] sandbox: landlock probe failed — check host kernel (CONFIG_SECURITY_LANDLOCK) / seccomp"
fi

# ---------- 0.0.0.0 显式放行（DSH CLI 拒绝 --host 0.0.0.0，这里用 loader patch 覆盖 webserver 行） ----------
OVERLAY=/app/overlay/webstartup.yml
[ -f "$OVERLAY" ] && echo "[dshc] applying overlay: bind 0.0.0.0:3080 via --patch $OVERLAY" || { echo "[dshc] ERROR: overlay missing" >&2; exit 1; }

# ---------- 以 DSH 用户 exec 启动（保持 SIGTERM 优雅退出） ----------
echo "[dshc] starting: dsh --profile web --patch $OVERLAY"
exec dsh --profile web --patch "$OVERLAY" "$@"