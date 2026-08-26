# ADR: product-extension registration

Status: accepted (2026-08-25); the consumer-named upstream prerequisite for a
host's render/export and import-into-governance seams.

## Context

A portfolio consumer verifies external artifacts through this package behind a
strict boundary and gates its own render direction on an upstream release that
registers its product extension. Its product semantics — the asset
materialization window and the objective condition AST — have no Blueprint
Core members; per the two-consumer amendment they belong in a registered
extension, and the compiled-in registry makes registration an upstream code
release, not a local act. The ask: a critical namespace with a digest-pinned
host schema riding the `:authored_extensions` validated channel.

## Decision

1. **Register `com.example.platform/estate-contract`** — owner `ExamplePlatform`,
   criticality `critical`, state `active`, `promoted_at_revision` nil (born
   critical, never promoted), with the FIRST product-owned `schema_digest` pin.
   No core member changes; `protocol_revision` stays 1. Born-critical is the
   established form (`com.example.commerce/graph`, `com.example/federation`);
   promoting the existing optional row instead would demand a protocol revision
   increment (the lifecycle rule) for a registry maturation with zero
   vocabulary change — an abuse of the revision mechanism (revisions gate core
   member-set evolution).

2. **Deprecate `com.example.platform/estate`** in the same release. Its payload
   role — a condition body carried verbatim as a free object — is superseded by
   the schema-validated channel. Deprecated optional bodies stay
   retained-with-notice, so existing artifacts remain verifiable; the namespace
   is never reused (retirement stays available for a later release).

3. **The schema document is corpus data**
   (`priv/conformance/schemas/estate-contract.schema.json`), hash-bound in the
   corpus index and shipped in the archive; `lib/` records only the digest pin.
   The pin↔file binding is test-enforced: the registry row's `schema_digest`
   equals `Digest.hash(:extension_schema, JCS(parsed document))` of the SHIPPED
   file (the federation pin test's pattern generalized from lib-owned schema
   code to the corpus fixture). Rejected alternatives: shipping the document as
   library code (the two-consumer amendment's "no product schema bodies" — the
   engine knows tables, never domains), or leaving the document owner-side only
   (the public pin would reference bytes no third-party host could obtain).

4. **The document's shape.** Two required members: `asset_materialization_window`
   (`definition {name, version}` + nullable `window_days` — the host's nil =
   all-time) and `objective_condition` (the host grammar: leaves
   `materialization_present` / `materialization_stale {max_age_days}` /
   `materialization_count_within {days, max}` over definition refs; composites
   `and`/`or` n-ary and `not` unary). Because the bounded dialect denies
   application-reachable `$ref` cycles, the recursion is hand-tiered as
   UNIFORM-DEPTH strict tiers: `tier_k` composites take args that are ALL
   `tier_{k-1}` (tier 1 over leaves), the top selector is
   `oneOf[leaf, tier_1, tier_2, tier_3]`, and every variant carries
   `type: "object"` (without it a bare string auto-passes `properties`/`required`
   and slides through on `const` alone). Exactly-one holds per shape class; the
   metered complexity is 415 of the 512 ceiling. Consequences recorded as
   intended divergences from the host algebra: portable depth is THREE composite
   tiers (the host allows 16 — deeper conditions stay host-side); depth-skipping
   args (`and[leaf, and[leaf]]`) are unrepresentable — the renderer normalizes
   by identity single-arg conjunction padding (`and[x] ≡ x`), boolean-equivalent;
   zero-args `and`/`or` identities are unrepresentable.

5. **The validated channel's effective controls.** A critical body validated at
   negotiation is controlled by the digest-pinned schema and the
   reserved-semantics denylist; when threaded through `:authored_extensions` it
   SKIPS the portability member-name and value-shape heuristics (the legitimate
   channel for encoded content). That skip is by design and is the reason a
   importing host re-scans validated bodies for classified content under its own
   posture — schema validity is structural, never a portability or
   classification proof.

## Consequences

The registry gains its first product-owned critical pin; the corpus grows the
validated-channel cells (valid attach, schema absent, digest mismatch,
criticality conflict, the tier-bound deny, deprecated-optional retention) and
two classes (`extension_schema_unavailable`, `extension_deprecated_retained`);
the applicability floor is now 16 surfaces × 31 classes / 90 required cells.
The registration surfaced and fixed a latent second-language defect: the TS
verifier's `items` evaluation had its schema/instance arguments swapped, so no
cross-language case had ever validated array items — the tier schemas are the
first corpus-bearing `items` user, and the agreement gate now proves both
languages agree on items validation. Consumers exact-pin the release by tag,
checksums, corpus digest, and registry digest as before.
