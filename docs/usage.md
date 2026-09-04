# Runbook (dshc)

English | [中文](usage.zh.md)

## Environment variables (container runtime)

| Variable | Notes |
|---|---|
| `DEEPSEEK_API_KEY` | LLM credential (bootstrap variable; env injection only) |
| `DEEPSEEK_BASE_URL` | optional, custom LLM endpoint (default `https://api.deepseek.com`) |
| `DSH_PERMISSION_MODE` | `workspace-write` (default) / `danger-full-access` (container only) |
| `DSHC_LOCALE` / `DSHC_THEME` | first-boot preference seed: GUI language (`zh`/`en`) and appearance (`light`/`dark`/`system`). The entrypoint writes only when `settings.yaml` does not yet exist; later GUI edits persist to that file and restarts never overwrite it |

> Telemetry: compose injects `DSH_TELEMETRY_DISABLED=1` fixed (upstream default on; the variable is a one-way switch, any non-empty value disables). To enable telemetry, delete that line in compose.yml.
>
> Working directory: the session workspace is pinned via overlay to `/home/dsh/workspace` (i.e. host `./workspace`, under `$HOME` — work surfaces like the directory picker hardcode browsing from `homedir()`, so the workspace must live inside the home to be visible). The baseline composition defaults to `process.cwd()`; overlay overrides `sandbox-policy.workspaceRoot` and `fs-sandbox.cwd`; to adjust, edit `overlay/webstartup.yml`.

## Key injection

```bash
# host-side .env (gitignored); compose passes it to the container automatically
cat >> .env <<'EOF'
DEEPSEEK_API_KEY=sk-...
EOF
docker compose up -d --build
```

DSH uses `DEEPSEEK_API_KEY` as the default credential; alternatively pre-seed `.credentials.yaml` in the state volume (DSH's native credentials mechanism).

## .env parameters (build and run)

The project-root `.env` (gitignored; template in [.env.example](../.env.example)) is read automatically by compose, so no `--build-arg` is needed:

| Variable | Default | Notes |
|---|---|---|
| `APT_MIRROR` / `NPM_REGISTRY` | upstream official sources | switch to domestic mirrors on slow networks (**build-time** effect) |
| `DSHC_PORT` | `3080` | host-side GUI port (always bound to loopback only; dshc has no built-in auth, see [security](security.md)) |
| `DSH_PERMISSION_MODE` | `workspace-write` | in-container agent permission mode |

After changing build parameters rerun `docker compose build`; runtime parameters take effect on `docker compose up -d` restart.

## Plugins: runtime install

The image ships only the official in-box closure. Install out-of-tree plugins via DSH's native mechanism (pnpm into the state volume's profile directory; persistent, needs network):

```bash
docker compose exec dshc dsh plugin --profile web add <package>
```

> Note: this scheme no longer has "template copy" nor a `DSH_ALLOW_PLUGIN_INSTALL` switch (removed by #11); the profile is auto-initialized by DSH on first start.

## Upgrading DSH (rebuild the image)

Where the version pins live:

| What is pinned | Where | Who verifies |
|---|---|---|
| DSH version | dshc git tag (tag = version pin); main builds resolve from the newest release tag | CI job "pack" upstream-tag guard + verify smoke gate |
| Closure | `file:` tarball deps in the per-build `install/package.json` + `package-lock.json` | frozen `npm ci` install |
| Node major | `engines.node` written by the generator into `install/package.json` + `NODE_VERSION` at the top of the Dockerfile | warning on mismatch at install; the FROM tag cannot read the manifest, so the two must change together |

Upgrading = follow [RELEASE.md](RELEASE.md): `git tag <new version> && git push origin <new version>` (CI packs → generates manifest+lock on the spot → multi-arch release `<new version>` + `latest`). A local build needs: `dist/` closure present → `node scripts/gen-install-manifest.mjs <version>` → inside node 24 `cd install && npm install --package-lock-only --no-audit --no-fund` → `docker compose build` → restart.

> Upgrading from an older version: run `docker compose down -v` first to reset the state volume. Both legacy volume kinds are expected to fail: volumes from the template/ three-file era list removed community packages and the new image refuses to start on parse failure; volumes from the first official-closure build (`DSH_HOME=/data`) keep data at top-level paths like `/data/profiles/`, whereas this version's harness home returns to the upstream default `~/.dsh` = `/data/.dsh` — the old data is not read, and DSH re-initializes as a fresh state.

## Remote access

By default `localhost:3080` is local-only. Three remote options:
- **SSH tunnel** (recommended, zero added services): `ssh -L 3080:127.0.0.1:3080 user@host`, then visit local `http://127.0.0.1:3080`.
- **cloudflared quick tunnel**: first install an out-of-tree plugin that provides it (see the Plugins section).
- **Reverse proxy**: Nginx/Caddy + TLS (+ basic auth), and pass `--trusted-host` to DSH.

## Troubleshooting

- `docker compose logs -f dshc` — watch startup logs and the `[dshc] sandbox:` self-check lines.
- `docker compose exec dshc dsh --profile web --dump-config` — dump the composition tree; confirm `webserver.config.host=0.0.0.0` applied.
- Sandbox unavailable: confirm the host kernel has `CONFIG_SECURITY_LANDLOCK=y` and `CONFIG_LSM` includes `landlock`; or, when bwrap is needed, use `--security-opt seccomp=unconfined` + an unprivileged userns and install bwrap inside the container yourself (not bundled by default; advanced).
- Port not open: confirm `docker compose ps` lists `127.0.0.1:3080->3080`; do not mistake the in-container bind for the overlay not having applied.
- State not persisting: `docker compose down` does not delete volumes; only `docker compose down -v` deletes `/data`.

## Headless one-shot mode (CI-friendly)

The image entrypoint boots the **web** profile by default (with the 0.0.0.0 overlay), so running headless requires **overriding the entrypoint** to reach the headless boot. DSH requires `node --expose-internals` (used by the cordis loader/HMR; NODE_OPTIONS forbids that flag, so it can only be an execArgv), so call bin.js directly:

```bash
docker compose run --rm --entrypoint "node --expose-internals" dshc \
  /app/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js --profile headless "your task"
```

No listening port, exits when done — convenient for scripting/CI.
