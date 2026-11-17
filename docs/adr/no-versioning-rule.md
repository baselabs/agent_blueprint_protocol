# ADR: no version tokens in identifiers

## npm distribution axis

The npm kit (the verifier's compiled distribution; published as
`@agent-blueprint-protocol/verifier`) carries its own package semver. That is a FIFTH
permitted version axis under one binding: the kit version MUST equal
the Hex package version at every release (a single release line, two
registries). Enforced mechanically by the version-sync gate in the
agreement script: the npm metadata's `version` == `mix.exs` `@version`,
seeded-red on a one-side bump. Dist-tags exist only as npm registry
plumbing (`latest`); they name no durable identity. The kit's machine
identity remains the embedded corpus digest, asserted equal to the
release-certified digest, versioned by digest, never by name, like
every other axis in this inventory.

## Release identity consumer contract

The release-identity consumer contract (the 0.8 line) extends the axis
inventory and states the precedence rules:

1. **`manifest_version`** (in `priv/release-metadata.json`) versions the
   manifest's SHAPE: a public-contract field, additive-only within a
   version. Every release before this contract is implicitly version 1.
2. **`verification_semantics_version`** is the semantics/census split's
   equivalence-class label (see `release-identity-semantics.md`): an
   integer, never gate-derived, changed only when verdicts for
   previously-certified inputs change.
3. **The verifier-kit identity** (`verifier_kit`: name, registry,
   version) rides the manifest, derived from the npm package metadata at
   derivation time; the kit version remains bound == the Hex line under
   the npm-axis amendment, and the kit embeds the manifest
   byte-identically.
4. **`priv/release-history.json`** is a durable version-bearing identity
   carrier (one append-only row per manifest-era release), like the
   CHANGELOG's per-release digest lines, a record, never an identifier.

Precedence: `protocol_revision` governs what artifacts may say (the wire
axis); `verification_semantics_version` governs what the verifier
concludes about previously-certified inputs (the computation axis); Hex
semver, git tags, and the manifest version govern the release identity.
The axes are independent; one event (for example an optional→critical
registry flip, which requires a revision increment) may move more than
one at once; none may be derived from another.

## Prerelease identity

Hex and npm carry the same complete semantic version, including a
prerelease suffix. The candidate uses `rc` as npm's distribution tag and
is marked prerelease in the source release. Tags are distribution
selection, not another durable identity. Version comparison uses semantic
version precedence, including numeric prerelease identifiers.
