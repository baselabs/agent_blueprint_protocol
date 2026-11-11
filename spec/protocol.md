# Agent Blueprint Protocol — specification

Status: normative protocol 1.0. This document is
the normative specification of the Agent Blueprint Protocol. The
reference implementation and its conformance corpus (digest
`sha-256:oYnkSmTkHGk4AmZ8Sul99_6KYJUIuj2SN2GZAiT1glw`, 604 cases) are
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
clients, billing, evaluation truth. The reference implementation is an inert library (§16).

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
- **Authored channel** — the validated critical-extension path by which a
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
vocabulary can only evolve at a revision boundary. Protocol revisions and verification semantics are separate axes (§7).
Release package versions do not appear in the artifact grammar.

A complete, valid Blueprint as it travels on the wire (the conformance
corpus's `blueprint-decode-valid` case, byte-exact — every fenced
JSON example in this specification is a corpus case):

```json-corpus:blueprint-decode-valid
{"blueprint_id":"example.demo/echo","capability_requirements":[{"approval_trait":"none","argument_schema":{"type":"object"},"authority_trait":"none","classification_ceiling":"internal","impact_class":"ordinary","operation_family":"example.demo.read_shape","operation_kind":"read","result_schema":{"type":"object"}}],"ceilings":{"max_attempts":3,"max_concurrency":2,"max_cost":{"amount":1000,"currency":"USD"},"max_depth":8,"max_descendants":64,"max_elapsed_ms":60000,"max_fan_out":4,"max_tokens":100000},"classification_ceiling":"internal","content_digest":"sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8","effect_intents":[{"impact_class":"ordinary","logical_operation":"record_summary","operation_kind":"mutation"}],"evaluation_assertions":[{"kind":"output_schema","port":"result","schema":{"type":"object"}}],"extensions":{"critical":{},"optional":{}},"input_ports":[{"classification_ceiling":"internal","name":"request","required":true,"schema":{"type":"object"}}],"output_contract":{"classification_ceiling":"internal","port":"result"},"output_ports":[{"classification_ceiling":"internal","name":"result","required":true,"schema":{"type":"object"}}],"producer":{"created_at":"2026-08-20T00:00:00Z","identity":"example.demo","toolchain":"example.demo.toolchain"},"protocol_revision":1,"release_number":1,"required_core_fields":[],"triggers":["manual"]}
```

### Member grammar — Blueprint Core (18 members)

Cardinality `1` members are required; `0..1` members are optional.
The failure precedence is the pinned closed-world order: unknown
member → missing required → type → constraint → cardinality →
nested → cross-field hooks. Every sub-member listed inside an
object/array type is required unless marked `(opt)`. The machine-
readable grammar artifacts (CDDL under `spec/grammar/`, with the
derived JSON Schema beside them) are bound to these tables by the
grammar-derivation gate: root member sets and required flags are
cross-read against the compiled registries, and the corpus goldens
validate under the derived schemas. The derived schemas close the
artifact root; sub-object closure and cross-member hooks remain the
reference implementation's to enforce.

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
object/array type is required unless marked `(opt)`. The machine-
readable grammar artifacts (CDDL under `spec/grammar/`, with the
derived JSON Schema beside them) are bound to these tables by the
grammar-derivation gate: root member sets and required flags are
cross-read against the compiled registries, and the corpus goldens
validate under the derived schemas. The derived schemas close the
artifact root; sub-object closure and cross-member hooks remain the
reference implementation's to enforce.

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

Every `max_cost.amount`, including Blueprint `ceilings`, Deployment
`host_bounds`, and `model_policy`, is an integer count of millionths
(10^-6) of one unit of the currency named by `currency`. The currency is an
three-uppercase-letter string matching `[A-Z]{3}`; verifiers check that
pattern, and the currency's meaning is ISO 4217. The scale never depends on the
currency's minor-unit exponent. Thus `amount: 1000, currency: "USD"` means
0.001 USD, with no floating-point amount.

### Identifier and timestamp profiles

The following ABNF uses ASCII code points. Each identifier or qualified
name is at most 512 UTF-8 bytes. These productions apply only to members
whose grammar names that profile; arbitrary port names and nonempty build
identity strings are not silently restricted to it.

```abnf
lower = %x61-7A
digit = %x30-39
identifier = (lower / digit) *(lower / digit / "." / "_" / "-")
producer-qualified-name = identifier "/" identifier
namespace-part = (lower / digit) *(lower / digit / "." / "-")
namespace = namespace-part "/" namespace-part
```

`producer.identity` uses `identifier`; `blueprint_id` uses the qualified
name. Federation identifier fields use `identifier`. Namespace decoding
uses the last production, at most 512 bytes; registration additionally
applies the stricter MCP-compatible label rules in protocol §8. Corpus references:
`blueprint-decode-valid`, `federation-decode-valid`, and the namespace
cases on `extension.resolve`.

`created_at`, binding `attested_at`, and lifecycle timestamp members use a
calendar-valid RFC 3339 profile: exactly `YYYY-MM-DDTHH:MM:SSZ`, four-digit
year, uppercase `T` and `Z`, whole seconds, no offset, fraction, leap second,
or zone annotation. Verifiers check the timestamp format and never judge
its time.
Signature `created_at` is authenticated and never compared to a clock by
signature verification or reconcile. The signature algorithm cases and
`reconcile-partial-observations` exercise these distinctions.

### Decoder limits

| Name | Maximum |
|---|---|
| `bytes` | 5,000,000 |
| `depth` | 64 |
| `members` | 1,000 |
| `items` | 10,000 |
| `nodes` | 200,000 |
| `string` | 100,000 UTF-8 bytes |
| `key` | 1,000 UTF-8 bytes |
| `number_lexeme` | 64 bytes |

`members` and `items` apply per container; `nodes` applies to the entire
value. An override MUST be a positive integer no larger than the maximum.
A ceiling failure is `ceiling:<name>`. The `bounds.new`, `json.decode`, and
`canonicalization.encode` exact-bound and maximum-plus-one cases certify
these rules. Every string is valid Unicode; no normalization is performed.
Equality compares code points exactly. String ordering uses code-point
order (equivalently UTF-8 byte order for valid scalar values), while JCS
object-key sorting uses UTF-16 code units as required by RFC 8785.
The grammar-defined identifiers above are ASCII. Arbitrary JSON strings
and free string members can contain other Unicode scalar values.

## 3. Bytes

- **Encoding:** interchange bytes MUST be UTF-8 JSON within the decoder
  ceilings. Duplicate members MUST deny `duplicate_member` (I-JSON);
  trailing bytes MUST deny `trailing_bytes`.
- **Integer window:** a pure-digit lexeme above ±(2^53−1) decodes as a
  float iff that double's canonical ECMAScript serialization reproduces
  the lexeme byte-exactly; every other above-bound lexeme MUST deny
  `number_not_double_expressible`. Core fields are integer-typed by
  schema: a float-tagged window value in a core field MUST deny
  `invalid_type`.
