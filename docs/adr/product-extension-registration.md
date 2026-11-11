# ADR: host-supplied extension registrations

Status: accepted; supersedes compiled product registrations in the 1.0 line.

## Decision

Product schemas and namespace registrations belong to their hosts. The public
packages ship the protocol's own federation registrations and generic extension
mechanisms. They carry no product-owned schema, registration, or projection.

Elixir hosts supply `%ExtensionRegistry{}` entries through
`Negotiation.Support.registry` and parsed schema documents through
`Negotiation.Support.schemas`. TypeScript hosts supply the equivalent
namespace-keyed entries and JSON schemas through the public `Support` type.
A host entry includes criticality, lifecycle state, and a schema digest pin.
For namespaces absent from the compiled registry, negotiation uses that entry.
For compiled namespaces, host overrides affect only lifecycle state.

Critical bodies validate against the held schema under the registered digest.
The `authored_extensions` input to Elixir artifact construction accepts the
namespaces negotiation validated. It does not authorize execution or establish
content classification. Hosts apply their own content policies.

## Consequences

A product registration needs no upstream package release. Generic conformance
cases exercise critical validation, schema availability and digest mismatch,
criticality conflicts, optional retention, and every lifecycle state through
host support. Product-specific schemas and fixtures stay in their product.

Version 1.0 changes the registry digest and verification-semantics version
to 3. Earlier compiled product examples are unknown without host registration;
the release manifest declares every affected prior census as
`diverged_by_registry_census`, certified by compatibility replay.
