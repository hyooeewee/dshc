# Security boundaries and hardening (dshc)

English | [中文](security.zh.md)

## The container boundary is the trust line

Default **zero host exposure**: every in-container agent capability (`workspace-write`/`danger-full-access` file permissions, bash execution, background jobs, SSH) happens inside the container boundary — invisible and unwritable to the host. **Only three explicit channels cross the boundary**:

1. **Port mapping** — compose defaults to `127.0.0.1:3080:3080`, exposing only localhost.
2. **Volume mounts** — by default only the state volume (at the upstream-default `~/.dsh`). **Mounting a host working directory crosses the boundary** (an agent's `danger-full-access` can write host files through the mount point); do it only deliberately, informed, and at your own risk, preferably read-only.
3. **Egress network** — LLM API, web_search, SSH plugins, etc. egress on demand; wildcard allowed.

**Note**: in-container `danger-full-access` mode is not host root — it only lets the agent fill *the container's* filesystem. What truly widens the blast radius is a "host directory mount".

## Hardening checklist (compose defaults)

- `read_only: true` — rootfs read-only; the only writable points are `~/.dsh` (state volume), `~/workspace` (workspace), `/tmp` (tmpfs).
- Runs as non-root user uid 10001 `dsh`.
- `cap_drop: ALL` + the regular default caps restored (no extra privilege).
- `security_opt: no-new-privileges:true`.
- Default seccomp kept; **not relaxed for the sandbox** (#2: Landlock works under default seccomp).
- `pids_limit / mem_limit / cpus` resource caps.
- tini PID1 + STOPSIGNAL SIGTERM (DSH's 5s graceful shutdown) + HEALTHCHECK.

## Sandbox (Linux)

DSH uses **bash** mode on Linux, handing commands to the sandbox via `bash -c`: the backend chain `bwrap → landlock` falls back automatically on probe. Under default seccomp **Landlock** applies (three landlock syscalls unconditionally allowed + no_new_privs); **bwrap does not work** (`unshare/mount/pivot_root` are blocked). **The image does not bundle bwrap by default** — default hardening relies entirely on Landlock; using bwrap (`seccomp=unconfined`, etc.) requires installing it in the container yourself (advanced). If the target kernel lacks `CONFIG_SECURITY_LANDLOCK=y` and the LSM does not include `landlock`, Landlock is unavailable — that is the only point where the host kernel needs evaluation. Logs can show the `[dshc] sandbox:` self-check line via `docker logs`.

## Secrets

- `DEEPSEEK_API_KEY` and other DEEPSEEK_* variables are DSH bootstrap variables; **do not write them to `.env`** — inject via environment (`docker compose` `environment:` / `--env-file`), ideally in a host-side `.env` that is gitignored.
- If a credential-writing out-of-tree plugin is installed at runtime (e.g. dsh-ssh, whose `dsh-ssh.json` holds plaintext passwords), the file lands in the state volume → treat its backups/permissions as credentials.
- The repo is public: **never write secrets into any issue/ticket/commit** (map #1 Notes already states this).

## Auth and remote access

The container has **no built-in auth**. By default it serves localhost only. For remote access use an **SSH tunnel**, a **cloudflared quick tunnel** (requires installing the corresponding out-of-tree plugin yourself) or a **reverse proxy + basic auth**, and set `--trusted-host`; do not map 3080 directly to the public internet.

## Plugins and image version

The image contains only the official in-box closure (`@deepseek-ai/*`); the rootfs is read-only, so the image *is* the version. To install out-of-tree plugins use DSH's native mechanism `docker compose exec dshc dsh plugin --profile web add <package>` (pnpm into the state volume's profile directory; persistent, needs network). Runtime plugins can only write inside the state volume; the image closure stays immutable.