- **base64url:** unpadded, exact alphabet; padded input MUST deny
  `base64url_padded`, non-alphabet input MUST deny `base64url_invalid`.
- **Canonicality:** interchange bytes MUST already be canonical —
  decode → re-encode → byte-compare; non-canonical bytes MUST deny
  `non_canonical_bytes` before any semantic read, and digests MUST be
  computed only over the exact received bytes.

The byte ceiling is checked first; containers check depth after an opening
delimiter has a following token, then check completed members or elements
in order (cardinality, key size, nodes, number or string size), reject
duplicates at object close, and reject trailing bytes before root node or
scalar checks; a missing or invalid value delimiter is a syntax error
before that value's sink checks.

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

On the conformance `canonicalization.encode` surface, input JSON is decoded
under the profile maxima before encoder bounds are applied.

## 5. Digest

```
digest_bytes = SHA-256( UTF8(domain_separator) || zero_octet || UTF8(JCS(digest_input)) )
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
| Signature (reserved; not part of the signing input, §6) | `agent-blueprint-protocol/signature` |
| Extension schema | `agent-blueprint-protocol/extension-schema` |
| Extension registry | `agent-blueprint-protocol/extension-registry` |
| Conformance report | `agent-blueprint-protocol/conformance-report` |
| Corpus index | `agent-blueprint-protocol/corpus-index` |

Separators carry no version token: `protocol_revision` is itself a
covered member. The wire form MUST be the self-identifying tagged string
`sha-256:<43-char unpadded base64url>`, never a bare hex blob; an
unknown algorithm tag MUST deny `digest_algorithm_unsupported`, a
malformed body MUST deny `digest_encoding_invalid`. The algorithm succession
rule is defined below (protocol §6).

## 6. Signature envelope

Signatures are detached and evidence-only. Artifact signature entries
MUST NOT embed keys; verification uses caller-supplied public keys.
An entry has exactly `protected` (the header object), `signed_attributes`
(the attributes object), and `signature` (unpadded base64url of 64 bytes).
The protected member is an object on this wire, not a compact-JWS string;
the compact form derives its protected segment from that object’s JCS bytes.
The `signature.verify` algorithm cases pin this shape.

- Format: RFC 7515 compact + RFC 7797 `b64=false` unencoded detached
  payload. The protected header has exactly `alg`, `kid`, `crit: ["b64"]`,
  and `b64: false`. Revision 1 verifiers MUST accept exactly `EdDSA` and
  `Ed25519` as `alg` values; producers SHOULD emit `Ed25519`, the fully
  specified identifier registered by [RFC 9864](https://www.rfc-editor.org/rfc/rfc9864.html).
  `EdDSA` remains valid throughout revision 1. Other strings, including
  case variants and `Ed448`, deny `signature_algorithm_unsupported`.
  The header as presented participates in the signing input: changing
  only its algorithm spelling invalidates the signature.
  An identifier alias for the same algorithm is not algorithm succession.
  A new signature or digest algorithm requires a new protocol revision
  and a verification-semantics increment.
- `signed_attributes = {algorithm, content_digest, created_at, key_id,
  purpose}` with `purpose` one of `blueprint` | `deployment` |
  `federation-envelope`. The signing input is the RFC 7797 §3 input
  `ASCII(BASE64URL(JCS(protected))) || "." || JCS(signed_attributes)`,
  where `protected` is the exact four-member header; no digest domain
  separator is part of it. A producer whose protected-header segment is
  not the JCS serialization of that header produces a signature that
  MUST deny `signature_not_verified`.
- `key_id` MUST be a nonempty string and `kid` MUST equal it. Periods are
  permitted: RFC 7797 §5.1 governs this detached payload; §5.2's period
  restriction applies to unencoded non-detached compact payloads. Other
  signature shape, canonicality, and artifact portability checks still apply.
- Because the digest covers `protocol_revision`, identity members,
  extensions, and `required_core_fields`, a signature cannot be lifted
  onto a different artifact, revision, or purpose; `key_id` prevents key
  substitution. A `key_id` matching no supplied key MUST halt verification
  with `signature_key_unsupported`, including during reconcile — the
  package performs no key discovery, fetch, or trust selection.
- The attestation kind registry is empty; a nonempty attestation array
  denies `attestation_malformed`.
- A supplied key whose `key_id` matches but which is not a usable
  Ed25519 public key — not exactly 32 bytes, a non-canonical encoding
  (y ≥ p, or x = 0 with the sign bit set), an encoding that decodes to
  no curve point, or a small-order point (any of the eight 8-torsion
  points, the identity and the order-2 point included) — MUST deny
  `signature_algorithm_unsupported` when no matched key is usable.
  `signature_key_unsupported` is reserved for a `key_id` that matches
  no supplied key.
- This protocol's strict verification profile: before any curve
  arithmetic, the signature's first half R MUST satisfy the same point
  rule as the public key (canonical encoding, decodes to a curve point,
  not small-order), and its second half S, read as a little-endian
  integer, MUST be less than the group order L = 2^252 +
  27742317777372353535851937790883648493. A signature failing either
  rule MUST deny `signature_not_verified`, whatever the cryptographic
  backend would conclude. RFC 8032 §5.1.7 specifies the S < L range
  check; canonical encoding and small-order rejection above are this
  protocol's profile. Verification MUST use the cofactorless equation
  [S]B = R + [k]A. Mixed-order points with nonzero prime-order components
  satisfy the point rule; the cofactored equation is insufficient. Under an honest key, R = the identity with
  S = k·a mod L satisfies that equation; only the key holder can build
  it, and this rule denies it.
- Order of the checks. (1) The envelope parses: exactly the three
  entry members; the exact four-member protected header, where an `alg`
  string other than `EdDSA` or `Ed25519` denies `signature_algorithm_unsupported`
  and any other header violation `signature_malformed`; the exact
  five signed attributes, where an `algorithm` string other than
  `Ed25519` denies `signature_algorithm_unsupported` and any other
  attribute violation `signature_malformed`; `kid` equal to `key_id`;
  and a signature body that decodes (unpadded base64url) to exactly
  64 bytes — all else `signature_malformed`. (2) The key facts: with no
  supplied key for the `key_id`, `signature_key_unsupported`; with
  matched keys none of which is usable, `signature_algorithm_unsupported`,
  whatever the well-formed 64-byte signature (an all-zero signature
  under a small-order key included). (3) The strict signature rule on R
  and S. (4) The equation. When several keys share the `key_id`, the
  unusable ones are set aside and the signature verifies if any usable
  one verifies it.

A second `signatures` entry naming the same `key_id` as an earlier entry
in the same Blueprint or Deployment denies `invalid_constraint` during
structure validation. A successful standalone signature verification
returns its verified signed attributes, including purpose and content digest.
`created_at` is signed and format-checked as a valid RFC 3339 Z-form
whole-second timestamp; standalone signature verification and reconcile
never judge its time.

## 7. Evolution and negotiation

`protocol_revision` is a digest-covered body member. This release is
revision 1. A consumer's support MUST declare an explicit revision SET
(never a range); a revision outside the set MUST deny
`protocol_revision_unsupported` — above-max and below-min alike, both
fail-closed.

`required_core_fields` is the producer's declaration of which covered
core members a consumer must honor. Three checks, all fail-closed:
every entry names a known core member (`required_core_field_unsupported`),
is digest-covered (`required_core_field_not_digest_covered` — an
evidence-only member laundered into a requirement is a tamper blind
spot), and is in the consumer's supported set.

### Extension criticality

For each `namespace → {criticality, payload}` in `extensions`, the
outcomes in this table are absolute requirements (MCP metadata registrations
also satisfy the lowercase, at-least-two-prefix-label rules (protocol §8)):

| Registry state | Declared critical | Declared optional |
|---|---|---|
| unregistered | deny `extension_unknown_critical` | retained verbatim, quarantined, never executed |
| reserved | deny `extension_unknown_critical` | retained verbatim; typed notice |
| active, criticality matches | supported | retained and executable |
| active, criticality mismatch | deny `extension_criticality_conflict` | deny `extension_criticality_conflict` |
| deprecated | supported + typed notice | supported + typed notice |
| retired | deny `extension_retired` | retained verbatim; typed notice |

An unknown optional extension MUST round-trip byte-exactly (`decode →
to_value → encode` is a fixed point, property-tested). Lifecycle
asymmetry: optional→critical promotion requires a revision increment;
demotion does not. A retired namespace MUST never be reused.

### Verification semantics and census (normative)

Two independent identities govern a verifier release. **Census** is the
record of what the release certifies: the conformance corpus digest and
the extension-registry digest. Census growth, meaning added corpus cases and
added or widened registry entries, MUST NOT alter verdicts for inputs
certified under a released census at the same verification-semantics version. **Verification semantics** is the
release's computational meaning for previously-certified inputs:
canonicalization, digest computation, decode verdicts, bounds
computation, negotiation outcomes, and signature verification behavior.
A security correction or registry addition that moves a verdict is a
verification-semantics change. A release that changes verification
semantics MUST name it by incrementing the release's semantics version (the reference
implementation carries it in its release manifest), and its release
history MUST record the increment and prior-census equivalence or
divergence; a release whose semantics version is
unchanged MUST produce, for every input certified under a prior census
of the same semantics version, the same verdict that prior release
produced. A registry change that alters negotiation outcomes for
previously-certified artifacts — for example a newly registered
critical namespace flipping `extension_unknown_critical` denials to
supported — is a verification-semantics change; registry census growth
that moves no previously-certified artifact's verdict is not. The two
axes are independent of `protocol_revision`, which governs what
artifacts may say; one event may move more than one axis.

Verification-semantics version 2 replaces version 1 for structured failures, non-vacuous evidence, verified signed
attributes, duplicate-signer rejection, the accepted algorithm alias,
federation namespace deprecation, and periods in detached signature key
identifiers. Protocol revision remains 1. The release
history records the increment; prior-census equivalence remains a per-case
projection claim, not a claim that the public APIs are unchanged.
The legacy federation namespace adds an `extension_deprecated` notice to
`negotiation-estate-contract-valid`; its valid verdict and previously
declared projection fields are unchanged.

Released identities are immutable: a published digest, corpus, registry,
manifest, or release-history row is never mutated in place; a correction
is a new release. The evidence boundary: semantics equivalence between
two releases is certified over the released censuses (per-case verdict
replay), never over the input space at large.

## 8. Extension registry

Namespace form: reverse-DNS-plus-path (`com.example.commerce/graph`),
lowercase, one `/`, length-ceilinged, and not parseable as an absolute
URI with a network authority (a namespace can never double as an
endpoint). Registry content is release-governed data. The reference implementation
compiles it into both libraries; that packaging choice is informative. The governance-canonical SOURCE is the specification
tree's registry document (`spec/registry/registry.json`), bound to both
compiled twins and the corpus index by the registry equality gate. Registered at this release:

| Namespace | Owner | Criticality | State |
|---|---|---|---|
| `com.example.commerce/graph` | ExampleCommerce | critical | active |
| `com.example.commerce/classification-labels` | ExampleCommerce | optional | active |
| `com.example.commerce/rubric-assertion` | ExampleCommerce | optional | active |
| `com.example.platform/estate` | ExamplePlatform | optional | deprecated |
| `com.example.platform/estate-contract` | ExamplePlatform | critical | active |
| `com.example/federation` | Agent Blueprint Protocol | critical | deprecated |
| `io.github.baselabs/federation` | Agent Blueprint Protocol | critical | active |

The active federation namespace is `io.github.baselabs/federation`, with
A2A declaration URI
`https://baselabs.github.io/agent_blueprint_protocol/extensions/federation`.
It pins the same schema as `com.example/federation`. Verifiers accept both
namespaces and both carriage keys; producers SHOULD use the active one.
The deprecated namespace remains supported with `extension_deprecated`
and is never retired in the 1.x line. A carrier containing both supported
keys denies `federation_mapping_conflict`.

