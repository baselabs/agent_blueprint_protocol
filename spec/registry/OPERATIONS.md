# Registry operations process

How namespaces enter and leave the compiled extension registry. The
registry is governance-canonical in `registry.json` (this directory);
the compiled twins (Elixir module and TypeScript verifier) are
hand-mirrored and bound by the registry-equality gate.

## Qualification

A registration request MUST provide: the namespace (reverse-DNS-plus-
path, not parseable as a network endpoint), an owner, the declared
criticality, and — for critical namespaces — a schema document whose
JCS digest is pinned. A request SHOULD state the A2A declaration URI.
Example-class identities are the norm until a product is public.

## Registration steps

1. The owner submits the entry (and, for critical entries, the schema
   document) as a change to `registry.json` mirrored into both
   compiled twins.
2. The registry-equality gate, the corpus (which rebinds the registry
   digest), and the full quality battery must pass; the corpus
   registry binding reds a corpus built for a different registry
   state.
3. The change lands with a CHANGELOG entry and an ADR record when it
   sets a precedent (the product-extension registration is the
   recorded example).

## Lifecycle

`reserved` → `active` → `deprecated` → `retired`. Promotion to a
critical declaration requires a protocol revision increment (the
digest-covered evolution rule); demotion does not. A retired namespace
is never reused. Deprecated entries retain verifiable artifacts with a
typed notice.

## Decision rights

The steward (named in IPR.md) accepts registrations; the two-consumer
rule governs promotion into shared surfaces: a member or helper earns
a shared seat only when two independently verified consumers use it.
The registry carries published facts, never authority.
