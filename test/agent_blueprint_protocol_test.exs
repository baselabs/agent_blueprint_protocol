defmodule AgentBlueprintProtocolTest do
  use ExUnit.Case
  doctest AgentBlueprintProtocol

  test "negotiate/2 delegates through the facade" do
    import AgentBlueprintProtocol.BlueprintFixture, only: [base_members: 1]
    alias AgentBlueprintProtocol.{Blueprint, Negotiation}

    value = AgentBlueprintProtocol.BlueprintFixture.with_digest(base_members([]))

    support = %Negotiation.Support{
      revisions: MapSet.new([1]),
      core_fields: MapSet.new(~w(blueprint_id producer triggers))
    }

    assert {:ok, %Negotiation.Outcome{}} = AgentBlueprintProtocol.negotiate(value, support)
    {:ok, bp} = Blueprint.from_value(value)
    assert {:ok, %Negotiation.Outcome{}} = AgentBlueprintProtocol.negotiate(bp, support)
  end

  test "decode_deployment/2 delegates through the facade" do
    import AgentBlueprintProtocol.DeploymentFixture, only: [fixture_bytes: 1]
    alias AgentBlueprintProtocol.Deployment

    assert {:ok, %Deployment{}} = AgentBlueprintProtocol.decode_deployment(fixture_bytes([]))
  end

  test "intersect/1 delegates through the facade" do
    alias AgentBlueprintProtocol.{
      Blueprint,
      BlueprintFixture,
      BoundsAlgebra,
      Deployment,
      DeploymentFixture
    }

    alias AgentBlueprintProtocol.BoundsAlgebra.{Result, Sources}

    {:ok, blueprint} = Blueprint.decode(BlueprintFixture.fixture_bytes([]))
    {:ok, deployment} = Deployment.decode(DeploymentFixture.fixture_bytes([]))
    {:ok, bp_bounds} = BoundsAlgebra.from_blueprint(blueprint)
    {:ok, dep_bounds} = BoundsAlgebra.from_deployment(deployment)

    sources = %Sources{
      blueprint: bp_bounds,
      deployment: dep_bounds,
      host: dep_bounds,
      protected_clamp: :acknowledge
    }

    assert {:ok, %Result{}} = AgentBlueprintProtocol.intersect(sources)
  end

  test "verify_compatibility/2 delegates through the facade" do
    alias AgentBlueprintProtocol.{Compatibility.Observed, Deployment, DeploymentFixture}

    {:ok, deployment} =
      DeploymentFixture.fixture_value([])
      |> Deployment.from_value()

    observed = %Observed{
      identities: [
        %{
          kind: "package",
          name: "agent_blueprint_protocol",
          version: "0.1.0",
          digest: DeploymentFixture.tagged("identity")
        }
      ]
    }

    assert {:ok, %AgentBlueprintProtocol.Evidence{}} =
             AgentBlueprintProtocol.verify_compatibility(deployment, observed)
  end

  test "reconcile/3 delegates through the facade" do
    alias AgentBlueprintProtocol.{
      Blueprint,
      BlueprintFixture,
      BoundsAlgebra,
      Deployment,
      Deployment.Observations,
      DeploymentFixture,
      Negotiation.Support,
      Reconcile
    }

    {:ok, blueprint} =
      BlueprintFixture.fixture_value([])
      |> Blueprint.from_value()

    {:ok, deployment} =
      DeploymentFixture.fixture_value([])
      |> Deployment.from_value()

    {:ok, host} = BoundsAlgebra.from_deployment(deployment)

    inputs = %Reconcile.Inputs{
      host_bounds: host,
      support: %Support{revisions: MapSet.new([1])},
      keys: [],
      protected_clamp: :acknowledge,
      observations: %Observations{now: ~U[2026-08-21T00:00:00Z]}
    }

    # The default pair's observed identities are empty — the compatibility
    # stage is not part of reconcile (the facade exposes it separately), so
    # this delegate test asserts the composed pass reaches Evidence.
    assert {:ok, %AgentBlueprintProtocol.Evidence{}} =
             AgentBlueprintProtocol.reconcile(blueprint, deployment, inputs)
  end

  test "the facade delegates deny typed on malformed arguments (rim discipline)" do
    alias AgentBlueprintProtocol.Error

    assert {:error, %Error{code: :invalid_type, subject: ["blueprint"]}} =
             AgentBlueprintProtocol.reconcile(:junk, :junk, :junk)

    assert {:error, %Error{code: :invalid_type, subject: ["deployment"]}} =
             AgentBlueprintProtocol.reconcile(%AgentBlueprintProtocol.Blueprint{}, :junk, :junk)

    assert {:error, %Error{code: :invalid_type, subject: ["inputs"]}} =
             AgentBlueprintProtocol.reconcile(
               %AgentBlueprintProtocol.Blueprint{},
               %AgentBlueprintProtocol.Deployment{},
               :junk
             )

    assert {:error, %Error{code: :invalid_type, subject: ["deployment"]}} =
             AgentBlueprintProtocol.verify_compatibility(:junk, :junk)

    assert {:error, %Error{code: :invalid_type, subject: ["observed"]}} =
             AgentBlueprintProtocol.verify_compatibility(
               %AgentBlueprintProtocol.Deployment{},
               :junk
             )
  end

  test "the facade pass: canonical_bytes/1 + the negotiate/intersect rims" do
    alias AgentBlueprintProtocol.Error

    # canonical_bytes/1 delegates over all three artifacts (the carrier-codec
    # named gap, closed by the facade pass) — over DECODED
    # artifacts (an empty struct carries no value).
    assert {:ok, %AgentBlueprintProtocol.Blueprint{} = blueprint} =
             AgentBlueprintProtocol.decode_blueprint(
               AgentBlueprintProtocol.BlueprintFixture.fixture_bytes([])
             )

    assert {:ok, bytes} = AgentBlueprintProtocol.canonical_bytes(blueprint)
    assert bytes == AgentBlueprintProtocol.BlueprintFixture.fixture_bytes([])

    assert {:ok, %AgentBlueprintProtocol.Deployment{} = deployment} =
             AgentBlueprintProtocol.decode_deployment(
               AgentBlueprintProtocol.DeploymentFixture.fixture_bytes([])
             )

    expected_deployment = AgentBlueprintProtocol.DeploymentFixture.fixture_bytes([])
    assert {:ok, ^expected_deployment} = AgentBlueprintProtocol.canonical_bytes(deployment)

    assert {:ok, %AgentBlueprintProtocol.Federation{} = envelope} =
             AgentBlueprintProtocol.decode_federation_envelope(
               AgentBlueprintProtocol.FederationFixture.bytes(terminal: true)
             )

    assert {:ok, _} = AgentBlueprintProtocol.canonical_bytes(envelope)

    assert {:error, %Error{code: :invalid_type, subject: ["artifact"]}} =
             AgentBlueprintProtocol.canonical_bytes(:junk)

    # The earliest delegates raised on malformed args; the rim now denies
    # typed like verify_compatibility/reconcile always did.
    assert {:error, %Error{code: :invalid_type, subject: ["support"]}} =
             AgentBlueprintProtocol.negotiate(%AgentBlueprintProtocol.Blueprint{}, :junk)

    assert {:error, %Error{code: :invalid_type, subject: ["artifact"]}} =
             AgentBlueprintProtocol.negotiate(:junk, :junk)

    assert {:error, %Error{code: :invalid_type, subject: ["sources"]}} =
             AgentBlueprintProtocol.intersect(:junk)
  end

  test "the public root delegates exactly the frozen facade surface" do
    # Each facade row landed with its owning surface: decode with the
    # artifact surfaces, negotiate and intersect with their rims, the
    # composed import, and the federation codecs.
    # (the federation profile); the next facade function belongs to the
    # surface that owns it.
    assert AgentBlueprintProtocol.__info__(:functions) == [
             canonical_bytes: 1,
             decode_blueprint: 1,
             decode_blueprint: 2,
             decode_deployment: 1,
             decode_deployment: 2,
             decode_federation_envelope: 1,
             decode_federation_envelope: 2,
             federation_mapping: 0,
             intersect: 1,
             negotiate: 2,
             reconcile: 3,
             verify_compatibility: 2
           ]
  end
end