Registration of a namespace carried as an MCP `_meta` key MUST satisfy
[MCP revision 2026-07-28's key grammar](https://modelcontextprotocol.io/specification/2026-07-28/basic#_meta):
this registry requires at least two prefix labels, each starting with a
lowercase letter, ending with a lowercase letter or digit, and containing
only lowercase letters, digits, or hyphens; the nonempty name starts and
ends with a lowercase letter or digit and permits lowercase letters,
digits, hyphens, underscores, and dots inside. These lowercase and
two-label restrictions are stricter than the MCP grammar. Prefixes whose second label is `mcp` or `modelcontextprotocol`
are reserved. The registry applies these rules at registration, without
narrowing revision 1 artifact decoding.

`com.example.platform/estate-contract` is the product-extension registration:
the first product-owned critical namespace with an authored schema pin. The
document ships as corpus data
(`priv/conformance/schemas/estate-contract.schema.json`); `lib/` carries only
the digest pin, test-bound to the shipped file. The deprecated
`com.example.platform/estate` placeholder retains its optional bodies with a
typed notice — existing artifacts stay verifiable.

Critical-extension bodies validate only against a host-supplied schema
whose digest matches the registry's `schema_digest`; a missing schema
denies `extension_schema_unavailable`, a mismatched digest denies
`extension_schema_digest_mismatch`. Entry changes are owner-made,
changelog-recorded, and ADR-recorded. The registry's own digest is
bound into the corpus index but not into artifact digests: an artifact
must remain verifiable against a registry that legitimately gained
entries after it was produced; hosts wanting pinning SHOULD use
`build_identities`.

## 9. Bounds algebra

Two bound families, never conflated with parse ceilings (those are
tighten-only decoder limits):

- **Operational** (8 members, all REQUIRED — absent is
  `missing_ceiling`, never infinity): `max_attempts`,
  `max_concurrency`, `max_cost`, `max_depth`, `max_descendants`,
  `max_elapsed_ms`, `max_fan_out`, `max_tokens`. Pointwise narrowest
  meet; every narrowing MUST emit clamp evidence.
- **Protected** (5 members: `classification_ceiling`,
  `disclosure_ceiling`, `effect_impact_ceiling`, `authority_trait`,
  `approval_trait`): ordinal lattices (plus set-monotone markers
  `{pci, phi}` on classification). Narrowing a protected bound MUST
  deny `protected_bound_clamp_denied` by default; a host MAY opt into
  an acknowledge posture, which MUST always record evidence.
  Obligation families (authority, approval, effect impact) meet at the
  STRICTEST value; markers are retained regulatory obligations whose
  effective set is the UNION of sources — dropping one is a widening.
  Despite its name, `effect_impact_ceiling` is an obligation: the strictest
  value wins. It does not cap what a Blueprint declares. A Blueprint
  declaring `secret` with deployment and host values `ordinary` produces
  effective `secret`, no clamp, even under the deny posture.

Laws (property-tested): meet is idempotent, commutative, associative;
effective bounds MUST NOT widen host policy (the effective value does not widen the host value universally); a clamp is emitted iff effective ≠ requested on an
operational field. `model_policy` and `data_bindings` are not
intersection inputs.

### Monetary units

Every `max_cost.amount` uses the millionths scale defined in protocol §2.
Verifiers compare amounts as integers and MUST deny mixed currencies with
`bound_unit_mismatch`; they perform no currency conversion.
Federation `resource_policy.cost` uses the same millionths scale in the
currency of the bound Deployment Manifest's `host_bounds.max_cost`.
This unit definition adds no new federation comparison or host operation.

### Lattice ordering and marker placement

The orders below run from first to last. Classification and disclosure
meet at the minimum; authority, approval, and impact obligations meet at
the maximum:

| Family | Order |
|---|---|
| classification | public, internal, confidential, restricted |
| disclosure | none, summary, detail, full |
| authority | none, local_policy, external_authority_required |
| approval | none, human_required, separated_human_required |
| impact | ordinary, money, authority, secret |

Only classification carries `pci` and `phi` markers in the algebra input
`{ordinal,markers}`; their effective set is the union, sorted in projections.
Artifact Blueprint and Deployment classification members remain strings.
Federation result classification is a closed object with `level` (one
classification ordinal) and `markers` (an array of distinct `pci` / `phi`
strings, possibly empty). Markers do not form new
ordinal levels. Corpus references: `bounds_algebra.intersect` widening and
marker cases, and `reconcile-protected-deny` / `reconcile-protected-acknowledge`.

### Predicates and bounded schemas

A predicate is a closed object with `op` and exactly its operands:

| Operators | Operands |
|---|---|
| `and`, `or` | `args`: nonempty predicate array |
| `not` | `args`: exactly one predicate |
| `eq`, `ne`, `lt`, `lte`, `gt`, `gte` | nonempty string-array `path`, JSON `value` |
| `in` | `path`, JSON-array `values` (may be empty) |
| `present`, `absent` | `path` |

The ceiling is 256 nodes, counted depth first on entry, including the root.
At entry the node-ceiling and object/duplicate checks precede operator
presence and type, known operator, unknown member, missing operand, operand
shape/cardinality, then path root. Unknown strings, including JavaScript
prototype-property names, deny `predicate_op_unknown`. Validation requires
the first path segment to name a declared port. Evaluation resolves later
segments as object members or canonical nonnegative decimal array indices
(`0` or a nonzero digit followed by digits). Missing paths make presence
false and absence true; value operators deny `predicate_path_unresolved`.
Equality and membership compare numbers mathematically and objects without
regard to member order. Ordering requires two numbers or two strings;
other pairs deny unresolved. `and` and `or` evaluate operands in order and
return the first error even if another operand fixes the boolean result.
Corpus references: every operator on `predicate`, `predicate-exact`,
`predicate-overflow`, and `predicate-constructor`.

The bounded JSON Schema 2020-12 dialect permits exactly `$ref`, `$defs`,
`type`, `enum`, `const`, `minimum`, `maximum`, `minLength`, `maxLength`,
`minItems`, `maxItems`, `required`, `properties`, `items`,
`additionalProperties`, and `oneOf`. Boolean schemas are permitted.
References are document-local JSON Pointers; unresolved references and
cycles deny. The complexity meter is bounded at 512 and counts visited
nodes, keywords, branches, and four times maximum path depth. String lengths
count code points. Keyword evaluation order is the order above with `$defs`
excluded from evaluation. Corpus references: the valid, unknown-keyword,
complexity, reference, type and cardinality cases on `schema.validate_instance`.

## 10. Compatibility and binding

A manifest's `blueprint_release` MUST bind to exactly one Blueprint
content digest (digest equality only — no fuzzy match).
`build_identities` carry exact identities; compatibility verification
MUST be identity-exact or deny: a range expression, missing entry, or
duplicate denies (`compatibility_identity_inexact`,
`compatibility_entry_missing`, `compatibility_duplicate_entry`).
Binding verification is a pinned deny-ordered check including
attestation freshness (`binding_attestation_stale`) and
descriptor-digest equality (`binding_descriptor_mismatch` — the tool
rug-pull case).

## 11. Federation profile

The logical TaskEnvelope has 23 possible members. Its transport carriers
combine native fields with an extension body under the registered
`io.github.baselabs/federation` profile or its deprecated
`com.example/federation` spelling. No new transport-native field is defined.
The mapping's 3 native, 5 partial, and 15 extension classifications describe
semantic correspondence; the following placement rules define carriage.

| Logical members | A2A Task carrier | MCP Task carrier |
|---|---|---|
| `task_identity`, `recovery_handle` | both reconstructed from `id` | both reconstructed from `taskId` |
| `checkpoint_status` or `terminal_state` | reconstructed from `status.state` through the A2A state codec | reconstructed from `status` through the MCP state codec |
| Every other present envelope member | `metadata["https://baselabs.github.io/agent_blueprint_protocol/extensions/federation"]` body | `_meta["io.github.baselabs/federation"]` body |

The deprecated A2A key is `https://example.com/extensions/federation`;
the deprecated MCP key is `com.example/federation`. A carrier MUST contain
exactly one supported federation key. Both supported keys together, or any
of the four native logical member names inside its extension body, MUST
deny `federation_mapping_conflict`. To encode a carrier, `recovery_handle`
MUST equal `task_identity`, and an observed checkpoint or terminal state
MUST be present. A missing observed state denies `invalid_constraint`;
a different recovery handle denies `federation_mapping_conflict`.

Before envelope verification, the decoder combines the body with the
native identifier twice (as `task_identity` and `recovery_handle`) and the
mapped state. Terminal states populate `terminal_state`; all other mapped
states populate `checkpoint_status`. It then validates the reconstructed
closed envelope, including bounds, portability, and cross-member hooks.
`parent_execution_reference`, `input_commitment`, `time_policy`, and
`checkpoint_request` remain in the body despite their partial native
correspondences. MCP `ttlMs` never supplies `time_policy`. Carrier cases on
`federation.decode` certify carriage-key selection and rejection of native
members in the extension body in both implementations.

State codecs MUST be
lossy-aware: A2A `SUBMITTED`/`REJECTED`/`AUTH_REQUIRED` deny crossing into MCP,
`UNSPECIFIED` is unmapped (`federation_state_unmappable`);
cancellation MUST remain a request, never a terminal receipt. A
Terminal Commitment digests task identity, terminal state, result
digest, result classification, compatibility ref, authority-proof
refs, and checkpoint-history commitment; ANY divergence between
receipts for one task identity MUST deny
`federation_terminal_conflict` — not just state divergence.
`Federation.verify_commitment` compares issuer/subject/audience
against the receiving context (`audience_mismatch`). AgentCard
signing carries a protobuf field-presence pre-normalization on top of
JCS (documented in the mapping so adapters do not inherit silent
verification failure). Correlation grants nothing.

### Terminal Commitment bytes

The commitment input is a JSON object with exactly `task_identity`,
`terminal_state`, `result_digest`, `result_classification_ceiling`,
`compatibility_reference`, `authority_proof_references`, and
`checkpoint_history_commitment`. The result and history digests come from
`evidence_receipt`; the other values come from the envelope. JCS orders the
object keys as `authority_proof_references`, `checkpoint_history_commitment`,
`compatibility_reference`, `result_classification_ceiling`, `result_digest`,
`task_identity`, `terminal_state`. Array-valued components retain their wire
order and are encoded as JSON arrays, never joined strings or sorted sets.
The hash preimage is UTF-8 `agent-blueprint-protocol/federation-envelope`,
one zero octet, then UTF-8 JCS of that object. Corpus reference:
the terminal-equivocation cases on `federation.verify_commitment`.

### Member grammar — Federation TaskEnvelope (23 members)

The reconstructed envelope is a closed world: one member per logical
field. The carrier placement above supplies its native members and
extension body before this grammar is applied. Cardinality `1` members are required;
`0..1` members are optional (absent — there is no null form). The
machine-readable grammar ships as the CDDL artifact under
`spec/grammar/` with the derived JSON Schema beside it. Cross-
member hooks: `checkpoint_status` MUST NOT coexist with `terminal_state`
(`invalid_constraint`), and the terminal hooks bind
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
| `result_classification_ceiling` | 1 | object{ level:classification enum; markers:array of distinct pci/phi strings } |
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

A denial has a closed `code` and a `subject` member path. The ceiling
family names one of the eight decoder limits as `ceiling:<key>`. Subjects
contain schema-defined member names and array indices where known, never
unknown names or input values; an unavailable path is an empty array.
Denials carry no input values or free-text detail. The reference API
represents this record as described in protocol §16. An
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
| `bound_unknown` | a bounds-algebra BoundSet names a member outside its closed 13-name vocabulary | bounds set | reject the artifact |
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
| `deployment_digest_mismatch` | binding compares deployment.blueprint_release.content_digest to the supplied Blueprint and they differ; it does not name the Deployment's own content-digest check | blueprint_release.content_digest | reject the manifest (tamper) |
| `digest_algorithm_unsupported` | an unknown digest algorithm tag | digest member | reject the artifact |
| `digest_encoding_invalid` | a malformed digest body | digest member | reject the artifact |
| `digest_mismatch` | a declared Blueprint or Deployment content digest differs from its covered bytes, signed attributes name a different artifact digest, or a federation receipt digest/commitment differs from its recomputation | known digest member | reject the artifact (tamper) |
| `duplicate_member` | a duplicate JSON member name (I-JSON) | bytes | reject the artifact |
| `extension_criticality_conflict` | declared criticality conflicts with the registry | extensions | reject the artifact |
| `extension_duplicate` | one namespace appears twice in extensions | extensions | reject the artifact |
| `extension_namespace_invalid` | a namespace fails the reverse-DNS-plus-path form | extensions | reject the artifact |
| `extension_payload_forbidden` | a payload appears where the registry forbids one | extensions | reject the artifact |
| `extension_retired` | a retired namespace is declared | extensions | reject the artifact |
| `extension_schema_digest_mismatch` | the digest of a host-supplied critical-extension schema differs from the registered schema pin; this is not an artifact-body digest comparison | extensions | reject the artifact |
| `extension_schema_unavailable` | no host schema is supplied for a digest-pinned critical body | extensions | reject the artifact |
| `extension_unknown_critical` | an unregistered or reserved namespace is declared critical | extensions | reject the artifact |
| `federation_mapping_conflict` | a state has no consistent mapping on the target transport | federation codec | reject the crossing |
| `federation_state_unmappable` | a state is unmappable (e.g. A2A UNSPECIFIED) | federation codec | reject the crossing |
| `federation_terminal_conflict` | two receipts for one task identity diverge in any commitment component | federation envelope | reject the later receipt |
| `forbidden_portable_value` | a value shape trips the portability denylist | offending member | reject the artifact |
| `integer_magnitude` | canonical encoding receives a tagged integer outside ±(2^53−1), including a hand-built value; this is not the JSON lexeme rule | integer value | reject the artifact |
| `invalid_cardinality` | an array violates min/max items | offending member | reject the artifact |
| `invalid_constraint` | a member fails a value constraint, signer key_ids repeat, or a federation receipt's signed created_at falls outside its explicit inclusive receiving-context pins | offending member | reject the artifact |
| `invalid_encoding` | a member fails its encoding form | offending member | reject the artifact |
| `invalid_number` | a number lexeme is malformed | bytes | reject the artifact |
| `invalid_syntax` | the JSON text is syntactically invalid | bytes | reject the artifact |
| `invalid_type` | a JSON tag disagrees with a field or instance schema (a float-tagged integral value still fails an integer field), a hand-built tagged value is malformed, or a host API argument has the wrong shape | known member or API argument | reject the artifact |
| `lifecycle_state_invalid` | a deployment lifecycle state is unknown | lifecycle | reject the manifest |
| `missing_ceiling` | an operational bound is absent (never infinity) | ceilings | reject the artifact |
| `missing_required_field` | a required member is absent | the member | reject the artifact |
| `no_authoritative_recovery` | a mutation-kind operation is bound while the effect owner's recovery is none | effect_owner | reject the import |
| `non_canonical_bytes` | interchange bytes are not already canonical | bytes | reject before any semantic read |
| `nonportable_content` | an authority-shaped claim rides portable content | offending member | reject the artifact |
| `number_not_double_expressible` | JSON decoding receives a pure-digit integer lexeme outside ±(2^53−1) whose conversion to a double and canonical serialization does not reproduce that lexeme exactly | number input | reject the artifact |
| `predicate_nodes_exceeded` | a predicate AST exceeds the node ceiling | predicate | reject the artifact |
| `predicate_op_unknown` | a predicate names an unknown operator | predicate | reject the artifact |
| `predicate_path_unresolved` | a predicate path resolves against no declared port | predicate | reject the artifact |
| `protected_bound_clamp_denied` | a protected bound narrows without the acknowledge opt-in | bounds | reject, or opt in and record evidence |
| `protocol_revision_unsupported` | the revision is outside the declared set (both directions) | protocol_revision | reject the artifact |
| `required_core_field_not_digest_covered` | a required core field names an evidence-only member | required_core_fields | reject the artifact |
| `required_core_field_unsupported` | a required core field is unknown or absent from the consumer's supported field set | required_core_fields | reject the artifact |
| `schema_complexity_exceeded` | a schema exceeds the complexity meter | schema document | reject the artifact |
| `schema_dialect_unknown` | a schema names an unknown dialect | schema document | reject the artifact |
| `schema_invalid_shape` | a schema is structurally malformed | schema document | reject the artifact |
| `schema_keyword_not_allowed` | a schema uses a keyword outside the bounded dialect | schema document | reject the artifact |
| `schema_keyword_value_invalid` | a schema keyword carries an invalid value | schema document | reject the artifact |
| `schema_ref_cycle` | a schema $ref cycle | schema document | reject the artifact |
| `schema_ref_unresolvable` | a schema $ref resolves nowhere | schema document | reject the artifact |
| `signature_algorithm_unsupported` | header alg is neither EdDSA nor Ed25519, signed_attributes.algorithm is not Ed25519, or no matching key is usable Ed25519 (wrong algorithm/length, non-canonical, off-curve, or small-order) | signatures | halt the import (reconcile denies) |
| `signature_key_unsupported` | no supplied key matches the `key_id` | signatures | halt the import (reconcile denies) |
| `signature_malformed` | a signature envelope fails its parse | signatures | halt the import (reconcile denies) |
| `signature_not_verified` | the cryptographic verification fails, or R or S breaks the strict encoding rule (§6) | signatures | halt the import (reconcile denies) |
| `trailing_bytes` | bytes follow the JSON value | bytes | reject the artifact |
| `unknown_bound` | a decoder-limit override names no field of Bounds (distinct from the algebra bound set) | decoder limits | reject the artifact |
| `unknown_member` | a member is outside the closed world | the member | reject the artifact |
Plus the parameterized ceiling family `ceiling:<key>` over the eight
decoder limit names. No authorization vocabulary exists in any
identifier — no `unauthorized` in either polarity (source-scanned
gate).

Non-error notices (not members of the error-code union):

| Notice | Meaning |
|---|---|
| `extension_deprecated` | a supported namespace is deprecated |
| `extension_retired` | an optional namespace is retired and its content is retained |
| `extension_unknown_optional_retained` | optional content is retained without interpreting it |
| `clamp_applied` | bounds narrowed with structured clamp evidence |

Conformance runners preserve present input types rather than coercing wrong
types to defaults: malformed binding objects and malformed nested support
collections deny `invalid_type` before the operation, JSON null remains a
schema instance, bound sources are constructed in blueprint/deployment/host
order before totality is checked, and omitted or null bounds, support, receiving context,
or receiving identity pins retain their existing absent-input meaning.

## 13. Evidence and reconcile

`reconcile(blueprint, deployment, inputs)` is the one call per import:
canonical → digest → negotiation → structure → portability →
signatures → bind → bounds, in that pinned order. Its result is an
evidence record of per-surface checks, effective bounds, clamp evidence,
and `not_verified` — which MUST be non-empty BY CONSTRUCTION, always
naming at least the seven host-owned surfaces this protocol structurally
cannot establish: `tenancy`, `live_policy`, `authority`,
`effect_ownership`, `execution`, `billing`, `evaluation_truth`. A
caller SHOULD NOT read an Evidence record and conclude "everything is
fine": the record itself names what it did not check.

A check MAY state `verified: true` only after at least one verification
ran and passed. Zero signatures yields `verified: false` with typed detail
`no_signatures_present`; reconcile still succeeds. A signature check that
passes carries a typed signatures detail naming distinct verifying key_ids.
No free-text detail strings are emitted. Retained or quarantined optional
extension payloads are not reported as verified payloads.

The binding detail lists checks performed and observations skipped. A bind
check is false unless every binding has a matching descriptor observation
and both `now` and a maximum attestation age are supplied; a future-date
check alone does not establish staleness verification. Those skipped surfaces and every false
check surface join `not_verified`. Canonical checks on structs establish
encodability; they do not establish equality to unavailable received bytes.
`signature_created_at` and `lifecycle_state` are always unverified by
reconcile. The timestamp is signed and format-checked but never judged;
lifecycle state is shape-checked and never judged.

Federation receipt verification separately supports the existing explicit
`created_after` and `created_before` receiving-context pins. Both are
optional, valid RFC 3339 Z-form whole seconds, inclusive, and compare the
signed `created_at`. The check runs after receipt-conflict detection;
malformed pins deny `invalid_type`, and a receipt outside a supplied pin
denies `invalid_constraint`.

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
604 cases covering every required cell of the 18-surface × 31-class
applicability floor, full-registry golden artifacts, RFC 8785 number
vectors, and deterministic Ed25519 fixtures, at corpus digest
`sha-256:oYnkSmTkHGk4AmZ8Sul99_6KYJUIuj2SN2GZAiT1glw`. Corpus identity
is the digest of the domain-separated index — versioned by digest, not
by name. The loader is pure over an in-memory path-to-bytes map and verifies
per-file hashes, exact file set (both directions), counts, id-uniqueness,
and applicability totality; the report refuses a vacuous green. Each shipped
CLI states on stderr whether the loaded corpus digest equals the
release-certified corpus digest in the release metadata. Other corpora,
including prior-release corpora, may run; their agreement does not establish
a pass on the release-certified corpus. This label is separate from the
canonical stdout report.

A repo-side second-language verifier (`verifier/`,
TypeScript on Node ≥ 24, `node:` builtins only, never in the Hex
archive) independently recomputes every corpus verdict and integrity
check with its own scanner, canonicalizer, and `node:crypto` Ed25519
path; the release gate requires its report to be byte-identical to the
Elixir escript's over both the repo corpus and the built archive's
corpus. Mutation gates break the implementation at pinned
points, including each reconcile stage and its order, and require the corpus to go red on each — a vacuous case set
is a build failure. A `signature.verify` case whose signature decodes
to 64 bytes also pins `expected.strict_signature`, the strict
signature rule's verdict on those bytes (§6), and an implementation
agrees with the case only when its own rule gives the same verdict, so
the corpus sees each clause of the rule even where a cryptographic
backend already rejects the same bytes.

### Conforming implementations (normative)

The verifier class covers every applicable cell of the corpus. An
implementation conforms at a release only when its complete results
document for the release-certified corpus is byte-identical to the
[certified results document](conformance/certified-results.json) shipped
with that release. The [runner contract](conformance/runner.md) specifies
the case format, dispatch, projections, integrity checks, and summary.
The [execution protocol](conformance/execution.md) lets an external harness
drive and judge an implementation without supplying expected answers.
Skipping cases or applicable surfaces is not conformance. The aggregate
report is a summary and is insufficient to establish per-case agreement.

An unsigned claim separately identifies implementation, source, platform,
and the exact corpus, registry, and results-document digests. A corpus
pass does not prove honest computation, anything outside that census,
or any host behavior. No producer conformance class is defined: producer
round trips and wire validity are covered by verifier cases, not a
separate claim of producer behavior.

## 16. The shipped surface (informative — the reference implementation)

The facade (`AgentBlueprintProtocol`) delegates and never implements;
every public function carries a `@spec` (build-gated), every public module a
boundary-stating moduledoc; implementation modules and helpers are hidden:

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
`Deployment`, `Schema` as the bounded 2020-12 dialect + instance validator,
`Predicate`, `Portability`), the algebra (`BoundsAlgebra`,
`Negotiation`, `Compatibility`, `Signature`, `Federation`, `Error`,
`Evidence`, `Reconcile`, `ExtensionRegistry`), and the conformance
tooling (`Conformance.Corpus/Runner/Report`; CLI implementation modules are internal).
The module tree is strictly downward (bytes → algebra → artifacts →
conformance); the engine knows tables, never domains.

