# dshc — DeepSeek Harness Container

> 📖 English · [中文](README.zh.md)

Run **DSH (DeepSeek Harness)** safely inside Docker: multi-arch (`linux/amd64` + `linux/arm64`),
default-hardened, built from a self-contained, reproducible dependency closure.

Design decisions: [docs/design.md](docs/design.md) · Security boundaries: [docs/security.md](docs/security.md) · Runbook: [docs/usage.md](docs/usage.md) · Driven by the wayfinder map [hyooeewee/dshc#1](https://github.com/hyooeewee/dshc/issues/1).

## Quick start

```bash
cp .env.example .env                     # then set your key inside: DEEPSEEK_API_KEY=sk-...
docker compose up -d --build
open http://127.0.0.1:3080               # host port via DSHC_PORT in .env (default 3080)
```

Alternatively `export DEEPSEEK_API_KEY=sk-...` instead of `.env`. DSH forbids `DEEPSEEK_*`
in container-side files; inject through the host-side environment either way.

## Features & boundaries

| Area | Decision | Docs |
|---|---|---|
| Platform | Linux amd64 + arm64 multi-arch on bookworm-slim | [design](docs/design.md) |
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
Dockerfile               multi-stage (locked closure → hardened runtime)
entrypoint.sh            first-boot preference seed + Landlock probe + exec dsh (DSH self-initializes the profile)
compose.yml              default hardening (read_only / cap_drop / no-new-privileges / ports / volumes)
overlay/webstartup.yml   composition overlay (0.0.0.0 bind — DSH rejects --host 0.0.0.0 — and ~/workspace pins)
install/                 minimal install manifest (@deepseek-ai/dsh only; frozen lockfile, minimumReleaseAge:0)
docs/                    design / security / usage
```

## Build

```bash
docker build -t ghcr.io/hyooeewee/dshc:latest .
# multi-arch publish (CI also does this; see .github/workflows/docker-build.yml)
docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/hyooeewee/dshc:latest --push .
```

Images publish to `ghcr.io/hyooeewee/dshc` (private package). DSH is a public npm
closure (frozen lockfile), so builds are reproducible without private registry access.
On throttled networks set `APT_MIRROR` / `NPM_REGISTRY` in `.env`.

## License note

The repo is public while the image package stays private. Redistribution terms of DSH and
its dependencies (`@deepseek-ai/*`) are unreviewed — evaluate before distributing images
publicly (map #1, "Out of scope").

## Language

Project text is English by policy (see `AGENTS.md` → Language). `README.zh.md` is the
Chinese counterpart of this file; the two carry the same content.
