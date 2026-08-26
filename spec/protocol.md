# Agent Blueprint Protocol — specification

Status: published pre-1.0 protocol (0.x release line). This document is
the normative specification of the Agent Blueprint Protocol. The
reference implementation and its conformance corpus (digest
`sha-256:sg6Fo7p8nZpJDzxFn4dXHBWgbGvEvtOk-7t3m7OT7Yo`, 94 cases) are
certified against this document at every release through the release
identity chain — the specification digest, the package version, and the
corpus and registry digests are pinned together per release, and the
release-candidate check asserts the chain from live state. Where this
document and the implementation disagree, one of them is defective and
the release does not ship until the chain is reconciled.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and
"OPTIONAL" in this document are to be interpreted as described in
BCP 14 [RFC2119] [RFC8174] when, and only when, they appear in all
capitals, as shown here. Keywords apply to what a conforming
implementation (the Conformance clause) is required to do; prose that
describes the reference implementation without stating a requirement is
informative.

**The protocol is non-authorizing.** It validates structure, canonical
bytes, bounds, compatibility, and evidence. Protocol validity never
grants authority: a consuming host remains responsible for identity,
tenancy, live policy, effect ownership, execution, and evidence
retention. Every verification result — including a fully green one — is
evidence, never a decision.

## 1. Scope, non-goals, and terminology

Two language-neutral artifacts:

- **Blueprint Core** — stable identity, typed ports, logical capability
  requirements, bounds, evidence commitments, registered extensions.
- **Deployment Manifest** — environment-local tool, principal, data,
  authority, effect, evaluation, and exact-build bindings for one
  Blueprint release digest.

Deliberately out of scope (host-owned): runtime kernel, live authority
and grants, effect admission/replay/recovery, product schemas, transport
clients, billing, evaluation truth. The package compiles to an inert
library: no supervision tree, no application callback, zero third-party
production dependencies.

### Terminology

- **Artifact** — a Blueprint or Deployment Manifest value together with
  its exact canonical bytes; the artifact's identity is its content
  digest — the digest of the artifact's digest-covered members over
  those canonical bytes (the digest section defines the exact input;
  the digest member itself, signatures, and attestations are
  excluded).
- **Host** — the consuming runtime. Every non-establishment obligation
  in this protocol belongs to a host, and a green result never
  transfers one to the package.
- **Deny** — the fail-closed outcome: a typed error code with subject
  and optional detail. A deny is never a repair and never a silent
  skip; where this document states a requirement as a deny, the
  requirement is absolute (MUST-level) and the error code named is the
  code that enforces it.
- **Quarantine** — retain byte-exactly without validating or executing:
  an unknown optional extension's payload round-trips, is typed as
  unscanned, and confers no portability claim.
- **Clamp** — the effective narrowing of an operational bound, emitted
  with evidence whenever effective differs from requested; protected
  bounds deny instead of clamping.
- **Ceiling vs bound** — operational bounds are magnitude limits that
  narrow pointwise; protected ceilings are ordinal-lattice positions
  (classification, disclosure, effect impact, authority, approval) that
  never widen and deny narrowing by default (both in the evolution
  laws). A parse ceiling is neither: it is a tighten-only decoder
  limit, never an intersection input.
- **Evidence** — a structured observation about bytes or structure:
  per-surface check results, clamp records, and the non-empty
  `not_verified` set naming what was NOT established. Evidence is
  input to a host decision; it is never a decision.
- **Portability** — the property that an artifact carries no
  environment-bound values (secrets, keys, grants, tenant ids,
  endpoints, engine ids); enforced structurally and honestly limited
  (the portability section).
- **Posture** — the declared stance of a surface: fail-closed (deny),
  acknowledge-and-record (clamp with evidence, or a typed notice), or
  opt-in (a host-supplied policy).
- **Authored channel** — the `:authored_extensions` path by which a
  producer-declared critical extension body, validated against a
  digest-pinned host schema, is treated as authored content and spared
  the generic value-shape heuristics (still covered by the artifact's
  digest).

## 2. Artifacts and the closed world

Both artifacts MUST decode as JSON objects under the bounded ceilings
(depth, members, items, nodes, string bytes, key bytes, number lexemes
— the ceiling family). Decoding MUST be fail-closed under the pinned
failure precedence: unknown member → missing required → type →
constraint → cardinality → nested → cross-field hooks.

The registries are closed worlds — the exact member sets the shipped
tables define:

- **Blueprint Core (18 members).** Required: `blueprint_id`,
  `protocol_revision`, `producer`, `release_number`,
  `capability_requirements`, `input_ports`, `output_ports`,
  `output_contract`, `triggers`, `ceilings`, `classification_ceiling`,
  `effect_intents`, `evaluation_assertions`, `extensions`,
  `required_core_fields`, `content_digest`. Optional: `signatures`,
  `attestations`.
- **Deployment Manifest (19 members).** Required: `protocol_revision`,
  `blueprint_release`, `scope_projection`, `tool_bindings`,
  `data_bindings`, `authority_requirement`, `effect_owner`,
  `signer_custody`, `eligibility`, `model_policy`, `host_bounds`,
  `lifecycle`, `build_identities`, `evaluation_binding`, `extensions`,
  `required_core_fields`, `deployment_digest`. Optional: `signatures`,
  `attestations`.

Every core member addition MUST be accompanied by a protocol revision
increment: an older consumer rejects an unknown member, so the
vocabulary can only evolve at a revision boundary. No identifier in the
package — module, function, path, corpus, or config — carries a version
token; the Hex package version is the sole version number.

