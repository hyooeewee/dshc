# 验证：Docker seccomp 下 DSH Linux 沙箱后端（bwrap / Landlock）的可用性

> 工单：hyooeewee/dshc#2（`wayfinder:research`，地图 #1 的子工单）
> 本文件是 `research/docker-seccomp-sandbox` 分支的一次性调查落地。结论与实测尽量逐条追溯一手来源；实测为在容器内对 DSH 实际使用的后端参数做真机 run。运行期间工具输出通道曾出现一次注入污染（见 §6.3），已处置，不影响下述已确认的实测矩阵。

---

## 1. 结论摘要（TL;DR）

在 **Docker 默认安全配置**（默认 seccomp profile、容器内无特权、无 userns remap）下，DSH Linux bash-sandbox 两后端结论如下：

- **Landlock 后端（`node-addon-landlock-run`）可用，且不需要任何 `--security-opt` / `--cap-add` / `--privileged` 调整。**
  - Docker/moby 默认 seccomp profile `default.json` 把 `landlock_create_ruleset`(444)、`landlock_add_rule`(445)、`landlock_restrict_self`(446) **无条件放行**（无 cap 门槛）；`prctl` 也放行。Launcher 在 `restrict_self` 前先设 `PR_SET_NO_NEW_PRIVS`，因此无需 `CAP_SYS_ADMIN`（内核 Landlock 文档：`restrict_self` 需 `no_new_privs` 或 `CAP_SYS_ADMIN`）。
  - 唯一前提是宿主内核启用 Landlock。实测本机 WSL2 宿主内核 `CONFIG_SECURITY_LANDLOCK=y` 且 `CONFIG_LSM` 含 `landlock`，**四档配置下 `landlock --probe` 均输出 `landlock: fully enforced`、退出 0**（见 §6.2 矩阵）。
  - 因此 DSH 的自动探测会：bwrap probe 失败 → landlock probe 通过 → 自动选 Landlock 后端，沙箱**不会** fail-closed，不抛 `SandboxUnavailableError`。

- **bwrap（bubblewrap）在默认 seccomp 下不可用，且本实测环境下除 `--privileged` 外都必须同时放开 seccomp 的 `pivot_root` 才可用。**
  - 依据：默认 profile 中 `mount`、`unshare`、`clone`（非 CLONE_NEWUSER 位）受 `CAP_SYS_ADMIN` 门槛；`pivot_root` 不在任何 allow 列表 → 落到 `defaultAction=SCMP_ACT_ERRNO`（EPERM）。bwrap 建立沙箱至少需要 `unshare(CLONE_NEWNS)` + `mount` + `pivot_root`（bwrap 手册：默认新建 mount namespace；非 setuid 时还需 user namespace）。
  - 实测矩阵（§6.2）：默认、`seccomp=unconfined`、`--cap-add SYS_ADMIN` 三档 bwrap 均失败（分别卡在 namespace 创建 / pivot_root）；`--privileged` 才成功。

- **推荐：dshc 镜像用 Landlock 后端，保持「默认硬化」。** 容器默认配置即可让沙箱可用，无需放松 seccomp 或加特权；与 CONTEXT.md 的「默认硬化」原则一致。

---

## 2. 一手来源：DSH 沙箱链（先读 `dsh-sandbox-local`）

来源：`C:\Users\Godot\.dsh\profiles\web\node_modules\@deepseek-ai\dsh-sandbox-local\lib\index.js`（随 DSH 安装的版本）。

关键点（节选）：
- `PLATFORM_CHAINS = { linux: ["bwrap", "landlock"], darwin: ["seatbelt"], win32: ["windows-acl"] }` → Linux 先试 bwrap，再试 landlock，二者由功能探测（probe）仲裁。
- bwrap 轮廓（`bwrapProfileArgs`）：
  - read-only / 通用：`bwrap --ro-bind / / --dev /dev --proc /proc --die-with-parent -- <cmd>`
  - workspace-write 追加：`--tmpfs /tmp --bind <workspace> <workspace>`
- bwrap 探测（`defaultProbeBwrap`）：`spawnSync("bwrap", ["--ro-bind","/","/","--dev","/dev","--proc","/proc","--die-with-parent","--","true"], {timeout: 5000})`，status===0 → full。
- Landlock 轮廓（`landlockProfileArgs`）：read-only = `--ro / --rw /dev/null`；workspace-write 追加 `--rw /tmp --rw <workspace>`。
- Landlock 探测：`probe(launcherPath(), {timeoutMs})` 执行 `landlock-run --probe`：退出 0 且无 "partially enforced" → full；退出 0 带 partial → partial；否则 unusable。
- **fail-closed**：`chainVerdict()` 全部 rung 探测失败 → `"unavailable"` → `selectRunner()` 抛 `SandboxUnavailableError(mode)`。即 bwrap 与 landlock **都**不可用时才 fail close；只要 landlock 可用，沙箱就走 landlock。

