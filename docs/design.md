# 设计文档（dshc）

决策由 wayfinder 地图 [hyooeewee/dshc#1](https://github.com/hyooeewee/dshc/issues/1) 的三个设计工单（#2/#3/#4）拧成，此处为落地摘要。

## 边界条件（已锁定）

1. **平台**：Linux，`node:22-bookworm-slim`，amd64 + arm64 多架构（buildx）。DSH 在非 win32 用 bash 模式，无需 pwsh；glibc → 勿用 alpine。
2. **DSH 内容**：是可 npm 安装的依赖闭包，不是 git 源码。镜像只需 `install/` 的极简清单（`package.json` 只声明 `@deepseek-ai/dsh` 单一依赖 + `pnpm-workspace.yaml` + `pnpm-lock.yaml`），`pnpm install --prod --frozen-lockfile` 即可复现。公共 registry、匿名可解析、无需私钥。
   - 清单已内部自洽：`pnpm-workspace.yaml` 设 `minimumReleaseAge: 0`（容器自带策略，不追上游高频发版）、`autoInstallPeers: true`（peers 必须随装，否则启动 ERR_MODULE_NOT_FOUND）、原生模块 `allowBuilds` 审批白名单。
   - **镜像不预装任何外挂包**（#11）：DSH 内置 web profile 模板（dsh-base + dsh-web-app）从安装本体闭包即可解析；外挂插件运行时经 DSH 原生机制装入状态卷。
   - 体积实测（旧三件套含社区包时代）：node_modules ≈384MB / 37k 文件；纯官方闭包更小，待重测。**注意：node-pty 不含预编译（tarball 无 prebuilds/ 目录，需 node-gyp 从源码编译）→ builder 必须装 python3/make/g++（实测验证）**；koffi/sharp/landlock launcher 才有 prebuild。
3. **沙箱**（#2 结论）：默认 seccomp 下 **Landlock 可用、零额外权限**（三个 landlock syscall 无条件放行，launcher 用 no_new_privs）；bwrap 需特权级放行。DSH 自动回退 bwrap→landlock，不 fail-closed。compose 保留默认 seccomp、不去加特权。**镜像默认不内置 bwrap**（默认硬化完全走 Landlock；走 bwrap 属高级，需自行安装 + seccomp=unconfined）。入口就绪自检跑 `landlock-run --probe`。
4. **用户模型**：单用户单实例，无内置认证。
5. **网络**：出站全开（LLM API / web_search / SSH / cloudflared 按需）；入站仅 3080。容器内绑 0.0.0.0 由入口 `--patch overlay/webstartup.yml` 显式放行（DSH CLI 有意拒绝 `--host 0.0.0.0`）；宿主侧 compose 只映射 `127.0.0.1:3080:3080`。
6. **持久化**：无状态镜像 + 状态卷 `/data`（即容器 `$HOME`；所有点前缀路径均循上游默认——harness home `~/.dsh` = `/data/.dsh`，其下含 `profiles/`、`sessions/`、`settings.yaml`、`.credentials.yaml`、`storages/`、`skills/`、`dsh-ssh.json`；agents/skill 共享根 `~/.agents` = `/data/.agents`。不设任何 `DSH_*` 路径覆盖，容器内 AI 按官方文档即可定位全部配置）。**profile 无需预置**（#11）：DSH 首次启动自动初始化内置 web profile（manifest + 用户补丁层 + pnpm workspace）并从 `/app/dsh/node_modules` 治愈模块回退符号链接闭包；外挂插件运行时经 `dsh plugin add` 装入 profile 目录（持久、需网络）。遥测经 compose 注入 `DSH_TELEMETRY_DISABLED=1` 关闭（上游默认开）。
7. **加固**（默认硬化）：非 root（uid 10001 `dsh`）、`cap_drop: ALL` + 常规默认 cap 集合、`no-new-privileges`、保留默认 seccomp、`read_only: true` + `/tmp` tmpfs + `/data`、`/workspace` 两个可写点、资源限制（pids/mem/cpu）、tini PID1、HEALTHCHECK 探 3080、STOPSIGNAL SIGTERM（DSH 自带 5s 优雅退出）。

## 启动命令（已核实）

DSH CLI 规范形为 **`dsh --profile web`**；`dsh web` 是其硬编码等价别名（`@deepseek-ai/dsh/lib/bin.js`）。**容器入口用 `node --expose-internals .../dsh/lib/bin.js --profile web --patch /app/overlay/webstartup.yml`** —— DSH 的 cordis-loader/HMR 需要 `--expose-internals`（NODE_OPTIONS 禁止该 flag，只能作为 execArgv；缺失时 HMR loader entry 报错）。另有 `--dump-config`（排障）、`--trusted-host`（远端 /api trust fence）。

## 镜像内布局

| 路径 | 性质 | 说明 |
|---|---|---|
| `/app` | 只读 | 代码 + `dsh/node_modules`（安装本体闭包）+ `overlay/` |
| `/data` | 状态卷 | 容器 `$HOME`；harness home 即上游默认 `~/.dsh`（=`/data/.dsh`），`profiles/web` 由 DSH 首启自建 |
| `/workspace` | 匿名卷（默认隔离） | 未挂载宿主目录时随容器生命周期 |
| `/tmp` | tmpfs | DSH spill/临时文件（0700 私有） |

## 发布

- 目标 `ghcr.io/hyooeewee/dshc`（私有包）。
- 流水线 GitHub Actions（buildx 多架构）见 `.github/workflows/docker-build.yml`。
- 冒烟（#9）：GUI 可达、bash 工具在 Landlock 沙箱内、容器内 danger-full-access 不穿透宿主、重启卷持久、`dsh --profile headless` 可用。

## 范围之外（不实现）

多用户/多租户 · 内置认证 · 公开分发/许可核查 · egress 白名单 · Windows 容器 · k8s 编排 · DSH 本体功能（属上游）。
