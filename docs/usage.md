# 运行手册（dshc）

## 环境变量（容器运行时）

| 变量 | 说明 |
|---|---|
| `DEEPSEEK_API_KEY` | LLM 凭证（bootstrap 变量，只能经 env 注入） |
| `DEEPSEEK_BASE_URL` | 可选，自定义 LLM 端点（默认 `https://api.deepseek.com`） |
| `DSH_PERMISSION_MODE` | `workspace-write`(默认) / `danger-full-access`（仅容器内） |

> 遥测：compose 固定注入 `DSH_TELEMETRY_DISABLED=1`（上游默认开；该变量是单向开关，任何非空值都关闭）。想开遥测需删除 compose.yml 里那一行。

## 密钥注入

```bash
# 宿主的 .env（已被 .gitignore 排除），compose 自动透传给容器
cat >> .env <<'EOF'
DEEPSEEK_API_KEY=sk-...
EOF
docker compose up -d --build
```

DSH 会把 `DEEPSEEK_API_KEY` 当默认凭证使用；也可改在状态卷预置 `.credentials.yaml`（DSH 原生凭证机制）。

## .env 参数（构建与运行）

项目根目录的 `.env`（已 gitignore，模板见 [.env.example](../.env.example)）由 compose 自动读取，无需再传 `--build-arg`：

| 变量 | 默认 | 说明 |
|---|---|---|
| `APT_MIRROR` / `NPM_REGISTRY` | 上游官方源 | 慢网络时切国内镜像（**构建期**生效） |
| `DSHC_PORT` | `3080` | 宿主侧 GUI 端口（始终只绑本机回环；dshc 无内置认证，见 [security](security.md)） |
| `DSH_PERMISSION_MODE` | `workspace-write` | 容器内 agent 权限模式 |

构建参数改动后需重新 `docker compose build`；运行参数 `docker compose up -d` 重启即生效。

## 插件：运行时安装

镜像只含官方 in-box 闭包。装外挂插件走 DSH 原生机制（pnpm 装进状态卷的 profile 目录，持久、需网络）：

```bash
docker compose exec dshc dsh plugin --profile web add <package>
```

> 注意：本方案已无「模板复制」与 `DSH_ALLOW_PLUGIN_INSTALL` 开关（#11 决议移除）；profile 由 DSH 首次启动自动初始化。

## 升级 DSH（重建镜像）

版本钉子的位置：

| 钉什么 | 在哪 | 谁来校验 |
|---|---|---|
| DSH 版本 | `install/package.json` 的 `dependencies` | 锁文件冻结 |
| pnpm 版本 | `install/package.json` 的 `packageManager` 字段 | corepack 自动取用 |
| Node 大版本 | `install/package.json` 的 `engines.node` + Dockerfile 顶部 `NODE_VERSION` | 安装时不匹配即警告；FROM 标签无法读 manifest，两者需同步改 |

升级 = 改对应字段 → 重新生成锁文件（`cd install && pnpm install --prod --lockfile-only`）→ `docker compose build` → 重起。`minimumReleaseAge:0` 使其不因线上刚发布的版本而失败。

> 从旧版升级到本版：请先 `docker compose down -v` 重置状态卷。两类旧卷都会失效（预期行为）：template/ 三件套时代的卷列着已移除的社区包，新镜像会因解析失败拒绝启动；官方闭包初版（`DSH_HOME=/data`）的卷，数据在 `/data/profiles/` 等顶层路径，而本版 harness home 回归上游默认 `~/.dsh` = `/data/.dsh`——旧数据不会被读到，DSH 会当作全新状态重新初始化。

## 远程访问

默认 `localhost:3080` 仅本机。远程三种选择：
- **SSH 隧道**（推荐，零新增服务）：`ssh -L 3080:127.0.0.1:3080 user@host`，再访问本地 `http://127.0.0.1:3080`。
- **cloudflared 快速隧道**：需先安装提供该能力的外挂插件（见「插件」章节）。
- **反向代理**：Nginx/Caddy + TLS（+ basic auth），并给 DSH 加 `--trusted-host`。

## 排障

- `docker compose logs -f dshc` — 看启动日志与 `[dshc] sandbox:` 自检行。
- `docker compose exec dshc dsh --profile web --dump-config` — dump 构成树；确认 `webserver.config.host=0.0.0.0` 已应用。
- 沙箱不可用：确认宿主内核 `CONFIG_SECURITY_LANDLOCK=y` 且 `CONFIG_LSM` 含 `landlock`；或需 bwrap 时用 `--security-opt seccomp=unconfined`+非特权 userns，并自行在容器内安装 bwrap（镜像默认未内置，高级）。
- 端口没通：确认 `docker compose ps` 里 `127.0.0.1:3080->3080` 已列出；别把容器内绑定误当作覆盖层未生效。
- 状态没持久：`docker compose down` 不删卷；`docker compose down -v` 才会删 `/data`。

## headless 一次性模式（CI 友好）

镜像 entrypoint 默认引导 **web** profile（并带 0.0.0.0 覆盖层），所以跑 headless 需**覆写 entrypoint** 才能进入 headless 引导。DSH 要求 `node --expose-internals`（cordis loader/HMR 使用；NODE_OPTIONS 禁止该 flag，只能作为 execArgv），所以直接调 bin.js：

```bash
docker compose run --rm --entrypoint "node --expose-internals" dshc \
  /app/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js --profile headless "你的任务"
```

无监听端口、跑完退出——方便脚本化/CI。