A complete, valid Blueprint as it travels on the wire (the conformance
corpus's `blueprint-decode-valid` case, byte-exact — every fenced
JSON example in this specification is a corpus case):

```json corpus:blueprint-decode-valid
{"blueprint_id":"example.demo/echo","capability_requirements":[{"approval_trait":"none","argument_schema":{"type":"object"},"authority_trait":"none","classification_ceiling":"internal","impact_class":"ordinary","operation_family":"example.demo.read_shape","operation_kind":"read","result_schema":{"type":"object"}}],"ceilings":{"max_attempts":3,"max_concurrency":2,"max_cost":{"amount":1000,"currency":"USD"},"max_depth":8,"max_descendants":64,"max_elapsed_ms":60000,"max_fan_out":4,"max_tokens":100000},"classification_ceiling":"internal","content_digest":"sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8","effect_intents":[{"impact_class":"ordinary","logical_operation":"record_summary","operation_kind":"mutation"}],"evaluation_assertions":[{"kind":"output_schema","port":"result","schema":{"type":"object"}}],"extensions":{"critical":{},"optional":{}},"input_ports":[{"classification_ceiling":"internal","name":"request","required":true,"schema":{"type":"object"}}],"output_contract":{"classification_ceiling":"internal","port":"result"},"output_ports":[{"classification_ceiling":"internal","name":"result","required":true,"schema":{"type":"object"}}],"producer":{"created_at":"2026-08-20T00:00:00Z","identity":"example.demo","toolchain":"example.demo.toolchain"},"protocol_revision":1,"release_number":1,"required_core_fields":[],"triggers":["manual"]}
```

### Member grammar — Blueprint Core (18 members)

Cardinality `1` members are required; `0..1` members are optional.
The failure precedence is the pinned closed-world order: unknown
member → missing required → type → constraint → cardinality →
nested → cross-field hooks. Every sub-member listed inside an
object/array type is required unless marked `(opt)`.

| Member | Card. | Type | Constraints |
|---|---|---|---|
| `blueprint_id` | 1 | string | value: producer-qualified name |
| `capability_requirements` | 1 | array<object{ operation_family:string; argument_schema:custom; result_schema:custom; operation_kind:enum(computation\|mutation\|read); impact_class:enum(authority\|money\|ordinary\|secret); classification_ceiling:enum(confidential\|internal\|public\|restricted); approval_trait:enum(human_required\|none\|separated_human_required); authority_trait:enum(external_authority_required\|local_policy\|none) }> | max 64, unique by operation_family |
| `ceilings` | 1 | object{ max_attempts:integer; max_concurrency:integer; max_depth:integer; max_descendants:integer; max_elapsed_ms:integer; max_fan_out:integer; max_tokens:integer; max_cost:object{ amount:integer; currency:string } } | — |
| `classification_ceiling` | 1 | enum(confidential\|internal\|public\|restricted) | — |
| `effect_intents` | 1 | array<object{ logical_operation:string; operation_kind:enum(computation\|mutation\|read); impact_class:enum(authority\|money\|ordinary\|secret) }> | max 64, unique by logical_operation |
| `evaluation_assertions` | 1 | array<custom> | max 128 |
| `extensions` | 1 | custom | — |
| `input_ports` | 1 | array<object{ name:string; schema:custom; classification_ceiling:enum(confidential\|internal\|public\|restricted); required:boolean }> | max 64, unique by name |
| `output_contract` | 1 | object{ port:string; classification_ceiling:enum(confidential\|internal\|public\|restricted) } | — |
| `output_ports` | 1 | array<object{ name:string; schema:custom; classification_ceiling:enum(confidential\|internal\|public\|restricted); required:boolean }> | max 64, unique by name |
| `producer` | 1 | object{ identity:string; created_at:string; toolchain:string } | — |
| `protocol_revision` | 1 | integer | value: positive integer |
| `release_number` | 1 | integer | value: positive integer |
| `required_core_fields` | 1 | array<string> | unique by value |
| `triggers` | 1 | array<enum(condition\|delegated\|evaluation\|manual\|schedule)> | min 1, unique by value |
| `signatures` | 0..1 | array<custom> | max 16 |
| `attestations` | 0..1 | array<any> | max 16 |
| `content_digest` | 1 | string | value: tagged digest |

### Member grammar — Deployment Manifest (19 members)

Cardinality `1` members are required; `0..1` members are optional.
The failure precedence is the pinned closed-world order: unknown
member → missing required → type → constraint → cardinality →
nested → cross-field hooks. Every sub-member listed inside an
object/array type is required unless marked `(opt)`.

