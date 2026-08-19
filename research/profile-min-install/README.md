# 模板 profile 最小可复制安装集与镜像体积估算

研究工单：[hyooeewee/dshc#3](https://github.com/hyooeewee/dshc/issues/3)（wayfinder:research，属于地图 #1）。

**执行代理结论：** DSH 的「模板 profile」不是 git 源码，而是一个可被 pnpm 从公共 registry 完整复现的依赖闭包。本机 profile
`C:\Users\Godot\.dsh\profiles\web` 的 `package.json` + `pnpm-workspace.yaml` + `pnpm-lock.yaml` 三件套已足以在空目录下用
`pnpm install --prod --frozen-lockfile` 复现出与真实 profile 几乎一致的 `node_modules`（~238 MB / ~33.5k 文件），无需把
`dsh.profile.bundles` 再写进 `package.json.dependencies`（lockfile 的 `packages:` 段已把整套 rc.7 闭包钉死）。

一手来源：本机 profile 目录三件套、公共 npm registry（`npm view` 交叉验证）、本机 pnpm 11.22.0 的 `help` 文档；体积数据在本机
`$env:TEMP\dshc-exp\exp-a`（bundles 声明版）与 `exp-b`（原样三件套拷贝版）实测。

---

## 1. 最小 bundle 集与精确版本（以 pnpm-lock.yaml 为准，npm view 交叉验证）

`dsh.profile.bundles` 声明的 4 个包 + 1 个 git 包，均在公共 registry（registry.npmjs.org，匿名可解析）可解析：

| 包 | 锁定版本（lockfile） | registry 解析（npm view） | 说明 |
|---|---|---|---|
| `@deepseek-ai/dsh-base` | `0.1.0-rc.7` | 同名同版，tarball `.../dsh-base/-/dsh-base-0.1.0-rc.7.tgz` | 核心 bundle，约 70+ 个 `dsh-*` 运行时依赖（profile 首层补丁） |
| `@deepseek-ai/dsh-web-app` | `0.1.0-rc.7` | 同名同版可解析 | Web 应用 bundle |
| `dshmarket` | `1.11.3` | 同名同版；peer `@deepseek-ai/cordis@^4.0.1` | 市场插件 |
| `@linxin666/dsh-web-ui-all` | `0.1.20` | 同名同版可解析 | Web UI 全家桶聚合 |
| `dsh-browser` | git：`github:Lum1104/dsh-browser` | 锁到 codeload tarball | 固定 SHA 见下 |

**dsh-browser 固定 SHA**（lockfile 原始行）：

```
dsh-browser@https://codeload.github.com/Lum1104/dsh-browser/tar.gz/02758b13893980fdf334aea320d20e0a5fd730ff(1b6685cdbe3b4d09f59c8a781deb1568)
```

- commit SHA：`02758b13893980fdf334aea320d20e0a5fd730ff`
- tarball 内容指纹：`1b6685cdbe3b4d09f59c8a781deb1568`（pnpm 锁文件中的缓存键）
- 复现写法：`"dsh-browser": "github:Lum1104/dsh-browser#02758b13893980fdf334aea320d20e0a5fd730ff"`

**重要发现 —— 复现不需要把 bundles 写进 dependencies：**
`@deepseek-ai/dsh-base` 与 `@deepseek-ai/dsh-web-app` **不在**本机 `package.json.dependencies`（那里只有 3 个：
`@linxin666/dsh-web-ui-all`、`dsh-browser`、`dshmarket`），但已物理装入 `node_modules/@deepseek-ai/`（176 个包），且完整的 rc.7
闭包已冻结进 `pnpm-lock.yaml` 的 `packages:` 段。实测：把 profile 的三件套原样拷贝到空目录执行
`pnpm install --prod --frozen-lockfile`，得到的 `node_modules` 同样含全部 176 个 `@deepseek-ai` 包（含 `dsh-base`、`dsh-web-app`）、
大小与 bundles 声明版几乎一致（238.2 vs 238.3 MB）。结论：**镜像构建只需搬入这三件套 + 全量 lockfile，`--frozen-lockfile` 即复现闭包**；
bundles 仅作为运行时 `dsh.profile.bundles` 声明存在，不参与安装解析。

---

## 2. 生产安装可行性

实测命令与结果（Windows 宿主，pnpm 11.22.0；Linux 结论为对脚本/预编译产物分析推导）：

| 方案 | 命令 | 结果 |
|---|---|---|
| 生产安装 | `pnpm install --prod`（bundles 声明版，空目录无 lockfile） | ✅ EXIT=0，1m1s，resolved 592 / added 535 |
| 冻结安装 | `pnpm install --prod --frozen-lockfile`（原三件套拷贝） | ✅ EXIT=0，48.6s，resolved 0（不联网解析，直接复用） |
| pnpm deploy | `pnpm --filter dsh-profile-min deploy <dir> --prod` | ❌ pnpm≥10 默认拒绝：`ERR_PNPM_DEPLOY_NONINJECTED_WORKSPACE`，需 `--legacy` 或 `inject-workspace-packages=true` |
| deploy --legacy | `pnpm deploy ... --prod --legacy` | ✅ EXIT=0，但产物 238.5 MB ≈ 直接 install，无体积收益、标记 Experimental |

**结论：** 主路径是 `pnpm install --prod --frozen-lockfile`（CI/镜像默认即 `--frozen-lockfile`，见 `pnpm help install`）。
`pnpm deploy` 对单包 profile 无体积优势且需 `--legacy`，不必采用。

**allowBuilds（原生构建白名单）—— 必须随 `pnpm-workspace.yaml` 一起复制**，否则 pnpm 11 默认不执行这些包的 install 脚本：
`@deepseek-ai/dsh-subprocess-local`、`@google/genai`、`cloudflared`、`cpu-features`、`koffi`、`node-pty`、`protobufjs`、`ssh2`。
其中关键副作用：node-pty 的 postinstall 恢复 `spawn-helper` 可执行位（`dsh-subprocess-local` 的
`ensure-spawn-helper.mjs` 只做 `chmod 755`，二进制本身随 node-pty 预编译预置）；cloudflared 的 postinstall 下载真身二进制。

**registry / .npmrc：** 无需任何 `.npmrc`——公共 registry 匿名可解析（实测 downloaded=0 依赖全部命中已有 store/远程可解析；
`npm view` 全部成功）。可选：Docker 构建如需内网代理可设 `registry`/`packageManager`，非必需。

**minimumReleaseAgeExclude：** profile 的 `pnpm-workspace.yaml` 含 `minimumReleaseAgeExclude`（列出 `dshmarket@1.11.3` 与全部
`*.rc.7`）。该列表是防御性的（pnpm 11 的发布年龄门控默认关闭时无副作用），但应整体复制 workspace yaml 以保持与真实 profile 行为一致。

---

## 3. 原生模块多架构（linux-x64 / linux-arm64）

| 模块 | 版本 | 预编译可用性 | 是否需要编译工具链 | 说明 |
|---|---|---|---|---|
| `koffi` | 3.1.5 | ✅ 平台预编译经可选依赖 `@koromix/koffi-linux-x64@3.1.5`(2.4MB) / `-linux-arm64`(2.3MB) | 不需要（预编译 .node） | 主包 install 脚本 `cnoke.cjs --prebuild` 为回退路径；命中预编译即跳过 |
| `node-pty` | 1.2.0-beta.15 | ✅ 随 npm tarball 预编译 `prebuilds/linux-x64/pty.node`(76KB)+`spawn-helper`、`linux-arm64/pty.node`(69KB)+`spawn-helper` | 不需要 | `scripts/prebuild.js` 仅检查 `prebuilds/<platform>-<arch>/`，找到即 exit 0；install 脚本 `prebuild.js \|\| node-gyp rebuild` 的 node-gyp 只会在缺预编译时触发 |
| `ssh2` | 1.17.0 | 纯 JS（asn1 + bcrypt-pbkdf） | 不需要 | 原生加速 `cpu-features` 为其 **optional** 依赖 |
| `cpu-features` | 0.0.10 | ❌ 无预编译 | **需要**（install: `node-gyp rebuild`） | Linux 需 python3 + make + g++（build-essential）。实测无编译器时 buildcheck 抛 `Unable to detect compiler type`，但因是 ssh2 的 optional 依赖，pnpm 容忍 build 失败、安装仍 EXIT=0 |
| `sharp` | 0.35.3 | ✅ 经可选依赖 `@img/sharp-linux-x64`(0.43MB)+`@img/sharp-libvips-linux-x64@1.3.2`(18.2MB)；arm64 同理 | 不需要 | 无 install 脚本；`install/build.js` 仅源码构建用。engines node>=20.9 |
| `cloudflared` | 0.7.3 | ⚠️ 真身二进制在 **postinstall** 里下载（`node lib/cloudflared.js bin install`） | 不需要编译，但构建/运行时需联网拉取 ~50MB 二进制 | npm 包本身仅 ~0.05MB；二进制落盘位置在包外（用户缓存/状态卷），镜像内应视为运行时状态而非构建产物 |
| `@deepseek-ai/node-addon-landlock-run` | 0.1.1 | ✅ 经平台包 `-linux-x64`(43KB) / `-linux-arm64`(72KB) 预编译 launcher | 不需要 | 「landlock launcher」= 该 node-addon；npm 上即有 linux-x64/arm64 预编译二进制 |
| `protobufjs` / `@google/genai` | — | 纯 JS（`genai` preinstall 为 `no-op` 回显） | 不需要 | allowBuilds 已列出 |

**工具链需求（build 阶段）：** 唯一真正需要 `node-gyp` 工具链的是 **cpu-features**（optional）。两条路：
(a) build 阶段安装 `build-essential python3 make g++`（推荐，保险、代价是 build 镜像更肥）；
(b) `pnpm install --prod --frozen-lockfile --no-optional`，跳过 cpu-features，ssh2 退回纯 JS（功能无损对本模板而言）。
其余全部天然带 linux-x64/arm64 预编译产物。

**glibc 约束：** koffi/node-pty/sharp 的预编译产物是 glibc 构建 → **必须用 glibc 基础镜像**
（`bookworm-slim` 是正确选择），不可用 `alpine`（musl 会加载失败）。

---

## 4. 体积估算（实测 + 镜像推算）

### 实测（Windows 宿主，仅 bundles + 闭包）

| 项 | 数值 |
|---|---|
| `node_modules` 总大小 | **~238.3 MB**（33,540 文件） |
| `pnpm install --prod` 用时 | ~1m（复用 store 时） |

### 主要体积构成（`node_modules` 顶层/作用域，MB）

| 目录/包 | ~MB | 备注 |
|---|---|---|
| `node-pty` | 26.7 | **最大单包**：tarball 内嵌全平台预编译，win32 的 `.pdb`（4–6MB/个×2 架构）是大头 |
| `@deepseek-ai`（176 个） | 20.4 | bundles 闭包本体 |
| `@img`（sharp 系） | 18.4 | 其中 libvips 系 ~18MB；Linux 上对应 `sharp-linux-*`+libvips-linux-* |
| `@opentelemetry` | 18.1 | telemetry 依赖 |
| `@linxin666` | 17.5 | web-ui-all 聚合（含 aionui-panel 5.4、remote-web-ui 2.8、pet 2.8、ssh 2.2 等） |
| `@earendil-works` | 13.9 | — |
| `@google` | 13.7 | — |
| `@shikijs` | 10.5 | 语法高亮相关 |
| `web-streams-polyfill` | 8.6 | — |
| `@mixmark-io` / `openai` / `@xterm` | 7.4 / 7.2 / 5.7 | — |
| `@deepseek-ai/dsh-web-frontend` | 4.4 | — |
| `sharp`（JS 部分）+`ssh2`+`cpu-features`+`koffi`+`cloudflared` | 0.9/1.1/0.6/1.7/0.05 | 原生模块本体都很小 |
| `dsh-browser` / `dshmarket` | 1.4 / 2.2 | — |

> Linux（x64/arm64）≈ 235–245 MB：与 Windows 实测的差异仅在平台门控的预编译包互换（sharp 换 linux 系、koffi 换 `@koromix/koffi-linux-*`），
> node-pty 的全平台预编译无论何种目标架构都会整包带入。

### 镜像体积推算

- DSH 依赖层（`node_modules`）：~238 MB 未压缩。
- Node 运行时：`node:22-bookworm-slim` 基础镜像（未压缩 ~180 MB / 压缩 ~75–85 MB，近似值，需在可联网环境对 Docker Hub manifest 复核）。
- **估算总镜像（bookworm-slim，非精简）：未压缩 ~0.4–0.45 GB；压缩 ~0.15–0.18 GB。**
  硬化层（非 root、只读 rootfs、状态卷）不额外增加体积。

### 可瘦身项

1. **`--prod`（必做）**：排除所有 devDependencies。本模板依赖全部是运行时依赖，`--prod` 收益有限，但仍是标准做法。
2. **跨架构预编译清理（收益最大）**：`node-pty` 的 `prebuilds/{win32,darwin}*` 在 Linux 镜像无用，约可回收 **~20 MB**；
   写一个安装后清理步骤（如 `find node_modules/node-pty/prebuilds -mindepth 1 -maxdepth 1 ! -name 'linux-*' -exec rm -rf`），并用 `--no-optional` 或工具链避免 cpu-features 编译。
3. **`--no-optional`（可选）**：跳过 `cpu-features`（ssh2 纯 JS 兜底）、`@img/sharp-*` 非目标平台可选包。本机实测 `@img/sharp-win32-x64` 占 18.3MB（仅 Windows 环境出现；Linux 构建会被 `cpu/os` 过滤掉，无需手动处理）。
4. **pnpm store 清理**：`pnpm install` 的 store 在镜像内无意义——构建时应把 store 放 CI 缓存/构建阶段，运行时镜像只保留产物 `node_modules`；或 `pnpm store prune`。镜像内 `.pnpm` 结构（hoisted 已禁用 .pnpm 目录）不影响。
5. **删除 `dsh-browser` 的源码/示例**：git 包整包进入（1.4MB），可保留（被 `@deepseek-ai/dsh` 运行时引用）。
6. **不引入 dev-only 前端构建产物**：`@linxin666/dsh-web-ui-all` 等已发布构建产物，无需在镜像内二次构建。

**注意区分 Linux/Windows 测量差异：** 上面 238.3MB 是 Windows 环境实测（`sharp` 选中 win32、`koffi` win32）。Linux 的目标体积应按「linux 平台包互换」理解（≈235–245MB），不要直接把 win32 `@img/sharp-win32-x64` 的 18.3MB 计入 Linux 镜像。

---

## 给后续工单的提示（供布局商议 #4 / Dockerfile 依赖层 #6 参考）

- **依赖层重构指令建议**：
  ```dockerfile
  # build stage（工具链，可选：若用 --no-optional 可去掉 build-essential）
  FROM node:22-bookworm-slim AS deps
  # 复制 package.json, pnpm-workspace.yaml, pnpm-lock.yaml
  RUN corepack enable && pnpm install --prod --frozen-lockfile \
      && pnpm store prune \
      && <清理 node-pty 非 linux 预编译>
  # runtime stage：只拷贝 node_modules + 入口
  ```
- 必须同时带 `pnpm-workspace.yaml`（含 `allowBuilds` 与 `minimumReleaseAgeExclude`）与**全量** `pnpm-lock.yaml`；`--frozen-lockfile` 保证离线/确定复现。
- 基础镜像锁定 glibc 的 `bookworm-slim`（非 alpine），以匹配 koffi/node-pty/sharp 预编译。
- 唯一硬编译依赖是 cpu-features（optional）——要么 build 阶段装 `build-essential python3 make g++`，要么 `--no-optional` 跳过。
- cloudflared 真身二进制为运行时下载（postinstall），应视为运行时/状态卷能力，不计入镜像固定体积。

## 证据文件
- 本机 profile：`C:\Users\Godot\.dsh\profiles\web\{package.json,pnpm-workspace.yaml,pnpm-lock.yaml}`（未改动）
- 实验目录：`$env:TEMP\dshc-exp\exp-a`（bundles 声明版，install-a.log）、`exp-b`（三件套拷贝版 frozen，install-b.log）、`exp-a\deploy-out2`（deploy --legacy）
- 校验来源：`npm view <pkg>@<ver> version dis.tarball`、`pnpm help install|deploy`
- 复查时可用 `npm view` 重新核验每个版本号仍在 registry 可解析。
