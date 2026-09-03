# dshc — DeepSeek Harness Container

> 📖 English · [中文](README.zh.md)

Run DSH (DeepSeek Harness) safely inside Docker: multi-arch (`linux/amd64` + `linux/arm64`), default-hardened, built from a self-contained, reproducible dependency closure.

- Design decisions: [docs/design.md](docs/design.md)
- Security boundaries: [docs/security.md](docs/security.md)
- Runbook: [docs/usage.md](docs/usage.md)
- Release flow: [RELEASE.md](RELEASE.md)

## Quick start

```bash
cp .env.example .env                     # then set your key inside: DEEPSEEK_API_KEY=sk-...
docker compose up -d --build
open http://127.0.0.1:3080               # host port via DSHC_PORT in .env (default 3080)
```

Alternatively `export DEEPSEEK_API_KEY=sk-...` instead of `.env`. DSH forbids `DEEPSEEK_*` in container-side files; inject through the host-side environment either way.

## Features & boundaries

| Area | Decision | Docs |
|---|---|---|
| Platform | Linux amd64 + arm64 multi-arch on bookworm-slim | [design](docs/design.md) |
| Version source | Upstream GitHub tag source build (e.g. `0.1.2-alpha.1`); the dshc git tag IS the version pin — npm-style naming, no `v` prefix | [release](RELEASE.md) |
| State | Stateless image; named volume mounted at the upstream-default `~/.dsh` (= `/home/dsh/.dsh`); code read-only | [design](docs/design.md) |
| Workspace | Isolated at `~/workspace` by default, never touches the host; an explicit bind = deliberate boundary crossing | [security](docs/security.md) |
| Sessions | `workspace-write` + GUI approval by default; `danger-full-access` affects the container only | [security](docs/security.md) |
| Sandbox | Linux Landlock (works under default seccomp, zero extra privileges); bwrap not bundled (advanced: self-install) | [security](docs/security.md) |
| Network | Egress open; inbound only the GUI port (`DSHC_PORT`, bound to localhost); no built-in auth | [security](docs/security.md) |
| Credentials | `DEEPSEEK_API_KEY` injected via environment/`.env`; never stored container-side | [usage](docs/usage.md) |
| Plugins | Image ships the official closure only; extra plugins install at runtime via `dsh plugin add` (into the state volume, needs network) | [usage](docs/usage.md) |
| Preferences | `DSHC_LOCALE` / `DSHC_THEME` seed language & appearance on first boot; later GUI edits persist and are never overwritten | [usage](docs/usage.md) |
| Remote access | `DSHC_TRUSTED_HOSTS` (comma-separated) allows non-localhost access via `--trusted-host` | [usage](docs/usage.md) |

All knobs live in `.env` (template: [.env.example](.env.example)) — build-time mirrors (`APT_MIRROR`, `NPM_REGISTRY`) and runtime settings alike.

## Layout

```
Dockerfile               multi-stage (packed closure install → hardened runtime)
entrypoint.sh            first-boot preference seed + Landlock probe + wslpath + token capture + trusted-hosts + exec dsh
compose.yml              default hardening (read_only / cap_drop / no-new-privileges / ports / volumes)
overlay/webstartup.yml   composition overlay (0.0.0.0 bind — DSH rejects --host 0.0.0.0 — and ~/workspace pins)
install/                 generated closure manifest + lock (gitignored; per-build products)
dist/                    packed closure tarballs (CI job "pack" artifacts; gitignored, required for the build)
scripts/gen-manifest.mjs regenerates install/ (package.json + pnpm-lock.yaml) for a version
docs/                    design / security / usage
RELEASE.md               release checklist (tag = version pin)
```

## How it works

### CI/CD pipeline (`.github/workflows/cd.yml`)

**Job 1: pack** (runs on tag push or `workflow_dispatch`)
1. Checks out upstream `deepseek-ai/deepseek-harness` at `dsh-<tag>`
2. `pnpm install --frozen-lockfile` + `build:official`
3. Packs three closure families via `pnpm run release:pack`:
   - `dist/npm` — `@deepseek-ai/dsh` family
   - `dist/npm-vendor` — vendored framework (`cordis`, `cosmokit`, `schemastery`, etc.)
   - `dist/npm-landlock` — `@deepseek-ai/node-addon-landlock-run` entry point
