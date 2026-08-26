# ADR: producer surface policy

Status: accepted (2026-08-25); records the disposition a consumer asked for at
the product-extension registration.

## Context

A consumer adopting this package as a verification boundary asked whether the
documented per-artifact constructors (`Blueprint.from_value/2`,
`Blueprint.content_digest/1`, `Deployment.from_value/2`, and the digest
helpers) are the intended PRODUCER surface for hosts that render artifacts, or
whether facade-level producers should grow (`AgentBlueprintProtocol.blah`
entry points that mint artifacts). The consumer's reading was yes — the
constructors are the producer surface.

## Decision

The constructors ARE the intended producer surface. The facade stays a
verification facade: it delegates and never implements, and no facade-level
producer functions grow. A host rendering an artifact composes the value
(members per its own product mapping), constructs it with
`from_value/2` — threading `:authored_extensions` for critical namespaces whose
bodies negotiation validated against a digest-pinned schema — computes the
content digest, and serializes with `canonical_bytes/1`. The round-trip
property (`decode → to_value → encode` is a fixed point) is the byte-exactness
guarantee a producer relies on.

## Consequences

No API change; this record closes the question for future hosts. Producer
guidance belongs in the protocol document's shipped-surface section, which
already names the constructors; if a producer helper ever proves load-bearing
for two independently verified hosts, it earns a facade seat through the same
two-consumer rule that governs core members.