| Member | Card. | Type | Constraints |
|---|---|---|---|
| `authority_requirement` | 1 | object{ adapter_identity:string; profile_identity:string } | — |
| `blueprint_release` | 1 | object{ blueprint_id:string; release_number:integer; content_digest:string } | — |
| `build_identities` | 1 | array<object{ kind:enum(adapter\|build\|extension\|package); name:string; version:string; digest:string }> | max 128, min 1, unique by name |
| `data_bindings` | 1 | array<object{ logical_dataset:string; classification_ceiling:enum(confidential\|internal\|public\|restricted); as_of:object{ mode:enum(none\|required); max_age_ms:custom } }> | max 64, unique by logical_dataset |
| `effect_owner` | 1 | object{ adapter_identity:string; idempotency:object{ key_derivation:enum(host); recovery:enum(authoritative\|none) } } | — |
| `eligibility` | 1 | object{ owner:custom; beneficiary:custom; runtime_principal:custom } | — |
| `evaluation_binding` | 1 | object{ adapter_identity:string; corpus:object{ name:string; digest:string } } | — |
| `extensions` | 1 | custom | — |
| `host_bounds` | 1 | object{ approval_trait:enum(human_required\|none\|separated_human_required); authority_trait:enum(external_authority_required\|local_policy\|none); classification_ceiling:enum(confidential\|internal\|public\|restricted); disclosure_ceiling:enum(detail\|full\|none\|summary); effect_impact_ceiling:enum(authority\|money\|ordinary\|secret); max_attempts:integer; max_concurrency:integer; max_cost:object{ amount:integer; currency:string }; max_depth:integer; max_descendants:integer; max_elapsed_ms:integer; max_fan_out:integer; max_tokens:integer } | — |
| `lifecycle` | 1 | object{ state:enum(active\|draft\|retired); activated_at (opt):string; retired_at (opt):string } | — |
| `model_policy` | 1 | object{ allowed_model_roles:array<string>; max_tokens:integer; max_cost:object{ amount:integer; currency:string } } | — |
| `protocol_revision` | 1 | integer | value: positive integer |
| `required_core_fields` | 1 | array<string> | unique by value |
| `scope_projection` | 1 | object{ adapter_identity:string } | — |
| `signer_custody` | 1 | enum(external_kms\|holder_edge\|host_managed) | — |
| `tool_bindings` | 1 | array<object{ logical_operation:string; adapter_identity:string; descriptor_digest:string; schema_digest:string; attested_at:string }> | max 128, unique by logical_operation |
| `signatures` | 0..1 | array<custom> | max 16 |
| `attestations` | 0..1 | array<any> | max 16 |
| `deployment_digest` | 1 | string | value: tagged digest |

## 3. Bytes

- **Encoding:** interchange bytes MUST be UTF-8 JSON within the decoder
  ceilings. Duplicate members MUST deny `:duplicate_member` (I-JSON);
  trailing bytes MUST deny `:trailing_bytes`.
- **Integer window:** a pure-digit lexeme above ±(2^53−1) decodes as a
  float iff that double's canonical ECMAScript serialization reproduces
  the lexeme byte-exactly; every other above-bound lexeme MUST deny
  `:number_not_double_expressible`. Core fields are integer-typed by
  schema: a float-tagged window value in a core field MUST deny
  `:invalid_type`.
- **base64url:** unpadded, exact alphabet; padded input MUST deny
  `:base64url_padded`, non-alphabet input MUST deny `:base64url_invalid`.
- **Canonicality:** interchange bytes MUST already be canonical —
  decode → re-encode → byte-compare; non-canonical bytes MUST deny
  `:non_canonical_bytes` before any semantic read, and digests MUST be
  computed only over the exact received bytes.

## 4. Canonicalization

The canonical form MUST be RFC 8785 JSON Canonicalization Scheme:

