# ADR: no version tokens in identifiers

Status: accepted (2026-08-20, user directive; mechanically enforced).

## Context

Protocol artifacts already carry `protocol_revision` as a digest-covered
member. Identifier-level version tokens (module names like `V2Decoder`,
paths like `priv/v1/`, function names like `decode_v2`) would create a
second, uncoordinated versioning axis — the classic drift surface where
two names claim to be current and neither is.

## Decision

No version token appears in any shipped identifier: module segment,
function or macro name, atom, struct key, corpus path, or config key.
The Hex package's semantic version is the sole permitted version
number. Enforced mechanically: the identifier-naming gate reds on every
conventional token form (leading `v<N>`, snake-boundary `_v<N>`,
CamelCase hump `V<N>`) and on path segments. ADR filenames are
slug-only (no numeric sequence prefixes) for the same reason — document
sequence numbers are a versioning axis.

## Consequences

Evolution happens at the revision boundary inside the artifact, where
it is digest-covered and negotiation-gated; the code surface stays
version-free and rename-stable. The mechanical gate makes regressions
loud. The one accepted exception (Hex semver) lives in `mix.exs` as a
string literal, outside identifier space.
