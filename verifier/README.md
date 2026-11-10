# Agent Blueprint Protocol for TypeScript

A typed, non-authorizing verifier library and conformance CLI. Node 24 or
newer; zero runtime dependencies. The npm and Hex packages share one version.
The specification is [published with the project](https://github.com/baselabs/agent_blueprint_protocol/blob/main/spec/protocol.md).

```sh
npm install @agent-blueprint-protocol/verifier
npx @agent-blueprint-protocol/verifier --help
```

For a candidate, append `@rc` to the install and npx package name. Stable
releases use `latest`. A staged version is
installable only after its npm approval. `npm view
@agent-blueprint-protocol/verifier@rc version` identifies the live candidate.

## CLI

| Mode | Behavior |
|---|---|
| no arguments | run the embedded certified corpus |
| `--corpus <dir>` | run an integrity-checked corpus, emit the aggregate report |
| `--prior-corpus <dir>` | replay the prior census under current semantics |
| `--results --corpus <dir>` | emit canonical per-case results |
| `--serve --corpus <dir>` | speak the external execution protocol |
| `--artifact <file>` | decode a Blueprint, Deployment, or federation envelope |
| `--help`, `--version` | usage or package version |
| `conformance run --corpus <dir> --results <file> -- <command...>` | drive and judge another implementation |

Runner exits: 0 agreement/valid/help/version, 1 disagreement/invalid artifact,
2 usage/readability/integrity failure, 3 internal invariant failure. Corpus
stderr states whether the digest matches the release-certified corpus.
Readers reject symlinks and nonregular files and cap a tree at 1,000 entries
and 5,000,000 bytes. Stdout reports and results are JCS without a trailing LF.
Harness exits 10–19 identify handshake mismatch, duplicate, missing, extra,
reordered, malformed, oversized, timeout, early-exit and disagreement outcomes
in that order. The execution contract in the specification defines each.

## Library

The package is ESM-only; `require()` is not supported.
Only the package root and `package.json` are exported. Import has no command
or filesystem side effects. Every function returns `Result<T>`:
`{ok:true,value}` or `{ok:false,error:{code,subject}}`. Public types use
`Uint8Array` and strings; consumers need no Node global declarations.
`ErrorCode` is exhaustive, including `ceiling:<key>` denials.

```js
// verify.mjs — run beside echo-blueprint.json
import { readFileSync } from "node:fs";
import { decodeBlueprint } from "@agent-blueprint-protocol/verifier";
const result = decodeBlueprint(readFileSync("echo-blueprint.json"));
console.log(result.ok ? "valid" : result.error.code); // valid
```

The following examples use canonical example bytes `blueprintBytes`,
`deploymentBytes`, `envelopeBytes`, caller-supplied `keys` and `observed`,
and integrity-checked corpus files `files`. They return evidence, never
permission. Check `ok` before reading `value`.

```ts
import {
  decodeBlueprint, decodeDeployment, decodeFederationEnvelope, canonicalBytes,
  negotiate, intersect, verifyCompatibility, reconcile, federationMapping,
  verifySignature, loadCorpus, runCorpus, buildReport, buildResultsDocument
} from "@agent-blueprint-protocol/verifier";

const bp = decodeBlueprint(blueprintBytes, {bounds: {depth: 32}});
const dep = decodeDeployment(deploymentBytes);
const envelope = decodeFederationEnvelope(envelopeBytes);
if (bp.ok) canonicalBytes(bp.value);

const support = {revisions: new Set([1]), coreFields: new Set<string>(),
  registry: {}, schemas: {}};
if (bp.ok) negotiate(bp.value, support);

// Each source supplies all thirteen bounds; classification uses
// {ordinal: "internal", markers: []}, cost uses {amount, currency}.
intersect({blueprint: requestedBounds, deployment: deploymentBounds,
  host: hostBounds, protectedClamp: "acknowledge"});
if (dep.ok) verifyCompatibility(dep.value, observed);
if (bp.ok && dep.ok) reconcile(bp.value, dep.value, {
  hostBounds, support, keys, protectedClamp: "deny",
  observations: {now: null, maxAttestationAgeMs: null, observed: {}}
});
federationMapping();
verifySignature(signatureEntry, keys);

const corpus = loadCorpus(files);
if (corpus.ok) {
  const run = runCorpus(corpus.value);
  if (run.ok) buildReport(corpus.value, run.value);
  buildResultsDocument(corpus.value);
}
```

Decoded views expose read-only JSON `value`, `canonicalBytes`, and
`contentDigest` (null for a federation envelope, whose commitment is a
separate identity). `Support`, `Inputs`, `Observations`, `Observed`,
`Context`, `PublicKey`, `BoundSet`, and decoder `Bounds` describe the
caller-supplied facts. `Evidence` includes typed checks, effective bounds,
clamps, and a nonempty `not_verified` list. Unsigned artifacts succeed with
signature verification explicitly unestablished; absent descriptor and
freshness observations remain unverified.

## External implementations and claims

```sh
agent-blueprint-protocol conformance run --corpus ./conformance --results results.json -- ./example-adapter
```

After a pass, add `--claim claim.json --implementation example-verifier
--implementation-version 1 --source https://example.com/source
--platform example-platform --date 2026-11-10` before `--`. A claim is unsigned
and identifies the implementation, corpus, registry and results bytes. A
non-certified corpus requires `--prior-corpus-digest <exact-digest>` to name
the prior census explicitly. Publish the claim and exact results document
beside source and the reproducible command. A public corpus pass proves
neither honest computation nor behavior outside the census nor any host
behavior. The kit includes the runner and execution contracts under `dist/spec/`.

## Import migration

| Previous internal import and symbol | Package-root replacement |
|---|---|
| `dist/verifier/blueprint.js`: `decode` | `decodeBlueprint` |
| `dist/verifier/deployment.js`: `decode` | `decodeDeployment` |
| `dist/verifier/federation.js`: `decode` | `decodeFederationEnvelope` |
| artifact modules: `canonicalBytes` | `canonicalBytes` |
| `dist/verifier/negotiation.js`: `negotiate` | `negotiate` |
| `dist/verifier/bounds_algebra.js`: `intersect` | `intersect` with a Sources object |
| `dist/verifier/compatibility.js`: `verify` | `verifyCompatibility` |
| `dist/verifier/signature.js`: `verify` | `verifySignature` |
| `dist/verifier/corpus.js`: `load` | `loadCorpus` |
| `dist/verifier/runner.js`: `run` | `runCorpus` |
| `dist/verifier/report.js`: `build`, `toBytes` | `buildReport`, `buildResultsDocument` |

Deep imports no longer resolve. Internal `{ok,v,e}` records become public
`{ok,value,error}` results. `reconcile` and `federationMapping` are new root
operations. Internal byte, schema and codec helpers have no supported deep
import replacement. The package-root surface is the supported TypeScript API.
