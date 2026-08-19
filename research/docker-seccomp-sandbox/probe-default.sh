#!/bin/bash
# DSH 沙箱后端在 Docker 默认 seccomp 下的探测脚本（容器内运行）
# 镜像: node:22-bookworm-slim；需先 apt 安装 bubblewrap 与 gcc 并编译 landlock-run
set -x

echo "===== [env] ====="
uname -r
grep -E 'CapEff|Seccomp' /proc/self/status

echo "===== [bwrap] DSH 精确探测命令（read-only 轮廓） ====="
bwrap --ro-bind / / --dev /dev --proc /proc --die-with-parent -- true
echo "bwrap probe exit: $?"

echo "===== [bwrap] read-only 轮廓真实执行 ====="
bwrap --ro-bind / / --dev /dev --proc /proc --die-with-parent -- bash -c 'echo confined-readonly-ok; touch /tmp/x 2>&1; echo touch-exit=$?'
echo "bwrap readonly exit: $?"

echo "===== [bwrap] workspace-write 轮廓（--tmpfs /tmp --bind /ws /ws） ====="
mkdir -p /ws
bwrap --ro-bind / / --dev /dev --proc /proc --die-with-parent --tmpfs /tmp --bind /ws /ws -- bash -c 'echo hi > /ws/f; cat /ws/f'
echo "bwrap workspace-write exit: $?"

echo "===== [landlock] probe（功能探测：建最大 ruleset 并 enforce） ====="
./landlock-run --probe
echo "landlock probe exit: $?"

echo "===== [landlock] read-only 轮廓真实执行（--ro / --rw /dev/null） ====="
./landlock-run --ro / --rw /dev/null -- bash -c 'echo landlock-readonly-ok; touch /tmp/x 2>&1; echo touch-exit=$?'
echo "landlock readonly exit: $?"

echo "===== [landlock] workspace-write 轮廓（--ro / --rw /dev/null --rw /tmp --rw /ws） ====="
./landlock-run --ro / --rw /dev/null --rw /tmp --rw /ws -- bash -c 'echo hi > /ws/f; cat /ws/f'
echo "landlock workspace-write exit: $?"