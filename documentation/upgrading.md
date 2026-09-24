# Upgrading and stability

The 0.x series is the public pre-1.0 line: shipped contracts may
change within 0.x under pre-1.0 conventions, and every contract change
lands with a red-capable test. The CHANGELOG records every public
change; the release identity chain (specification digest, package
version, corpus and registry digests) is asserted from live state on
every build, so a release cannot ship with stale identity claims.

## Version axes

Hex semver, git release tags, the release-metadata fields, the
verification-semantics version, the npm kit identity, the release
history, and the digests themselves are the version-bearing identities —
no identifier in the package carries a version token. Upgrading means a
new digest chain, not a renamed module.

## What never changes silently

Canonicalization (RFC 8785), the digest domain separators, the
closed member worlds per revision, and the non-authorizing boundary.
Evolution happens at digest-covered revision boundaries, gated by
negotiation. Since 0.8.0 these stability claims carry a named axis: the
release manifest's `verification_semantics_version` changes exactly
when verification semantics for previously-certified inputs change (the
specification's Evolution clause defines the axis; census growth — more
corpus cases, more registry entries — never moves it).

## The release-identity manifest and the release history

`priv/release-metadata.json` is a versioned public contract
(`manifest_version`; additive-only within a version). The npm kit
embeds the same bytes. `priv/release-history.json` carries one
append-only row per manifest-era release (since the manifest's
introduction) — the mapping a
consumer reads to learn which semantics version spans which releases.
Released identities are immutable: a published digest, corpus,
registry, manifest, or history row is never edited in place; corrections
are new releases.

## Guidance for exact-pinned consumers

A consumer that pins an exact release and persists verification
identity (replaying imports against the persisted identity) should
partition the identity fields along the protocol's own line:

- **Replay identity** — equality-compared on every replay:
  `manifest_version`, `verification_semantics_version`, the artifact's
  `protocol_revision`, `registry_digest`, `blueprint_digest`,
  `deployment_digest`, `effective_bounds`, and the consumer's own
  adapter, product-build, and authority identities.
- **Provenance metadata** — recorded, never equality-compared:
  `package_version`, the package checksum, `corpus_digest`, and
  `spec_digest`. These move with census and release bookkeeping; a
  byte-identical historical import under a newer pin must not conflict
  on them.

Under that partition, upgrading between two releases that share a
`verification_semantics_version` AND an unchanged registry census
replays historical imports green; any true semantics change conflicts
loudly on the integer. Registry movement conflicts BY DESIGN:
`registry_digest` is the fail-closed vocabulary detector below, so a
release that grows the registry still requires the consumer to re-pin
it deliberately — the conflict is the detector working, not a break. The boundary
stated plainly: the equivalence a semantics version certifies is over
the released censuses (per-case verdict replay), and the compatibility
matrix (`prior_census_verdicts`) names, per prior census, exactly what
this release certifies.

## Enumerating fail-closed at a pin

The extension registry (`spec/registry/registry.json`, pinned by
`registry_digest` in the manifest) enumerates every extension the
release knows with its criticality, state, and schema digest — the
census that defines what fail-closed means for extension negotiation at
that pin. To detect widening between pins, diff the registry files at
the two releases' tags; a registry change that alters negotiation
outcomes for previously-certified artifacts is a verification-semantics
change and bumps the semantics version (the specification's Evolution
clause).
