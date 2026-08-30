# Release checklist (source-built images)

How a new DSH version ships as a dshc image. Everything hangs off one pin: the
**dshc git tag** (wayfinder map #12, endpoint ticket #16). The tag name IS the
upstream npm-style version — no `v` prefix, no `dshc` suffix.

## Steps

1. **Pick the upstream release**: a git tag `dsh-v<version>` in
   `github.com/deepseek-ai/deepseek-harness` (upstream tag naming is `dsh-v`
   + npm-style version; GitHub releases lead npm publish by design — source
   builds track the tag, not the registry).

2. **Re-pin the closure for `<version>`**:
   - put the packed tarballs at `dist/{npm,npm-vendor,npm-landlock}` — CI job
     "pack" produces them; locally, run the upstream pipeline yourself or pull
     the `dsh-closure` artifact from a successful workflow run;
   - `node scripts/gen-install-manifest.mjs <version>` — rewrites
     `install/package.json` (every family tarball as a `file:` dep,
     `engines` `^24`, `dshUpstreamVersion`);
   - regenerate the frozen lockfile inside node 24:
     `npm install --package-lock-only --no-audit --no-fund`
     (in `install/`; the lock records the full tree — platform optionals included);
   - sanity-check that the closure installs frozen: `docker build .` (needs
     `dist/` present).

3. **Smoke the image**:
   `docker run --rm --entrypoint node dshc:test /app/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js --version`
   → must print `<version>`.

4. **Tag and ship**: `git tag 0.1.2-alpha.1 && git push origin 0.1.2-alpha.1`.
   CI runs job "pack" (upstream-tag guard → pipeline → verify smoke gate) then
   job "build" (linux/amd64 + arm64 images, `0.1.2-alpha.1` + `latest` tags).

5. **One-time semver migration** (historical debt): the old image was labeled
   `v0.1.1` but shipped `0.1.1-rc.2` (a pre-release `< 0.1.1`). Alias
   `0.1.1-rc.2` on the old ghcr image and let `latest` follow the new source
   build. (docker.io/godotttt is discontinued — deleted.)

## Notes

- The Dockerfile has no version input: it consumes whatever tarballs sit in
  `dist/`; the committed `install/` manifest pins their `file:` specifiers and
  the lockfile.
- The closure install uses **npm**, not pnpm — same as the upstream
  `verify-packed-install`: pnpm cannot satisfy transitive `^0.1.x` ranges from
  `file:` tarballs (observed 404 on `@deepseek-ai/dsh-sdk-app`).
- Platform-native modules (node-pty via node-gyp, koffi via cmake) compile at
  install on the per-architecture image build; everything else is
  platform-neutral pure JS (prototype #15).
- Main-branch (`latest`) builds take the version from
  `install/package.json`'s `dshUpstreamVersion`; guard, pipeline and smoke run
  the same way.