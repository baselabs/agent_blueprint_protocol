# Changelog

All notable public changes to `agent_blueprint_protocol` are documented here.

## 0.1.0 — 2026-08-23

Initial public release: the Agent Blueprint Protocol, its Elixir
reference implementation, the conformance corpus, and the
second-language verifier.

### Normative docs + release-candidate gates

- `docs/protocol.md`: the normative protocol document (ships in the Hex
  archive) — artifacts and the closed member registries, bounded bytes
  and the integer window, RFC 8785 canonicalization, domain-separated
  digests, the detached-JWS envelope, evolution and extension rules, the
  compiled registry's first-release entries, the bounds algebra laws,
  the 74-code error vocabulary, the evidence contract, and the
  conformance corpus identity (88 cases at the recorded digest).
- `docs/design/requirement-map.md` (repository-side, not in the Hex
  archive): every build gate's recorded red
  proof — each quality-alias step, every architecture-lane test case,
  and the conformance lanes — re-derived live (plant → run → restore)
  with verbatim failing output.
- `docs/adr/` (repository-side, slug-only filenames): the seven
  decisions of record —
  the non-authorizing boundary, the detached JWS envelope, the
  two-consumer amendment, deny-default protected-bound clamps, the
  compiled-in registry (closing the package-boundary contradiction of
  record), the federation lanes, and the no-versioning rule.
- New architecture gates, both red-proven at birth:
  - **publish guard** — no internal-planning reference, private-tool
    path, or home-directory path in any archived file (byte patterns
    plus word-bounded text patterns that cannot false-positive inside
    base64url tokens; registry owner/namespace/URI data is published by
    design and exempted on record);
  - **spec coverage** — every public function carries a matching
    `@spec` (default-arity rule recorded) and every shipped module's
    moduledoc states the non-authorizing boundary (39 modules gained
    an honest stance sentence; `ExtensionRegistry.federation_schema/0`
    gained its missing `@spec`).
- `mix release.candidate` (also in `mix quality`): re-derives the
  requirement map's completeness from live project state (every
  architecture test case, every live quality-alias step), structure-
  checks each entry's red fence, and couples `docs/protocol.md` to the
  shipped implementation (facade functions, registry namespaces, corpus
  digest and case total, the stance sentence).
- Internal-reference scrub of the shipped surface: tracker numerals,
  internal design-shorthand citations, and a portfolio-terminology
  section removed from `docs/federation-mapping.md`, README, CHANGELOG,
  and `lib/` comments/`@doc`s (comments and docs only — zero behavior
  change).
- README Status and Installation rewritten to the published 0.1.0
  state.

### Second-language verifier + agreement gate

- `conformance/verifier/`: the repo-side TypeScript verifier (Node ≥ 24,
  `node:` builtins only, zero npm runtime deps; never in the Hex archive) —
  an independent recomputation of every corpus surface and integrity check,
  with a CLI byte-compatible with the Elixir escript (`--corpus` required;
  exit 0/1/2; report bytes on stdout, no trailing newline).
- `mix verifier.agreement` (in `mix quality`): byte-agrees the TS report
  with the escript's over the repo corpus AND the built Hex archive's,
  runs the self-check battery (RFC 8785 Appendix B three-way, the integer-window
  matrix incl. the mis-round lexeme, Ed25519 key acceptance, stored
  JOSE vectors), and proves three seeded reds fire (verdict inversion,
  report member drift, window-check deletion) — with a calibration
  self-proof of the raise path.
- `conformance/verifier/testdata/jose-vectors.json` +
  `scripts/generate_jws_vectors.exs`: the stored detached-JWS vectors, KAT-
  anchored to RFC 8032 §7.1 TEST 1, verified Elixir-signed → node-verified
  in both detached and compact forms.
