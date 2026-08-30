# Release checklist (source-built images)

How a new DSH version ships as a dshc image. Everything hangs off one pin: the
**dshc git tag** (wayfinder map #12, endpoint ticket #16). The tag name IS the
upstream npm-style version — no `v` prefix, no `dshc` suffix.

## Tag = release

`git tag <version> && git push origin <version>` is the whole flow. CI:

- job **pack** — guard (`dsh-v<version>` must exist upstream) → shallow clone →
  `pnpm install --frozen-lockfile` → `build:official` → `release:pack`
  (dsh/vendor/landlock) → `verify-packed-install` smoke gate → artifacts;
- job **build** — regenerates `install/package.json` + `package-lock.json`
  **from those artifacts** (`gen-install-manifest.mjs` + `npm install
  --package-lock-only`), then builds the multi-arch image that installs exactly
  that closure, pushing `<version>` to ghcr.io + Docker Hub.

No pre-staged `install/` update is needed for a tag build — the manifest and
lock are recreated per run from the packed tarballs, so "give a version → ship".

## Recommended: keep `latest`/main in sync (optional)

After a successful tag release, refresh the committed `install/` so main's
`latest` and local `docker compose build` track the new version:

1. get the tarballs: download the `dsh-closure` artifact of that run (or run
   the pack pipeline yourself) → expand to `dist/{npm,npm-vendor,npm-landlock}`;
2. `node scripts/gen-install-manifest.mjs <version>` — rewrites
   `install/package.json` (251 `file:` deps, `engines` `^24`,
   `dshUpstreamVersion`, native-surface overrides) and strips `file:` integrity
   from `install/package-lock.json` (packed tarball bytes are not deterministic
   across runs);
3. regenerate the frozen lock: in node 24,
   `cd install && npm install --package-lock-only --no-audit --no-fund`;
4. sanity `docker build .` (needs `dist/` present), then commit.

## One-time semver migration (historical debt)

The old image was labeled `v0.1.1` but shipped `0.1.1-rc.2` (a pre-release
`< 0.1.1`). Alias `0.1.1-rc.2` on the old image (ghcr.io + Docker Hub) and let
`latest` follow the new source build.

## Notes

- The Dockerfile has no version input: it consumes whatever tarballs sit in
  `dist/`; the in-context `install/` pins their `file:` specifiers + lock.
- The closure install uses **npm**, not pnpm — same as the upstream
  `verify-packed-install`: pnpm cannot satisfy transitive `^0.1.x` ranges from
  `file:` tarballs (observed 404 on `@deepseek-ai/dsh-sdk-app`).
- Platform-native modules (node-pty via node-gyp, koffi via cmake) compile at
  install on the per-architecture image build; everything else is
  platform-neutral pure JS (prototype #15).
- Because the lock is regenerated per run, the npm-ci image layer rebuilds on
  every release (fresh install, not cached) — expected; registry-dependency
  resolution stays pinned by the overrides in `gen-install-manifest.mjs`.
- Main-branch (`latest`) builds resolve the version from
  `install/package.json`'s `dshUpstreamVersion`; guard, pipeline and smoke run
  the same way.
- Docker Hub overview is synced from `README.md` by the CI "Update Docker Hub
  description" step (plain `docker push` does not sync descriptions).