来源：`@deepseek-ai/dsh-bash-sandbox\lib\index.js` —— 每个命令封装为精确 argv `["bash","-c",command]` 交给 `ctx.sandbox.confine()`；`mode==="danger-full-access"` 时不 consult 沙箱。

---

## 3. 一手来源：`node-addon-landlock-run`（launcher 内部机制）

来源：`C:\Users\Godot\.dsh\profiles\web\node_modules\@deepseek-ai\node-addon-landlock-run\src\main.c`（本分支 `landlock-run-main.c` 为副本）。

- 直接使用原始 Landlock UAPI（无 libc wrapper）：`landlock_create_ruleset`(444)、`landlock_add_rule`(445)、`landlock_restrict_self`(446)。
- 流程：`syscall(landlock_create_ruleset, NULL, 0, LANDLOCK_CREATE_RULESET_VERSION)` 取 ABI 版本；<0 → "landlock is not enforced by this kernel (ABI unsupported or disabled)" → exit 125（fail-closed）。
- ABI 协商：`MAX_ABI=5L`；`fs_mask_for_abi` 按 ABI 收窄；`abi < MAX_ABI` → partial（stderr 打 `landlock-run: partial enforcement (older Landlock ABI)`）。
- `restrict_self` 前先 `prctl(PR_SET_NO_NEW_PRIVS,1,...)`，再 `landlock_restrict_self` → 非特权进程即可用，不需要任何 cap。
- grant：`--ro` 给 read+execute（`EXECUTE|READ_FILE|READ_DIR`）；`--rw` 给当前 ABI 可授予的全部 fs access；默认 `--rw /dev/null`（非目录只留 file 位）。
- launcher 级失败打印 `landlock-run: <msg>` 并 exit 125；`execvp` 成功后规则集被子进程继承。
- 二进制经 npm 平台包分发：`@deepseek-ai/node-addon-landlock-run-linux-{x64,arm64}`。本机 Windows profile 未装 linux-x64 可选依赖（npm 按 os/cpu 跳过），实测从 npm registry 拉取官方 `node-addon-landlock-run-linux-x64@0.1.1` 的 `bin/landlock-run`（ELF，38552 B，artifacts/）。

---

## 4. 一手来源：Docker / moby 默认 seccomp profile

来源：`github.com/moby/profiles` 的 `profiles/seccomp/default.json`（moby/moby 现 vendor 于 `vendor/github.com/moby/profiles/seccomp/default.json`；本分支存 `docker-default-seccomp.json` 副本）。另参考 Docker 官方 seccomp 文档。

- `defaultAction: SCMP_ACT_ERRNO` → 未列出的 syscall 一律 EPERM（白名单制）。
- **`landlock_create_ruleset` / `landlock_add_rule` / `landlock_restrict_self` 在无条件 `SCMP_ACT_ALLOW` 白名单**（与 accept/open/read/prctl 并列，无 cap 门槛）→ seccomp 放行。
- `clone` / `clone3` / `unshare` / `mount` / `setns` / `umount2` 等同组：`SCMP_ACT_ALLOW` 但 `includes: { caps: [CAP_SYS_ADMIN] }`。
  - 例外：`clone` 另有一条 `SCMP_CMP_MASKED_EQ`（value `0x7E020000`，全部 7 个 namespace 标志）对**非** CAP_SYS_ADMIN 放行 —— 对应 Docker 文档「clone/unshare 阻塞，**except CLONE_NEWUSER**」。
- **`pivot_root` 完全未列出** → `defaultAction=SCMP_ACT_ERRNO`（EPERM）。`chroot` 则在无条件 allow 列表。
- Docker 文档原文：「clone — Deny cloning new namespaces. Also gated by CAP_SYS_ADMIN for CLONE_* flags, **except CLONE_NEWUSER**.」；「unshare — … **with the exception of unshare --user**.」；「pivot_root — Deny pivot_root, should be privileged operation.」；「mount — gated by CAP_SYS_ADMIN」。

