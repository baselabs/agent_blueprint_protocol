// The verifier CLI — the mirror of AgentBlueprintProtocol.Conformance.Cli:
// `--corpus <dir>` is REQUIRED (no default, so a vacuous run is impossible);
// exit 0 agreement, 1 disagreement, 2 usage error or corpus integrity
// failure. Report bytes go to stdout with NO trailing newline — including
// on exit 1 (disagreement still prints the report; the escript's
// IO.binwrite parity). Exit 3 marks an internal invariant (outside the
// 0/1/2 contract, exactly as an escript crash is — loud, never laundered
// into "disagreement").

import { readdirSync, readFileSync, lstatSync, openSync, closeSync, readSync, fstatSync } from "node:fs";
import { join, relative, sep } from "node:path";
import type { CaseObj } from "./corpus.ts";
import { member } from "./corpus.ts";
import type { Value } from "./value.ts";
import { load, loadPriorCensus } from "./corpus.ts";
import { encode } from "./canonical.ts";
import { toBytes } from "./report.ts";
import { run } from "./runner.ts";
import { decode as decodeBlueprint } from "./blueprint.ts";
import { decode as decodeDeployment } from "./deployment.ts";
import { decode as decodeEnvelope } from "./federation.ts";
import { obj, str } from "./value.ts";

const USAGE = `usage: agent-blueprint-protocol [--corpus <dir> | --prior-corpus <dir> | --artifact <file> | --help | --version]
No arguments: verify the installed release's embedded corpus.
--corpus <dir>: verify a corpus and report agreement.
--prior-corpus <dir>: replay a released corpus under current verification.
--artifact <file>: verify a Blueprint, Deployment Manifest, or Federation TaskEnvelope.
--help: print this help. --version: print the package version.
Exit codes: 0 agreement or valid artifact (also help/version); 1 disagreement or invalid artifact;
2 usage, unreadable input, or corpus integrity failure; 3 internal error.`;
const BYTE_CAP = 5_000_000;

function releaseMetadata(): { package_version: string; corpus_digest: string } {
  for (const path of ["../release-metadata.json", "../priv/release-metadata.json", "./release-metadata.json"]) {
    try { return JSON.parse(readFileSync(new URL(path, import.meta.url), "utf8")); }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  }
  throw new Error("release metadata missing");
}

function main(argv: string[]): number {
  if (argv.length === 1 && argv[0] === "--help") { process.stdout.write(USAGE + "\n"); return 0; }
  if (argv.length === 1 && argv[0] === "--version") { process.stdout.write(releaseMetadata().package_version + "\n"); return 0; }
  if (argv.length === 2 && argv[0] === "--artifact" && argv[1] !== "" && typeof argv[1] === "string") {
    return verifyArtifact(argv[1]!);
  }

  // --prior-corpus: the compatibility-replay entry (a RELEASED census under
  // a newer verifier — the registry/floor couplings suspended by the
  // loader's prior-census mode). The report and exit contract are identical
  // to --corpus; the compatibility gate byte-compares this output against
  // the Elixir side's in-process report.
  const prior = argv.length === 2 && argv[0] === "--prior-corpus" && argv[1] !== "" && typeof argv[1] === "string";

  if (!(prior || (argv.length === 2 && argv[0] === "--corpus" && argv[1] !== "" && typeof argv[1] === "string"))) {
    process.stderr.write(USAGE + "\n");
    return 2;
  }
  const dir = argv[1]!;

  let map: Map<string, Buffer>;
  try {
    map = readCorpus(dir);
  } catch {
    process.stderr.write(
      "corpus unreadable: missing, unreadable, not regular, or over the file or byte ceiling\n",
    );
    return 2;
  }

  const corpus = prior ? loadPriorCensus(map) : load(map);
  if (!corpus.ok) {
    // Value-free by construction: the code names the corpus's own state.
    // The ":" prefix mirrors the escript's inspect(error.code) formatting.
    process.stderr.write("corpus integrity failure: :" + corpus.e + "\n");
    return 2;
  }

  if (!corpus.v.cases.every((file) => file.cases.every(readerInput))) {
    process.stderr.write("corpus integrity failure: :invalid_type\n");
    return 2;
  }
  const certified = corpus.v.identity === releaseMetadata().corpus_digest ? "matches" : "does not match";
  process.stderr.write(`corpus digest ${certified} the release-certified corpus\n`);
  const results = run(corpus.v);
  const bytes = toBytes(corpus.v.identity, results);

  // exitCode (not process.exit) so piped stdout drains before exit.
  process.stdout.write(bytes);
  const agreed = results.flat().filter((r) => r.agree).length;
  return agreed === results.flat().length && agreed > 0 ? 0 : 1;
}

function fieldShape(input: Value, key: string, predicate: (v: Value) => boolean): boolean {
  const value = member(input, key);
  return value === null || predicate(value);
}

