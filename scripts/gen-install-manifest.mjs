#!/usr/bin/env node
// Regenerates install/package.json from the packed closure tarballs under
// dist/ (CI artifact layout: dist/npm, dist/npm-vendor, dist/npm-landlock).
// Usage: node scripts/gen-install-manifest.mjs [version]
// The version defaults to the @deepseek-ai/dsh tarball in dist/npm.
// Decision record: wayfinder map #12, ticket #16 (git tag is the version pin;
// install/package.json carries the upstream version for main-branch builds).
import { execSync } from 'node:child_process';
import { readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
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

// Native/platform registry deps pinned to the versions the upstream tag's
// lockfile tested (research #14 / map #12). Reproducibility of the native
// surface matters: registry-latest may differ (observed koffi 3.1.6 vs 3.1.1).
// Pure-JS minors (tsx/esbuild/protobufjs drift) stay within-range by design.
const UPSTREAM_PINS = {
  'koffi': '3.1.1',
  '@koromix/koffi-linux-x64': '3.1.1',
  '@koromix/koffi-linux-arm64': '3.1.1',
  'node-addon-require-builtin': '0.1.4',
  'protobufjs': '7.6.4',
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

const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
manifest.packageManager = 'pnpm@11.7.0'; // upstream release baseline
manifest.engines = { node: '^24.0.0' }; // runtime base image is node 24
manifest.dshUpstreamVersion = version;
manifest.dependencies = dependencies;
manifest.overrides = UPSTREAM_PINS;
writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');

console.log(`manifest: ${manifestPath}`);
console.log(`dshUpstreamVersion: ${version}`);
console.log(`dependencies: ${Object.keys(dependencies).length} file: tarballs`);