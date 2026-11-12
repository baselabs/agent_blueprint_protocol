# Host integration

This guide is for applications that consume Blueprint/Deployment pairs. It assembles every host input, runs reconciliation, and distinguishes checks that ran from checks left unverified. Run the Elixir examples in `iex -S mix` in a project with the [package installed](quickstart.md). The [host import Livebook](../docs/livebooks/host-import.livemd) runs the full sequence, including absent, partial, complete, mismatched, and stale observations.

## Where inputs come from

| Input | Host source | Elixir / TypeScript |
|---|---|---|
| Artifact bytes | The producer's exact canonical release files | `binary()` / `Uint8Array` or UTF-8 string |
| Decoder ceilings | Host input-size and complexity configuration | `Bounds` or map / `{bounds: Bounds}` |
| Revision and required core-field support | Revisions and digest-covered core fields the host actually implements | `Negotiation.Support` with `MapSet`s / `Support` with `Set`s |
| Registrations and held schemas | Host-managed namespace registrations and matching schema documents | `support.registry`, `support.schemas`; see [extensions](extensions.md#register-a-namespace-with-the-host) |
| Public keys | The host's trusted public-key inventory, obtained independently of the artifact | `Signature.PublicKey` with raw 32-byte `key` / `PublicKey` with `Uint8Array` |
| All thirteen host bounds | The host's configured operational limits and protected posture | `BoundsAlgebra.BoundSet` / `BoundSet` |
| Protected clamp posture | Host choice to deny or acknowledge protected narrowing | `:deny` or `:acknowledge` / `"deny"` or `"acknowledge"` |
| Build identities | Host inventory of installed builds | `Compatibility.Observed` / `Observed`; exact `kind`, `name`, `version`, `digest` tuples |
| Descriptor observations | Host inventory of the tool descriptors being compared | `Deployment.Observations.observed` / `Observations.observed`; logical-operation-to-tagged-digest map |
| Observation time and age | Host clock and configured maximum age of binding timestamps | `DateTime` and integer milliseconds / timestamp string and integer milliseconds |

Never construct production observations by copying the declarations being checked. The notebooks explicitly use fixture observations from the example so they are self-contained. That demonstrates the comparison API, not independent discovery. In an integration, obtain build identities and descriptor digests from the host's own inventory and host bounds from its configured limits. Keys inside conformance fixtures are public test data, not a production trust source.

## Set decoder bounds

Build a parsing profile before reading artifacts. This is independent of the thirteen operational and protected host bounds:

```elixir
{:ok, profile} = AgentBlueprintProtocol.Bounds.new(%{depth: 32})
profile.depth # => 32
```

## Decode the installed samples

```elixir
alias AgentBlueprintProtocol.{BoundsAlgebra, Compatibility, Deployment, Reconcile}
alias AgentBlueprintProtocol.Negotiation.Support

dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
blueprint_bytes = File.read!(Path.join(dependency_root, "examples/echo-blueprint.json"))
deployment_bytes = File.read!(Path.join(dependency_root, "examples/echo-deployment.json"))
{:ok, blueprint} = AgentBlueprintProtocol.decode_blueprint(blueprint_bytes, %{depth: 32})
{:ok, deployment} = AgentBlueprintProtocol.decode_deployment(deployment_bytes, %{depth: 32})
```

Decoder ceilings are separate from resource bounds. They can only tighten the protocol maxima: bytes `5_000_000`, depth `64`, members `1_000`, items `10_000`, nodes `200_000`, string bytes `100_000`, key bytes `1_000`, and number-lexeme bytes `64`. Unknown keys or invalid limits deny. Decoding checks structure, portability, canonical bytes, and declared digest; it does not verify signatures.

## Configure all thirteen bounds

The following values are explicit example host configuration. Keep the variables from the preceding block:

```elixir
{:ok, host_bounds} =
  BoundsAlgebra.BoundSet.new(%{
    max_attempts: 2,
    max_concurrency: 2,
    max_cost: %{amount: 1000, currency: "USD"},
    max_depth: 8,
    max_descendants: 64,
    max_elapsed_ms: 60_000,
    max_fan_out: 4,
    max_tokens: 100_000,
    classification_ceiling: %{ordinal: :internal, markers: MapSet.new()},
    disclosure_ceiling: :none,
    effect_impact_ceiling: :ordinary,
    authority_trait: :none,
    approval_trait: :none
  })
```

The first eight fields are operational maxima. Cost is integer millionths of the named currency unit; currencies must agree. The remaining five are protected bounds: classification plus markers, disclosure, effect impact, authority trait, and approval trait. Intersection never widens a source. Operational narrowing records clamps; protected narrowing denies unless explicitly acknowledged. All three sources must supply all thirteen fields for intersection even though `BoundSet.new/1` can construct a partial value. The npm `BoundSet` uses the same field names, string enum values, and `classification_ceiling: {ordinal: "internal", markers: []}`.

## Reconcile with explicit support and keys

```elixir
support = %Support{
  revisions: MapSet.new([1]),
  core_fields: MapSet.new(),
  registry: %{},
  schemas: %{}
}

inputs = %Reconcile.Inputs{
  host_bounds: host_bounds,
  support: support,
  keys: [],
  protected_clamp: :acknowledge,
  observations: %Deployment.Observations{}
}

{:ok, evidence} = AgentBlueprintProtocol.reconcile(blueprint, deployment, inputs)
{:ok, effective} = BoundsAlgebra.BoundSet.to_map(evidence.effective_bounds)
2 = effective.max_attempts
```

The shipped samples are unsigned, so empty keys succeed with separate unverified signature checks for `subject: ["blueprint"]` and `["deployment"]`. For signed files, supply trusted `%Signature.PublicKey{key_id: ..., algorithm: :ed25519, key: raw_bytes}` records (npm: `{keyId, algorithm: "ed25519", key}`). A signed Blueprint and unsigned Manifest leave the global signatures surface unverified. See the [subject-aware reader](reading-evidence.md) and [signed producer pair](compose-and-sign.md).

`core_fields`/`coreFields` is not a list to copy from the artifact. It names supported core semantics; requesting an unsupported or non-digest-covered field denies. Custom critical extensions need both a registration and the pinned held schema. Reconciliation derives validated critical namespaces itself.

## Compare observations and freshness

Build compatibility is a separate call: `verify_compatibility(deployment, %Compatibility.Observed{identities: inventory})` or `verifyCompatibility(deployment, {identities: inventory})`. Its success is Evidence. Reconciliation does not run this build-inventory comparison for you.

For descriptor observations, missing entries skip those comparisons; present entries are checked and a mismatch denies. Only complete coverage adds `:binding_descriptors` to `Evidence.Binding.checked`. No observations, partial observations, and full descriptors without a clock can all return `{:ok, evidence}`. Their binding check remains `verified: false` while any optional kind is skipped. Inspect its `checked`, `not_verified`, and outer `verified` fields.

Continuing the example, this explicitly labeled fixture copies the example's descriptor declarations, then changes one digest to demonstrate denial:

```elixir
manifest = JSON.decode!(deployment_bytes)

fixture_observed =
  Map.new(manifest["tool_bindings"], &{&1["logical_operation"], &1["descriptor_digest"]})

other_digest =
  AgentBlueprintProtocol.Digest.to_tagged(
    AgentBlueprintProtocol.Digest.hash(:blueprint_content, "different descriptor fixture")
  )

operation = fixture_observed |> Map.keys() |> Enum.sort() |> hd()
mismatch = Map.put(fixture_observed, operation, other_digest)

{:error, %AgentBlueprintProtocol.Error{code: :binding_descriptor_mismatch}} =
  Deployment.verify_binding(deployment, blueprint, %Deployment.Observations{observed: mismatch})

fresh = %Deployment.Observations{
  observed: fixture_observed,
  now: ~U[2026-08-20 00:00:01Z],
  max_attestation_age_ms: 1_000
}

{:ok, fresh_evidence} =
  AgentBlueprintProtocol.reconcile(blueprint, deployment, %{inputs | observations: fresh})

binding =
  Enum.find(fresh_evidence.checks, &(&1.surface == :bind and &1.subject == ["deployment"]))

true = binding.verified

{:error, %AgentBlueprintProtocol.Error{code: :binding_attestation_stale}} =
  AgentBlueprintProtocol.reconcile(blueprint, deployment, %{
    inputs
    | observations: %{fresh | now: ~U[2026-08-20 00:00:02Z]}
  })
```

In TypeScript the corresponding fresh observation is `{observed: inventory, now: "2026-08-20T00:00:01Z", maxAttestationAgeMs: 1000}`. Use `null` for omitted clock/age inputs; Elixir uses `nil`. The deterministic time above fits the example's fixed binding timestamps. A real host supplies its current clock and chosen age limit.

## Read evidence and preserve host boundaries

Read both artifact subjects, effective bounds, every clamp, retained extensions, and the nonempty `not_verified` list. Signature creation time and lifecycle state remain unverified by reconciliation. Tenancy, live policy, authority, effect ownership, execution, billing, and evaluation truth remain host-owned. Protocol evidence does not make those local decisions.

- [Read typed evidence](reading-evidence.md)
- [Handle typed denials](handling-errors.md)
- [TypeScript runnable reconciliation and JSON detail readers](typescript.md)
- [Check artifacts in CI](verifying-in-ci.md)
