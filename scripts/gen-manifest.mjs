import { execSync } from "node:child_process";
import { mkdirSync, readdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const dist = join(root, "dist");
const manifestPath = join(root, "package.json");

const tarName = (tgz) => {
  const out = execSync(`tar -xOf ${JSON.stringify(tgz)} package/package.json`, {
    encoding: "utf8",
  });
  return JSON.parse(out).name;
};

const scan = (subdir) =>
  existsSync(join(dist, subdir))
    ? readdirSync(join(dist, subdir))
        .filter((f) => f.endsWith(".tgz"))
        .sort()
    : [];

let version = process.argv[2];
if (!version) {
  const dsh = scan("npm").find((f) => /^deepseek-ai-dsh-(.+)\.tgz$/.test(f));
  if (!dsh)
    throw new Error(
      'no @deepseek-ai/dsh tarball in dist/npm — run CI job "pack" first or pass the version',
    );
  version = dsh.match(/^deepseek-ai-dsh-(.+)\.tgz$/)[1];
}

const dependencies = {};
for (const subdir of ["npm", "npm-vendor", "npm-landlock"]) {
  for (const file of scan(subdir)) {
    const name = tarName(join(dist, subdir, file));
    dependencies[name] = `file:../dist/${subdir}/${file}`;
  }
}
dependencies["react"] = "^18.2.0";
dependencies["react-dom"] = "^18.2.0";

mkdirSync(dirname(manifestPath), { recursive: true });
const manifest = existsSync(manifestPath)
  ? JSON.parse(readFileSync(manifestPath, "utf8"))
  : { name: "dsh-closure", version: "0.0.0", private: true };
manifest.packageManager = "pnpm@11.7.0"; // upstream release baseline
manifest.engines = { node: "^24.0.0" }; // runtime base image is node 24
manifest.dshUpstreamVersion = version;
manifest.dependencies = dependencies;
writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + "\n");

console.log(`manifest: ${manifestPath}`);
console.log(`dshUpstreamVersion: ${version}`);
console.log(
  `dependencies: ${Object.keys(dependencies).length} (${Object.keys(dependencies).length - 2} file: tarballs + react + react-dom)`,
);
