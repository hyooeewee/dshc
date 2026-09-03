# dshc — DeepSeek Harness Container

> 📖 [English](README.md) · 中文

把 DSH（DeepSeek Harness） 安全地跑进 Docker：多架构（linux/amd64 + arm64）、默认硬化、基于自包含且可复现的依赖闭包构建。

- 设计决策：[docs/design.md](docs/design.md)
- 安全边界：[docs/security.md](docs/security.md)
- 运行手册：[docs/usage.md](docs/usage.md)
- 发布流程：[RELEASE.md](RELEASE.md)

## 快速开始

```bash
cp .env.example .env                     # then set your key inside: DEEPSEEK_API_KEY=sk-...
docker compose up -d --build
open http://127.0.0.1:3080               # host port via DSHC_PORT in .env (default 3080)
```

也可以不建 `.env`，直接 `export DEEPSEEK_API_KEY=sk-...`。DSH 禁止 `DEEPSEEK_*` 出现在容器侧文件里，无论哪种方式都经宿主侧环境注入。

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
| 远程访问 | `DSHC_TRUSTED_HOSTS`（逗号分隔）允许非 localhost 访问，通过 `--trusted-host` 传给 DSH | [usage](docs/usage.md) |

所有旋钮集中在 `.env`（模板见 [.env.example](.env.example)）——构建期镜像源（`APT_MIRROR`、`NPM_REGISTRY`）与运行时设置同文件管理。

## 目录布局

```
Dockerfile               multi-stage (packed closure install → hardened runtime)
entrypoint.sh            first-boot preference seed + Landlock probe + wslpath + token capture + trusted-hosts + exec dsh
compose.yml              default hardening (read_only / cap_drop / no-new-privileges / ports / volumes)
overlay/webstartup.yml   composition overlay (0.0.0.0 bind — DSH rejects --host 0.0.0.0 — and ~/workspace pins)
install/                 生成的闭包清单 + 锁（gitignored；每次构建的产物）
dist/                    打包闭包 tarball（CI job "pack" 产物；gitignored，构建必需）
scripts/gen-manifest.mjs 为某版本生成 install/ (package.json + pnpm-lock.yaml)
docs/                    design / security / usage
RELEASE.md               发布 checklist（tag 即版本钉点）
```

## 工作原理

### CI/CD 流水线 (`.github/workflows/cd.yml`)

**Job 1: pack**（tag 推送或 `workflow_dispatch` 触发）
1. Checkout 上游 `deepseek-ai/deepseek-harness` 的 `dsh-<tag>`
2. `pnpm install --frozen-lockfile` + `build:official`
3. 通过 `pnpm run release:pack` 打包三个闭包族：
   - `dist/npm` — `@deepseek-ai/dsh` 族
   - `dist/npm-vendor` — 打包框架（`cordis`、`cosmokit`、`schemastery` 等）
   - `dist/npm-landlock` — `@deepseek-ai/node-addon-landlock-run` 入口点
4. 验证打包安装，上传 tarball 为 artifact

**Job 2: build**（依赖 pack）
1. 下载闭包 tarball，铺设到 `dist/`
2. 运行 `scripts/gen-manifest.mjs <version>` → 生成带 `file:./dist/...` 依赖的 `package.json`
3. `pnpm install --lockfile-only` → 从清单生成 `pnpm-lock.yaml`
4. 将 `package.json` + `pnpm-lock.yaml` 自动提交到 `main` 分支（经 `git-auto-commit-action`）
5. 多架构 Docker 构建（`linux/amd64,linux/arm64`），带 GHA 层缓存，推送到：
   - `ghcr.io/hyooeewee/dshc`
   - `godotttt/dshc` (Docker Hub)
6. 从 README 同步更新 Docker Hub 简介

### Docker 构建（pnpm 全链路）

Dockerfile 直接消费 `dist/` 下的打包闭包——**不**从 npm registry 拉 DSH。

```dockerfile
# builder 阶段
COPY package.json pnpm-lock.yaml dist/ ./
RUN corepack enable \
  && pnpm install --prod --frozen-lockfile --ignore-scripts --update-checksums \
  && pnpm store prune

# runtime 阶段
COPY --from=builder /buildspace/node_modules ./dsh/node_modules
```

关键点：
- **pnpm 端到端**：上游打包用 pnpm，锁文件由 pnpm 生成，Docker 安装用 pnpm——零 npm/pnpm 解析差异
- `--prod`：仅安装生产依赖
- `--frozen-lockfile`：强制锁文件精确版本
- `--ignore-scripts`：跳过构建脚本（原生插件已在 tarball 预编译）
- `--update-checksums`：接受本地 tarball 校验和（与 registry 不同）
- `pnpm store prune`：精简镜像体积

### 入口脚本 (`entrypoint.sh`)

容器启动时：
1. **首启偏好**：按 `DSHC_LOCALE` / `DSHC_THEME` 种子写入 `settings.yaml`（仅文件缺失时；GUI 后续修改永不覆盖）
2. **Landlock 探测**：复用 `@deepseek-ai/node-addon-landlock-run` 包自身的解析逻辑定位平台二进制；探测可用性（可选依赖缺失时优雅跳过）
3. **wslpath**：安装 `/usr/local/bin/wslpath` (Node.js 脚本) 用于 Windows 路径翻译（DSH 用于 WSL2 宿主路径）
4. **受信主机**：读取 `DSHC_TRUSTED_HOSTS`（逗号分隔），转 `--trusted-host` 传给 DSH 以允许非 localhost 访问
5. **Token 捕获**：从 stdout 捕获 `token=...` 写入 `~/.dsh/.web-auth`，供 GUI 自动登录
6. **启动 DSH**：运行 `node --expose-internals dsh bin.js --profile web --patch /app/overlay/webstartup.yml`

## 本地构建

需要 `dist/` 下的闭包 tarball（下载 CI artifact `dsh-closure` 或自行跑打包管线）：

```bash
# 1. 把闭包 tarball 放进 dist/（CI artifact "dsh-closure"，或自行跑打包管线——见 RELEASE.md）
# 2. 生成 install/（清单 + 冻结锁；node 24）：
node scripts/gen-manifest.mjs 0.1.2-alpha.1
pnpm install --lockfile-only
# 3. 构建（多架构发布交给 CI；docker compose build 同样可行）
docker build -t ghcr.io/hyooeewee/dshc:latest .
docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/hyooeewee/dshc:latest --push .
```

镜像发布到 `ghcr.io/hyooeewee/dshc`（私有包）与 `godotttt/dshc`（Docker Hub，其简介由本 README 同步）。网络受限时在 `.env` 设置 `APT_MIRROR` / `NPM_REGISTRY`。

发布是 tag 驱动的：tag 推送会让 CI 打包上游 `dsh-v<version>` 并只安装这批 artifacts，发布 `<version>` **与** `latest`（latest = 最新发布 tag；main 推送按最新 tag 重建 `latest`）。`install/` 的清单与锁是每次构建的产物，由 CI 自动提交到 `main`。

## 许可注意

仓库公开、镜像包私有。DSH 及其依赖（`@deepseek-ai/*`）的再分发条款未核查——公开分发镜像前请先评估。

## 语言约定

仓库文本按约定以英文为准（见 `AGENTS.md` → Language）；本文件是 README.md 的中文对照版，两者内容一致。