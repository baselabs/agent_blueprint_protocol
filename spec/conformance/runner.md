# Conformance runner contract

This document is normative for the verifier conformance class. It defines
case execution and projections, independently of implementation language.
The execution protocol is in [execution.md](execution.md).

## Corpus and identity

A corpus has `index.json`, `cases/*.json`, JSON data under `schemas/` and
`vectors/`, and optional raw byte sidecars under `raw/*.raw`. Paths use `/`
on every platform. The index format is
`agent-blueprint-protocol-conformance-corpus-index`. Its members are:

| Member | Type and meaning |
|---|---|
| `format` | the exact format string above |
| `protocol_revision` | positive integer wire revision |
| `total_cases` | positive integer total |
| `corpus_digest` | tagged SHA-256 of the index without this member, using the corpus-index domain separator |
| `registry_digest` | tagged digest of the registry census |
| `files` | array of objects: `path` (relative string), `sha256_base64url` (SHA-256 of raw file bytes, unpadded base64url), `cases` (nonnegative integer; zero for data) |
| `applicability` | object keyed by surface, then class; each cell is a positive case count or an object with a nonempty string `n_a` reason |
| `public_key_fingerprints` | array of public fixture-key fingerprints; informational census data, never a trust store |
| `bool_extra` | boolean included to exercise index canonicalization |
| `float_extra` | number included to exercise index canonicalization |
| `null_extra` | null included to exercise index canonicalization |

The index MUST be canonical JSON. Integrity checks MUST reject an incorrect
index digest, registry mismatch, differing file set in either direction,
incorrect raw file hash, duplicate case id, inconsistent file or total count,
invalid case, unbound raw sidecar, or incomplete applicability floor.
An empty corpus MUST NOT pass. Prior-census mode suspends only the current
registry and current applicability-floor coupling; the prior index's own
integrity, counts, classes, and cell counts remain enforced.

`index.schema.json` and `case-file.schema.json` define the shared shapes.
Each case MUST also validate against its `<surface>.schema.json` document
(with dots replaced by hyphens). These separate validation layers keep each
schema within the protocol's bounded schema complexity limit. The successful
reconcile `evidence` member additionally validates against `evidence.schema.json`;
its `inputs.support` member, when present, validates against `support.schema.json`. All use the
2020-12 vocabulary subset in the protocol; the dialect is supplied by the
caller rather than a `$schema` annotation. The schemas live in this spec
tree, outside the corpus file census, so introducing format documentation
does not invalidate a prior corpus's exact file set.

A case file has format `agent-blueprint-protocol-conformance-cases` and a
`cases` array. Each case has string `id`, `surface`, `class`, object `input`,
and object `expected`. Optional `tamper` describes a byte mutation:
`base_case` string, `byte_index` nonnegative integer, `xor` integer 1–255,
and optional `target` string (`input.text`, `input.entry`, or
`input.base64url`). The derived bytes MUST equal the case's stored bytes.

## Inputs and dispatch

Invalid argument shapes are intentionally expressible in cases. A schema
accepting any JSON type at such a position permits testing a typed denial;
it does not permit that shape in an artifact. No host operation executes.

Byte sources select, in order: true `non_binary` (a deliberately wrong API
type), string `text` (UTF-8 bytes), string `base64url` (decoded bytes), then
string `raw_file` (the identified sidecar). A raw source also carries
`sha256_base64url`, the unpadded SHA-256 of those sidecar bytes; the loader
checks the reference and hash before execution. `bounds` is an optional,
nullable decoder override object; wrong shapes reach the bounds denial.

| Surface | Input members and execution | Successful projection |
|---|---|---|
| `json.decode` | byte source, `bounds`; bounded JSON decode | `value`: decoded JSON |
| `canonicalization.encode` | byte source decoded under maximum ceilings, then encode under `bounds` | `encoded`: canonical bytes, base64url in results |
| `base64url.decode` | `base64url`: strict unpadded segment | `decoded`: bytes, base64url in results |
| `digest.tagged` | string `tagged`, or string `text` plus string `domain` and `declared` | `tagged`: normalized digest, or `verified`: true |
| `blueprint.decode` | byte source, `bounds` | `digest`: recomputed content digest |
| `deployment.decode` | byte source, `bounds`; optional `binding` with `blueprint` bytes, `now` timestamp and `max_attestation_age_ms` | `digest`: recomputed deployment digest |
| `signature.verify` | `entry`: JSON text of the signature entry; `keys`: array of `{key_id, key}` strings, key as base64url raw 32-byte public key | `verified`: true |
| `schema.validate_instance` | object `schema` or string `schema_file`; `instance`: JSON including null; optional `dialect` string | `valid`: true |
| `negotiation.negotiate`, `extension.resolve` | `artifact`: decoded JSON; optional nullable `support` | `revision`: integer; `critical`, `quarantined`, `notices`: sorted string arrays |
| `bounds.new` | optional nullable `bounds` | `bounds`: all eight effective decoder limits |
| `bounds_algebra.intersect` | `blueprint`, `deployment`, `host`: bound maps; optional `protected_clamp`: `acknowledge` or default deny | `effective`: bound map; `clamp_count`: integer |
| `portability.scan` | byte source | `clean`: true |
| `compatibility.verify` | byte source for Deployment; `observed.identities`: array of exact `{kind,name,version,digest}` identities | `verified`: true |
| `federation.decode` | byte source and `bounds`, or one of the state/carrier inputs below | `canonical`: base64url canonical envelope bytes; codec `value`: string, or carrier `decoded`: true |
| `federation.verify_commitment` | `envelope`: canonical bytes as text; optional nullable receiving `context` | `task_identity`: string |
| `reconcile` | `blueprint`, `deployment`: canonical bytes as text; `inputs`: import options below | `evidence`: the complete typed evidence projection |
| `predicate` | `mode`: `validate` or `evaluate`; `predicate`: JSON AST; `port_names`: string array; `ports`: JSON object for evaluation | `valid`: true for validation; `value`: boolean for evaluation |

