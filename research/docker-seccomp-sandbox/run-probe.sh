#!/bin/bash
# 通用探测：在给定容器安全配置下跑 bwrap 与 landlock 后端（DSH 精确参数）
# 用法: bash run-probe.sh <label>
set -u
LABEL="${1:-???}"
echo "################ PROBE [$LABEL] ################"
echo "== env =="
uname -r
grep -E 'CapEff|Seccomp' /proc/self/status
command -v bwrap && bwrap --version || echo "bwrap missing"
echo
echo "== [bwrap] DSH read-only 探测 (bwrap --ro-bind / / --dev /dev --proc /proc --die-with-parent -- true) =="
bwrap --ro-bind / / --dev /dev --proc /proc --die-with-parent -- true
echo "  bwrap-readonly-probe exit: $?"
echo
echo "== [bwrap] read-only 真实执行 =="
bwrap --ro-bind / / --dev /dev --proc /proc --die-with-parent -- bash -c 'echo confined-readonly-ok; touch /tmp/x 2>&1; echo touch-exit=$?'
echo "  bwrap-readonly-run exit: $?"
echo
echo "== [bwrap] workspace-write 轮廓 =="
mkdir -p /ws
bwrap --ro-bind / / --dev /dev --proc /proc --die-with-parent --tmpfs /tmp --bind /ws /ws -- bash -c 'echo hi >/ws/f; cat /ws/f'
echo "  bwrap-workspace-write exit: $?"
echo
echo "== [landlock] probe =="
/opt/landlock-run --probe
echo "  landlock-probe exit: $?"
echo
echo "== [landlock] read-only (--ro / --rw /dev/null) =="
/opt/landlock-run --ro / --rw /dev/null -- bash -c 'echo landlock-readonly-ok; touch /tmp/x 2>&1; echo touch-exit=$?'
echo "  landlock-readonly-run exit: $?"
echo
echo "== [landlock] workspace-write (--ro / --rw /dev/null --rw /tmp --rw /ws) =="
/opt/landlock-run --ro / --rw /dev/null --rw /tmp --rw /ws -- bash -c 'echo hi >/ws/f; cat /ws/f'
echo "  landlock-workspace-write exit: $?"
echo "################ END [$LABEL] ################"