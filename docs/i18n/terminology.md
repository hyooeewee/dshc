# Terminology

本表约定本仓库的中英术语统一译法。

**通用规则：**
- "中文"列为中文译文的正文默认用词。若该列为英文，则中文译文的正文中保留英文不翻译。
- 首次出现按"首次出现"列书写（带括号注释）；后续出现只写括号前的部分（可能为中文，也可能为英文），不出现括号内的注释。
- "不要译作"列为严格禁止的译法。
- 如果某术语已经作为另一个术语的组成部分被括注过，则该术语后续单独出现时无需再次括注。

## 保留英文的术语（中文正文中不翻译）

| English | 中文 | 首次出现 | 不要译作 | 备注 |
|---|---|---|---|---|
| DSH | DSH（DeepSeek Harness） | DSH（DeepSeek Harness） | 海马/马具 | 被容器化的目标应用 |
| Docker | Docker | Docker | — | — |
| dshc | dshc | dshc | 本方案/容器方案 | 工程与产物名 |
| entrypoint | entrypoint | entrypoint | 入口脚本/启动入口 | 容器启动入口脚本 |
| overlay | overlay | overlay | 覆盖层（作补丁语义时） | composition overlay |
| multi-arch | multi-arch | multi-arch | 多架构（首次可写作 multi-arch（多架构）） | 平台 x86_64/arm64 |
| seccomp | seccomp | seccomp | — | — |
| Landlock | Landlock | Landlock | — | 沙箱后端，保留英文 |
| bwrap | bwrap | bwrap | — | bubblewrap，保留缩写 |
| bash | bash | bash | — | DSH 在 Linux 用 bash 模式 |
| pwsh | pwsh | pwsh | — | 仅 win32 需要 |
| cordis | cordis | cordis | — | DSH 的框架层，保留英文 |
| buildx | buildx | buildx | — | — |
| workspace-write | workspace-write | workspace-write | 工作区写权限 | 权限模式名，保留英文 |
| danger-full-access | danger-full-access | danger-full-access | 全权限 | 权限模式名，保留英文 |
| GHCR | GHCR | GHCR | — | ghcr.io |
| CI | CI | CI | 持续集成 | — |
| gateway/API | — | — | — | 未使用，避免误用 |

## 可翻译术语（有固定中文译法）

| English | 中文 | 首次出现 | 不要译作 | 备注 |
|---|---|---|---|---|
| container | 容器 | 容器 | — | — |
| image | 镜像 | 镜像 | 映像 | — |
| state volume | 状态卷 | 状态卷 | 持久卷（可作首现括注） | 挂在上游默认 `~/.dsh` |
| stateless image | 无状态镜像 | 无状态镜像 | — | 镜像内代码与依赖不可变 |
| default-hardened | 默认硬化 | 默认硬化 | 默认加固（可作首现括注） | 容器默认安全加固 |
| container boundary | 容器边界 | 容器边界 | 容器界限 | 容器与宿主间的信任线 |
| host | 宿主 | 宿主 | 主机/服务器 | 相对容器而言 |
| read-only rootfs | 只读 rootfs | 只读 rootfs | — | — |
| writable point | 可写点 | 可写点 | — | 卷/绑定两个可写点 |
| bind mount | 绑定挂载 | 绑定挂载（bind mount） | 绑载 | 宿主目录显式挂载 |
| workspace | 工作区 | 工作区 | — | 会话工作区 `~/workspace` |
| harness home | harness home | harness home | 主目录 | DSH 配置根 `~/.dsh` |
| sandbox | 沙箱 | 沙箱 | 沙盒 | DSH 自身的隔离机制 |
| graceful shutdown | 优雅退出 | 优雅退出 | 平滑退出 | DSH 5s 优雅退出 |
| first boot | 首次启动 | 首次启动（first boot） | 首启 | — |
| preference seed | 偏好种子 | 偏好种子 | 预设偏好 | DSHC_LOCALE/DSHC_THEME 首启写入 |
| out-of-tree plugin | 外挂包 | 外挂插件（out-of-tree plugin） | 自定义插件/模板插件 | 不在安装本体闭包内的插件 |
| in-box bundle | 箱内 bundle | in-box bundle | 官方插件（口语） | 随安装本体闭包分发的官方 bundle |
| credential | 密钥 | 密钥 | 凭据（可作首现括注） | DEEPSEEK_API_KEY |
| version pin | 版本钉点 | 版本钉点 | 版本固定/钉版本 | dshc git tag 即版本钉点 |
| dependency closure | 依赖闭包 | 依赖闭包 | 依赖集合 | 从上游源码打包出的闭包 |
| source build | 源码构建 | 源码构建 | — | 上游 GitHub tag 源码打包 |
| session | 会话 | 会话 | — | — |
| egress | 出站 | 出站 | 外发流量 | 网络出站全开 |
| inbound | 入站 | 入站 | 入口流量 | 入站仅 GUI 端口 |
| port mapping | 端口映射 | 端口映射 | 端口转发 | compose 端口映射 |
| single user / single instance | 单用户单实例 | 单用户单实例 | 多租户 | 一个容器 = 一个 DSH 实例 |
| built-in auth | 内置认证 | 内置认证 | — | 容器无内置认证 |

## 待定术语（pending terms）

以下术语尚无定论，中文正文暂保留英文；裁定后移入上方表格。
- `wslpath`（Windows 路径翻译脚本）
- `tmpfs`
- `userns`（非特权用户命名空间）
