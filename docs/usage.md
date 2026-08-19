# 运行手册（dshc）

## 环境变量（容器运行时）

| 变量 | 说明 |
|---|---|
| `DEEPSEEK_API_KEY` | LLM 凭证（bootstrap 变量，只能经 env 注入） |
| `DEEPSEEK_BASE_URL` | 可选，自定义 LLM 端点（默认 `https://api.deepseek.com`） |
| `DSH_PERMISSION_MODE` | `workspace-write`(默认) / `danger-full-access`（仅容器内） |
| `DSH_ALLOW_PLUGIN_INSTALL` | `1` 则首启把 node_modules 复制进状态卷（可装插件） |
| `DSH_TELEMETRY_DISABLED` | 默认已 `1`（遥测默认关闭，双保险） |

## 密钥注入

```bash
# 宿主的 .env（已被 .gitignore 排除），compose 自动透传给容器
cat >> .env <<'EOF'
DEEPSEEK_API_KEY=sk-...
EOF
docker compose up -d --build
```

DSH 会把 `DEEPSEEK_API_KEY` 当默认凭证使用；也可改在状态卷预置 `.credentials.yaml`（DSH 原生凭证机制）。

## 插件：运行时安装

默认只读闭包不可装插件（`node_modules` 只读符号链接）。需要时：

```bash
# 该开关只在首次启动生效：在第一次 `up` 前设好，之后才会把 node_modules 复制进状态卷。
# 若已以默认模式启动过，需 `docker compose down -v`（清 /data 卷）再按此启动。
DSH_ALLOW_PLUGIN_INSTALL=1 docker compose up -d --build
# 进容器执行安装（示范）
docker compose exec dshc dsh plugin --profile web add <package>
```

> 注意：`DSH_ALLOW_PLUGIN_INSTALL` 是「首启」开关；运行中改它无效。

## 升级 DSH（重建镜像）

模板锁定了版本（`template/profile/pnpm-lock.yaml`）。升级 = 更新模板三件套（从一份新 DSH profile 复制）→ `docker compose build` → 重起。`minimumReleaseAge:0` 使其不因线上刚发布的版本而失败。

## 远程访问

默认 `localhost:3080` 仅本机。远程三种选择：
- **SSH 隧道**（推荐，零新增服务）：`ssh -L 3080:127.0.0.1:3080 user@host`，再访问本地 `http://127.0.0.1:3080`。
- **cloudflared 快速隧道**：容器内已含 `dsh-remote-web-ui` 插件，可用其公网隧道。
- **反向代理**：Nginx/Caddy + TLS（+ basic auth），并给 DSH 加 `--trusted-host`。

## 排障

- `docker compose logs -f dshc` — 看启动日志与 `[dshc] sandbox:` 自检行。
- `docker compose exec dshc dsh --profile web --dump-config` — dump 构成树；确认 `webserver.config.host=0.0.0.0` 已应用。
- 沙箱不可用：确认宿主内核 `CONFIG_SECURITY_LANDLOCK=y` 且 `CONFIG_LSM` 含 `landlock`；或需 bwrap 时用 `--security-opt seccomp=unconfined`+非特权 userns（高级）。
- 端口没通：确认 `docker compose ps` 里 `127.0.0.1:3080->3080` 已列出；别把容器内绑定误当作覆盖层未生效。
- 状态没持久：`docker compose down` 不删卷；`docker compose down -v` 才会删 `/data`。

## headless 一次性模式（CI 友好）

镜像 entrypoint 默认引导 **web** profile（并带 0.0.0.0 覆盖层），所以跑 headless 需**覆写 entrypoint** 才能进入 headless 引导。DSH 要求 `node --expose-internals`（cordis loader/HMR 使用；NODE_OPTIONS 禁止该 flag，只能作为 execArgv），所以直接调 bin.js：

```bash
docker compose run --rm --entrypoint "node --expose-internals" dshc \
  /app/template-profile/node_modules/@deepseek-ai/dsh/lib/bin.js --profile headless "你的任务"
```

无监听端口、跑完退出——方便脚本化/CI。
