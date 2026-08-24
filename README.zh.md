# dshc — DeepSeek Harness Container

> 📖 [English](README.md) · [中文](README.zh.md)

把 **DSH（DeepSeek Harness）** 安全地跑进 Docker：多架构（linux/amd64 + arm64）、默认硬化、基于自包含且可复现的依赖闭包构建。

设计决策：[docs/design.md](docs/design.md) · 安全边界：[docs/security.md](docs/security.md) · 运行手册：[docs/usage.md](docs/usage.md) · 由 wayfinder 地图 [hyooeewee/dshc#1](https://github.com/hyooeewee/dshc/issues/1) 驱动。

## 快速开始

```bash
cp .env.example .env                     # then set your key inside: DEEPSEEK_API_KEY=sk-...
docker compose up -d --build
open http://127.0.0.1:3080               # host port via DSHC_PORT in .env (default 3080)
```

也可以不建 `.env`，直接 `export DEEPSEEK_API_KEY=sk-...`。DSH 禁止 `DEEPSEEK_*`
出现在容器侧文件里，无论哪种方式都经宿主侧环境注入。

## 特性与边界

| 项 | 决策 | 文档 |
|---|---|---|
| 平台 | Linux amd64 + arm64 多架构，bookworm-slim 基础镜像 | [design](docs/design.md) |
| 数据 | 无状态镜像；状态卷挂在上游默认 `~/.dsh`（即 `/home/dsh/.dsh`）；代码只读 | [design](docs/design.md) |
| 工作区 | 默认隔离在 `~/workspace`，不碰宿主；显式挂载=有意穿透边界 | [security](docs/security.md) |
| 会话 | 默认 `workspace-write` + GUI 审批；`danger-full-access` 只影响容器内 | [security](docs/security.md) |
| 沙箱 | Linux Landlock（默认 seccomp 可用，零额外权限）；bwrap 未内置（高级可自装） | [security](docs/security.md) |
| 网络 | 出站全开；入站仅 GUI 端口（`DSHC_PORT`，宿主只绑 localhost）；无内置认证 | [security](docs/security.md) |
| 密钥 | `DEEPSEEK_API_KEY` 经环境变量/`.env` 注入；绝不落在容器侧文件 | [usage](docs/usage.md) |
| 插件 | 镜像只装官方闭包；外挂插件运行时经 `dsh plugin add` 安装（装入状态卷，需网络） | [usage](docs/usage.md) |
| 偏好 | `DSHC_LOCALE` / `DSHC_THEME` 首启种子语言与外观；之后 GUI 的修改落盘且永不覆盖 | [usage](docs/usage.md) |

所有旋钮集中在 `.env`（模板见 [.env.example](.env.example)）——构建期镜像源
（`APT_MIRROR`、`NPM_REGISTRY`）与运行时设置同文件管理。

## 目录布局

```
Dockerfile               multi-stage (locked closure → hardened runtime)
entrypoint.sh            first-boot preference seed + Landlock probe + exec dsh (DSH self-initializes the profile)
compose.yml              default hardening (read_only / cap_drop / no-new-privileges / ports / volumes)
overlay/webstartup.yml   composition overlay (0.0.0.0 bind — DSH rejects --host 0.0.0.0 — and ~/workspace pins)
install/                 minimal install manifest (@deepseek-ai/dsh only; frozen lockfile, minimumReleaseAge:0)
docs/                    design / security / usage
```

## 构建

```bash
docker build -t ghcr.io/hyooeewee/dshc:latest .
# multi-arch publish (CI also does this; see .github/workflows/docker-build.yml)
docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/hyooeewee/dshc:latest --push .
```

镜像发布到 `ghcr.io/hyooeewee/dshc`（私有包）。DSH 本体是公共 npm 依赖闭包（冻结锁文件），无需私有仓库即可复现构建。网络受限时在 `.env` 设置 `APT_MIRROR` / `NPM_REGISTRY`。

## 许可注意

仓库公开、镜像包私有。DSH 及其依赖（`@deepseek-ai/*`）的再分发条款未核查——公开分发镜像前请先评估（地图 #1「Out of scope」）。

## 语言约定

仓库文本按约定以英文为准（见 `AGENTS.md` → Language）；本文件是 README.md 的中文对照版，两者内容一致。
