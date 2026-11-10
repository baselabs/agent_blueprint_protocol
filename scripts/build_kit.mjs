// Kit assembly for @agent-blueprint-protocol/verifier.
//
//   node scripts/build_kit.mjs        (after `tsc -p tsconfig.json`)
//
// Stages the installable surface under dist/: the embedded corpus (a
// byte-identical copy of the certified priv/conformance tree — the
// agreement gate asserts the digest equality) and the kit bin wrapper.
// The verifier CLI's own contract stays explicit-only (--corpus
// required, no default, no vacuous run); the WRAPPER supplies the
// embedded corpus as the default so `npx` verifies out of the box.

import { copyFileSync, cpSync, mkdirSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
if(process.argv[2]==="--clean"){rmSync(join(root,"dist"),{recursive:true,force:true});process.exit(0);}

rmSync(join(root,"dist/package"),{recursive:true,force:true});
rmSync(join(root,"dist/corpus"),{recursive:true,force:true});
cpSync(join(root, "priv/conformance"), join(root, "dist/corpus"), { recursive: true });

// The release-identity manifest rides the kit byte-identically (npm
// consumers hold the same contract as the Hex package); the agreement
// gate asserts kit-embedded manifest == priv/release-metadata.json.
for(const name of ["release-metadata.json","release-history.json"])copyFileSync(join(root,"priv",name),join(root,"dist",name));

mkdirSync(join(root, "dist/kit"), { recursive: true });

const kitCli = `#!/usr/bin/env node
// Kit bin for @agent-blueprint-protocol/verifier. Forwards to the
// compiled verifier CLI. With no --corpus argument, the EMBEDDED
// corpus is used (the exact bytes the release gates verified); pass
// --corpus <dir> to verify any other corpus. Exit codes are the
// verifier's own: 0 agreement, 1 disagreement, 2 usage/integrity, 3
// internal invariant.
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const cli = join(here, "..", "verifier", "cli.js");
const embedded = join(here, "..", "corpus");

const args = process.argv.slice(2);
if (args.length === 0) {
  args.push("--corpus", embedded);
}

const result = spawnSync(process.execPath, [cli, ...args], { stdio: "inherit" });
process.exit(result.status ?? 3);
`;

const binPath = join(root, "dist/kit/cli.mjs");
writeFileSync(binPath, kitCli, { mode: 0o755 });

console.log("kit: staged dist/corpus, dist/release-metadata.json (embedded, byte-identical), and dist/kit/cli.mjs");

cpSync(join(root,"spec"),join(root,"dist/spec"),{recursive:true});
const packageRoot=join(root,"dist/package");
mkdirSync(join(packageRoot,"dist"),{recursive:true});
for(const name of ["verifier","kit","corpus","spec"])cpSync(join(root,"dist",name),join(packageRoot,"dist",name),{recursive:true});
for(const name of ["release-metadata.json","release-history.json"])copyFileSync(join(root,"dist",name),join(packageRoot,"dist",name));
for(const name of ["CHANGELOG.md","LICENSE","NOTICE"])copyFileSync(join(root,name),join(packageRoot,name));
copyFileSync(join(root,"verifier/README.md"),join(packageRoot,"README.md"));
const manifest=JSON.parse(readFileSync(join(root,"package.json"),"utf8"));
delete manifest.scripts;delete manifest.devDependencies;
writeFileSync(join(packageRoot,"package.json"),JSON.stringify(manifest,null,2)+"\n");
