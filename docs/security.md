# 安全边界与加固（dshc）

## 容器边界是信任线

默认**零宿主暴露**：容器内 agent 的一切能力（`workspace-write`/`danger-full-access` 文件权限、bash 执行、后台任务、SSH）都发生在容器边界内，宿主不可见、不可写。**穿透边界的只有三处显式通道**：

1. **端口映射** — compose 默认 `127.0.0.1:3080:3080`，只暴露本机 localhost。
2. **卷挂载** — 默认只有状态卷 `/data`。**挂宿主工作目录会穿透边界**（agent 的 `danger-full-access` 可经挂载点写宿主文件），只在你有意、知情、自担风险时做，且建议只读挂载。
3. **出站网络** — LLM API、web_search、SSH 插件等按需出站；通配放行。

**注意**：容器内的 `danger-full-access` 模式不等于宿主 root——它只让 agent 写满 *容器内* 的文件系统。真正扩大影响面的是「宿主目录挂载」。

## 加固清单（compose 默认值）

- `read_only: true` — rootfs 只读；唯一可写点 `/data`、`/workspace`、`/tmp`(tmpfs)。
- 非 root 用户 uid 10001 `dsh` 运行。
- `cap_drop: ALL` + 补回常规默认 cap（不额外提权）。
- `security_opt: no-new-privileges:true`。
- 保留默认 seccomp；**不为沙箱放松**（#2：Landlock 在默认 seccomp 下即可用）。
- `pids_limit / mem_limit / cpus` 资源上限。
- tini PID1 + STOPSIGNAL SIGTERM（DSH 5s 优雅退出）+ HEALTHCHECK。

## 沙箱（Linux）

DSH 在 Linux 用 **bash** 模式，命令经 `bash -c` 交给沙箱：后端链 `bwrap → landlock`，按探测自动回退。默认 seccomp 下 **Landlock** 生效（三个 landlock syscall 无条件放行 + no_new_privs），**bwrap 用不了**（`unshare/mount/pivot_root` 被拦）。若目标机内核未启用 `CONFIG_SECURITY_LANDLOCK=y` 且 LSM 含 `landlock`，Landlock 会不可用——那是唯一需要评估宿主内核的点。日志可通过 `docker logs` 看 `[dshc] sandbox:` 自检行。

## 密钥

- `DEEPSEEK_API_KEY` 等 DEEPSEEK_* 变量是 DSH 的 bootstrap 变量，**禁止写 `.env`**；经环境变量（`docker compose` 的 `environment:` / `--env-file`）注入，最好放宿主 `.env` 并 gitignore。
- `dsh-ssh.json`（含明文密码）由 dsh-ssh 插件写进 `/data` 状态卷 → 备份/权限要当凭证对待。
- 仓库是 public：**不要在任何 issue/工单/提交里写密钥**（地图 #1 Notes 已写明）。

## 认证与远程访问

容器**无内置认证**。默认只效力于本机 localhost。需要远程访问时，用 **SSH 隧道**、**cloudflared 快速隧道**（dsh-remote-web-ui 插件）或**反向代理 + basic auth**，并配 `--trusted-host`；不要把 3080 直接映射到公网。

## 插件与镜像版本

默认镜像闭包**不可在运行时装插件**（`node_modules` 只读符号链接）——镜像即版本。要装插件：开 `DSH_ALLOW_PLUGIN_INSTALL=1`（状态卷复制，可持久）或改模板重建镜像。这减少了镜像被运行时篡改的可写面，是一层安全选择。