`domain` selects `blueprint_content`, `deployment_content`,
`federation_envelope`, `signature`, `extension_schema`, `extension_registry`,
`conformance_report`, or `corpus_index`.

Support members: `revisions` (integer array, default `[1]`), `core_fields`
(string array, default empty), `registry` (namespace-to-entry object),
`schemas` (namespace-to-schema object). Registry-entry members: `owner`
string, `criticality` string, `state` string, nullable `schema_digest` and
`a2a_uri` strings, nullable integer `promoted_at_revision`. Absent overrides
use the compiled registry. Schemas are digest-pinned by that registry.

Bound maps use the thirteen names in the protocol. Costs are
`{amount,currency}`; classification is `{ordinal,markers}`; other protected
bounds are strings. Bound sources are constructed in blueprint, deployment,
host order before totality is checked.

The federation decode router accepts text, base64url and the non-binary
marker, followed by codecs; it does not select a raw-file-only input.
Federation codec inputs, in precedence order, are strings `from_a2a_state`,
`to_a2a_state`, `from_mcp_state`, `to_mcp_state`, then objects
`from_a2a_carrier`, `from_mcp_carrier`. Byte inputs take precedence over codecs.
Receiving-context members are `keys` (as above), nullable `issuer`, `subject`,
`audience` strings, nullable `issuer_key_sets` (issuer-to-key-array object),
nullable `created_after`, `created_before` timestamp strings, and
`prior_receipts` (array of string `task_identity`, `terminal_state`,
`commitment` objects). These are inputs to existing receipt checks only.

Import `inputs` members: `host_bounds`, `support`, `keys` as above;
`protected_clamp` selects deny or acknowledge; `observations` has `now`,
which is null or a calendar-valid whole-second Z-form timestamp string
(`YYYY-MM-DDTHH:MM:SSZ`), nullable integer `max_attestation_age_ms`, and `observed`, a map from
logical operation to descriptor digest. The runner parses canonical bytes
without running standalone artifact validation before the composed pass,
so negotiation, structure, portability, signatures, binding, and bounds
retain their pinned order. The evidence has protocol revision, both digests,
ordered `checks` (`surface`, member-path `subject`, boolean `verified`, typed
`detail`), `effective_bounds`, ordered `clamps`, retained optional namespaces,
and ordered, deduplicated `not_verified`. A clamp has `field`, `class`, `unit`,
`requested`, `effective`, `source`, and `acknowledged`. Signature detail is
`{key_ids:[...]}` or `no_signatures_present`; binding detail has string arrays
`checked` and `not_verified`; digest detail is a tagged digest; other details
are null, `retained`, or `quarantined`.

## Agreement and output

An expected invalid result has `verdict: invalid` and `code`; reconcile also
pins `subject`, an array of member names and indices. An expected valid
result has `verdict: valid` and one or more projected fields. Legacy cases
may pin a subset of the projection. Numbers compare by mathematical value.
Legacy byte fields accept their exact UTF-8 string or base64url spelling.
A results document always uses base64url for byte-bearing projections.

Every signature case with a decodable 64-byte signature also projects
`strict_signature`: its independently computed strict point/scalar verdict,
even if cryptographic verification denied. It MUST agree with the expected
boolean where that boolean is present. Error precedence is the protocol's
per-surface precedence and input rules above. A failure projects its code,
including `ceiling:<key>`.

The aggregate report remains one JCS object, without a trailing newline:
`format`, `corpus_digest`, `total`, `agreed`, `disagreed`, `agreement`, and
`exit_status`. Its format is `agent-blueprint-protocol-conformance-report`.
Agreement requires a nonzero total and zero disagreements.

A results document is JCS with no trailing newline, format
`agent-blueprint-protocol-conformance-results`, `corpus_digest`,
`registry_digest`, and `results` sorted by case id. Each row has `id`,
`surface`, and `result` (the implementation's complete projection including
`verdict`). It has no implementation identity. The certified document is
[certified-results.json](certified-results.json).

For reconcile, any other `now` value denies `invalid_type` with subject
`["now"]`. Omission is equivalent to null.

Both runners accept `--corpus <dir>`, `--results --corpus <dir>`, and
`--serve --corpus <dir>`. Their shared exit codes are 0 agreement, 1
disagreement, and 2 usage/readability/integrity failure. The kit uses 3 for
an internal invariant failure and additionally offers no-argument embedded-corpus mode,
`--prior-corpus`, `--artifact`, `--help`, `--version`, and the external harness.
Help and version exit 0; artifact mode exits 0 valid, 1 invalid, 2 unreadable.

Before corpus output, stderr has exactly one certification line:
`corpus digest matches the release-certified corpus` or
`corpus digest does not match the release-certified corpus`.
The label never changes stdout JSON. Readers reject symlinks and nonregular
files, cap the tree at 1,000 entries and 5,000,000 file bytes, ignore Finder
metadata, and disclose no unreadable path or contents in their error line.
These corpus file-count and total-byte caps are tooling limits, separate
from artifact decoder limits. They MAY be raised in a minor release without
changing artifact limits or earlier corpus identities and claims.

The deprecated federation import is paired with
`negotiation-import-deprecated-federation`: reconcile accepts its schema-pinned
critical body, and negotiation projects the typed `extension_deprecated` notice.
The reference Evidence record has no notices member; the notice is never
invented as an evidence field.
