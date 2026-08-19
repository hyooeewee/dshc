#!/usr/bin/env bash
# dshc — 容器入口（tini 为 PID1，本脚本经 exec 变为 PID2 的 DSH 进程）
set -euo pipefail

# dsh CLI 不在默认 PATH（node:bookworm-slim 无 node_modules/.bin），先补上
export PATH="/app/template-profile/node_modules/.bin:$PATH"

# ---------- 状态卷就绪 ----------
mkdir -p /data/agents

# ---------- 首启：初始化 web profile（模板 → 状态卷） ----------
PROFILE_WEB="/data/profiles/web"
TPL="/app/template-profile"

if [ ! -f "$PROFILE_WEB/package.json" ]; then
  echo "[dshc] first boot: provisioning web profile from read-only template"
  mkdir -p "$PROFILE_WEB"
  # 清单文件复制进状态卷（可被 DSH 热写：cordis.patch.yml、package.json 等）
  # 含冻结的 pnpm-lock.yaml，保证后续 `dsh plugin` 安装仍以镜像版本为准（--frozen 一致性）
  cp -a \
    "$TPL/package.json" "$TPL/pnpm-workspace.yaml" "$TPL/pnpm-lock.yaml" \
    "$TPL/cordis.yml" "$TPL/cordis.patch.yml" \
    "$PROFILE_WEB/"

  if [ "${DSH_ALLOW_PLUGIN_INSTALL:-0}" = "1" ]; then
    echo "[dshc] DSH_ALLOW_PLUGIN_INSTALL=1 -> copying node_modules into state volume (writable, ~380MB)"
    cp -a "$TPL/node_modules" "$PROFILE_WEB/node_modules"
  else
    # 默认：node_modules 只读符号链接指向镜像内闭包 → 镜像即版本、不可运行时装插件
    ln -s "$TPL/node_modules" "$PROFILE_WEB/node_modules"
  fi
else
  echo "[dshc] profile already present in state volume; reusing"
  # 默认只读模式下，若状态卷缺 node_modules 符号链接则补齐（幂等）。
  # 注意：DSH_ALLOW_PLUGIN_INSTALL 只在首启生效；改开关需清 /data 卷重建才会复制。
  [ -d "$PROFILE_WEB" ] && [ ! -e "$PROFILE_WEB/node_modules" ] && ln -s "$TPL/node_modules" "$PROFILE_WEB/node_modules" || true
fi

# ---------- 沙箱就绪自检（信息性；#2：默认 seccomp 下 Landlock 可用） ----------
# launcher 在平台专属可选包下（node-addon-landlock-run-linux-{x64,arm64}/bin/landlock-run）
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
  echo "[dshc] sandbox: launcher not found at $LANDLOCK (inspect node_modules layout)"
fi

# ---------- 0.0.0.0 显式放行（DSH CLI 拒绝 --host 0.0.0.0，用 loader patch 覆盖 webserver 行） ----------
OVERLAY=/app/overlay/webstartup.yml
[ -f "$OVERLAY" ] && echo "[dshc] applying overlay: bind 0.0.0.0:3080 via --patch $OVERLAY" || { echo "[dshc] ERROR: overlay missing" >&2; exit 1; }

# ---------- 以 dsh 用户 exec 启动（保持 SIGTERM 优雅退出） ----------
echo "[dshc] starting: dsh --profile web --patch $OVERLAY"
exec dsh --profile web --patch "$OVERLAY" "$@"