4. Verifies the packed install, uploads tarballs as artifact

**Job 2: build** (depends on pack)
1. Downloads closure tarballs, lays them out under `dist/`
2. Runs `scripts/gen-manifest.mjs <version>` → generates `package.json` with `file:./dist/...` dependencies
3. `pnpm install --lockfile-only` → generates `pnpm-lock.yaml` from the manifest
4. Commits `package.json` + `pnpm-lock.yaml` to `main` branch (via `git-auto-commit-action`)
5. Multi-arch Docker build (`linux/amd64,linux/arm64`) with GHA layer cache, pushes to:
   - `ghcr.io/hyooeewee/dshc`
   - `godotttt/dshc` (Docker Hub)
6. Updates Docker Hub description from README

### Docker build (pnpm full-chain)

The Dockerfile consumes the packed closure under `dist/` — it does **not** pull DSH from npm registry.

```dockerfile
# builder stage
COPY package.json pnpm-lock.yaml dist/ ./
RUN corepack enable \
  && pnpm install --prod --frozen-lockfile --ignore-scripts --update-checksums \
  && pnpm store prune

# runtime stage
COPY --from=builder /buildspace/node_modules ./dsh/node_modules
```

Key points:
- **pnpm end-to-end**: upstream pack uses pnpm, lockfile generated by pnpm, Docker installs with pnpm — zero npm/pnpm resolution drift
- `--prod`: install production deps only
- `--frozen-lockfile`: enforce exact versions from generated lockfile
- `--ignore-scripts`: skip build scripts (native addons are prebuilt in tarballs)
- `--update-checksums`: accept local tarball checksums (they differ from registry)
- `pnpm store prune`: reduce image size

### Entrypoint (`entrypoint.sh`)

On container start:
1. **First-boot prefs**: seeds `settings.yaml` with `DSHC_LOCALE` / `DSHC_THEME` (only if file missing; GUI edits never overwritten)
2. **Landlock probe**: resolves `@deepseek-ai/node-addon-landlock-run` platform binary via package's own resolution logic; probes availability (skips gracefully if optional dep missing)
3. **wslpath**: installs `/usr/local/bin/wslpath` (Node.js script) for Windows path translation (used by DSH for WSL2 host paths)
4. **Trusted hosts**: reads `DSHC_TRUSTED_HOSTS` (comma-separated), passes `--trusted-host` to DSH for non-localhost access
5. **Token capture**: captures `token=...` from stdout, writes to `~/.dsh/.web-auth` for GUI auto-login
6. **Exec DSH**: runs `node --expose-internals dsh bin.js --profile web --patch /app/overlay/webstartup.yml`

## Build locally

You need the closure tarballs under `dist/` (download CI artifact `dsh-closure` or run the pack pipeline):

```bash
# 1. get closure tarballs into dist/ (CI artifact "dsh-closure", or run pack pipeline)
# 2. generate install/ (manifest + frozen lock; node 24):
node scripts/gen-manifest.mjs 0.1.2-alpha.1
pnpm install --lockfile-only
# 3. build (multi-arch publish is CI's job; docker compose build works too)
docker build -t ghcr.io/hyooeewee/dshc:latest .
docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/hyooeewee/dshc:latest --push .
```

Images publish to `ghcr.io/hyooeewee/dshc` (private package) and `godotttt/dshc` (Docker Hub; its overview is synced from this README). On throttled networks set `APT_MIRROR` / `NPM_REGISTRY` in `.env`.

Releases are tag-driven: a tag push makes CI pack the upstream `dsh-v<version>` and install exactly those artifacts, publishing `<version>` **and** `latest` (latest = newest release tag; main pushes rebuild `latest` from the newest tag). The `install/` manifest + lock are per-build products, auto-committed to `main` by CI.

## License note

The repo is public while the image package stays private. Redistribution terms of DSH and its dependencies (`@deepseek-ai/*`) are unreviewed — evaluate before distributing images publicly.

## Language

Project text is English by policy (see `AGENTS.md` → Language). `README.zh.md` is the Chinese counterpart of this file; the two carry the same content.