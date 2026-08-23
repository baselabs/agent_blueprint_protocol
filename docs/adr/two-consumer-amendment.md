# ADR: two-consumer rule amendment

Status: accepted (2026-08-20).

## Context

The field-registry governance rule required two independently verified
consumers before a member earns a core seat — the guard against
single-product vocabulary soaking into a language-neutral protocol. As
applied literally to EVERY member, it would have blocked the protocol's
own machinery.

## Decision

Protocol-mechanism members — `protocol_revision`, content digests,
`required_core_fields`, `extensions` — are the protocol's own machinery
and are exempt from the two-consumer rule. Everything else keeps the
rule: a core field requires at least two independently verified
consumers, or it rides in a registered product extension instead. The
ceiling vector was ratified as a unit on the execution spec's own
naming.

## Consequences

Product-specific semantics (graph authoring, rubric assertions,
classification labels) live in registered extensions owned by their
products, promotable only with a revision increment when a second host
proves the same semantics. The core stays small and neutral; registry
entries carry the honesty record of who consumes what. This is the
load-bearing reason the package contains no product schema bodies.
