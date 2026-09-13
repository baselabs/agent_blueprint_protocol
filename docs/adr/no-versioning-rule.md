# ADR: no version tokens in identifiers

Status: accepted (2026-08-20; contract-identity amendment 2026-08-24;
version-axis inventory amendment 2026-08-26; npm-axis amendment 2026-09-13).

## Context

Protocol artifacts already carry `protocol_revision` as a digest-covered
member. Identifier-level version tokens (module names like `V2Decoder`,
paths like `priv/v1/`, function names like `decode_v2`) would create a
second, uncoordinated versioning axis — the classic drift surface where
two names claim to be current and neither is.

## Decision

No version token appears in any shipped identifier: module segment,
function or macro name, atom, struct key, corpus path, or config key.
The Hex package's semantic version and its exact `mix.exs` package-tag source
reference are the sole permitted version-bearing durable identities. Enforced
mechanically: the identifier-naming gate reds on every
conventional token form (leading `v<N>`, snake-boundary `_v<N>`,
CamelCase hump `V<N>`) and on path segments. ADR filenames are
slug-only (no numeric sequence prefixes) for the same reason — document
sequence numbers are a versioning axis.

## Consequences

Evolution happens at the revision boundary inside the artifact, where
it is digest-covered and negotiation-gated; the code surface stays
version-free and rename-stable. The mechanical gate makes regressions
loud. The accepted package surfaces live in `mix.exs`: Hex semver and the exact
`source_ref: "v#{@version}"` tag identity. Path, source kind, and spelling are
part of the mechanical allowlist; a lookalike in any other location is rejected.
Wire revisions remain digest-covered data. No module, function, path, config key,
queue, event, database object, or internal compatibility branch may derive its
name from a release, task, or implementation sequence.


## Amendment — the version-axis inventory (2026-08-26)

The release identity chain added version-bearing fields beyond Hex
semver; this amendment records the complete permitted axis inventory
(the gauge for "no second versioning axis"):

1. **Hex package semver** (`mix.exs` `@version`) — the release line.
2. **Git release tags** (`v<x.y.z>`) — the source state of a release.
3. **Release-metadata fields** (`priv/release-metadata.json`):
   `package_version`, `spec_digest`, `corpus_digest`,
   `registry_digest`, `index_sha256_base64url` — the certified
   identity chain, asserted from live state by the release-candidate
   check.
4. **The digests themselves** — the machine identity of specification,
   corpus, and registry; versioned by digest, never by name.

No other durable identity carries a version token; the
identifier-naming gate's enforcement is unchanged. Document sequence
numbers remain banned (slug-only ADR filenames).


## Amendment — the npm distribution axis (2026-09-13)

The npm kit `@rjpalermo/agent-blueprint-protocol` (the verifier's
compiled distribution) carries its own package semver. That is a FIFTH
permitted version axis under one binding: the kit version MUST equal
the Hex package version at every release (a single release line, two
registries). Enforced mechanically by the version-sync gate in the
agreement script: `package.json` `version` == `mix.exs` `@version`,
seeded-red on a one-side bump. Dist-tags exist only as npm registry
plumbing (`latest`); they name no durable identity. The kit's machine
identity remains the embedded corpus digest, asserted equal to the
release-certified digest — versioned by digest, never by name, like
every other axis in this inventory.
