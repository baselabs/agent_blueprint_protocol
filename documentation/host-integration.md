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

## A worked import (the shipped echo pair)

Every input is host-supplied: your bound set, your support posture,
your keys, your clamp posture, your observations. Under the DEFAULT
`:deny` clamp posture this pair denies typed — the host bounds narrow
the protected `disclosure_ceiling`, and protected narrowings deny
unless the host opts in:

```elixir
{:ok, blueprint} = AgentBlueprintProtocol.decode_blueprint(File.read!("examples/echo-blueprint.json"))
{:ok, deployment} = AgentBlueprintProtocol.decode_deployment(File.read!("examples/echo-deployment.json"))
host_bounds = AgentBlueprintProtocol.BoundsAlgebra.from_deployment(deployment) |> elem(1)
support = %AgentBlueprintProtocol.Negotiation.Support{revisions: MapSet.new([1])}
observations = %AgentBlueprintProtocol.Deployment.Observations{now: ~U[2026-08-21T00:00:00Z], max_attestation_age_ms: 86_400_000, observed: %{}}
inputs = %AgentBlueprintProtocol.Reconcile.Inputs{host_bounds: host_bounds, support: support, keys: [], protected_clamp: :deny, observations: observations}
{:error, error} = AgentBlueprintProtocol.reconcile(blueprint, deployment, inputs)
error.code # => :protected_bound_clamp_denied
```

The acknowledge posture records the narrowing as clamp evidence
instead of denying — and the green result still names exactly what was
NOT verified:

```elixir
{:ok, blueprint} = AgentBlueprintProtocol.decode_blueprint(File.read!("examples/echo-blueprint.json"))
{:ok, deployment} = AgentBlueprintProtocol.decode_deployment(File.read!("examples/echo-deployment.json"))
host_bounds = AgentBlueprintProtocol.BoundsAlgebra.from_deployment(deployment) |> elem(1)
support = %AgentBlueprintProtocol.Negotiation.Support{revisions: MapSet.new([1])}
observations = %AgentBlueprintProtocol.Deployment.Observations{now: ~U[2026-08-21T00:00:00Z], max_attestation_age_ms: 86_400_000, observed: %{}}
inputs = %AgentBlueprintProtocol.Reconcile.Inputs{host_bounds: host_bounds, support: support, keys: [], protected_clamp: :acknowledge, observations: observations}
{:ok, evidence} = AgentBlueprintProtocol.reconcile(blueprint, deployment, inputs)
length(evidence.not_verified) # => 7
```

Those seven are the point: tenancy, live policy, authority, effect
ownership, execution, billing, evaluation truth — the surfaces this
protocol structurally cannot establish, named in every result. Your
admission decision consumes `evidence.checks`, `evidence.clamps`, and
`evidence.not_verified`; nothing in the record makes it for you.
