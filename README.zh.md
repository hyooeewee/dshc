# dshc — DeepSeek Harness Container

> 📖 [English](README.md) · 中文

把 **DSH（DeepSeek Harness）** 安全地跑进 Docker：多架构（linux/amd64 + arm64）、默认硬化、基于上游 **GitHub tag 源码**构建——GitHub 发布总是领先 npm，因此镜像以 tag 为准：在该 tag 上打包一次闭包、按架构安装（地图 #12）。

设计决策：[docs/design.md](docs/design.md) · 安全边界：[docs/security.md](docs/security.md) · 运行手册：[docs/usage.md](docs/usage.md) · 发布流程：[RELEASE.md](RELEASE.md) · wayfinder 地图：[hyooeewee/dshc#1](https://github.com/hyooeewee/dshc/issues/1)、[#12](https://github.com/hyooeewee/dshc/issues/12)。

## 快速开始

```bash
cp .env.example .env                     # then set your key inside: DEEPSEEK_API_KEY=sk-...
docker compose up -d --build
open http://127.0.0.1:3080               # host port via DSHC_PORT in .env (default 3080)
```

本地构建需要 `dist/` 下的打包闭包（CI 产出——从 workflow 运行下载 `dsh-closure`
artifact，或自行跑打包管线；见 [RELEASE.md](RELEASE.md)）。

也可以不建 `.env`，直接 `export DEEPSEEK_API_KEY=sk-...`。DSH 禁止 `DEEPSEEK_*`
出现在容器侧文件里，无论哪种方式都经宿主侧环境注入。

## 特性与边界

| 项 | 决策 | 文档 |
|---|---|---|
| 平台 | Linux amd64 + arm64 多架构，bookworm-slim 基础镜像 | [design](docs/design.md) |
| 版本来源 | 上游 GitHub tag 源码构建（如 `0.1.2-alpha.1`）；dshc 的 git tag 即版本钉点——npm 风格命名、不带 `v` 前缀 | [release](RELEASE.md) |
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
Dockerfile               multi-stage (packed closure install → hardened runtime)
entrypoint.sh            first-boot preference seed + Landlock probe + exec dsh (DSH self-initializes the profile)
compose.yml              default hardening (read_only / cap_drop / no-new-privileges / ports / volumes)
overlay/webstartup.yml   composition overlay (0.0.0.0 bind — DSH rejects --host 0.0.0.0 — and ~/workspace pins)
install/                 闭包清单（全部家族 tarball 作 file: 依赖；冻结 package-lock.json，engines ^24）
dist/                    打包闭包 tarball（CI job "pack" 产物；gitignored，构建必需）
scripts/                 gen-install-manifest.mjs — 为新版本重生成 install/package.json
docs/                    design / security / usage
RELEASE.md               发布 checklist（tag 即版本钉点）
```

## 构建

Dockerfile 消费 `dist/` 下的**打包闭包**——不从 registry 拉 DSH。CI 通过复刻上游发布
管线在指定 tag 上产出这些 tarball（`.github/workflows/docker-build.yml` 的 job "pack"）；
本地构建同样需要它们：

```bash
# 1. 把闭包 tarball 放进 dist/（CI artifact "dsh-closure"，或自行跑打包管线——见 RELEASE.md）
# 2. 为版本重生成清单（每次发布一次）：
node scripts/gen-install-manifest.mjs 0.1.2-alpha.1
# 3. 构建（多架构发布交给 CI；docker compose build 同样可行）
docker build -t ghcr.io/hyooeewee/dshc:latest .
docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/hyooeewee/dshc:latest --push .
```

镜像发布到 `ghcr.io/hyooeewee/dshc`（私有包）。闭包用 npm 安装（上游 `verify-packed-install`
的语义——pnpm 无法从 `file:` tarball 满足传递 `^0.1.x` 范围），无需私有仓库即可复现构建。
网络受限时在 `.env` 设置 `APT_MIRROR` / `NPM_REGISTRY`。

## 许可注意

仓库公开、镜像包私有。DSH 及其依赖（`@deepseek-ai/*`）的再分发条款未核查——公开分发镜像前请先评估（地图 #1「Out of scope」）。

## 语言约定

仓库文本按约定以英文为准（见 `AGENTS.md` → Language）；本文件是 README.md 的中文对照版，两者内容一致。
