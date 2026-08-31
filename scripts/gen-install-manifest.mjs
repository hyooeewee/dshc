#!/usr/bin/env node
// Regenerates install/package.json + package-lock.json from the packed closure
// tarballs under dist/ (CI artifact layout: dist/npm, dist/npm-vendor,
// dist/npm-landlock). Both files are build products: nothing under install/ is
// committed (dshc/AGENTS + .gitignore); the release pipeline writes them per
// build. Usage: node scripts/gen-install-manifest.mjs [version]
// The version defaults to the @deepseek-ai/dsh tarball in dist/npm.
// Decision record: wayfinder map #12, ticket #16 (git tag is the version pin;
// `latest` and local dev builds read the newest release tag from git).
import { execSync } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const dist = join(root, 'dist');
const manifestPath = join(root, 'install', 'package.json');

const tarName = (tgz) => {
  // pnpm pack names: <scope-without-@ where / -> ->... e.g. deepseek-ai-dsh-0.1.2-alpha.1.tgz
  const out = execSync(`tar -xOf ${JSON.stringify(tgz)} package/package.json`, { encoding: 'utf8' });
  return JSON.parse(out).name;
};

const scan = (subdir) =>
  existsSync(join(dist, subdir))
    ? readdirSync(join(dist, subdir)).filter((f) => f.endsWith('.tgz')).sort()
    : [];

// Registry deps pinned to the versions the upstream tag's lockfile tested
// (research #14 / map #12): native/platform surface (koffi, require-builtin)
// AND the toolchain (tsx/esbuild + esbuild platform binaries) drift against
// registry-latest otherwise (observed koffi 3.1.6 vs 3.1.1, esbuild 0.28.2 vs
// 0.28.1, tsx 4.23.13 vs 4.22.4). Everything else resolves within the ranges
// the upstream lockfile allowed; the exact match is enforced by npm overrides.
const UPSTREAM_PINS = {
  'koffi': '3.1.1',
  '@koromix/koffi-linux-x64': '3.1.1',
  '@koromix/koffi-linux-arm64': '3.1.1',
  'node-addon-require-builtin': '0.1.4',
  'protobufjs': '7.6.4',
  'tsx': '4.22.4',
  'esbuild': '0.28.1',
  '@esbuild/linux-x64': '0.28.1',
  '@esbuild/linux-arm64': '0.28.1',
};

let version = process.argv[2];
if (!version) {
  const dsh = scan('npm').find((f) => /^deepseek-ai-dsh-(.+)\.tgz$/.test(f));
  if (!dsh) throw new Error('no @deepseek-ai/dsh tarball in dist/npm — run CI job "pack" first or pass the version');
  version = dsh.match(/^deepseek-ai-dsh-(.+)\.tgz$/)[1];
}

const dependencies = {};
for (const subdir of ['npm', 'npm-vendor', 'npm-landlock']) {
  for (const file of scan(subdir)) {
    const name = tarName(join(dist, subdir, file));
    dependencies[name] = `file:../dist/${subdir}/${file}`;
  }
}
// UI peer roots: family client packages declare react on ^18.x and react-dom's
// peer react@^18.3.1 must be satisfied by a root dep for npm's cold resolution
// (observed react@undefined ERESOLVE on a fresh install/ without a lock).
dependencies['react'] = '^18.2.0';
dependencies['react-dom'] = '^18.2.0';

mkdirSync(dirname(manifestPath), { recursive: true });
// Preserve hand-tuned fields if package.json exists, else start from a minimal
// base: nothing under install/ is committed, so a fresh checkout has no file.
const manifest = existsSync(manifestPath)
  ? JSON.parse(readFileSync(manifestPath, 'utf8'))
  : { name: 'dsh-closure', version: '0.0.0', private: true };
manifest.packageManager = 'pnpm@11.7.0'; // upstream release baseline
manifest.engines = { node: '^24.0.0' }; // runtime base image is node 24
manifest.dshUpstreamVersion = version;
manifest.dependencies = dependencies;
manifest.overrides = UPSTREAM_PINS;
writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');

// npm 11 records a sha512 integrity for each file: tarball at lock generation.
// Tarballs are re-generated per release (gzip mtimes differ between runs) and
// install/ is a per-build product, so a stale lock with byte-level integrity
// would fail npm ci with EINTEGRITY (e.g. rebuilding locally after downloading
// a newer artifact). Strip it — the specifier keeps pinning path/version,
// registry deps keep their own integrity.
const lockPath = join(root, 'install', 'package-lock.json');
if (existsSync(lockPath)) {
  const lock = JSON.parse(readFileSync(lockPath, 'utf8'));
  let stripped = 0;
  for (const entry of Object.values(lock.packages)) {
    if (entry && typeof entry.resolved === 'string' && entry.resolved.startsWith('file:')) {
      delete entry.integrity;
      stripped += 1;
    }
  }
  if (stripped) {
    writeFileSync(lockPath, JSON.stringify(lock, null, 2) + '\n');
    console.log(`lock: stripped file: integrity from ${stripped} entries`);
  }
}

console.log(`manifest: ${manifestPath}`);
console.log(`dshUpstreamVersion: ${version}`);
console.log(`dependencies: ${Object.keys(dependencies).length} (${Object.keys(dependencies).length - 2} file: tarballs + react + react-dom)`);