function readerInput(row: CaseObj): boolean {
  const input = row.input;
  if (row.surface === "negotiation.negotiate" || row.surface === "extension.resolve") {
    const support = member(input, "support");
    if (support === null || support.t === "null") return true;
    if (support.t !== "obj") return false;
    return ["revisions", "core_fields"].every((key) => fieldShape(support, key, (v) => v.t === "arr")) &&
      fieldShape(support, "schemas", (v) => v.t === "obj") &&
      fieldShape(support, "registry", (v) => v.t === "obj" && v.v.every(([, entry]) => entry.t === "obj"));
  }
  if (row.surface === "bounds_algebra.intersect") {
    return ["blueprint", "deployment", "host"].every((key) => fieldShape(input, key, (v) =>
      v.t === "obj" && v.v.every(([, bound]) => bound.t !== "obj" || member(bound, "ordinal") === null ||
        fieldShape(bound, "markers", (markers) => markers.t === "arr"))));
  }
  return true;
}

// Single-artifact mode — a kit-side convenience the escript deliberately
// does NOT mirror (its CLI contract stays --corpus-only, so a vacuous run
// stays impossible there). One artifact file, verified against all three
// artifact kinds; valid iff any kind decodes. A valid report names the
// kind; an invalid report names each kind's typed denial code, so the
// file's own shape is legible from the report alone. The agreement
// script replays every decode-surface corpus case through this mode and
// requires the case's own expected verdict (the mode's gate).
function verifyArtifact(path: string): number {
  let bytes: Buffer;

  try {
    const info = lstatSync(path);
    if (!info.isFile()) throw new Error("not a regular file");
    if (info.size > BYTE_CAP) throw new Error("over byte ceiling");
    bytes = readRegular(path, BYTE_CAP);
  } catch {
    process.stderr.write(
      "artifact unreadable: missing, not a regular file, or over the byte ceiling\n",
    );
    return 2;
  }

  const blueprint = decodeBlueprint(bytes);
  const deployment = decodeDeployment(bytes);
  const envelope = decodeEnvelope(bytes);

  const kind = blueprint.ok ? "blueprint" : deployment.ok ? "deployment" : envelope.ok ? "federation" : null;

  const members: [string, ReturnType<typeof str>][] = [
    ["format", str("agent-blueprint-protocol-artifact-report")],
    ["verdict", str(kind === null ? "invalid" : "valid")],
  ];

  if (kind === null) {
    members.push(
      ["blueprint", str(blueprint.ok ? "valid" : blueprint.e)],
      ["deployment", str(deployment.ok ? "valid" : deployment.e)],
      ["federation", str(envelope.ok ? "valid" : envelope.e)],
    );
  } else {
    members.push(["kind", str(kind)]);
  }

  const encoded = encode(obj(members));
  if (!encoded.ok) throw new Error("artifact report must encode");

  process.stdout.write(encoded.v);
  return kind === null ? 1 : 0;
}

// At most 1,000 entries and 5,000,000 bytes across the entire tree.
// Symlinks and special files deny before reading; reads are bounded even if a file grows.
function readRegular(path: string, cap: number): Buffer {
  const fd = openSync(path, "r");
  try {
    const info = fstatSync(fd);
    if (!info.isFile() || info.size > cap) throw new Error("unreadable");
    const chunks: Buffer[] = [];
    let size = 0;
    for (;;) {
      const chunk = Buffer.alloc(Math.min(64 * 1024, cap - size + 1));
      const count = readSync(fd, chunk);
      if (count === 0) return Buffer.concat(chunks, size);
      size += count;
      if (size > cap) throw new Error("over byte ceiling");
      chunks.push(chunk.subarray(0, count));
    }
  } finally { closeSync(fd); }
}

function readCorpus(dir: string): Map<string, Buffer> {
  const map = new Map<string, Buffer>();
  let count = 0;
  let total = 0;
  const walk = (current: string) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      if (entry.name === ".DS_Store" || entry.name.startsWith("._")) continue;
      if (++count > 1_000) throw new Error("over file ceiling");
      const path = join(current, entry.name);
      const info = lstatSync(path);
      if (info.isDirectory()) walk(path);
      else if (info.isFile()) {
        if (info.size > BYTE_CAP - total) throw new Error("over byte ceiling");
        const bytes = readRegular(path, BYTE_CAP - total);
        total += bytes.length;
        map.set(relative(dir, path).split(sep).join("/"), bytes);
      } else throw new Error("not a regular file");
    }
  };
  try {
    if (!lstatSync(dir).isDirectory()) throw new Error("not a directory");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return map;
    throw error;
  }
  walk(dir);
  return map;
}

try {
  process.exitCode = main(process.argv.slice(2));
} catch (error) {
  process.stderr.write("verifier internal error: " + (error as Error).message + "\n");
  process.exitCode = 3;
}
