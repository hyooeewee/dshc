# dshc — DeepSeek Harness Container

> 📖 English · [中文](README.zh.md)

Run **DSH (DeepSeek Harness)** safely inside Docker: multi-arch (`linux/amd64` + `linux/arm64`),
default-hardened, built from the upstream **GitHub tag source** — GitHub releases lead npm
publish by design, so images track the tag: the closure is packed once at that tag and
installed per architecture (map #12).

Design decisions: [docs/design.md](docs/design.md) · Security boundaries: [docs/security.md](docs/security.md) · Runbook: [docs/usage.md](docs/usage.md) · Release flow: [RELEASE.md](RELEASE.md) · Wayfinder maps: [hyooeewee/dshc#1](https://github.com/hyooeewee/dshc/issues/1), [#12](https://github.com/hyooeewee/dshc/issues/12).

## Quick start

```bash
cp .env.example .env                     # then set your key inside: DEEPSEEK_API_KEY=sk-...
docker compose up -d --build
open http://127.0.0.1:3080               # host port via DSHC_PORT in .env (default 3080)
```

Local builds need the packed closure under `dist/` **and** a generated `install/`
(CI produces both — download the `dsh-closure` artifact from a workflow run, or run
the pack pipeline yourself; then run the two commands under [Build](#build); see
[RELEASE.md](RELEASE.md)).

Alternatively `export DEEPSEEK_API_KEY=sk-...` instead of `.env`. DSH forbids `DEEPSEEK_*`
in container-side files; inject through the host-side environment either way.

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

All knobs live in `.env` (template: [.env.example](.env.example)) — build-time mirrors
(`APT_MIRROR`, `NPM_REGISTRY`) and runtime settings alike.

## Layout

```
Dockerfile               multi-stage (packed closure install → hardened runtime)
entrypoint.sh            first-boot preference seed + Landlock probe + exec dsh (DSH self-initializes the profile)
compose.yml              default hardening (read_only / cap_drop / no-new-privileges / ports / volumes)
overlay/webstartup.yml   composition overlay (0.0.0.0 bind — DSH rejects --host 0.0.0.0 — and ~/workspace pins)
install/                 generated closure manifest + lock (gitignored; per-build products)
dist/                    packed closure tarballs (CI job "pack" artifacts; gitignored, required for the build)
scripts/                 gen-install-manifest.mjs — regenerates install/ for a version
docs/                    design / security / usage
RELEASE.md               release checklist (tag = version pin)
```

## Build

The Dockerfile consumes the **packed closure** under `dist/` — it does not pull DSH from
the registry. CI produces those tarballs by replicating the upstream release pipeline at
an explicit tag (`.github/workflows/docker-build.yml`, job "pack"); locally you need them too:

```bash
# 1. get the closure tarballs into dist/ (CI artifact "dsh-closure", or run the pack
#    pipeline yourself — see RELEASE.md)
# 2. generate install/ (manifest + frozen lock; node 24):
node scripts/gen-install-manifest.mjs 0.1.2-alpha.1
cd install && npm install --package-lock-only --no-audit --no-fund
# 3. build (multi-arch publish is CI's job; docker compose build works too)
docker build -t ghcr.io/hyooeewee/dshc:latest .
docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/hyooeewee/dshc:latest --push .
```

Images publish to `ghcr.io/hyooeewee/dshc` (private package) and `godotttt/dshc` (Docker
Hub; its overview is synced from this README). The closure is installed with npm (the
upstream `verify-packed-install` semantics — pnpm cannot satisfy transitive `^0.1.x`
ranges from `file:` tarballs), so builds are reproducible without private registry
access. On throttled networks set `APT_MIRROR` / `NPM_REGISTRY` in `.env`.

Releases are tag-driven: a tag push makes CI pack the upstream `dsh-v<version>` and
install exactly those artifacts, publishing `<version>` **and** `latest` (latest =
newest release tag; main pushes rebuild `latest` from the newest tag). The `install/`
manifest + lock are per-build products, never committed.

## License note

The repo is public while the image package stays private. Redistribution terms of DSH and
its dependencies (`@deepseek-ai/*`) are unreviewed — evaluate before distributing images
publicly (map #1, "Out of scope").

## Language

Project text is English by policy (see `AGENTS.md` → Language). `README.zh.md` is the
Chinese counterpart of this file; the two carry the same content.
