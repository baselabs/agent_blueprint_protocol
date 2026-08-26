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
  its exact canonical bytes; the artifact's identity is the content
  digest of those bytes.
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
example in this specification is a corpus case):

```json corpus:blueprint-decode-valid
{"blueprint_id":"example.demo/echo","capability_requirements":[{"approval_trait":"none","argument_schema":{"type":"object"},"authority_trait":"none","classification_ceiling":"internal","impact_class":"ordinary","operation_family":"example.demo.read_shape","operation_kind":"read","result_schema":{"type":"object"}}],"ceilings":{"max_attempts":3,"max_concurrency":2,"max_cost":{"amount":1000,"currency":"USD"},"max_depth":8,"max_descendants":64,"max_elapsed_ms":60000,"max_fan_out":4,"max_tokens":100000},"classification_ceiling":"internal","content_digest":"sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8","effect_intents":[{"impact_class":"ordinary","logical_operation":"record_summary","operation_kind":"mutation"}],"evaluation_assertions":[{"kind":"output_schema","port":"result","schema":{"type":"object"}}],"extensions":{"critical":{},"optional":{}},"input_ports":[{"classification_ceiling":"internal","name":"request","required":true,"schema":{"type":"object"}}],"output_contract":{"classification_ceiling":"internal","port":"result"},"output_ports":[{"classification_ceiling":"internal","name":"result","required":true,"schema":{"type":"object"}}],"producer":{"created_at":"2026-08-20T00:00:00Z","identity":"example.demo","toolchain":"example.demo.toolchain"},"protocol_revision":1,"release_number":1,"required_core_fields":[],"triggers":["manual"]}
```

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

## 12. Error vocabulary

A closed typed set — `%Error{code, subject, detail}`. An
implementation MUST NOT emit an undeclared code, and every declared
code must be reachable (enforced two-directionally by a build gate).
The 74 codes of this release:

`base64url_invalid · base64url_padded · invalid_syntax ·
invalid_encoding · invalid_number · number_not_double_expressible ·
duplicate_member · trailing_bytes · unknown_bound ·
non_canonical_bytes · integer_magnitude · unknown_member ·
missing_required_field · invalid_type · invalid_constraint ·
invalid_cardinality · digest_algorithm_unsupported ·
digest_encoding_invalid · digest_mismatch · signature_algorithm_unsupported
· signature_key_unsupported · signature_malformed ·
signature_not_verified · attestation_malformed · schema_dialect_unknown
· schema_keyword_not_allowed · schema_keyword_value_invalid ·
schema_complexity_exceeded · schema_ref_unresolvable · schema_ref_cycle
· schema_invalid_shape · predicate_op_unknown ·
predicate_path_unresolved · predicate_nodes_exceeded ·
extension_duplicate · extension_namespace_invalid ·
protocol_revision_unsupported · required_core_field_unsupported ·
required_core_field_not_digest_covered · extension_unknown_critical ·
extension_criticality_conflict · extension_retired ·
extension_schema_unavailable · extension_schema_digest_mismatch ·
extension_payload_forbidden · bound_unknown · missing_ceiling ·
bound_source_missing · bound_unit_mismatch · bound_value_invalid ·
protected_bound_clamp_denied · deployment_digest_mismatch ·
binding_incomplete · no_authoritative_recovery ·
binding_attestation_stale · binding_descriptor_mismatch ·
lifecycle_state_invalid · compatibility_identity_inexact ·
compatibility_entry_missing · compatibility_duplicate_entry ·
forbidden_portable_value · federation_state_unmappable ·
federation_mapping_conflict · nonportable_content · audience_mismatch
· federation_terminal_conflict · corpus_index_invalid ·
corpus_hash_mismatch · corpus_file_set_mismatch ·
corpus_case_id_duplicate · corpus_count_mismatch ·
corpus_applicability_incomplete · corpus_empty · corpus_case_invalid`

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
caller cannot read an Evidence record and conclude "everything is
fine": the record itself names what it did not check.

## 14. Portability

Portable artifacts MUST NOT contain secrets, private keys, live grants,
tenant identifiers, raw endpoints, database primary keys, or backend
engine identifiers — enforced structurally (member-name and value-shape
denylists over the open regions, at any depth, name-spelling-normalized)
and red-cased per class in the corpus. A portability pass SHOULD NOT be
read as sufficiency — the guard is necessary, not sufficient: opaque
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
