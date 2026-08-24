# dshc — DeepSeek Harness Container

Run **DSH (DeepSeek Harness)** safely inside Docker: multi-arch (`linux/amd64` + `linux/arm64`),
default-hardened, built from a self-contained, reproducible dependency closure.

> 📖 中文文档：[README.zh.md](README.zh.md)
> Design: [docs/design.md](docs/design.md) · Security: [docs/security.md](docs/security.md) · Usage: [docs/usage.md](docs/usage.md)

## Quick start

```bash
export DEEPSEEK_API_KEY=sk-...          # DSH forbids DEEPSEEK_* in .env; inject via env
docker compose up -d --build
open http://127.0.0.1:3080              # host-side default binds only localhost
```

## Layout

```
Dockerfile               multi-stage (locked closure → hardened runtime)
entrypoint.sh            Landlock probe + 0.0.0.0 overlay + exec dsh (DSH self-initializes the profile)
compose.yml              default hardening (read_only / cap_drop / no-new-privileges / ports / volumes)
overlay/webstartup.yml   0.0.0.0 bind overlay (DSH rejects --host 0.0.0.0)
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

## Language

Project text is English by policy (see `AGENTS.md` → Language). `README.zh.md` is the Chinese translation.