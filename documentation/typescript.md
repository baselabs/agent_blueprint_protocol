# The TypeScript quickstart

The verifier ships as an installable npm kit,
`@agent-blueprint-protocol/verifier@rc`: the compiled verifier, its
embedded conformance corpus (byte-identical to the release-certified
copy), the release-identity manifest, and one bin installed under two
names (`verifier` and `agent-blueprint-protocol`). Node 24 or newer; zero
runtime dependencies. The kit carries the same version number as the
Hex package, but a kit release goes live on npm only after a maintainer
approves its staged publish, so it can trail the Hex release. npx runs the latest published kit; `npm view @agent-blueprint-protocol/verifier@rc version` shows which.

## Verify the kit (one command)

```bash
npx @agent-blueprint-protocol/verifier@rc
```

With no arguments the kit runs its EMBEDDED corpus over every protocol
surface (448 cases in the 1.0.0-rc.1 kit) and prints the single-line report.
Green is `"agreement":true` and exit 0; the report names the corpus
digest, so what you verified is an exact, identified byte set. A separate
stderr line states whether that digest matches the release-certified corpus:

```json
{"agreed":199,"agreement":true,"corpus_digest":"sha-256:…","disagreed":0,"exit_status":0,"format":"agent-blueprint-protocol-conformance-report","total":199}
```

`--help` prints usage for `agent-blueprint-protocol`, every mode, and the
exit codes; `--version` prints the package version. Both exit 0. Unknown
arguments exit 2. Exit 3 indicates an internal error.

## Verify any corpus

`--corpus <dir>` points the kit at
any conformance corpus directory — a copy extracted from a git release
tag's verification kit, or one you built yourself — and the same
integrity-first rules apply (missing files, hash mismatches, and empty
corpora are typed failures, exit 2; a tampered corpus cannot verify
green). The reader rejects symlinks and special files and limits the
whole tree to 1,000 entries and 5,000,000 bytes. A corpus whose digest differs
from the release-certified digest is labeled on stderr, including prior-corpus
replay; stdout retains the same report format.

```bash
npx @agent-blueprint-protocol/verifier@rc --corpus ./conformance
```

`--prior-corpus <dir>` replays a previously released corpus under the
current verifier; the release gates use it to certify each release's
compatibility claims.

## Verify one artifact file

`--artifact <file>` verifies a single JSON artifact — a Blueprint, a
Deployment Manifest, or a federation TaskEnvelope — against all three
kinds; valid iff any kind decodes. Green names the kind; a denial names
each kind's typed code, so the file's shape is legible from the report
alone:

```bash
$ npx @agent-blueprint-protocol/verifier@rc --artifact echo-blueprint.json
{"format":"agent-blueprint-protocol-artifact-report","kind":"blueprint","verdict":"valid"}
```

Exit 0 is a verified artifact (evidence, never authority); exit 1 is a
typed denial; exit 2 is a usage or readability failure. The mode's
verdicts are gated: the release agreement check replays every
text-only decode-surface corpus case through `--artifact` and requires
each case's own expected verdict (companion-input cases stay with the
full corpus run).

## As a dependency

```bash
npm install @agent-blueprint-protocol/verifier@rc
```

The package carries the compiled verifier modules under
`dist/verifier/` with `.d.ts` declarations (it declares no `exports` map,
so import them by file path, for example
`@agent-blueprint-protocol/verifier/dist/verifier/runner.js`); the corpus
loader, runner, and every verification surface (decode, canonicalization,
digests, signatures, negotiation, bounds algebra, federation) are
importable. The embedded corpus is under `dist/corpus/` and the release
manifest at `dist/release-metadata.json`.

```js
// verify.mjs — run with: node verify.mjs (beside echo-blueprint.json)
import { readFileSync } from "node:fs";
import { decode } from "@agent-blueprint-protocol/verifier/dist/verifier/blueprint.js";

const result = decode(readFileSync("echo-blueprint.json"));
console.log(result.ok ? "valid" : result.e); // valid
```

A denial is `{ ok: false, e: "<code>" }`, with the same codes as the
Elixir package (see the [error guide](errors.md)).

The Elixir reference implementation and this kit byte-agree on every
corpus verdict — that agreement is a release gate, not a claim.

## What verification means

A typed fact about bytes and structure. Nothing is authorized, nothing
executes, no key material is held. See [what a blueprint is](what-a-blueprint-is.md), the [error
guide](errors.md), and — for how this kit's identity relates to
discovery-side trust manifests — the [ARD mapping](../docs/ard-mapping.md).