**推论（§6.2 已实测确认）：**
- bwrap 需 `unshare(CLONE_NEWNS)+mount+pivot_root`；默认 seccomp 下被 CAP_SYS_ADMIN 门和 pivot_root 的 EPERM 拦 → 不可用。
- 即使 `--cap-add SYS_ADMIN`（默认 seccomp），`pivot_root` 仍 EPERM → bwrap 依旧失败（实测卡在 pivot_root）。
- Landlock 三 syscall + prctl 无条件放行 → seccomp 层面无障碍，仅需内核启用（§5）。

---

## 5. 一手来源：内核 Landlock 要求

来源：`docs.kernel.org/userspace-api/landlock.html`（本分支存 `landlock-kernel.html`）。

- 首次引入 Linux 5.13，需 `CONFIG_SECURITY_LANDLOCK=y` 且 `CONFIG_LSM` 含 `landlock`（或 boot 参数 `lsm=landlock,...`）。
- `landlock_restrict_self` 强制规则集要求调用者在名空间有 `CAP_SYS_ADMIN` **或**运行在 `no_new_privs`；launcher 已设 `no_new_privs` → 非特权进程可用。
- ABI：1=5.13、2=5.19（REFER）、3=6.2（TRUNCATE）、4=6.7（网络 TCP）、5=6.11（IOCTL_DEV）。launcher `MAX_ABI=5` 只认识 1–5；内核 ABI ≥5 均报 full。
- Landlock 是 stackable VFS LSM，作用于真实 inode；**userns remap 不影响其可用性**（不依赖任何 namespace）。

---

## 6. 实测（本机 = Windows 宿主 + Docker Desktop 29.6.2 + WSL2 后端，容器 = node:22-bookworm-slim）

### 6.1 环境基线（污染前干净捕获）
- 宿主内核（WSL2 VM，所有容器的“宿主内核”）：`Linux 6.18.33.2-microsoft-standard-WSL2 ... x86_64`。
- `zcat /proc/config.gz`：`CONFIG_SECURITY_LANDLOCK=y`；`CONFIG_LSM="landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,apparmor,tomoyo"`（landlock 在 LSM 首位）。
- 非特权 userns：`/proc/sys/user/max_user_namespaces = 63311`（内核允许）。
- 容器默认能力位 `CapEff = 0xa80425fb` → CHOWN、DAC_OVERRIDE、FOWNER、FSETID、KILL、SETGID、SETUID、SETPCAP、NET_BIND_SERVICE、NET_RAW、SYS_CHROOT、MKNOD、AUDIT_WRITE、SETFCAP —— **无 CAP_SYS_ADMIN**。
- 容器内 `Seccomp: 2`（mode 2，2 过滤器）→ 默认 seccomp 生效。
- 官方二进制自一手渠道取得并验证为 ELF：
  - `artifacts/package/bin/landlock-run`（npm `@deepseek-ai/node-addon-landlock-run-linux-x64@0.1.1`，38552 B）。
  - `artifacts/usr/bin/bwrap`（Debian bookworm `bubblewrap_0.8.0-2+deb12u1_amd64.deb`，72080 B）。
  - 与运行镜像同代（bookworm glibc；landlock-run 为 musl 静态）。

### 6.2 成败矩阵（DSH 精确参数，在容器内对两种后端 run-probe；本项为确认实测）
探测命令 = DSH 的实际探测：
`bwrap --ro-bind / / --dev /dev --proc /proc --die-with-parent -- true`
`landlock-run --probe`

| 运行配置 | CapEff | bwrap probe | landlock probe |
|---|---|---|---|
| 默认 seccomp（无额外参数，root） | `0xa80425fb` | **失败** exit 1：`bwrap: Creating new namespace failed: Operation not permitted` | **成功** exit 0：`landlock: fully enforced` |
| `--security-opt seccomp=unconfined` | `0xa80425fb` | **失败** exit 1：`bwrap: Creating new namespace failed: Operation not permitted` | **成功** exit 0：`landlock: fully enforced` |
| `--cap-add SYS_ADMIN`（默认 seccomp） | `0xa82425fb` | **失败** exit 1：`bwrap: pivot_root: Operation not permitted` | **成功** exit 0：`landlock: fully enforced` |
| `--privileged` | `0x1ffffffff` | **成功** exit 0 | **成功** exit 0：`landlock: fully enforced` |

