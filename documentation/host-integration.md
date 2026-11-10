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
Enum.take(evidence.not_verified, 7) # => [:tenancy, :live_policy, :authority, :effect_ownership, :execution, :billing, :evaluation_truth]
```

Those seven are the point: tenancy, live policy, authority, effect
ownership, execution, billing, evaluation truth — the surfaces this
protocol structurally cannot establish, named in every result. Your
admission decision consumes `evidence.checks`, `evidence.clamps`, and
`evidence.not_verified`; nothing in the record makes it for you.

## Exact pins and replay identity

If you pin an exact release and persist verification identity across
imports (replaying a stored binding against a re-verified import), do
not equality-compare every identity field forever: partition along the
protocol's published line — replay identity (`manifest_version`,
`verification_semantics_version`, `protocol_revision`,
`registry_digest`, the artifact digests, `effective_bounds`) versus
provenance metadata (`package_version`, package checksum,
`corpus_digest`, `spec_digest`) — so a census-only release upgrade
replays your history green while any true semantics change conflicts
loudly. The partition, the semantics-version contract, and why a
registry-digest conflict is the fail-closed detector working (not a
break) live in the [upgrading guide](upgrading.md).

An unsigned artifact is accepted with an unverified signatures check and
`:no_signatures_present` detail. A successful signatures check names the
distinct verifying key_ids in `Evidence.Signatures`. `Evidence.Binding`
lists performed and skipped checks; absent or unrelated observations do
not establish freshness or descriptor equality. False checks and skipped
surfaces appear in `not_verified`.

`signature_created_at`, `lifecycle_state`, `key_time_validity`, and
`signature_time_validity` also appear there. Signed timestamps are format-
checked; lifecycle state is shape-checked. Reconcile judges neither.

Despite its name, `effect_impact_ceiling` is an obligation. The strictest
source value wins; a Blueprint's `secret` remains `secret` when deployment
and host declare `ordinary`, with no clamp under the deny posture.
