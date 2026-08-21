# dshc — DeepSeek Harness Container

把 **DSH（DeepSeek Harness）** 跑进 Docker 的容器工程：多架构（linux/amd64 + arm64）、默认硬化、把 DSH 安全地装进容器边界里。

> 决策记录见 [`docs/design.md`](docs/design.md)；安全边界详见 [`docs/security.md`](docs/security.md)；运行手册见 [`docs/usage.md`](docs/usage.md)。设计由 wayfinder 地图 [hyooeewee/dshc#1](https://github.com/hyooeewee/dshc/issues/1) 驱动。

## 快速开始

```bash
# 1) 提供 API key（DSH 将 DEEPSEEK_* 列为 bootstrap 变量，禁止写 .env，只能经环境变量注入）
export DEEPSEEK_API_KEY=sk-...

# 2) 构建 + 启动（默认硬化参数见 compose.yml）
docker compose up -d --build

# 3) 浏览器访问
open http://127.0.0.1:3080
```

## 特性与边界（一句话版）

| 项 | 决策 | 文档 |
|---|---|---|
| 平台 | Linux amd64 + arm64 多架构，bookworm-slim | [design](docs/design.md) |
| 数据 | 无状态镜像 + 状态卷 `/data`(=DSH_HOME)，代码只读 | [design](docs/design.md) |
| 工作区 | 默认容器内隔离 `/workspace`，不碰宿主；显式挂载=穿透边界 | [security](docs/security.md) |
| 会话 | 默认 `workspace-write` + GUI 审批；`danger-full-access` 只影响容器内 | [security](docs/security.md) |
| 沙箱 | Linux Landlock（默认 seccomp 可用，零额外权限）；bwrap 未内置（高级可自装） | [security](docs/security.md) |
| 网络 | 出站全开；入站仅 3080，宿主默认仅映射 localhost；无内置认证 | [security](docs/security.md) |
| 密钥 | `DEEPSEEK_API_KEY` 经环境变量/`--env-file` 注入 | [usage](docs/usage.md) |
| 插件 | 默认闭包不可运行时装插件；开 `DSH_ALLOW_PLUGIN_INSTALL=1` 可装且持久 | [usage](docs/usage.md) |

## 目录布局

```
├── Dockerfile           多阶段构建（builder 锁闭包 → runtime 硬化）
├── entrypoint.sh        首启模板复制 + 0.0.0.0 放行 + exec dsh
├── compose.yml          默认硬化参数（read_only / cap_drop / no-new-privileges / 端口 / 卷）
├── overlay/webstartup.yml   0.0.0.0 绑定覆盖层（DSH 拒绝 --host 0.0.0.0，用 loader patch 放行）
├── template/profile/    DSH profile 模板（lockfile 冻结，minimumReleaseAge:0）
└── docs/                设计 / 安全 / 运行
```

## 构建

```bash
# 单架构（本地）
docker build -t ghcr.io/hyooeewee/dshc:latest .

# 多架构（发布，GitHub Actions 已配好，见 .github/workflows/docker-build.yml）
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/hyooeewee/dshc:latest --push .
```

镜像发布到 `ghcr.io/hyooeewee/dshc`（私有包）；DSH 本体为公共 npm 依赖闭包（固定锁文件），无需私钥，可复现构建。

## 许可注意

仓库公开、镜像包私有。DSH 及其依赖（`@deepseek-ai/*`、`@linxin666/*`、`dshmarket`）的再分发许可未核查，公开镜像分发前请先评估（地图 #1「Out of scope」）。
