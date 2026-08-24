# ADR: no version tokens in identifiers

Status: accepted (2026-08-20; contract-identity amendment 2026-08-24).

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
