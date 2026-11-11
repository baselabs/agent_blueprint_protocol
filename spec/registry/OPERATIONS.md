# Registry operations process

The shipped registry contains the protocol's two federation registrations.
`registry.json` is its canonical source; the compiled Elixir and TypeScript
forms are bound to it by the registry equality check. Product and third-party
entries belong in the host support registry, not in these packages.

## Host registrations

A host supplies a namespace-keyed entry through `Negotiation.Support.registry`
in Elixir or `Support.registry` in TypeScript. Each entry declares criticality
and lifecycle state, and a critical entry pins the canonical schema digest.
The host supplies the schema document through `schemas`. Namespaces absent from
the shipped registry resolve from this input. Overrides for shipped entries
can change only lifecycle state; compiled criticality and schema pins prevail.

## Qualification

A registration request MUST provide: the namespace (reverse-DNS-plus-
path, not parseable as a network endpoint), an owner, the declared
criticality, and, for critical namespaces, a schema document whose JCS
digest is pinned. A request SHOULD state the A2A declaration URI.
Examples use generic reserved-domain identities.

## Registration steps

1. For a protocol-owned namespace, the owner submits the entry (and, for critical entries, the schema
   document) as a change to `registry.json` and implements it in both
   language packages.
2. The registry-equality check, corpus checks, and CI checks must pass.
   Corpus verification fails when cases were generated for a different
   registry state.
3. The change lands with a CHANGELOG entry and an ADR record when it
   sets a precedent.

## Lifecycle

`reserved` → `active` → `deprecated` → `retired`. Promotion to a
critical declaration requires a protocol revision increment (the
digest-covered evolution rule); demotion does not. A retired namespace
is never reused. Deprecated entries retain verifiable artifacts with a
typed notice. Entries the release ships deprecate and never retire within
1.x. The retired state remains available for host-owned entries.

## Decision rights

The registry steward accepts registrations; the two-consumer
rule governs promotion into shared surfaces: a member or helper earns
a shared seat only when two independently verified consumers use it.
The registry carries published facts, never authority.

## MCP metadata registrations

A namespace carried as an MCP `_meta` key follows the grammar in
[MCP revision 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/basic#_meta).
This registry requires at least two prefix labels. Each begins with a
lowercase letter, ends with a lowercase letter or digit, and permits
lowercase letters, digits, and hyphens inside. The nonempty name begins and
ends with a lowercase letter or digit; its interior also permits lowercase
letters, digits, hyphens, underscores, and dots. These lowercase and
two-label restrictions are stricter than the MCP grammar. A prefix whose second label is `mcp` or `modelcontextprotocol` is
reserved. The registry equality gate checks registrations; artifact
decoding retains its revision 1 namespace grammar.

## Federation namespace

`io.github.baselabs/federation` is active and critical, with A2A URI
`https://baselabs.github.io/agent_blueprint_protocol/extensions/federation`.
It retains the schema pin of `com.example/federation`. Producers SHOULD
use the active namespace; both are supported. The deprecated spelling
emits `extension_deprecated` and is never retired in the 1.x line.

## Review and disputes

The maintainer evaluates namespace control, public owner identity, grammar,
criticality, schema digest reproducibility, compatibility, and test coverage.
Requests are reviewed on a best-effort basis, in the order received. An applicant can request reconsideration in the same public discussion. Unresolved disputes go to the registry steward with the evidence and requested change.
A dispute does not change a released registry entry.
