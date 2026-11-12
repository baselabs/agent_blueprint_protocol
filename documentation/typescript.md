# TypeScript guide

This guide is for TypeScript developers integrating the verifier. You will install the ESM package, decode an [artifact](glossary.md#artifact), inspect typed errors, reconcile the shipped examples, verify a signature, and run the CLI.

## Prerequisites

Use Node.js 24 or newer. The package is ESM-only and has no runtime dependencies. Import from the package root.

## Install and decode

In a new working directory, install the exact release and download both canonical samples. The npm archive does not contain `examples/`:

```sh
npm init -y
npm install @agent-blueprint-protocol/verifier@1.0.0
mkdir -p examples
curl --fail --location https://raw.githubusercontent.com/baselabs/agent_blueprint_protocol/v1.0.0/examples/echo-blueprint.json --output examples/echo-blueprint.json
curl --fail --location https://raw.githubusercontent.com/baselabs/agent_blueprint_protocol/v1.0.0/examples/echo-deployment.json --output examples/echo-deployment.json
```

Save the following block as `verify.mjs`, then run `node verify.mjs`. It prints `valid`.

```js
import { readFileSync } from "node:fs";
import { decodeBlueprint } from "@agent-blueprint-protocol/verifier";

const result = decodeBlueprint(readFileSync("examples/echo-blueprint.json"));
console.log(result.ok ? "valid" : result.error.code); // valid
```

Decoding checks canonical bytes, structure, portability, and the content digest. The sample is unsigned; decoding establishes no cryptographic signature.

### Run the TypeScript examples

Node 24 can run the erasable TypeScript in the `.mts` files below directly. To also check their types, install the development tools once:

```sh
npm install --save-dev typescript @types/node
```

For each named file, run `npx tsc --strict --module nodenext --moduleResolution nodenext --target es2022 --types node --skipLibCheck false --noEmit <filename.mts>`, then `node <filename.mts>`. Each file is independent unless a prerequisite is stated.

### Read a denial

Save the next block as `denial.mts`. It returns the `unknown_member` description.

The `Result<T>` type is either `{ok: true, value}` or `{ok: false, error}`. `ErrorCode` is a closed union. This denial example checks every code at compile time:

```ts
import { decodeBlueprint, type ErrorCode } from "@agent-blueprint-protocol/verifier";

function describeError(code: ErrorCode): string {
  switch (code) {
    case "attestation_malformed":
    case "audience_mismatch":
    case "base64url_invalid":
    case "base64url_padded":
    case "binding_attestation_stale":
    case "binding_descriptor_mismatch":
    case "binding_incomplete":
    case "bound_source_missing":
    case "bound_unit_mismatch":
    case "bound_unknown":
    case "bound_value_invalid":
    case "ceiling:bytes":
    case "ceiling:depth":
    case "ceiling:items":
    case "ceiling:key":
    case "ceiling:members":
    case "ceiling:nodes":
    case "ceiling:number_lexeme":
    case "ceiling:string":
    case "compatibility_duplicate_entry":
    case "compatibility_entry_missing":
    case "compatibility_identity_inexact":
    case "corpus_applicability_incomplete":
    case "corpus_case_id_duplicate":
    case "corpus_case_invalid":
    case "corpus_count_mismatch":
    case "corpus_empty":
    case "corpus_file_set_mismatch":
    case "corpus_hash_mismatch":
    case "corpus_index_invalid":
    case "deployment_digest_mismatch":
    case "digest_algorithm_unsupported":
    case "digest_encoding_invalid":
    case "digest_mismatch":
    case "duplicate_member":
    case "extension_criticality_conflict":
    case "extension_duplicate":
    case "extension_namespace_invalid":
    case "extension_payload_forbidden":
    case "extension_retired":
    case "extension_schema_digest_mismatch":
    case "extension_schema_unavailable":
    case "extension_unknown_critical":
    case "federation_mapping_conflict":
    case "federation_state_unmappable":
    case "federation_terminal_conflict":
    case "forbidden_portable_value":
    case "integer_magnitude":
    case "invalid_cardinality":
    case "invalid_constraint":
    case "invalid_encoding":
    case "invalid_number":
    case "invalid_syntax":
    case "invalid_type":
    case "lifecycle_state_invalid":
    case "missing_ceiling":
    case "missing_required_field":
    case "no_authoritative_recovery":
    case "non_canonical_bytes":
    case "nonportable_content":
    case "number_not_double_expressible":
    case "predicate_nodes_exceeded":
    case "predicate_op_unknown":
    case "predicate_path_unresolved":
    case "protected_bound_clamp_denied":
    case "protocol_revision_unsupported":
    case "required_core_field_not_digest_covered":
    case "required_core_field_unsupported":
    case "schema_complexity_exceeded":
    case "schema_dialect_unknown":
    case "schema_invalid_shape":
    case "schema_keyword_not_allowed":
    case "schema_keyword_value_invalid":
    case "schema_ref_cycle":
    case "schema_ref_unresolvable":
    case "signature_algorithm_unsupported":
    case "signature_key_unsupported":
    case "signature_malformed":
    case "signature_not_verified":
    case "trailing_bytes":
    case "unknown_bound":
    case "unknown_member":
      return code;
    default: {
      const exhaustive: never = code;
      return exhaustive;
    }
  }
}

const denied = decodeBlueprint('{"unknown":true}');
if (denied.ok) throw new Error("Expected a typed denial");
console.log(describeError(denied.error.code)); // "unknown_member"
```

## Reconcile the shipped examples

Save this as `reconcile.mts`, then type-check it and run `node reconcile.mts`. It reads the two downloaded samples and prints `true`. These explicit bounds are example host configuration; real hosts supply their own limits. See [host inputs](host-integration.md) for their sources and observation types.

```ts
import { readFileSync } from "node:fs";
import {
  decodeBlueprint,
  decodeDeployment,
  reconcile,
  type BoundSet,
  type Inputs,
  type Support,
} from "@agent-blueprint-protocol/verifier";

const blueprint = decodeBlueprint(readFileSync("examples/echo-blueprint.json"));
const deployment = decodeDeployment(readFileSync("examples/echo-deployment.json"));
if (!blueprint.ok) throw new Error(blueprint.error.code);
if (!deployment.ok) throw new Error(deployment.error.code);

const support: Support = {
  revisions: new Set([1]),
  coreFields: new Set(),
  registry: {},
  schemas: {},
};
const hostBounds: BoundSet = {
  max_attempts: 3,
  max_concurrency: 2,
  max_cost: { amount: 1000, currency: "USD" },
  max_depth: 8,
  max_descendants: 64,
  max_elapsed_ms: 60000,
  max_fan_out: 4,
  max_tokens: 100000,
  classification_ceiling: { ordinal: "internal", markers: [] },
  disclosure_ceiling: "summary",
  effect_impact_ceiling: "ordinary",
  authority_trait: "none",
  approval_trait: "none",
};
const inputs: Inputs = {
  hostBounds,
  support,
  keys: [],
  protectedClamp: "acknowledge",
  observations: { now: null, maxAttestationAgeMs: null, observed: {} },
};
const result = reconcile(blueprint.value, deployment.value, inputs);
if (!result.ok) throw new Error(result.error.code);
console.log(result.value.not_verified.length > 0); // true
```

## Verify a signature

Save the next block as `signature.mts`, then type-check it and run `node signature.mts`. `verifySignature` accepts a signature entry and the [host](glossary.md#host)'s public keys. This public corpus vector prints `example-signing-key`:

```ts
import {
  verifySignature,
  type JsonValue,
  type PublicKey,
} from "@agent-blueprint-protocol/verifier";

const entry: JsonValue = {
  protected: { alg: "Ed25519", b64: false, crit: ["b64"], kid: "example-signing-key" },
  signature: "peIiqKzhXAcT2X5vvp2YtXxrSfX3ApXtjWL4flmwai-zlFoZqYdV63oKcuTP1wDiRIi61NlD-8vGJM2ze6JACQ",
  signed_attributes: {
    algorithm: "Ed25519",
    content_digest: "sha-256:lSNm0cD67wEL0uy3EFDCBe3TA5FzvO6iCL0W0Db8HMo",
    created_at: "2026-08-23T00:00:00Z",
    key_id: "example-signing-key",
    purpose: "deployment",
  },
};
const key: PublicKey = {
  keyId: "example-signing-key",
  algorithm: "ed25519",
  key: Uint8Array.from([
    165, 209, 133, 92, 105, 214, 159, 224, 214, 44, 215, 98, 216, 253, 170, 13,
    71, 61, 144, 2, 36, 30, 195, 114, 207, 240, 236, 51, 182, 192, 192, 163,
  ]),
};
const checked = verifySignature(entry, [key]);
if (!checked.ok) throw new Error(checked.error.code);
console.log(checked.value.keyId); // "example-signing-key"
```

Standalone signature verification returns attributes. Compare `purpose` and `contentDigest` with the intended artifact; the call takes no expected-artifact argument. Reconciliation also compares each verified digest with its artifact. A returned creation time is signed data, not an independently verified clock.

### Checkout alternative

For contributors, clone the `v1.0.0` tag, run the [contributor bootstrap](../CONTRIBUTING.md#clean-checkout-setup), and run the same scripts from the checkout root. Its `examples/` directory already supplies the files. Installation does not require a checkout.

## CLI

The package installs the `agent-blueprint-protocol` and `verifier` commands. Both names accept the same modes.

| Mode | Result | Exit codes |
| --- | --- | --- |
| No arguments | Verify the package's embedded corpus and print an aggregate report. | `0` agreement, `1` disagreement, `3` internal error. |
| `--help` | Print usage. | `0`; `2` for invalid arguments. |
| `--version` | Print the package version. | `0`; `2` for invalid arguments; `3` if package metadata cannot be read. |
| `--corpus <dir>` | Verify a corpus and print the aggregate report. | `0` agreement, `1` disagreement, `2` usage or corpus-read/integrity failure, `3` internal error. |
| `--prior-corpus <dir>` | Verify an earlier released corpus with the same report format. | `0` agreement, `1` disagreement, `2` usage or corpus-read/integrity failure, `3` internal error. |
| `--artifact <file>` | Decode a Blueprint, Deployment Manifest, or Federation TaskEnvelope and print a typed report. | `0` valid, `1` invalid, `2` unreadable input or usage error, `3` internal error. |
| `--results --corpus <dir>` | Print a canonical [results document](glossary.md#results-document) with per-case projections. | `0` agreement, `1` disagreement, `2` usage or corpus-read/integrity failure, `3` internal error. |
| `--serve --corpus <dir>` | Run as an adapter for the external execution protocol. | `0` clean completion, `2` invalid input or handshake, `3` internal error. |
| `conformance run ... -- <command>` | Run the external harness against an adapter. | `0` agreement, `2` usage, corpus, or claim input failure, `3` internal error, `10` handshake mismatch, `11` duplicate response, `12` missing response, `13` extra response, `14` reordered response, `15` malformed line, `16` oversized line, `17` response timeout, `18` early exit, `19` disagreement. |

For `conformance run`, the harness writes a results document only after receiving all expected responses and a clean adapter exit. See the [execution protocol](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0/spec/conformance/execution.md) for the line format and outcomes.

## Package-root reference

All functions below return `Result<T>`. On denial, read `error.code` and the value-free `error.subject` path; never read `value` before checking `ok`. Parameters are required unless a default is shown. Read-only types describe data, not permission. The source contracts are [facade.ts](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0/verifier/facade.ts) and [index.ts](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0/verifier/index.ts).

| Export and signature (outer return is `Result<…>`) | Inputs, defaults, and success value |
|---|---|
| `decodeBlueprint(input: Uint8Array \| string, options: DecodeOptions = {})` → `Blueprint` | Canonical UTF-8 bytes; validates structure, portability, and digest. `options.bounds` tightens decoder ceilings; omitted ceilings use protocol maxima. |
| `decodeDeployment(input: Uint8Array \| string, options: DecodeOptions = {})` → `Deployment` | Same boundary for a Manifest. Does not compare it with a Blueprint or independently check signatures. |
| `decodeFederationEnvelope(input: Uint8Array \| string, options: DecodeOptions = {})` → `FederationEnvelope` | Canonical envelope; checks structure and portability. `contentDigest` is `null`. |
| `canonicalBytes(value: Artifact)` → `Uint8Array` | Encodes the view's JSON `value`. Does not insert a digest or sign edited content. |
| `negotiate(value: Blueprint \| Deployment, options: Support)` → `Negotiated` | Required revision/core-field support, registry, and held schemas. Returns revision, critical and quarantined names, retained optional names, and notices. |
| `intersect(options: Sources)` → `Intersection` | Three total bound sets. `protectedClamp` defaults to `"deny"`; `"acknowledge"` records permitted protected narrowing. Returns `effective` and `clamps`. |
| `verifyCompatibility(value: Deployment, observed: Observed)` → `Evidence` | Exact independently observed kind/name/version/digest tuples. Missing, duplicate, or inexact identities deny. |
| `reconcile(blueprint: Blueprint, deployment: Deployment, options: Inputs)` → `Evidence` | All host input fields are required; no implicit key discovery, limits, or clock. Skipped checks remain unverified. |
| `federationMapping()` → `readonly MappingRow[]` | No arguments. Returns 23 inert mapping rows inside a `Result`; does not perform carrier conversion. |
| `verifySignature(entry: JsonValue, keys: readonly PublicKey[])` → `SignedAttributes` | Detached entry and caller-trusted raw Ed25519 public keys. Returns verified algorithm, digest, time, key ID, and purpose. Missing key or failed verification denies. |
| `loadCorpus(files: ReadonlyMap<string, Uint8Array>, options: {priorCensus?: boolean} = {})` → `Corpus` | Paths relative to corpus root, including index/data/cases. Integrity-checks the set. `priorCensus` defaults to `false`; `true` permits an earlier census, without establishing release certification. Returns an in-memory handle. |
| `runCorpus(value: Corpus)` → `readonly (readonly CaseResult[])[]` | Handle returned by this package instance's loader. Nested arrays group file results; flatten them for per-case `caseId`/`agree`. |
| `buildReport(value: Corpus, results: readonly (readonly CaseResult[])[])` → `Report` | Same handle plus run results. Returns aggregate totals, `agreement`, and `exit_status`. A disagreement is a successful report value with `agreement: false`. |
| `buildResultsDocument(value: Corpus)` → `ResultsDocument` | Executes projections for the loaded corpus. Returns an object containing format, digests, and per-case rows. It does not serialize bytes or write a file. Use the CLI's `--results` for canonical output. |

Decoder `Bounds` has eight optional tighten-only keys: `bytes`, `depth`, `members`, `items`, `nodes`, `string`, `key`, and `number_lexeme`. These are input parsing limits, distinct from the thirteen operational/protected fields of `BoundSet`. For example, `decodeBlueprint(bytes, {bounds: {depth: 32}})`; placing `depth` outside `bounds` does not configure it.

### Exported data types and constants

This is the complete root type surface, including the `ErrorCode` re-export:

| Types | Use |
|---|---|
| `JsonValue`, `ProtocolError`, `Result<T>`, `ErrorCode` | Plain JSON, closed denial codes, paths, and success/denial union. |
| `Bounds`, `CeilingKey`, `DecodeOptions` | Eight decoder ceilings and their options wrapper. |
| `Artifact`, `Blueprint`, `Deployment`, `FederationEnvelope` | Read-only decoded views with JSON value, canonical bytes, kind, and content digest. |
| `PublicKey`, `SignedAttributes` | Caller-supplied verification keys and returned signed attributes. |
| `Support`, `Negotiated` | Host negotiation inputs and returned extension facts. |
| `Classification`, `Cost`, `BoundSet`, `Sources`, `Clamp`, `Intersection` | Classification plus markers, integer money, three bound sources, and narrowing evidence. |
| `Observations`, `Observed`, `Inputs` | Descriptor/freshness observations, build inventory, and reconciliation inputs. |
| `Check`, `Evidence`, `MappingRow` | Check details, aggregate evidence, and mapping data. |
| `Corpus`, `CaseResult`, `Report`, `ResultsDocument` | Loaded handle, per-case agreement, aggregate report, and result projections. |
| `KnownNotice`, `Notice`; `KnownEvidenceSurface`, `EvidenceSurface`; `KnownEvidenceCheckKind`, `EvidenceCheckKind`; `KnownSignatureAlgorithm`, `SignatureAlgorithm`; `KnownSignaturePurpose`, `SignaturePurpose` | Known literals plus open output identifier types. |

`KNOWN_NOTICES`, `KNOWN_EVIDENCE_SURFACES`, `KNOWN_EVIDENCE_CHECK_KINDS`, `KNOWN_SIGNATURE_ALGORITHMS`, and `KNOWN_SIGNATURE_PURPOSES` are frozen objects of known output names. They are not exhaustive lists for all of 1.x. Use a default branch for future identifiers and detail shapes.

### Decode, negotiate, compare, and intersect

Save as `inspect.mts`. Type-check it, then run `node inspect.mts` after the sample downloads. The inventory below is a fixture copied from the example for this demonstration; use independent inventory in an integration.

```ts
import { readFileSync } from "node:fs";
import {
  decodeBlueprint, decodeDeployment, canonicalBytes, negotiate, intersect,
  verifyCompatibility, federationMapping, type BoundSet, type Observed,
} from "@agent-blueprint-protocol/verifier";

const bp = decodeBlueprint(readFileSync("examples/echo-blueprint.json"), {bounds: {depth: 32}});
const dep = decodeDeployment(readFileSync("examples/echo-deployment.json"));
if (!bp.ok) throw new Error(bp.error.code);
if (!dep.ok) throw new Error(dep.error.code);
const bytes = canonicalBytes(bp.value);
if (!bytes.ok) throw new Error(bytes.error.code);
const negotiated = negotiate(bp.value, {
  revisions: new Set([1]), coreFields: new Set(), registry: {}, schemas: {},
});
if (!negotiated.ok) throw new Error(negotiated.error.code);
const host: BoundSet = {
  max_attempts: 2, max_concurrency: 2, max_cost: {amount: 1000, currency: "USD"},
  max_depth: 8, max_descendants: 64, max_elapsed_ms: 60000, max_fan_out: 4,
  max_tokens: 100000, classification_ceiling: {ordinal: "internal", markers: []},
  disclosure_ceiling: "none", effect_impact_ceiling: "ordinary",
  authority_trait: "none", approval_trait: "none",
};
const narrowed = intersect({blueprint: {...host, max_attempts: 3}, deployment: host, host});
if (!narrowed.ok) throw new Error(narrowed.error.code);
const manifest = JSON.parse(readFileSync("examples/echo-deployment.json", "utf8"));
const observed: Observed = {identities: manifest.build_identities};
const compatible = verifyCompatibility(dep.value, observed);
if (!compatible.ok) throw new Error(compatible.error.code);
const mapping = federationMapping();
if (!mapping.ok) throw new Error(mapping.error.code);
console.log(negotiated.value.protocolRevision, narrowed.value.effective.max_attempts, mapping.value.length);
// 1 2 23
```

For an envelope, download the exact sample, then save the following as `envelope.mts`, type-check it, and run `node envelope.mts`:

```sh
curl --fail --location https://raw.githubusercontent.com/baselabs/agent_blueprint_protocol/v1.0.0/examples/federation-envelope.json --output examples/federation-envelope.json
```

```ts
import { readFileSync } from "node:fs";
import { decodeFederationEnvelope } from "@agent-blueprint-protocol/verifier";
const result = decodeFederationEnvelope(readFileSync("examples/federation-envelope.json"));
if (!result.ok) throw new Error(result.error.code);
console.log(result.value.kind, result.value.contentDigest); // federation null
```

### Read JSON evidence details

Elixir detail structs become JSON objects in the npm API. Signature detail is `{key_ids: string[]}` or the string `"no_signatures_present"`. Binding detail is `{checked: string[], not_verified: string[]}`. A clamp detail has `field`, `class`, `unit`, `requested`, `effective`, `source`, and `acknowledged`; its public typed counterpart is `Clamp`.

Save as `details.mts`. Type-check it and run `node details.mts`; it prints `true`. Use `signatureSummary` separately for each artifact subject in real evidence.

```ts
import type { Check, JsonValue } from "@agent-blueprint-protocol/verifier";
function object(value: JsonValue): value is {readonly [key: string]: JsonValue} {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function strings(value: JsonValue | undefined): value is readonly string[] {
  return Array.isArray(value) && value.every(item => typeof item === "string");
}
function signatureSummary(check: Check): string {
  const d = check.detail;
  if (check.surface !== "signatures") return "unknown";
  if (!check.verified && d === "no_signatures_present") return "not verified";
  if (check.verified && object(d) && strings(d.key_ids)) return d.key_ids.join(", ");
  return "unknown";
}
function detailSummary(check: Check): JsonValue {
  const d = check.detail;
  switch (check.surface) {
    case "signatures": return signatureSummary(check);
    case "bind":
      if (object(d) && strings(d.checked) && strings(d.not_verified)) {
        return {checked: d.checked, skipped: d.not_verified, verified: check.verified};
      }
      return "unknown";
    case "bounds":
      if (object(d) && typeof d.field === "string" &&
          (d.class === "operational" || d.class === "protected") &&
          typeof d.unit === "string" && (d.source === "host" || d.source === "deployment") &&
          typeof d.acknowledged === "boolean" && d.requested !== undefined && d.effective !== undefined) {
        return {field: d.field, requested: d.requested, effective: d.effective};
      }
      return "unknown";
    default: return "unknown";
  }
}
const checks: readonly Check[] = [
  {surface: "signatures", subject: ["blueprint"], verified: true, detail: {key_ids: ["producer-key-1"]}},
  {surface: "signatures", subject: ["deployment"], verified: false, detail: "no_signatures_present"},
  {surface: "bind", subject: ["deployment"], verified: false,
    detail: {checked: ["release_binding", "binding_completeness", "effect_recovery"],
      not_verified: ["binding_descriptors", "binding_staleness"]}},
  {surface: "bounds", subject: ["max_attempts"], verified: true,
    detail: {field: "max_attempts", class: "operational", unit: "count", requested: 3,
      effective: 2, source: "host", acknowledged: false}},
  {surface: "future_surface", subject: [], verified: false, detail: {}},
];
const summaries = ["blueprint", "deployment"].map(artifact => {
  const check = checks.find(c => c.surface === "signatures" && c.subject.length === 1 && c.subject[0] === artifact);
  return [artifact, check ? detailSummary(check) : "unknown"];
});
const allDetails = checks.map(detailSummary); // Includes binding, clamp, and unknown branches.
console.log(summaries[1]?.[1] === "not verified" && allDetails[4] === "unknown"); // true
```

This fixture shows a mixed signed/unsigned pair. The global `signatures` entry in `not_verified` means at least one relevant subject remains unverified. Preserve both `surface` and `subject` when looking up canonical, digest, structure, portability, or negotiation checks too.

### Load and run a corpus in memory

Save as `corpus.mts`, type-check it, and run `node corpus.mts`. It reads the installed package's corpus and prints `true true`. All file I/O here is explicit caller code; importing the library does no I/O.

```ts
import { readdirSync, readFileSync } from "node:fs";
import { join, relative, sep } from "node:path";
import { loadCorpus, runCorpus, buildReport, buildResultsDocument } from "@agent-blueprint-protocol/verifier";
const root = "node_modules/@agent-blueprint-protocol/verifier/dist/corpus";
const files = new Map<string, Uint8Array>();
function walk(dir: string): void {
  for (const entry of readdirSync(dir, {withFileTypes: true})) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) walk(path);
    else if (entry.isFile()) files.set(relative(root, path).split(sep).join("/"), readFileSync(path));
    else throw new Error("Expected regular package files");
  }
}
walk(root);
const loaded = loadCorpus(files); // {priorCensus: false} by default
if (!loaded.ok) throw new Error(loaded.error.code);
const run = runCorpus(loaded.value);
if (!run.ok) throw new Error(run.error.code);
const report = buildReport(loaded.value, run.value);
if (!report.ok) throw new Error(report.error.code);
const document = buildResultsDocument(loaded.value);
if (!document.ok) throw new Error(document.error.code);
console.log(report.value.agreement, document.value.results.length === run.value.flat().length);
```

To write canonical results, use `npx @agent-blueprint-protocol/verifier@1.0.0 --results --corpus node_modules/@agent-blueprint-protocol/verifier/dist/corpus > results.json`. `JSON.stringify(document.value)` produces JSON but is not a canonical-byte guarantee.

## Import migration

Import from `@agent-blueprint-protocol/verifier`. Deep imports are not part of the supported API.

| Previous import and function | Package-root export |
| --- | --- |
| `dist/verifier/blueprint.js`: `decode` | `decodeBlueprint` |
| `dist/verifier/deployment.js`: `decode` | `decodeDeployment` |
| `dist/verifier/federation.js`: `decode` | `decodeFederationEnvelope` |
| Artifact modules: `canonicalBytes` | `canonicalBytes` |
| `dist/verifier/negotiation.js`: `negotiate` | `negotiate` |
| `dist/verifier/bounds_algebra.js`: `intersect` | `intersect` with a `Sources` object |
| `dist/verifier/compatibility.js`: `verify` | `verifyCompatibility` |
| `dist/verifier/signature.js`: `verify` | `verifySignature` |
| `dist/verifier/corpus.js`: `load` | `loadCorpus` |
| `dist/verifier/runner.js`: `run` | `runCorpus` |
| `dist/verifier/report.js`: `build`, `toBytes` | `buildReport`, `buildResultsDocument` |

The public `Result<T>` shape uses `value` on success and a typed `error` on denial. Internal `{ok, v, e}` records and deep imports no longer resolve. The [migration guide](migrating-to-1.0.md) covers the Elixir changes.

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

Save this final example as `notices.mts`; type-check it and run `node notices.mts` (no output).

```ts
import { KNOWN_NOTICES, type Notice } from "@agent-blueprint-protocol/verifier";
function deprecated(notice: Notice): boolean {
  switch (notice) {
    case KNOWN_NOTICES.extension_deprecated: return true;
    default: return false;
  }
}
```

Elixir consumers match structs on the fields they use. Release-manifest
readers ignore unknown additive members but reject unknown equivalence
claims. Every unknown nonzero harness exit is failure. New revisions,
profiles, execution versions, modes, and flags are opt-in; existing contracts
and earlier corpus claims keep their meaning.

Every `max_cost.amount` is an integer count of millionths (10^-6) of one unit
of its uppercase ISO 4217 currency, independent of the currency's minor-unit
exponent. For example, `{amount: 1000, currency: "USD"}` means 0.001 USD.
Amounts compare as integers; mixed currencies deny. Federation
`resource_policy.cost` has the same scale in the bound Deployment Manifest's
`host_bounds.max_cost.currency`.

## Next steps

- [Quickstart](quickstart.md)
- [Conformance guide](conformance.md)
- [Migration guide](migrating-to-1.0.md)
- [Glossary](glossary.md)
- [Protocol specification](../spec/protocol.md)