- `Signature`: small-order key rejection hardened — the identity (order 1)
  and order-2 encodings no longer pass `usable_ed25519_key?` (found by the
  mirror's torsion battery; latent on this OTP).
- `Federation.decode`: an empty claim value or compatibility identity now
  denies `:invalid_constraint` instead of raising `FunctionClauseError`
  (never-raising posture restored; found by the mirror's parity battery).
- `Conformance.Runner`: a malformed observed identity element denies typed
  `:invalid_type` instead of raising (the prior-receipts pattern).
- Corpus regenerated to 88 cases (digest
  `sha-256:QsRbWGreygTJ0m47csgfpwYtoNId3FbjNP49sK-X-MY`): two
  obligation-varying intersect cases pin the protected-bound meet direction
  inside corpus agreement (previously corpus-invisible; carried by the
  verifier's vectors); the mutation gate gains an `obligation-meet-min`
  entry (7 total). The real-escript end-to-end test covers the halt shim's
  exit contract in-suite (the coverage-exclusion ack's substance).

### Conformance corpus subsystem

- `Conformance.{Corpus,Runner,Report,Cli}`: the portable conformance corpus —
  pure loader with the 16×29 applicability floor compiled in, two-directional
  integrity with typed errors (corpus-registry and corpus-digest bindings,
  tamper verbatim-vs-derived audits, vacuous-green refusal), a code-level
  shape-agnostic runner over all 16 surfaces, a JCS report bound to the corpus
  identity, and an escript CLI (`--corpus` required; exit 0/1/2).
- `priv/conformance/`: 86 shipped cases, full-registry goldens (evidence
  members included), RFC 8785 vectors, deterministic key fixtures.
- `mix conformance.verify` + `mix conformance.mutations` wired into
  `mix quality` — five named implementation mutations each proven to redden
  the corpus, plus a corpus-expectation-flip calibration entry.
- `ExtensionRegistry.digest/0` (+ the `:extension_registry` digest domain):
  the corpus-registry binding.
- Facade: `canonical_bytes/1` (the named canonicalize gap) and typed
  `negotiate`/`intersect` rims. Decode surfaces deny typed on non-binary
  input (was a `FunctionClauseError` raise).
- Eight new error codes: the seven corpus integrity codes + the recorded
  `:corpus_case_invalid` addition.


### Added

- Federation profile: `AgentBlueprintProtocol.Federation` with
  the 23-member `TaskEnvelope` (one wire member per logical field of the
  protocol's federation seam; decoded through the shared registry engine,
  canonical-before-semantics, cross-field rules, and a per-member
  portability pass where an authority-shaped identity claim denies
  `:nonportable_content`); the lossy-aware A2A/MCP state codecs
  (UNSPECIFIED denies at intake; crossing into MCP denies for
  rejected/submitted/auth_required; cancellation is never a terminal
  receipt); the carrier placement laws for both transports
  (`Task.metadata[a2a_uri]` on A2A, `_meta[namespace]` on MCP — the
  `_meta` key grammar forbids a URI key); `terminal_commitment/1` over
  the seven commitment components; and `verify_commitment/2` with the signature
  BINDING step (the signed content digest must name the receiving
  envelope's covered bytes — an honestly-signed statement naming a
  different digest is evidence over THAT digest), the
  issuer/subject/audience comparison (`:audience_mismatch`), and
  `:federation_terminal_conflict` on any divergence between receipts for
  one task identity. Facade rows `decode_federation_envelope/2` and
  `federation_mapping/0` (the 23-row mapping as data, bijective with the
  envelope's members by an architecture gate). Published mapping doc
  `docs/federation-mapping.md` with the pinned live sources, the A2A
  primary / MCP draft-tracking flag and revisit trigger, and the
  ttlMs-is-not-an-execution-bound, AUTH_REQUIRED-is-not-authorization,
  and AgentCard protobuf pre-normalization notes.
- Federation hardening (independent review): a
  signature whose signed `purpose` is not `federation-envelope` never
  verifies a federation receipt (the symmetric cross-surface purpose gap, closed
  on this surface — cross-surface signature lifting denied
  `:invalid_constraint`); the receipt's `kid`/`key_id` positions are
  portability-scanned strict (PEM/hex secrets deny
  `:forbidden_portable_value`; the signature blob stays deliberately
  opaque — every honest signature is entropy-dense and never survives
  verification without the key); `terminal_commitment/1` and
  `verify_commitment/2` are total over hand-built structs (typed denials
  replace raises on absent/non-string members and malformed commitment
  spellings); the carrier-reconstruction lane re-imposes the decoder's
  member/item/node/string/depth ceilings and the UTF-8 gate on hand-built
  carrier maps; duplicate regulated markers deny `:invalid_cardinality`.
  Receiver posture documented (purpose pinning, key-ids-as-labels,
  keys-are-not-issuers, replay-is-receiver-policy).
- Federation residual hardening: `Federation.Context` gains
  `issuer_key_sets` — per-issuer key attribution where the receipt's
  claimed (and binding-proven) `issuer` member selects the signature key
  pool, with strictest-wins precedence over the flat pool and deny-all
  for an empty map (cross-attribution now denies by mechanism) — and
  `created_after`/`created_before` freshness pins over the SIGNED
  `created_at` (receiver-supplied inclusive window, Z-form double-gated,
  checked after conflict detection so equivocation still reports
  `:federation_terminal_conflict`). Fixes a live crash the adversarial
  pass reproduced: `verify_commitment` with the Context's `keys: nil`
  default raised `FunctionClauseError` — nil/malformed pools now deny
  `:invalid_type` typed. Attribution-miss denials name the issuer
  subject; a value-free structural guard pins every federation denial's
  subject to schema shape with nil detail. Signature-blob opacity ruled
  irreducible in-package (honest signatures are entropy-dense); the
  boundary is shape-checked, never echoed, and never survives
  verification without the key.
- Error vocabulary: `:forbidden_portable_value` is now declared and
  emitted through per-site literals (the per-site vocabulary walk could
  not see the module-attribute-carried emission — a live closedness hole,
  closed with a staged red); the federation codes
  `:federation_state_unmappable`, `:federation_mapping_conflict`,
  `:nonportable_content`, `:audience_mismatch`, and
  `:federation_terminal_conflict` declared exactly as emitted.

- Reconcile hardening (independent review): the
  composed pass gates non-object artifact roots at the canonical stage
  (typed denial, never a raise); `Reconcile.Inputs` drops the unused
  observed-identities field (the eight-stage pass performs no
  compatibility verification — hosts call `verify_compatibility/2`;
  recorded contract delta); the portability stage mirrors each
  artifact's own per-position scan modes (authored schema documents and
  predicate operands, the blueprint's five identifier member tables,
  strict elsewhere) instead of strict-scanning everything; `Evidence
  .build/1` validates every field's shape and denies struct inputs
  typed; compatibility re-asserts the identity manifest's cardinality
  and closed four-member entries, and case-folds range tags (LATEST
  denies like latest); signatures checks carry the entry count as
  detail; the two facade delegates deny typed on malformed
  arguments; the vocabulary gate treats sigil-built code positions as
  dynamic build failures, sees piped call sites, and fixes the
  case/cond branch tag.
- Reconcile, compatibility, and the evidence record:
  `AgentBlueprintProtocol.Reconcile.reconcile/3` — the one call per
  import, running the pinned stage order canonical → digest →
  negotiation → structure → portability → signatures → bind → bounds,
  each stage reject-or-annotate, never repair, under host-supplied
  `Reconcile.Inputs` (host policy bounds, negotiation support, trusted
  public keys, observed build identities, the protected-clamp posture,
  and the bind-time observations). The signature stage BINDS each
  entry's signed `content_digest` to the artifact's recomputed digest —
  an honestly-signed statement naming a different digest is evidence
  over that digest, not this artifact (`:digest_mismatch`). The
  portability stage runs the direct scans under the authored channel
  re-derived from this import's negotiated critical extensions; the
  structure stage is the registry validation, kept disjoint so both
  guards are independently observable. Every clamp lands as
  `Evidence.clamps` and as a per-bound `:bounds` check carrying the
  `%ClampEvidence{}`. `AgentBlueprintProtocol.Compatibility.verify/2` —
  identity-exact matching of manifest `build_identities` against
  host-observed identities: ranges deny `:compatibility_identity_inexact`
  on both sides, duplicate candidates (including byte-identical
  observations) and duplicated manifest names deny
  `:compatibility_duplicate_entry`, unmatched entries deny
  `:compatibility_entry_missing`, extra observed identities are
  evidence-neutral; `exact?/1` is the public exact-version predicate.
  `AgentBlueprintProtocol.Evidence` — the non-authorizing verification
  record whose `not_verified` is non-empty BY CONSTRUCTION: `build/1`
  unions in the seven host-owned surfaces (tenancy, live_policy,
  authority, effect_ownership, execution, billing, evaluation_truth),
  never replacing them; callers may only add. The facade gains
  `verify_compatibility/2` and `reconcile/3`, and `Error.code` widens
  to carry the `{:ceiling, key}` family. All eight reconcile stage
  guards and the Evidence constructor are mutation-redded (each guard's
  removal fails its committed tamper or order test).

- Bounds-algebra hardening pass: classification comparison
  moves to the PRODUCT order the meet computes in (ordinal ≤ AND markers
  ⊇) — a marker dropped at ANY ordinal is a widening (obligations are not
  tradeable against scope), `widens?` becomes `¬(a ⪯ b)` and so
  fail-closed on every incomparable pair (an independent review's
  blocking finding: `{pci}` vs `{phi}` previously compared non-widening
  in both directions), and `narrower` requires both components. The rim is now
  deny-typed everywhere it previously raised on struct-bypass inputs:
  hostile map keys and unknown/extra names deny `:bound_unknown` with the
  CONTAINING surface as subject (never the attacker key — the echo
  channel closes), plain-map markers and marker maps with extra keys deny
  `:bound_value_invalid` at construction and again at `intersect`'s
  revalidation, malformed lifter sub-shapes read as absent (total,
  never-raising), off-lattice envelope strings deny with a constructible
  subject (the error builder itself was a crash site), a string on a
  numeric host bound denies `:invalid_type`, duplicate or extra members
  in hand-built `host_bounds`/`ceilings` objects deny `:invalid_type`
  (decode already enforced both), bound values above the parse profile's
  declared integer magnitude deny, `widens?`/`narrower` never raise on
  forged values (total predicates, fail-closed in the widening
  direction), and `Result.t`'s clamps type resolves its module. Every
  fix re-probed live against the finding's original probe input.
- Bounds algebra: `AgentBlueprintProtocol.BoundsAlgebra` —
  the pointwise narrowest intersection of the Blueprint's declared
  bounds, the Deployment's `host_bounds`, and the host's live policy over
  the closed thirteen-bound vocabulary, with per-family direction
  (scope families narrow at the low end; authority/approval/effect
  narrow at the STRICT end; classification markers are
  retained regulatory obligations whose effective set is the UNION of
  the sources' sets — dropping one is the widening the mutation gate
  names). Protected narrowings never happen silently: under the default
  `:deny` posture they deny `:protected_bound_clamp_denied` carrying
  the field/requested/effective triple; under `:acknowledge` they clamp
  with `acknowledged: true` evidence ALWAYS. Operational narrowings
  emit `ClampEvidence{field, class, unit, requested, effective, source,
  acknowledged}` with `:host` attribution on ties and composites (the
  live policy is the operative constraint), clamps ordered by the
  name-sorted vocabulary. `max_cost` compares within one currency only
  (`:bound_unit_mismatch`, order-free). All three sources must be total:
  an operational absence denies `:missing_ceiling`, a protected absence
  `:bound_source_missing`, under the pinned precedence (source order,
  then numerics → cost → protected, each name-sorted). `widens?/2` is
  fail-closed on incomparable pairs; `Bound.narrower/2` is
  direction-encoded per family and function-total (marker-bearing
  classification is a partial order — the lexicographic
  ordinal-then-marker superset relation). The lifters derive the
  Blueprint side totally (classification is the WIDEST across all five
  declaration sites; approval/authority/impact are the strictest claims
  across capabilities/effects with bottoms for empty arrays; disclosure
  is the identity element `:full` — the Blueprint declares no
  disclosure member) and lift the Deployment from `host_bounds` only
  (`model_policy` and `data_bindings` are not intersection inputs).
  The new `AgentBlueprintProtocol.Error{code, subject, detail}` record
  (typed shape, string subject paths, `detail` only for the
  protected deny) lands with the algebra surface; the facade gains
  `intersect/1`. Property lane: idempotent/commutative/associative
  (pinned fold encoding), `not widens?(effective, host)` universal,
  clamp iff `effective ≠ requested`, marker-union law — with the
  min→max, marker-intersection, direction-flip, struct-default, and
  silent-path mutations each proven RED against them.

### Fixed

- The bounds-algebra rim's coverage claim was corrected to a true
  100% (measured 2026-08-22: the then-committed suite reached only
  97.7% — the deny-typed rim's catch-all clauses had no tests). The rim probes now ship as tests: struct-bypass forged
  values through `widens?/2` and `Bound.narrower/2` for every family,
  wrong-shape cost at construction, non-map `new/1`, absent-name
  `fetch/2`, non-`Sources`/junk-posture/non-set-source `intersect/1`,
  and the `host_bounds` lifter shape matrix (absent, malformed member,
  malformed value, off-lattice ordinal, non-string on a protected
  name), each asserting the typed denial or fail-closed verdict.
  Eleven representative rim mutations each redded their test before
  restore. Two provably unreachable arms were removed (the only
  production change): `widens_value/3`'s unknown-name arm (its only
  caller iterates `names/0`, always `@table` keys) and `member_of/2`'s
  `{:object, _}` clause (no call site passes an object tuple).
  An independent re-review of the follow-up range then found the rim's
  one remaining hole: `widens?/2` matched any `%BoundSet{}` regardless
  of `bounds`' type, so a struct-forged `%BoundSet{bounds: nil}` raised
  `BadMapError` from either argument position instead of failing
  closed (the head now guards `is_map` on both, dropping the forgery
  to the fail-closed catch-all), plus its guard-family sibling
  `BoundSet.to_map/1` (same forged shape raised; now deny-typed
  `:invalid_type` with subject `["bound_set"]`). Both probed red
  before the fix, green after.
  `mix quality` has reported a true 100.00% since.
- A one-off suite flake, root-caused: the
  "mutating the signatures member" test replaced the first `A` in the
  base64url signature, which lands on the FINAL character ~7% of random
  signatures — the one position whose value is canonicality-constrained
  — producing a correctly-rejected non-canonical string
  (`:signature_malformed`). The tamper now targets the first character
  (a significant 6-bit position at every base64url length), making the
  test deterministic for every key.

### Core surfaces

- Deployment Manifest + binding: the 19-member table
  (re-derived against the protocol's Deployment Manifest definition) on the
  SAME generic engine — `AgentBlueprintProtocol.Deployment` mirrors the
  Blueprint pipeline stage-for-stage (canonical verify → registry
  validation → portability scan → digest comparison) under the
  `:deployment_content` domain, with only the table, the scan's open
  regions (extension bodies, eligibility expressions), and the digest
  domain as deltas. The binding surface: `binds?/2` (digest equality and
  nothing else, against the paired Blueprint's recomputed digest,
  constant-time, total over malformed deployment input) and the six-stage
  `verify_binding/3` with a pinned order — release digest
  (`:deployment_digest_mismatch`), release identity and tool-binding
  completeness (`:binding_incomplete`), mutation/recovery
  (`:no_authoritative_recovery`, the stricter of both operation sources),
  attestation staleness (`:binding_attestation_stale`, future attestations
  deny), and observed rug-pull (`:binding_descriptor_mismatch`); stages
  carrying host observations skip exactly when their inputs are absent.
  Table semantics: `blueprint_release` with a REQUIRED digest;
  exact-only build identities (the range vocabulary — comparators,
  wildcards, `latest`, range spans — denies
  `:compatibility_identity_inexact`; prerelease/build suffixes are exact
  pins); the `as_of` total rule; lifecycle temporal rules
  (`:lifecycle_state_invalid`); `host_bounds` totality over the thirteen
  bound names (structure only — the algebra surface owns the rest); empty
  `allowed_model_roles` valid. Every `adapter_identity`/`profile_identity`
  and every string nested in tool/data/build members is strict-scanned
  (`:forbidden_portable_value` in deployment positions). A signature's
  `purpose` is asserted per artifact (`deployment` here, `blueprint` in
  `Blueprint` — the symmetric cross-surface gap this closes). The extension
  envelope judgment is extracted to `AgentBlueprintProtocol.Extension` so
  both tables carry one definition, and `Negotiation` resolves the
  artifact kind from the digest member so each
  artifact's `required_core_fields` check against its own vocabulary. The
  facade gains `decode_deployment/2`, and a new architecture gate proves
  the no-second-pipeline invariant (delegation to `Registry.validate` plus
  no local stage definitions — planted-red proven, after the exports-only
  form was found vacuous by the same mutation).
- Deployment hardening pass: `verify_binding/3` gains a
  stage-0 shape totality — a non-object root, DUPLICATE root members, or a
  malformed `tool_bindings` entry (shape, operands, digest) denies before
  any cross-artifact judgment, and validated entries thread every later
  stage (the blocking finding of an independent review: malformed
  bindings were silently discarded, failing OPEN); negotiation restores revision-first
  order ahead of the new artifact-kind resolution, which now requires a
  well-formed string digest member (a malformed tag is machinery
  `:invalid_type`); the exact-version detector becomes one total charset
  rule (bare tilde, OR/comma/semicolon lists, and not-equal comparators
  join the denied range vocabulary); `max_attestation_age_ms` is
  shape-guarded (a non-integer bound silently failed to apply);
  scheme-relative network-path references (`//authority/path`) deny in
  every strict scan position; and the portability member-name denylist
  folds kebab/SCREAMING/camel spellings onto one normalized form (the
  normalization lesson swept across the guard family).
- Negotiation + compiled-in extension registry: the
  evolution gate (`AgentBlueprintProtocol.Negotiation`) with the pinned
  internal precedence (revision → required_core_fields → extensions) and
  registry-consistent reason rules for malformed machinery; explicit revision
  SET support (never ranges — a miss denies `:protocol_revision_unsupported`
  in both directions); the three fail-closed required-core-field checks;
  the positional extension state machine (unregistered critical denies,
  unregistered optional QUARANTINES byte-exactly with a notice fact,
  criticality conflict denies for live states before state handling,
  deprecated/retired/reserved cells all decided); critical-body validation
  only against digest-pinned host schemas (`:extension_schema_unavailable`
  / `:extension_schema_digest_mismatch`); and a reserved-semantics
  denylist (bound-shaped member names, camelCase twins included) over ALL
  extension bodies. The registry (`ExtensionRegistry`) is compiled-in
  data — drift unrepresentable, backed by a new beam-census gate that
  asserts no shipped module touches the filesystem (planted-red proven) —
  carrying the five first-release entries with `com.example/federation`'s schema
  authored in-repo under the new `:extension_schema` digest domain.
  `Blueprint.from_value/2`'s `:authored_extensions` option opens the
  encoded-content carriage channel: negotiation-validated critical bodies
  skip the portability value-shape heuristics (their controls are the
  schema pin and the denylist). The facade gains `negotiate/2`.
- Portability named-encoding closures: the raw-key floor
  drops to 24 decoded bytes (catches AES-128-class hex keys) with hyphenated
  UUIDs exempt by shape in every mode (the spec-pinned honest-limit
  calibration); padded standard base32 (up to six pad chars) joins the
  padded-base64 class; and a colon-chunked hex fingerprint class (the SSH
  fingerprint / EUI form, 24+ decoded bytes) denies while the chunk grammar
  spares tagged content addresses and MAC addresses.
- Blueprint artifact + generic registry engine: the ONE
  table-driven decode/validate engine (`AgentBlueprintProtocol.Registry`)
  parameterized by `AgentBlueprintProtocol.Blueprint.table/0`'s
  18-member field registry (base §6), with the pinned failure precedence
  (unknown member → missing required → type → constraint → cardinality →
  nested → cross-field hooks). `Blueprint.decode/2` runs the fail-closed
  pipeline in order: canonical verify (`:non_canonical_bytes` before any
  semantic read or digest work — the canonicality obligation, digests computed only
  over exact received bytes), registry validation (closed world;
  tag-strict integer typing so a float-tagged window value in an
  integer-typed core field denies `:invalid_type` — the window-float obligation,
  visible only at this layer), the portability scan, then the
  content-digest comparison (`:digest_mismatch`). Also ships
  `AgentBlueprintProtocol.Predicate` (the closed, order-independent
  predicate algebra: grammar validation against declared ports, the
  256-node ceiling, and error-dominant `evaluate/2`), and
  `AgentBlueprintProtocol.Portability` (the never-portable structural
  guard: the 34-name member denylist over the open regions and the
  value-shape denylist — PEM armour, compact JWS, network-authority URIs,
  ≥32-byte clean base64url with the identifier-style exemption — over every
  other string including signature `key_id`). The facade gains
  `decode_blueprint/2`.
- Public Elixir package starter with zero third-party/Hex production
  dependencies.
- Explicit non-authorizing product boundary and release-candidate posture.
- RFC 8785 JSON Canonicalization Scheme (`AgentBlueprintProtocol.Canonicalization`):
  UTF-16 code-unit member sorting, §3.2.2.2 string escaping, hand-written
  ECMA-262 §7.1.12.1 number serialization (byte-exact against every finite
  RFC 8785 Appendix B vector), and `verify/2` decode→re-encode→byte-compare
  interchange enforcement with fail-closed guards for duplicate names,
  invalid UTF-8/lone surrogates, and out-of-bound integers on the encode path.
- Strict unpadded base64url codec (`AgentBlueprintProtocol.Base64Url`):
  RFC 4648 §5 alphabet, RFC 7515 §2 padding-free wire form, and RFC 4648
  §3.3/§3.5 canonicality — padded input, non-alphabet characters, and
  non-canonical pad-bit spellings (which alias the same bytes) all reject
  with value-free reasons.
- Tagged content digests (`AgentBlueprintProtocol.Digest`):
  `"sha-256:<43-char unpadded base64url>"` wire strings over domain-separated
  preimages (`SHA-256(separator || <<0>> || canonical JCS bytes)` under the
  registered base-§8.2 separators), `from_tagged/1` fail-closed parsing
  (unknown algorithm tag vs malformed body, wrong-length bodies included),
  constant-time `equal?/2`, and `verify_content/3` (parse, then compare;
  divergence denies `:digest_mismatch`). SHA-256 conformance is pinned to the
  FIPS 180-4 known-answer vectors.
- Detached JWS signature envelope (`AgentBlueprintProtocol.Signature`):
  RFC 7515 compact serialization with the RFC 7797 `b64=false` unencoded
  detached payload — the signing input is
  `BASE64URL(JCS(protected_header)) || "." || JCS(signed_attributes)` —
  Ed25519 verified through `:crypto`, verify-only (an architecture gate
  enforces no `:crypto.sign` call, no private-key parameters, and no
  key-material shape anywhere in the shipped source). Host-supplied trusted
  keys match by `key_id` (`:signature_key_unsupported` when absent,
  `:signature_not_verified` on divergence — facts, never authorization).
  The exact four-member protected header (`alg/crit/b64/kid`) and the five
  signed attributes are closed-world with fail-closed, value-free denials;
  `kid` must equal the signed `key_id`, which is dot-free so the unencoded
  payload can never carry `.` (RFC 7797 §5.2). Compact rendering (`h..s`,
  empty payload segment per RFC 7515 Appendix F) supports standard-tooling
  cross-checks. RFC 8032 §7.1 TEST 1 is reproduced byte-exact. Attestations
  share the envelope with a registered `kind` and `statement_digest`; the
  kind registry is empty, so attestations deny `:attestation_malformed`
  today (fail-closed until kinds become data).

### Changed

- Integer window decode rule (the amendment): a pure-digit number lexeme
  above the I-JSON bound ±(2^53−1) now decodes as a float when it is exactly
  that double's canonical ECMAScript serialization (e.g. the RFC 8785
  Appendix B vectors `9007199254740992`, `295147905179352830000`), and
  denies with the new `:number_not_double_expressible` reason otherwise
  (retiring the interim `:integer_magnitude` decode reason). Canonical
  pure-digit float output in [2^53, 10^21) now round-trips `verify/2`; the
  encode/verify asymmetry previously documented here is closed.
- Bounded JSON Schema 2020-12 dialect + instance validator
  (`AgentBlueprintProtocol.Schema`): the closed 16-keyword subset
  (`type properties required items enum const minimum maximum minLength
  maxLength minItems maxItems additionalProperties oneOf $defs` plus
  document-local `$ref`) over the tagged algebra, with everything else —
  `pattern`/`format`/`patternProperties`/`if-then-else`/`allOf`/remote
  `$ref` and the rest of the 2020-12 keyword universe — denying
  `:schema_keyword_not_allowed`. 2020-12 semantics read first-hand and
  pinned: type-targeted assertions auto-pass other types, missing keywords
  never fail, `oneOf` is exactly-one, boolean schemas are the substrate,
  numbers compare by mathematical value across the integer/float tags
  (tag-blind `type:"integer"` — the tags do not survive the wire), object
  equality is order-blind, and string lengths count codepoints (not
  graphemes, not UTF-16 units). Resource posture: complexity metered as
  `nodes + keywords + Σ(branches) + depth × 4` against the 512 profile
  ceiling; evaluation memoized on (schema node, instance location) —
  closing the acyclic-`$ref`-DAG exponential blowup for passing AND failing
  instances; document-local RFC 6901 pointers (split-then-unescape, `~1`
  before `~0`) resolve at parse, and application-reachable reference cycles
  deny while dead `$defs` self-references parse. Both `parse/2` and
  `validate_instance/3` are total — malformed tagged shapes deny, never
  raise. Multi-failure reasons follow a fixed canonical keyword order
  (mirrored for the TS verifier).
