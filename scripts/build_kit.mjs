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

import { cpSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));

cpSync(join(root, "priv/conformance"), join(root, "dist/corpus"), { recursive: true });

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
const hasCorpus = args.includes("--corpus");
const hasArtifact = args.includes("--artifact");
if (!hasCorpus && !hasArtifact) {
  args.push("--corpus", embedded);
}

const result = spawnSync(process.execPath, [cli, ...args], { stdio: "inherit" });
process.exit(result.status ?? 3);
`;

const binPath = join(root, "dist/kit/cli.mjs");
writeFileSync(binPath, kitCli, { mode: 0o755 });

console.log("kit: staged dist/corpus (embedded, byte-identical) and dist/kit/cli.mjs");
