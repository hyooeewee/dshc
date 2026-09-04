# Design notes (dshc)

English | [中文](design.zh.md)

Decisions are forged from the three design tickets (#2/#3/#4) behind wayfinder map [hyooeewee/dshc#1](https://github.com/hyooeewee/dshc/issues/1); this is the landing summary.
The source-build migration (map [#12](https://github.com/hyooeewee/dshc/issues/12), tickets #13–#16) rewrote this file's Build input and Release sections: the image moved from a "registry dependency closure" to "a closure packed from the upstream GitHub tag source".

## Locked boundary conditions

1. **Platform**: Linux, `node:22-bookworm-slim`, amd64 + arm64 multi-arch (buildx). DSH uses bash mode on non-win32, so pwsh is not needed; glibc → do not use alpine.
2. **DSH payload (from map #12)**: a *packed closure built from the upstream
   source*, not a registry install. CI job "pack" replicates the upstream
   release pipeline at an explicit GitHub tag (`build:official` → `release:pack`;
   pure-JS platform-neutral tarballs, verified in prototype #15); the image
   then only installs that closure: the in-context `install/package.json` (a
   per-build product, never committed) pins every family tarball as a `file:`
   dependency and `package-lock.json` freezes the resolved tree. Installer uses **npm** (the upstream `verify-packed-install` semantics —
   pnpm cannot satisfy transitive `^0.1.x` ranges from `file:` tarballs).
   - The manifest is self-consistent: `engines.node ^24` matches the runtime
     base image; `dshUpstreamVersion` carries the pinned upstream version
     (main-branch builds read it — the dshc git tag is the version pin).
   - **The image pre-installs no out-of-tree plugins** (#11): DSH's built-in web profile template resolves from the installed closure alone; out-of-tree plugins load into the state volume at runtime via DSH's native mechanism.
   - Toolchain (installer stage): node-pty has no prebuild → node-gyp compiles
     it; koffi rebuilds from source on the node 24 ABI → **cmake required**
     (prototype #15); landlock launcher + platform packages ship prebuilt.
3. **Sandbox** (#2 conclusion): under the default seccomp **Landlock works with zero extra privileges** (the three landlock syscalls are unconditionally allowed, launcher uses no_new_privs); bwrap needs a privileged allowance. DSH falls back bwrap→landlock automatically, not fail-closed. compose keeps the default seccomp and adds no privileges. **The image does not bundle bwrap by default** (default hardening goes entirely through Landlock; using bwrap is advanced: self-install + `seccomp=unconfined`). The entrypoint readiness check runs `landlock-run --probe`.
4. **User model**: single user, single instance, no built-in auth.
5. **Network**: egress fully open (LLM API / web_search / SSH / cloudflared on demand); inbound only 3080. Binding 0.0.0.0 inside the container is explicitly allowed by the entrypoint `--patch overlay/webstartup.yml` (the DSH CLI deliberately rejects `--host 0.0.0.0`); the host-side compose maps only `127.0.0.1:3080:3080`.
6. **Persistence**: stateless image + a state volume mounted at the upstream-default harness home (`~/.dsh` = `/home/dsh/.dsh`, the volume covers only that subpath; beneath it are `profiles/`, `sessions/`, `settings.yaml`, `.credentials.yaml`, `storages/`, `skills/`, `dsh-ssh.json`). `$HOME` stays the image default `/home/dsh` — no `HOME`/`DSH_HOME` override, so the in-container AI locates every config via the official docs; the agents/skill shared root likewise follows the upstream default `~/.agents`. **No profile is pre-seeded** (#11): DSH initializes the built-in web profile (manifest + user patch layer + pnpm workspace) on first start and heals the module fallback symlink closure from `/app/dsh/node_modules`; out-of-tree plugins load into the profile directory at runtime via `dsh plugin add` (persistent, needs network), and the pnpm store points to the state volume via `npm_config_store_dir` (rootfs read-only). Telemetry is disabled via compose-injected `DSH_TELEMETRY_DISABLED=1` (upstream default on).
7. **Hardening** (default hardened): non-root (uid 10001 `dsh`), `cap_drop: ALL` + the regular default cap set, `no-new-privileges`, default seccomp kept, `read_only: true` + `/tmp` tmpfs + two writable points as volume/bind (`~/.dsh`, `~/workspace`), resource limits (pids/mem/cpu), tini as PID1, HEALTHCHECK probing 3080, STOPSIGNAL SIGTERM (DSH's own 5s graceful shutdown).

## Startup command (verified)

The DSH CLI canonical form is **`dsh --profile web`**; `dsh web` is its hardcoded equivalent alias (`@deepseek-ai/dsh/lib/bin.js`). **The container entrypoint uses `node --expose-internals .../dsh/lib/bin.js --profile web --patch /app/overlay/webstartup.yml`** — DSH's cordis-loader/HMR needs `--expose-internals` (NODE_OPTIONS forbids that flag, so it can only be an execArgv; when absent the HMR loader entry errors). Also available: `--dump-config` (troubleshooting), `--trusted-host` (remote /api trust fence).

## In-image layout

| Path | Nature | Notes |
|---|---|---|
| `/app` | read-only | code + `dsh/node_modules` (installed closure) + `overlay/` |
| `/home/dsh` | `$HOME` | real user home; the `.dsh` and `workspace` subpaths mount the volume/bind separately |
| `/home/dsh/.dsh` | state volume | harness home (upstream default `~/.dsh`); `profiles/web` is created by DSH on first start |
| `/home/dsh/workspace` | host bind mount (default `./workspace`) or in-volume directory | **session workspace**: overlay pins `sandbox-policy.workspaceRoot` and `fs-sandbox.cwd` here (baseline default `process.cwd()`). Placed under `$HOME` because work surfaces like the directory picker hardcode browsing from `homedir()` |
| `/tmp` | tmpfs | DSH spill/temp files (0700 private) |

## Release (from map #12)

- Target `ghcr.io/hyooeewee/dshc` (private package).
- Dual-job GitHub Actions pipeline (map #12 / ticket #16): job "pack" replicates
  the upstream pipeline on a native amd64 runner (upstream-tag guard → build →
  pack → verify smoke gate) and uploads the closure as artifacts; job "build"
  runs the multi-arch buildx build, which only installs the closure (arm64
  skips the full build under QEMU).
- The dshc git tag IS the version (npm-style, no `v` prefix); a tag push ships
  `<version>` + `latest` (newest release tag). `install/` (closure manifest +
  frozen lock) is a per-build product regenerated from each run's artifacts and
  is never committed. Full steps: `RELEASE.md`.
- Smoke test (#9): GUI reachable, bash tools inside the Landlock sandbox, in-container danger-full-access does not reach the host, volume persists across restarts, `dsh --profile headless` works.

## Out of scope (not implemented)

Multi-user/multi-tenant · built-in auth · public distribution/license audit · egress allowlist · Windows containers · k8s orchestration · DSH core features (upstream).
