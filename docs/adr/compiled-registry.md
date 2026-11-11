# ADR: compiled-in extension registry

Status: accepted.

## Decision

The release ships only the protocol's federation registrations:
`io.github.baselabs/federation` is critical and active;
`com.example/federation` is critical and deprecated. Both pin the protocol's
federation schema. The deprecated spelling remains supported throughout 1.x.
Product and third-party registrations are supplied by the host through
negotiation support, with the schema documents the host holds.

`spec/registry/registry.json` is the canonical source for shipped entries.
Elixir and TypeScript compile equivalent data into their libraries. Runtime
registry lookup performs no file I/O. The registry equality check binds both
compiled forms, the canonical document, and the corpus index to one digest.

## Host registrations

An entry for a namespace absent from the shipped registry supplies its own
criticality, state, and schema digest pin. A host entry for a compiled namespace
can select its lifecycle state but cannot reclassify it or replace its pin.
Critical bodies validate against a held schema whose canonical digest matches
the resolved entry. Optional bodies retain their lifecycle behavior.

## Identity and lifecycle

The registry digest identifies shipped content and is bound into the corpus
index. Artifact digests cover extension content rather than the registry
itself. Hosts can pin extension build identities separately.

Shipped namespaces deprecate and never retire within 1.x. Host-owned entries
retain the general reserved, active, deprecated, and retired state mechanism.
A registry change that moves prior-census verdicts increments verification
semantics and declares the divergence through compatibility replay.
