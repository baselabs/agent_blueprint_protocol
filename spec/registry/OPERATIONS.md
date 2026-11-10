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
Requests are reviewed in the order received. An applicant can
request reconsideration in the same public discussion; unresolved disputes
go to the steward, BaseLabs Holdings, with the evidence and requested change.
A dispute does not change a released registry entry.