- No whitespace between tokens (§3.2.1).
- Control characters U+0000–U+001F escaped as lowercase `\uXXXX` except
  the five short escapes; `"` and `\` escaped; a lone surrogate denies
  (§3.2.2.2).
- Numbers per ECMA-262 7.1.12.1 including the Note 2 enhancement:
  `1.0 → "1"`, `1.0e22 → "1e+22"`, `-0.0 → "0"`, `5.0e-324 → "5e-324"`,
  `1.7976931348623157e308 → "1.7976931348623157e+308"`; NaN and Infinity
  deny (§3.2.2.3).
- Object members sorted as UTF-16 code units compared as unsigned
  integers (§3.2.3) — NOT by UTF-8 byte order: for `U+FF3A` vs
  `U+10000`, UTF-16 order puts `U+10000` first.

## 5. Digest

```
digest_bytes = SHA-256( domain_separator || <<0>> || JCS(digest_input) )
```

`digest_input` is the artifact object minus `content_digest` (or
`deployment_digest`), `signatures`, and `attestations` — everything
else is covered, including extensions and unknown-but-optional
extension payloads retained verbatim.

| Purpose | Separator |
|---|---|
| Blueprint content | `agent-blueprint-protocol/blueprint-content` |
| Deployment content | `agent-blueprint-protocol/deployment-content` |
| Federation envelope | `agent-blueprint-protocol/federation-envelope` |
| Signature input | `agent-blueprint-protocol/signature` |
| Conformance report | `agent-blueprint-protocol/conformance-report` |
| Corpus index | `agent-blueprint-protocol/corpus-index` |

Separators carry no version token: `protocol_revision` is itself a
covered member. The wire form MUST be the self-identifying tagged string
`sha-256:<43-char unpadded base64url>`, never a bare hex blob; an
unknown algorithm tag MUST deny `:digest_algorithm_unsupported`, a
malformed body MUST deny `:digest_encoding_invalid`. Algorithm succession
is therefore a data change, not a format break.

## 6. Signature envelope

Signatures are detached and evidence-only. The package verifies; it
MUST NOT sign, MUST NOT accept a private key on any public function,
and MUST NOT embed public keys in artifacts (the host supplies trusted
keys).

- Format: RFC 7515 compact + RFC 7797 `b64=false` unencoded detached
  payload. Protected header: `{alg: EdDSA, kid, crit: ["b64"], b64:
  false}`. Ed25519 only; an unknown `alg` MUST deny.
- `signed_attributes = {algorithm, content_digest, created_at, key_id,
  purpose}` with `purpose` one of `blueprint` | `deployment` |
  `federation-envelope`; the signing input is the signature domain
  separator, a zero byte, and JCS(signed_attributes).
- Because the digest covers `protocol_revision`, identity members,
  extensions, and `required_core_fields`, a signature cannot be lifted
  onto a different artifact, revision, or purpose; `key_id` prevents key
  substitution. A `key_id` matching no supplied key MUST produce a
  `verified: false` check entry with `:signature_key_unsupported` — the
  package performs no key discovery, fetch, or trust selection.
- Attestations use the identical envelope with a registered `kind` and
  a `statement_digest`. The attestation kind registry is empty by
  design in this release.
- Small-order Ed25519 public keys (identity and order-2 encodings)
  MUST reject `:signature_key_unsupported`.

## 7. Evolution and negotiation

`protocol_revision` is a digest-covered body member. This release is
revision 1. A consumer's support MUST declare an explicit revision SET
(never a range); a revision outside the set MUST deny
`:protocol_revision_unsupported` — above-max and below-min alike, both
fail-closed.

`required_core_fields` is the producer's declaration of which covered
core members a consumer must honor. Three checks, all fail-closed:
every entry names a known core member (`:required_core_field_unsupported`),
is digest-covered (`:required_core_field_not_digest_covered` — an
evidence-only member laundered into a requirement is a tamper blind
spot), and is in the consumer's supported set.

### Extension criticality

For each `namespace → {criticality, payload}` in `extensions`, the
outcomes in this table are absolute requirements:

| Registry state | Declared critical | Declared optional |
|---|---|---|
| unregistered | deny `:extension_unknown_critical` | retained verbatim, quarantined, never executed |
| reserved | deny `:extension_unknown_critical` | retained verbatim; typed notice |
| active, criticality matches | supported | retained and executable |
| active, criticality mismatch | deny `:extension_criticality_conflict` | deny `:extension_criticality_conflict` |
| deprecated | supported + typed notice | supported + typed notice |
| retired | deny `:extension_retired` | retained verbatim; typed notice |

An unknown optional extension MUST round-trip byte-exactly (`decode →
to_value → encode` is a fixed point, property-tested). Lifecycle
asymmetry: optional→critical promotion requires a revision increment;
demotion does not. A retired namespace MUST never be reused.

## 8. Extension registry

Namespace form: reverse-DNS-plus-path (`com.example.commerce/graph`),
lowercase, one `/`, length-ceilinged, and not parseable as an absolute
URI with a network authority (a namespace can never double as an
endpoint). The registry MUST ship as compiled-in data in the package —
registry content is a code release; there is no registry directory or
file, and drift between shipped code and shipped registry is
unrepresentable. Registered at this release:

| Namespace | Owner | Criticality | State |
|---|---|---|---|
| `com.example.commerce/graph` | ExampleCommerce | critical | active |
| `com.example.commerce/classification-labels` | ExampleCommerce | optional | active |
| `com.example.commerce/rubric-assertion` | ExampleCommerce | optional | active |
| `com.example.platform/estate` | ExamplePlatform | optional | deprecated |
| `com.example.platform/estate-contract` | ExamplePlatform | critical | active |
| `com.example/federation` | Agent Blueprint Protocol | critical | active |

`com.example.platform/estate-contract` is the product-extension registration:
the first product-owned critical namespace with an authored schema pin. The
document ships as corpus data
(`priv/conformance/schemas/estate-contract.schema.json`); `lib/` carries only
the digest pin, test-bound to the shipped file. The deprecated
`com.example.platform/estate` placeholder retains its optional bodies with a
typed notice — existing artifacts stay verifiable.

Critical-extension bodies validate only against a host-supplied schema
whose digest matches the registry's `schema_digest`; a missing schema
denies `:extension_schema_unavailable`, a mismatched digest denies
`:extension_schema_digest_mismatch`. Entry changes are owner-made,
changelog-recorded, and ADR-recorded. The registry's own digest is
bound into the corpus index but not into artifact digests: an artifact
must remain verifiable against a registry that legitimately gained
entries after it was produced; hosts wanting pinning SHOULD use
`build_identities`.

## 9. Bounds algebra

Two bound families, never conflated with parse ceilings (those are
tighten-only decoder limits):

- **Operational** (8 members, all REQUIRED — absent is
  `:missing_ceiling`, never infinity): `max_attempts`,
  `max_concurrency`, `max_cost`, `max_depth`, `max_descendants`,
  `max_elapsed_ms`, `max_fan_out`, `max_tokens`. Pointwise narrowest
  meet; every narrowing MUST emit clamp evidence.
- **Protected** (5 members: `classification_ceiling`,
  `disclosure_ceiling`, `effect_impact_ceiling`, `authority_trait`,
  `approval_trait`): ordinal lattices (plus set-monotone markers
  `{pci, phi}` on classification). Narrowing a protected bound MUST
  deny `:protected_bound_clamp_denied` by default; a host MAY opt into
  an acknowledge posture, which MUST always record evidence.
  Obligation families (authority, approval, effect impact) meet at the
  STRICTEST value; markers are retained regulatory obligations whose
  effective set is the UNION of sources — dropping one is a widening.

Laws (property-tested): meet is idempotent, commutative, associative;
effective bounds MUST NOT widen host policy (`not widens?(effective,
host)` universally); a clamp is emitted iff effective ≠ requested on an
operational field. `model_policy` and `data_bindings` are not
intersection inputs.

## 10. Compatibility and binding

A manifest's `blueprint_release` MUST bind to exactly one Blueprint
content digest (digest equality only — no fuzzy match).
`build_identities` carry exact identities; compatibility verification
MUST be identity-exact or deny: a range expression, missing entry, or
duplicate denies (`:compatibility_identity_inexact`,
`:compatibility_entry_missing`, `:compatibility_duplicate_entry`).
Binding verification is a pinned deny-ordered check including
attestation freshness (`:binding_attestation_stale`) and
descriptor-digest equality (`:binding_descriptor_mismatch` — the tool
rug-pull case).

## 11. Federation profile

A 23-member task envelope carried in A2A `Task.metadata` / MCP `_meta`
under the registered `com.example/federation` extension; the full
field-by-field A2A/MCP mapping (3 native, 5 partial, 15 extension
members) also ships with the reference implementation's document set.
Zero native wire fields; no native transport. State codecs MUST be
lossy-aware: A2A `REJECTED`/`AUTH_REQUIRED` deny crossing into MCP,
`UNSPECIFIED` is unmapped (`:federation_state_unmappable`);
cancellation MUST remain a request, never a terminal receipt. A
Terminal Commitment digests task identity, terminal state, result
digest, result classification, compatibility ref, authority-proof
refs, and checkpoint-history commitment; ANY divergence between
receipts for one task identity MUST deny
`:federation_terminal_conflict` — not just state divergence.
`Federation.verify_commitment` compares issuer/subject/audience
against the receiving context (`:audience_mismatch`). AgentCard
signing carries a protobuf field-presence pre-normalization on top of
JCS (documented in the mapping so adapters do not inherit silent
verification failure). Correlation grants nothing.

### Member grammar — Federation TaskEnvelope (23 members)

The envelope is a closed world: one wire member per logical field,
carried as the extension body under the `com.example/federation`
namespace on both transports. Cardinality `1` members are required;
`0..1` members are optional (absent — there is no null form). Cross-
member hooks: `checkpoint_status` MUST NOT coexist with `terminal_state`
(`:invalid_constraint`), and the terminal hooks bind
`terminal_state`/`evidence_receipt` presence together. The receipt's
`terminal_commitment` is the domain-separated digest of the seven
Terminal-Commitment components.

| Member | Card. | Wire form |
|---|---|---|
| `task_identity` | 1 | identifier string |
| `idempotency_identity` | 1 | identifier string |
| `parent_execution_reference` | 0..1 | identifier string |
| `initiating_subject` | 0..1 | identifier string |
| `blueprint_digest` | 1 | tagged digest |
| `deployment_digest` | 1 | tagged digest |
| `input_commitment` | 1 | tagged digest |
| `result_schema` | 1 | tagged digest (result schema identity) |
| `result_classification_ceiling` | 1 | classification enum element |
| `time_policy` | 1 | object{ elapsed_ms: positive integer } |
| `resource_policy` | 1 | object{ attempts, concurrency, tokens, cost: positive integers } |
| `recovery_handle` | 1 | identifier string |
| `issuer` | 1 | identifier string |
| `subject` | 1 | identifier string |
| `audience` | 1 | identifier string |
| `identity_mapping_evidence` | 1 | identity-evidence object (correlation only) |
| `checkpoint_request` | 0..1 | object{ kind: checkpoint enum; request_digest: tagged digest } |
| `checkpoint_status` | 0..1 | checkpoint-status enum |
| `checkpoint_commitment` | 0..1 | tagged digest |
| `terminal_state` | 0..1 | terminal-state enum |
| `evidence_receipt` | 0..1 | object{ result_digest: tagged; checkpoint_history_commitment: tagged; terminal_commitment: tagged; signature: detached JWS envelope } |
| `compatibility_reference` | 1 | array (min 1, unique by name) of object{ name: identifier; identity: nonempty string } |
| `authority_proof_references` | 1 | array of tagged digests |

## 12. Error vocabulary

A closed typed set — `%Error{code, subject, detail}`. An
implementation MUST NOT emit an undeclared code, and every code it
declares MUST be reachable (enforced two-directionally by a build
gate).
The 74 codes of this release, with semantics (when the code is
raised, the subject it names, and the host action it demands):

| Code | Raised when | Subject | Host action |
|---|---|---|---|
| `attestation_malformed` | an attestation envelope fails its structural parse | attestations | reject the artifact |
| `audience_mismatch` | a federation receipt's issuer/subject/audience does not match the receiving context | federation envelope | reject the receipt |
| `base64url_invalid` | a base64url lexeme carries a non-alphabet character | offending member | reject the artifact |
| `base64url_padded` | a base64url value arrives padded | offending member | reject the artifact |
| `binding_attestation_stale` | a tool-binding attestation is older than the pinned freshness window | tool_bindings | reject the import as stale |
| `binding_descriptor_mismatch` | a bound tool's descriptor digest differs from the observed descriptor | tool_bindings | halt the binding (rug-pull guard) |
| `binding_incomplete` | the binding check set is incomplete where completeness is required | bind surface | halt the import (reconcile denies) |
| `bound_source_missing` | an intersection input names a bound source that is absent | bounds sources | reject the intersection call |
| `bound_unit_mismatch` | two bounds meet with incompatible units | bounds | reject the intersection call |
| `bound_unknown` | an unknown bound name appears | bounds | reject the artifact |
| `bound_value_invalid` | a bound value fails its shape or range check | bounds | reject the artifact |
| `compatibility_duplicate_entry` | build_identities carries a duplicate identity | build_identities | reject the manifest |
| `compatibility_entry_missing` | verification names an identity with no manifest entry | build_identities | deny compatibility |
| `compatibility_identity_inexact` | a build identity is a range or fuzzy form | build_identities | reject the manifest |
| `corpus_applicability_incomplete` | the corpus applicability floor has uncovered cells | corpus index | operator: fix the corpus; never a wire condition |
| `corpus_case_id_duplicate` | two corpus cases share an id | corpus | operator: fix the corpus |
| `corpus_case_invalid` | a corpus case fails its own schema | corpus | operator: fix the corpus |
| `corpus_count_mismatch` | the index case total disagrees with the case set | corpus index | operator: regenerate the index |
| `corpus_empty` | the corpus carries no cases | corpus | operator: fix the corpus |
| `corpus_file_set_mismatch` | the corpus file set differs from the index (both directions) | corpus | operator: fix the corpus |
| `corpus_hash_mismatch` | a corpus file's hash differs from the index entry | corpus | operator: fix the corpus |
| `corpus_index_invalid` | the corpus index fails its structural parse | corpus index | operator: regenerate the index |
| `deployment_digest_mismatch` | the declared deployment digest differs from the computed digest | deployment_digest | reject the manifest (tamper) |
| `digest_algorithm_unsupported` | an unknown digest algorithm tag | digest member | reject the artifact |
| `digest_encoding_invalid` | a malformed digest body | digest member | reject the artifact |
| `digest_mismatch` | a content digest differs from the computed digest | content_digest | reject the artifact (tamper) |
| `duplicate_member` | a duplicate JSON member name (I-JSON) | bytes | reject the artifact |
| `extension_criticality_conflict` | declared criticality conflicts with the registry | extensions | reject the artifact |
| `extension_duplicate` | one namespace appears twice in extensions | extensions | reject the artifact |
| `extension_namespace_invalid` | a namespace fails the reverse-DNS-plus-path form | extensions | reject the artifact |
| `extension_payload_forbidden` | a payload appears where the registry forbids one | extensions | reject the artifact |
| `extension_retired` | a retired namespace is declared | extensions | reject the artifact |
| `extension_schema_digest_mismatch` | a critical body's validating schema digest differs from the registry pin | extensions | reject the artifact |
| `extension_schema_unavailable` | no host schema is supplied for a digest-pinned critical body | extensions | reject the artifact |
| `extension_unknown_critical` | an unregistered or reserved namespace is declared critical | extensions | reject the artifact |
| `federation_mapping_conflict` | a state has no consistent mapping on the target transport | federation codec | reject the crossing |
| `federation_state_unmappable` | a state is unmappable (e.g. A2A UNSPECIFIED) | federation codec | reject the crossing |
| `federation_terminal_conflict` | two receipts for one task identity diverge in any commitment component | federation envelope | reject the later receipt |
| `forbidden_portable_value` | a value shape trips the portability denylist | offending member | reject the artifact |
| `integer_magnitude` | an integer above the parse window | offending lexeme | reject the artifact |
| `invalid_cardinality` | an array violates min/max items | offending member | reject the artifact |
| `invalid_constraint` | a member fails its check constraint | offending member | reject the artifact |
| `invalid_encoding` | a member fails its encoding form | offending member | reject the artifact |
| `invalid_number` | a number lexeme is malformed | bytes | reject the artifact |
| `invalid_syntax` | the JSON text is syntactically invalid | bytes | reject the artifact |
| `invalid_type` | a member's JSON type disagrees with the schema | offending member | reject the artifact |
| `lifecycle_state_invalid` | a deployment lifecycle state is unknown | lifecycle | reject the manifest |
| `missing_ceiling` | an operational bound is absent (never infinity) | ceilings | reject the artifact |
| `missing_required_field` | a required member is absent | the member | reject the artifact |
| `no_authoritative_recovery` | a mutation-kind operation is bound while the effect owner's recovery is none | effect_owner | reject the import |
| `non_canonical_bytes` | interchange bytes are not already canonical | bytes | reject before any semantic read |
| `nonportable_content` | an authority-shaped claim rides portable content | offending member | reject the artifact |
| `number_not_double_expressible` | an above-window integer is not exactly double-expressible | offending lexeme | reject the artifact |
| `predicate_nodes_exceeded` | a predicate AST exceeds the node ceiling | predicate | reject the artifact |
| `predicate_op_unknown` | a predicate names an unknown operator | predicate | reject the artifact |
| `predicate_path_unresolved` | a predicate path resolves against no declared port | predicate | reject the artifact |
| `protected_bound_clamp_denied` | a protected bound narrows without the acknowledge opt-in | bounds | reject, or opt in and record evidence |
| `protocol_revision_unsupported` | the revision is outside the declared set (both directions) | protocol_revision | reject the artifact |
| `required_core_field_not_digest_covered` | a required core field names an evidence-only member | required_core_fields | reject the artifact |
| `required_core_field_unsupported` | a required core field names no known core member | required_core_fields | reject the artifact |
| `schema_complexity_exceeded` | a schema exceeds the complexity meter | schema document | reject the artifact |
| `schema_dialect_unknown` | a schema names an unknown dialect | schema document | reject the artifact |
| `schema_invalid_shape` | a schema is structurally malformed | schema document | reject the artifact |
| `schema_keyword_not_allowed` | a schema uses a keyword outside the bounded dialect | schema document | reject the artifact |
| `schema_keyword_value_invalid` | a schema keyword carries an invalid value | schema document | reject the artifact |
| `schema_ref_cycle` | a schema $ref cycle | schema document | reject the artifact |
| `schema_ref_unresolvable` | a schema $ref resolves nowhere | schema document | reject the artifact |
| `signature_algorithm_unsupported` | an unknown signature algorithm | signatures | halt the import (reconcile denies) |
| `signature_key_unsupported` | no supplied key matches, or a small-order key | signatures | halt the import (reconcile denies) |
| `signature_malformed` | a signature envelope fails its parse | signatures | halt the import (reconcile denies) |
| `signature_not_verified` | the cryptographic verification fails | signatures | halt the import (reconcile denies) |
| `trailing_bytes` | bytes follow the JSON value | bytes | reject the artifact |
| `unknown_bound` | a bounds member name is unknown | bounds | reject the artifact |
| `unknown_member` | a member is outside the closed world | the member | reject the artifact |
Plus the parameterized ceiling family `{:ceiling, key}` over the eight
decoder limit names. No authorization vocabulary exists in any
identifier — no `:unauthorized` in either polarity (source-scanned
gate).

## 13. Evidence and reconcile

`reconcile(blueprint, deployment, inputs)` is the one call per import:
canonical → digest → negotiation → structure → portability →
signatures → bind → bounds, in that pinned order. Its result is an
`%Evidence{}` of per-surface checks, effective bounds, clamp evidence,
and `not_verified` — which MUST be non-empty BY CONSTRUCTION, always
naming at least the seven host-owned surfaces this protocol structurally
cannot establish: `tenancy`, `live_policy`, `authority`,
`effect_ownership`, `execution`, `billing`, `evaluation_truth`. A
caller SHOULD NOT read an Evidence record and conclude "everything is
fine": the record itself names what it did not check.

## 14. Portability

Portable artifacts MUST NOT contain secrets, private keys, live grants,
tenant identifiers, raw endpoints, database primary keys, or backend
engine identifiers — enforced structurally (member-name and value-shape
denylists over the open regions, at any depth, name-spelling-normalized)
and red-cased per class in the corpus. A portability pass is not
sufficiency — the guard is necessary, not sufficient: opaque
quarantined extension bodies are typed as unscanned, and portability
claims attach only to schema-validated content. Concrete provider/model
names, credentials, engine ids, and endpoints resolve host-side and are
unrepresentable in self-fulfilling artifacts.

## 15. Conformance

The package ships a portable conformance corpus (`priv/conformance/`):
94 cases covering every required cell of the 16-surface × 31-class
applicability floor, full-registry golden artifacts, RFC 8785 number
vectors, and deterministic Ed25519 fixtures, at corpus digest
`sha-256:sg6Fo7p8nZpJDzxFn4dXHBWgbGvEvtOk-7t3m7OT7Yo`. Corpus identity
is the digest of the domain-separated index — versioned by digest, not
by name. The loader is pure over `%{path => binary}` and verifies
per-file hashes, exact file set (both directions), counts, id-uniqueness,
and applicability totality; the report refuses a vacuous green.

A repo-side second-language verifier (`conformance/verifier/`,
TypeScript on Node ≥ 24, `node:` builtins only, never in the Hex
archive) independently recomputes every corpus verdict and integrity
check with its own scanner, canonicalizer, and `node:crypto` Ed25519
path; the release gate requires its report to be byte-identical to the
Elixir escript's over both the repo corpus and the built archive's
corpus. A mutation gate breaks the implementation at seven named
points and requires the corpus to go red on each — a vacuous case set
is a build failure.

### Conforming implementations (normative)

An implementation conforms to this specification at a given release
when all three of the following hold. Partial conformance is not
conformance: an implementation that skips applicable corpus cells does
not conform at this release.

1. **Corpus pass.** It executes every case of the released conformance
   corpus — pinned by the digest above, every applicable cell of the
   applicability floor — and produces the expected verdict for each,
   refusing a vacuous pass.
2. **Report agreement.** Its case-report document over that corpus is
   byte-identical to the reference implementation's report; the report
   format is part of the wire contract, and the second-language
   verifier carries the discipline.
3. **Release identity.** Its release pins the corpus digest and the
   registry digest it certifies against, so specification, evidence,
   and implementation co-version; a release that cannot name its
   evidence is not a release of this protocol.

## 16. The shipped surface (informative — the reference implementation)

The facade (`AgentBlueprintProtocol`) delegates and never implements;
every public function carries a `@spec` (build-gated), every module a
boundary-stating moduledoc:

| Function | Contract |
|---|---|
| `decode_blueprint/1,2` | bounded, canonical-first Blueprint decode |
| `decode_deployment/1,2` | bounded, canonical-first Deployment decode |
| `decode_federation_envelope/1,2` | bounded TaskEnvelope decode |
| `canonical_bytes/1` | the artifact's canonical JCS bytes |
| `negotiate/2` | revision/required-field/extension evolution gate |
| `intersect/1` | bounds meet over blueprint/deployment/host sources |
| `verify_compatibility/2` | identity-exact build compatibility |
| `reconcile/3` | the one composed non-authorizing pass per import |
| `federation_mapping/0` | the 23-row A2A/MCP mapping as data |

Layered under it: the bytes layer (`Json`, `Canonicalization`,
`Base64Url`, `Digest`, `Bounds`), the artifacts (`Blueprint`,
`Deployment`, `Extension`, `Registry` as the one generic table-driven
engine, `Schema` as the bounded 2020-12 dialect + instance validator,
`Predicate`, `Portability`), the algebra (`BoundsAlgebra`,
`Negotiation`, `Compatibility`, `Signature`, `Federation`, `Error`,
`Evidence`, `Reconcile`, `ExtensionRegistry`), and the conformance
tooling (`Conformance.Corpus/Runner/Report/Cli` + the escript entry).
The module tree is strictly downward (bytes → algebra → artifacts →
conformance); the engine knows tables, never domains.

### Producer surface

Hosts that render artifacts produce them through the per-artifact
constructors, never through facade-level minting: compose the member
value, construct it with `Blueprint.from_value/2` or
`Deployment.from_value/2` (threading `:authored_extensions` for
critical namespaces whose bodies negotiation validated against a
digest-pinned schema), compute the release identity with the
artifact's `content_digest/1`, and serialize with its
`canonical_bytes/1`. The round-trip property (decode → `to_value/1` →
encode is a fixed point) is the byte-exactness guarantee a producer
relies on. The facade stays a verification facade: it delegates and
never implements, and no facade-level producer functions grow (the
accepted producer-surface decision record).

## 17. Security considerations (normative)

The threat model is not invented for this section: every threat below is
exercised by the conformance corpus as a named red class, and the gate
in the reference implementation reds a threat row that cites a class the
corpus does not carry.

| Threat | Vector | Corpus class | Mitigation |
|---|---|---|---|
| Artifact tamper | bytes edited after signing | `tamper_meaningful_byte` `digest_mismatch` | content digests over exact received bytes; `:digest_mismatch` before any semantic read |
| Canonicality laundering | non-canonical spellings of the same value | `invalid_duplicate` | MUST-already-be-canonical interchange bytes; `:non_canonical_bytes` |
| Signature substitution | a signature lifted onto another artifact/purpose | `signature_invalid` | purpose-pinned signed attributes; digest covers revision + identity members |
| Protocol downgrade | an older/newer revision forced on a consumer | `revision_above_max` `revision_below_min` | explicit revision SETs, both directions deny `:protocol_revision_unsupported` |
| Extension rug-pull via registry | unknown/retired namespace forced critical | `extension_unknown_critical` | registry-state table; deny with typed codes |
| Schema-pin evasion | critical body validated against a different schema | `extension_schema_unavailable` | digest-pinned schemas; `:extension_schema_digest_mismatch` |
| Tool rug-pull | a bound tool's descriptor replaced out-of-band | `binding_stale` `compatibility_range_rejected` | binding verification: descriptor-digest equality + attestation freshness + identity-exact entries |
| Ceiling widening | a bound or ceiling raised after the fact | `bound_widening_operational` `bound_widening_protected` | bounds may narrow only; protected narrowing denies by default; effective bounds never widen host policy |
| Quarantined-content laundering | unscanned payload smuggled into a claim | `extension_unknown_optional_roundtrip` `forbidden_portable_value` | quarantine is typed unscanned; portability claims attach only to schema-validated content |
| Receipt equivocation | two diverging terminal receipts for one task | `terminal_equivocation` `federation_terminal_conflict` | Terminal Commitment over seven components; ANY divergence denies |
| Misaddressed execution | a receipt verified by the wrong receiver | `audience_mismatch` | issuer/subject/audience checked against the receiving context |
| Required-field laundering | an evidence-only member promoted to a requirement | `required_field_not_covered` | required core fields MUST be digest-covered |

The non-authorizing boundary is itself a security property: every
verification result is evidence, the `not_verified` set is non-empty by
construction naming the host-owned surfaces, and no code path grants
authority. Small-order Ed25519 keys reject; the package performs no key
discovery or trust selection — a wrong key is a typed denial, never a
silent pass.

## 18. Privacy considerations (normative)

The portability guard is the protocol's data-minimization profile,
stated as a normative constraint set: portable artifacts MUST NOT carry
secrets, private keys, live grants, tenant identifiers, raw endpoints,
database primary keys, or backend engine identifiers — enforced
structurally at any depth (member-name and value-shape denylists,
name-spelling-normalized) and exercised per class by the corpus
(`forbidden_portable_value`). The honest limits are part of the
contract: quarantined extension bodies are typed as unscanned
(`extension_unknown_optional_roundtrip` carries the round-trip
obligation), and portability claims attach only to schema-validated
content — a producer MUST NOT present a portability pass as a privacy
guarantee. Federation identity members (`issuer`, `subject`,
`audience`, `identity_mapping_evidence`) are correlation material only:
an authority-shaped claim in the evidence block denies
`:nonportable_content`, and possession of a key is never an identity
claim.

## 19. Positioning — protocol neighbors (informative)

The Agent Blueprint Protocol does not compete with the transport and
discovery protocols; it completes them. AI Catalog owns discovery,
verifiable identity, and attestation; A2A owns agent-to-agent tasks;
MCP owns tools and data. ABP owns the portable CONTRACT layer — the
artifact that says what an agent is, what it may do (bounds, ceilings),
what it must prove (evidence), and how a host verifies all of it
fail-closed without granting authority. A blueprint rides IN A2A task
metadata and MCP `_meta` (the federation profile proves the carriage);
a Trust-Manifest-style discovery record can reference a blueprint by
digest without either protocol subsuming the other. Where a neighbor
mandates a signature envelope, ABP already speaks it: detached JWS over
JCS canonical bytes is the shared primitive.
