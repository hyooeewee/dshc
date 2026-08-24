# dshc（DeepSeek Harness Container）

将 DSH（DeepSeek Harness）容器化的工程：产出 Docker 镜像（Dockerfile、入口脚本、docker-compose、构建流水线）与中文文档，让用户在 Docker 中安全地使用 DSH。

## Language

**dshc**:
本仓库的工程名与产物名（镜像、文档、流水线）。指容器化方案本身，不是 DSH。
_Avoid_: container 方案、Docker 项目

**DSH（DeepSeek Harness）**:
被容器化的目标应用：一个 AI agent 开发环境与 Web GUI（Node + pnpm workspace 的多进程服务，通过 pwsh 执行命令）。
_Avoid_: harness、dsh 泛指、这套工具

**容器边界**:
容器与宿主之间的信任线。默认零宿主暴露；挂载点、端口映射、状态卷是仅有的越界通道。
_Avoid_: 沙箱（沙箱是容器内 DSH 自身的概念，不是容器的隔离机制）

**默认隔离工作区**:
容器内 `/workspace`，默认不与宿主共享，容器删除即数据消失；显式命名挂载会穿透容器边界。
_Avoid_: 共享工作区、宿主工作目录

**无状态镜像 + 状态卷**:
镜像内代码与依赖不可变；DSH 运行时数据（`~/.dsh` 的配置、技能、插件、agent 预设、dsh-ssh.json、会话/日志）存于唯一状态卷。
_Avoid_: 镜像内写状态、全部持久化

**默认硬化**:
容器默认安全加固：非 root 运行、drop capabilities、no-new-privileges、seccomp、只读 rootfs + 唯一可写卷、资源限制、健康检查与优雅退出。
_Avoid_: 最小阻力配置

**单用户实例**:
一个容器 = 一个 DSH 实例 = 一个浏览器使用者；无内置认证，暴露与否由宿主侧端口映射决定。
_Avoid_: 多租户、内置登录

**多架构发布**:
同一镜像标签同时构建 linux/amd64 与 linux/arm64（buildx），覆盖 x86 服务器与 Apple Silicon / ARM 主机。
_Avoid_: 单架构镜像

**in-box bundle（箱内 bundle）**:
随 `@deepseek-ai/dsh` 安装本体依赖闭包分发的官方 bundle（如 dsh-base、dsh-web-app）；DSH 每次启动自动维护安装闭包的符号链接回退目录，profile 无需自带 node_modules。
_Avoid_: 官方插件（口语可用；精确概念是"是否在安装本体闭包内"，与官方与否不完全重合）

**外挂包（out-of-tree plugin）**:
不在安装本体闭包内的插件（含第三方社区包）；运行时经 DSH 原生机制（`dsh plugin add`，需网络）装入 profile 目录。镜像默认不预装任何外挂包。
_Avoid_: 自定义插件、模板插件