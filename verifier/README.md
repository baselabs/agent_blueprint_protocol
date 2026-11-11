# Agent Blueprint Protocol for TypeScript

A typed, non-authorizing verifier library and conformance CLI. Node 24 or
newer; zero runtime dependencies. For Elixir, see
[agent_blueprint_protocol](https://hex.pm/packages/agent_blueprint_protocol).
The specification is [published with the project](https://github.com/baselabs/agent_blueprint_protocol/blob/main/spec/protocol.md).

```sh
npm install @agent-blueprint-protocol/verifier
npx @agent-blueprint-protocol/verifier --help
```

Install the published package and run its CLI with `npx @agent-blueprint-protocol/verifier`. `npm view @agent-blueprint-protocol/verifier version` identifies the published package version.

## CLI

| Mode | Behavior |
|---|---|
| no arguments | run the embedded certified corpus |
| `--corpus <dir>` | run an integrity-checked corpus, emit the aggregate report |
| `--prior-corpus <dir>` | verify an earlier released corpus under this release's semantics |
| `--results --corpus <dir>` | emit canonical per-case results |
| `--serve --corpus <dir>` | speak the external execution protocol |
| `--artifact <file>` | decode a Blueprint, Deployment, or federation envelope |
| `--help`, `--version` | usage or package version |
| `conformance run --corpus <dir> --results <file> -- <command...>` | drive and judge another implementation |

Runner exit codes: 0 for agreement, a valid artifact, help, or version; 1 for disagreement or an invalid artifact; 2 for a usage, read, or corpus-integrity failure; 3 for an internal error. On a corpus run, standard error states whether the digest matches the release-certified corpus. Corpus readers reject symbolic links and non-regular files, and cap a corpus at 1,000 files and 5,000,000 bytes. Reports and results on standard output are JSON Canonicalization Scheme (JCS, RFC 8785) bytes without a trailing newline. Harness exit codes 10 to 19 mean, in order: handshake mismatch, duplicate, missing, extra, or reordered response, malformed line, oversized line, timeout, early exit, and disagreement. The execution contract in the specification defines each.

## Library

The package is ESM-only; `require()` is not supported.
Only the package root and `package.json` are exported. Import has no command
or filesystem side effects. Every function returns `Result<T>`:
`{ok:true,value}` or `{ok:false,error:{code,subject}}`. Public types use
`Uint8Array` and strings; consumers need no Node global declarations.
`ErrorCode` is exhaustive, including `ceiling:<key>` denials.

Save [`examples/echo-blueprint.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/main/examples/echo-blueprint.json) beside the script; the npm package does not include it.

```js
// verify.mjs — run beside echo-blueprint.json
import { readFileSync } from "node:fs";
import { decodeBlueprint } from "@agent-blueprint-protocol/verifier";
const result = decodeBlueprint(readFileSync("echo-blueprint.json"));
console.log(result.ok ? "valid" : result.error.code); // valid
```

The following examples assume canonical artifact bytes `blueprintBytes`, `deploymentBytes`, and `envelopeBytes`; caller-supplied `keys`, `observed`, `signatureEntry`, `requestedBounds`, `deploymentBounds`, and `hostBounds`; and `files`, a `Map` from corpus-relative path to file bytes. They return evidence, never permission. Check `ok` before reading `value`.

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
separate identity). `Support`, `Inputs`, `Observations`, `Observed`, `PublicKey`, `BoundSet`, and decoder `Bounds` describe the
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
the prior released corpus explicitly. Publish the claim and exact results
document beside source and the reproducible command. A public corpus pass
proves neither honest computation nor behavior outside the corpus nor any
host behavior. The package includes the runner and execution contracts under
`dist/spec/`.

## Migrating from 0.8

Deep imports from `dist/verifier/` no longer resolve; import from the package root. The [TypeScript guide](https://github.com/baselabs/agent_blueprint_protocol/blob/main/documentation/typescript.md#import-migration) maps each previous import to its replacement.

## Compatibility within 1.x

Node 24 remains the runtime floor for all of 1.x; Node 26 is also supported.
TypeScript 5.0.2 is the compiler floor. Packed declarations are checked at
that floor and at the TypeScript version used in CI with `moduleResolution: "nodenext"`,
`skipLibCheck: false`, and no `@types/node` dependency.

`ErrorCode` stays a closed union throughout 1.x, so exhaustive switches are
safe. Output identifiers are open string types: `Notice`, `EvidenceSurface`,
`EvidenceCheckKind`, `SignatureAlgorithm`, and `SignaturePurpose`. Their
`KNOWN_*` constants list known values. Inputs remain strict. Evidence check
kinds and detail variants can grow; look up the names you know and never
interpret an unknown entry as proof. Keep a default branch:

```ts
import { KNOWN_NOTICES, type Notice } from "@agent-blueprint-protocol/verifier";
function deprecated(notice: Notice): boolean {
  switch (notice) {
    case KNOWN_NOTICES.extension_deprecated: return true;
    default: return false;
  }
}
```

Release-manifest readers ignore unknown additive members but reject unknown
equivalence claims. Every unknown nonzero harness exit is failure. New revisions,
profiles, execution versions, modes, and flags are opt-in; existing contracts
and earlier corpus claims keep their meaning.

Every `max_cost.amount` is an integer count of millionths (10^-6) of one unit
of its uppercase ISO 4217 currency, independent of the currency's minor-unit
exponent. For example, `{amount: 1000, currency: "USD"}` means 0.001 USD.
Amounts compare as integers; mixed currencies deny. Federation
`resource_policy.cost` has the same scale in the bound Deployment Manifest's
`host_bounds.max_cost.currency`.
