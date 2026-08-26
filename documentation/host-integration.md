# Host integration — reconcile into an import path

The one call per import: `AgentBlueprintProtocol.reconcile/3` runs the
pinned eight-stage pass — canonical, digest, negotiation, structure,
portability, signatures, bind, bounds — reject-or-annotate, never
repair, under host-supplied inputs.

## The result is an Evidence record

Every result carries per-surface checks, effective bounds, clamp
evidence, and `not_verified` — non-empty BY CONSTRUCTION, always
naming at least the seven host-owned surfaces this protocol cannot
establish: tenancy, live policy, authority, effect ownership,
execution, billing, evaluation truth. You cannot read an Evidence
record and conclude "everything is fine"; the record names what it did
not check.

## Bounds meet at the narrowest point

```elixir
{:ok, profile} = AgentBlueprintProtocol.Bounds.new(%{depth: 32})
profile.depth # => 32
AgentBlueprintProtocol.Bounds.maximum().depth # => 64
```

Effective bounds never widen host policy (property-tested). Operational
narrowings clamp with evidence; protected narrowings deny unless you
opt into the acknowledge posture.

## Import wiring

A host embeds reconcile into its import path: artifacts arrive from
wherever, reconcile produces the Evidence record, and the HOST decides
— admit to quarantine, admit to staging, reject. The protocol's
verdicts are inputs to that decision, never the decision.