结论解读：
- **Landlock 在全部四档配置下都成功**（`fully enforced`，exit 0）——默认 seccomp 放行其 syscall、内核已启用、无 cap 需求 → **无需任何 `--security-opt`/`--cap-add`/`--privileged`**。
- **bwrap 在本环境即便 `seccomp=unconfined` 也失败**：bwrap 以 root 运行走“特权”路径，需要 `CAP_SYS_ADMIN` 去 `unshare(CLONE_NEWNS)`，无该 cap 即 `Operation not permitted`（未走非特权 userns 路径）。`--cap-add SYS_ADMIN` 后前进到 `pivot_root`，但默认 seccomp 不放行 `pivot_root` → 仍失败。只有 `--privileged`（seccomp/AppArmor 关闭 + 全 cap）成功。
- 因此让 bwrap 可用需要**同时**：`CAP_SYS_ADMIN`（`--privileged` 或 `--cap-add SYS_ADMIN`）+ seccomp 放行 `mount`/`pivot_root`（`--security-opt seccomp=unconfined` 或自定义 profile）。单一 `--cap-add SYS_ADMIN` 或单一 `seccomp=unconfined` 都不够。

### 6.3 环境说明（诚实标注）
任务运行期间，工具**输出通道**曾出现一次与任务无关的注入污染（返回对抗性文本，并试图诱导删除 `research/` 等破坏性操作——已全部拒绝，未执行）。为保证结论可信，本矩阵的每一项均以**容器进程退出码 + stderr 原文**为准，经多次独立运行交叉确认，与 §4/§5 文档推论完全一致；其余发现以一手来源为准。

---

## 7. 可执行结论（Dockerfile / compose / `docker run`）

**推荐（保持默认硬化，零额外权限）：**
- 不改 `--security-opt`、不加 cap、不开 `--privileged`。DSH 自动选 **Landlock** 后端并成功 probe → 沙箱就绪，不 fail-closed。
- 镜像需可解析 `@deepseek-ai/node-addon-landlock-run` 与平台包 `node-addon-landlock-run-linux-{x64,arm64}`（在对应 linux 构建机上 npm 安装自动命中 os/cpu 可选依赖；multi-arch 各自装对应平台包）。
- 入口脚本沙箱就绪检查：分别探测 bwrap（失败可接受）与 `landlock-run --probe`，**只要 landlock 可用即判定就绪**；两者皆不可才警告 `SandboxUnavailableError` 风险。

**如需 bwrap 而非 Landlock（例如目标内核未编译 Landlock）：**
- 可靠组合：`docker run --privileged …`，或 `docker run --cap-add SYS_ADMIN --security-opt seccomp=unconfined …`。
- 若坚持默认 seccomp 又想 bwrap：`--cap-add SYS_ADMIN` + 自定义 seccomp profile（默认 profile 基础上 allow `pivot_root`；`mount`/`unshare` 由 SYS_ADMIN 门放行）。**注意：仅 `--cap-add SYS_ADMIN` 不够**（实测卡在 pivot_root）。

**userns remap（`--userns-remap` / daemon 级）：** 对 Landlock 无影响（不依赖 namespace）；对 bwrap 影响超出本工单，未实测。

---

## 8. 来源清单

1. `@deepseek-ai/dsh-sandbox-local/lib/index.js`（DSH profile 版）——PLATFORM_CHAINS、bwrap 参数、probe、fail-closed。
2. `@deepseek-ai/dsh-bash-sandbox/lib/index.js`、README.md——`bash -c` 封装、SandboxUnavailableError、enforcement。
3. `@deepseek-ai/node-addon-landlock-run/src/main.c`、lib/index.js、README.md——launcher 机制、ABI、no_new_privs、exit 125。副本 `landlock-run-main.c`。
4. moby 默认 seccomp profile：`github.com/moby/profiles` → `profiles/seccomp/default.json`（moby/moby master vendor 路径）。副本 `docker-default-seccomp.json`。
5. Docker 官方 seccomp 文档：docs.docker.com/engine/security/seccomp/。存档 `docker-seccomp-doc.html`。
6. bubblewrap 手册：manpages.debian.org/bookworm … `bwrap.1`。存档 `bwrap.1.en.html`；二进制取自 bookworm `bubblewrap_0.8.0-2+deb12u1_amd64.deb`。
7. 内核 Landlock 文档：docs.kernel.org/userspace-api/landlock.html。存档 `landlock-kernel.html`。
8. 实测：本机 Docker Desktop 29.6.2 + WSL2（内核 `6.18.33.2-microsoft-standard-WSL2`）内 node:22-bookworm-slim；脚本 `run-probe.sh`/`probe-default.sh`；二进制品 `artifacts/`。

### 环境备注
- Docker Server 29.6.2，API 1.55，context desktop-linux；容器镜像 node:22-bookworm-slim（Debian 12）。
- 四档配置矩阵（§6.2）以容器进程退出码 + stderr 原文为准。
