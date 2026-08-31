# Release checklist (source-built images)

How a new DSH version ships as a dshc image. Everything hangs off one pin: the
**dshc git tag** (wayfinder map #12, endpoint ticket #16). The tag name IS the
upstream npm-style version — no `v` prefix, no `dshc` suffix.

## Tag = release

`git tag <version> && git push origin <version>` is the whole flow. CI:

- job **pack** — guard (`dsh-v<version>` must exist upstream) → shallow clone →
  `pnpm install --frozen-lockfile` → `build:official` → `release:pack`
  (dsh/vendor/landlock) → `verify-packed-install` smoke gate → artifacts;
- job **build** — writes `install/package.json` + `package-lock.json` **from
  those artifacts** (`gen-install-manifest.mjs <version>` + `npm install
  --package-lock-only`), builds the multi-arch image that installs exactly that
  closure, pushing `<version>` **and `latest`** to ghcr.io + Docker Hub.

Nothing under `install/` is committed (`install/` is gitignored, `.gitignore`):
the manifest and lock are per-build products recreated from each run's packed
tarballs. Tag = release, `latest` = newest release tag.

## Local / main-branch builds

Main pushes and `workflow_dispatch` resolve the version from the **newest
release tag** (`git tag --list '[0-9]*' --sort=-v:refname`); a repo with no
release tag yet fails the run with a clear message. Building locally:

1. get the closure tarballs into `dist/{npm,npm-vendor,npm-landlock}` (CI
   artifact "dsh-closure", or run the pack pipeline yourself);
2. `node scripts/gen-install-manifest.mjs <version>` — writes
   `install/package.json` (251 `file:` deps, `engines` `^24`,
   `dshUpstreamVersion`, overrides; strips `file:` integrity from the lock);
3. `cd install && npm install --package-lock-only --no-audit --no-fund`
   (node 24) — regenerates the frozen lock;
4. `docker build .` or `docker compose up -d --build`.

## One-time semver migration (historical debt)

The old image was labeled `v0.1.1` but shipped `0.1.1-rc.2` (a pre-release
`< 0.1.1`). Alias `0.1.1-rc.2` on the old image (ghcr.io + Docker Hub) and let
`latest` follow the new source build.

## Notes

- The Dockerfile has no version input: it consumes whatever tarballs sit in
  `dist/`; the in-context `install/` pins their `file:` specifiers + lock.
- The closure install uses **npm**, not pnpm — same as the upstream
  `verify-packed-install`: pnpm cannot satisfy transitive `^0.1.x` ranges from
  `file:` tarballs (observed 404 on `@deepseek-ai/dsh-sdk-app`). The generator
  adds `react`/`react-dom` (^18.2.0) as explicit UI peer roots — npm's cold
  resolution needs react present to satisfy react-dom's peer (observed
  `react@undefined` ERESOLVE without them).
- Platform-native modules (node-pty via node-gyp, koffi via cmake) compile at
  install on the per-architecture image build; everything else is
  platform-neutral pure JS (prototype #15).
- Because the lock is regenerated per run, the npm-ci image layer rebuilds on
  every release (fresh install, not cached) — expected.
- Version drift against registry-latest is closed by the overrides in
  `gen-install-manifest.mjs` (`UPSTREAM_PINS`), pinned to the upstream tag's
  lockfile: natives koffi/@koromix-koffi-linux-\* 3.1.1, node-addon-require-builtin
  0.1.4; toolchain tsx 4.22.4, esbuild + @esbuild/linux-\* 0.28.1; schemastery
  neighbor protobufjs 7.6.4. Everything else resolves within the ranges upstream
  allowed (npm semantics, like the upstream verify gate). Note: upstream patches
  node-pty@1.2.0-beta.15 (same version we resolve); the patch is not applied by
  npm and only touches darwin spawn-helper — inert on the linux image.
- Docker Hub overview is synced from `README.md` by the CI "Update Docker Hub
  description" step (plain `docker push` does not sync descriptions).