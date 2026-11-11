# TypeScript guide

This guide is for TypeScript developers integrating the verifier. You will install the ESM package, decode an [artifact](glossary.md#artifact), inspect typed errors, reconcile the shipped examples, verify a signature, and run the CLI.

## Prerequisites

Use Node.js 24 or newer. The package is ESM-only and has no runtime dependencies. Import from the package root.

## Install and decode

Install the package:

```sh
npm install @agent-blueprint-protocol/verifier@1.0.0
```

This example runs from a repository checkout beside `examples/echo-blueprint.json`:

```js
import { readFileSync } from "node:fs";
import { decodeBlueprint } from "@agent-blueprint-protocol/verifier";

const result = decodeBlueprint(readFileSync("examples/echo-blueprint.json"));
console.log(result.ok ? "valid" : result.error.code); // valid
```

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
describeError(denied.error.code); // "unknown_member"
```

## Reconcile the shipped examples

Run this TypeScript example from the repository root. It uses the shipped [Blueprint](glossary.md#blueprint) and Deployment Manifest, and supplies the host inputs explicitly.

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

`verifySignature` accepts a signature entry and the [host](glossary.md#host)'s public keys. This corpus vector returns its verified attributes:

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