### Producer surface

Hosts that render artifacts produce them through the per-artifact
constructors, never through facade-level minting: compose the member
value, construct it with `Blueprint.from_value/2` or
`Deployment.from_value/2` (threading `:authored_extensions` for
critical namespaces whose bodies negotiation validated against a
digest-pinned schema; the caller supplies that provenance, and the constructor
checks membership in this artifact's critical region), compute the release identity with the
artifact's `content_digest/1`, and serialize with its
`canonical_bytes/1`. The round-trip property (decode → `to_value/1` →
encode is a fixed point) is the byte-exactness guarantee a producer
relies on. The conformance CLI emits a separate corpus-certification label on stderr
without changing the canonical stdout report (§15). The facade stays a verification facade: it delegates and
never implements, and no facade-level producer functions grow (the
accepted producer-surface decision record).

### The blueprint card (informative — a derived projection)

A "blueprint card" is a DERIVED, non-normative projection of a
Blueprint for discovery and display contexts: a small member set
(typically the identity, producer, classification ceiling, a capability
summary, and the content digest) extracted from VERIFIED artifact
bytes. Three rules govern it. The full artifact remains the only
source of truth — a card asserts nothing the artifact does not, and
carries the content digest precisely so any reader can bind the
summary back to the exact verified bytes. A card is never a conforming
implementation surface: partial conformance is not conformance (the
conformance clause), and nothing in this protocol verifies a card as a
standalone artifact. Consumers either re-derive a card from bytes they
verified themselves or treat one they received as unverified display
data — the same posture as any other pre-verification summary.

### The release-identity manifest (informative — the reference implementation)

The reference implementation ships
`priv/release-metadata.json` (mirrored byte-identically inside its npm
kit) as the machine-readable release identity. It is a versioned public
contract of the REFERENCE IMPLEMENTATION — not a conformance
requirement: a third-party conformer publishes its own identity
statement satisfying the conformance clause (§15). Within a
`manifest_version`, evolution is additive-only — fields are added,
never removed, retyped, or resemanticized; a breaking shape change bumps
`manifest_version` and is itself a release. The fields at manifest
version 2: the format tag, the manifest version, the package name and
version, the `verification_semantics_version` (§7's axis), the
`digest_identity` label naming the closed digest scheme (RFC 8785 JCS
canonical bytes; SHA-256; domain-separated preimages; tagged unpadded
base64url — unchanged across every release to date), the wire
`protocol_revisions_supported`, `prior_census_verdicts` (the certified
compatibility matrix: per prior census digest,
`equivalent` — per-case verdict agreement, certified by replay; or
`diverged_by_registry_census` — divergences explained by registry
growth; or `not_equivalent` — an authored semantics-break claim), the
specification, corpus, and registry digests, the corpus index hash, the
verifier runtime floor, the verifier-kit identity (name, registry,
version), and the archive-authorization stance. The companion
`priv/release-history.json` carries one append-only row per manifest-era
release — the retroactive mapping a consumer binds when upgrading
between pins.

## 17. Security considerations (normative)

The threat model is not invented for this section: every threat below is
exercised by the conformance corpus as a named red class, and the gate
in the reference implementation reds a threat row that cites a class the
corpus does not carry.

| Threat | Vector | Corpus class | Mitigation |
|---|---|---|---|
| Artifact tamper | bytes edited after signing | `tamper_meaningful_byte` `digest_mismatch` | content digests over exact received bytes; `digest_mismatch` denies (checked after structure and portability in standalone decode; checked before negotiation and structure in reconcile, always before signatures and binding) |
| Canonicality laundering | non-canonical spellings of the same value | `invalid_duplicate` | MUST-already-be-canonical interchange bytes; `non_canonical_bytes` |
| Signature substitution | a signature lifted onto another artifact/purpose | `signature_invalid` | purpose-pinned signed attributes; digest covers revision + identity members |
| Protocol downgrade | an older/newer revision forced on a consumer | `revision_above_max` `revision_below_min` | explicit revision SETs, both directions deny `protocol_revision_unsupported` |
| Extension rug-pull via registry | unknown/retired namespace forced critical | `extension_unknown_critical` | registry-state table; deny with typed codes |
| Schema-pin evasion | critical body validated against a different schema | `extension_schema_unavailable` | digest-pinned schemas; `extension_schema_digest_mismatch` |
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
contract: identifier-shaped values with the UUID grammar are exempt
by shape, so the guard is structural, not semantic — a tenant
identifier encoded as a UUID is not caught by the value-shape arm; quarantined extension bodies are typed as unscanned
(`extension_unknown_optional_roundtrip` carries the round-trip
obligation), and portability claims attach only to schema-validated
content — a producer MUST NOT present a portability pass as a privacy
guarantee. Federation identity members (`issuer`, `subject`,
`audience`, `identity_mapping_evidence`) are correlation material only:
an authority-shaped claim in the evidence block denies
`nonportable_content`, and possession of a key is never an identity
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
digest without either protocol subsuming the other. AI Catalog and ABP both
use detached JWS over JCS. Catalog requires the protected `typ` marker and
forbids the protected `b64` header, so their signatures are not interchangeable.

SCITT is IETF work on transparent supply-chain statements; ABP detects
receipt divergence only against locally held prior receipts and is not a
transparency service. OASF is an open schema framework for
agent metadata; ABP's artifact and evidence contracts have a different scope.
WIMSE is IETF work on workload identity across systems; ABP accepts supplied
keys and never establishes a workload identity. AuthZEN is OpenID Foundation
work on authorization interoperability; ABP produces non-authorizing evidence.
AP2 is an open agent payments protocol; ABP's money bound is a magnitude
constraint and carries no payment authority. These are positioning statements,
not mappings or conformance claims about those projects.

## 20. Registry considerations

Revision 1 fixes the `sha-256` digest tag, `EdDSA` and `Ed25519`
identifiers for one signature algorithm, the three signed purposes, digest
domains, and artifact member sets. Registry operations follow
[the operations process](registry/OPERATIONS.md).

### Evolution within a major version

A minor release MAY add the following opt-in capabilities. It MUST NOT
change existing bytes, defaults, required inputs, or documented return
contracts of existing calls:

- Protocol revisions, each with its own member and algorithm sets. A verifier
  MUST keep accepting every earlier supported revision throughout the major.
  A new signature algorithm MUST enter through a new protocol revision.
- Registered namespaces and federation profiles. An incompatible federation
  envelope MUST use a new registered critical namespace beside the existing
  profiles; existing profiles MUST NOT retire during the major. A successor
  profile MUST bind its own profile identity into its commitment preimage
  so it cannot be presented as an earlier profile. The current envelope and
  commitment preimage remain unchanged.
- Conformance surfaces and corpus cases. Each new corpus is a new census;
  claims against an earlier corpus digest remain valid for that digest.
- CLI modes and flags, explicitly selected execution-protocol versions, notices,
  evidence check kinds and detail variants, and additional runtime support.
  Harnesses and adapters MUST continue to support execution version 1 for
  the whole major; a successor MUST be selected explicitly.

Within the major, the error-code set and each code's meaning MUST remain
unchanged. `ErrorCode` is closed for all of 1.x. A new mechanism MUST reuse
an existing code whose meaning fits; otherwise it waits for the next major.
Inputs certified under a released census MUST keep their verdicts at the
same verification-semantics version. A security correction or registry
addition that moves a verdict MUST increment that version and declare it
in the release history, recording prior-census equivalence or divergence
as specified in section 7. Artifact member sets and signed-byte formats
for existing revisions, and the format of every released results document,
claim, and corpus, MUST remain unchanged. New inputs under a new revision
do not reinterpret earlier revisions.

The reference distributions retain Node 24, Elixir 1.19, OTP majors 27,
28, and 29, and TypeScript 5.0.2 as their runtime and compiler floors
throughout 1.x. Added Node, OTP, and Elixir versions expand support; they
never raise those floors. The contributor OTP gate is separate from the
shipped library requirements.

Consumer compatibility follows the declared open and closed surfaces:
error codes support exhaustive handling; notices, evidence surfaces, check
kinds, detail variants, and returned signature algorithm and purpose names
are open. Consumers look up known names and retain a default branch; an
unknown entry establishes no familiar fact. Elixir struct matches select
only fields used. Release-manifest readers ignore unknown additive members
but never an unknown equivalence claim. Any unknown nonzero harness exit
is failure. These rules add no host authorization or execution requirement.

## 21. References

### Normative references

- [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119.html), Key words for use in RFCs to Indicate Requirement Levels (March 1997).
- [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174.html), Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words (May 2017).
- [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259.html), The JavaScript Object Notation Data Interchange Format (December 2017).
- [RFC 7493](https://www.rfc-editor.org/rfc/rfc7493.html), The I-JSON Message Format (March 2015).
- [RFC 8785](https://www.rfc-editor.org/rfc/rfc8785.html), JSON Canonicalization Scheme (June 2020).
- [RFC 7515](https://www.rfc-editor.org/rfc/rfc7515.html), JSON Web Signature (May 2015).
- [RFC 7797](https://www.rfc-editor.org/rfc/rfc7797.html), JSON Web Signature Unencoded Payload Option (February 2016).
- [RFC 8032](https://www.rfc-editor.org/rfc/rfc8032.html), Edwards-Curve Digital Signature Algorithm (January 2017).
- [RFC 8037](https://www.rfc-editor.org/rfc/rfc8037.html), CFRG Elliptic Curve Diffie-Hellman and Signatures in JOSE (January 2017).
- [RFC 9864](https://www.rfc-editor.org/rfc/rfc9864.html), Fully-Specified Algorithms for JOSE and COSE (October 2025).
- [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339.html), Date and Time on the Internet: Timestamps (July 2002).
- [RFC 8610](https://www.rfc-editor.org/rfc/rfc8610.html), Concise Data Definition Language (June 2019).
- [RFC 9682](https://www.rfc-editor.org/rfc/rfc9682.html), Updates to the Concise Data Definition Language (November 2024).
- [JSON Schema Core, draft 2020-12](https://json-schema.org/draft/2020-12/json-schema-core) and [Validation, draft 2020-12](https://json-schema.org/draft/2020-12/json-schema-validation); only the subset (protocol §9) applies.
- [ECMA-262, sixth edition, June 2015](https://262.ecma-international.org/6.0/#sec-tostring-applied-to-the-number-type), number serialization (ECMA-262 §7.1.12.1) and its Note 2.
- [A2A v1.0.1](https://github.com/a2aproject/A2A/releases/tag/v1.0.1), released May 2026, the federation mapping's released transport baseline.
- [MCP revision 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28) and [Tasks extension v0.2.3, dated specification](https://github.com/modelcontextprotocol/ext-tasks/blob/v0.2.3/specification/2026-07-28/tasks.md). The Tasks lane remains draft-tracking while the extension is Beta.

### Informative references

- [A2A v1.1.0-rc](https://github.com/a2aproject/A2A/tree/v1.1.0-rc), an informative candidate reference; candidates are not the released baseline.
- [SCITT](https://datatracker.ietf.org/wg/scitt/about/), [in-toto](https://in-toto.io/), and [SLSA v1.2](https://slsa.dev/spec/v1.2/).
- [OASF](https://github.com/agntcy/oasf), [WIMSE](https://datatracker.ietf.org/wg/wimse/about/), [AuthZEN](https://openid.net/wg/authzen/), and [AP2](https://ap2-protocol.org/).
