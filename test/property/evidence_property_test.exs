defmodule AgentBlueprintProtocol.Property.EvidenceTest do
  @moduledoc """
  The Evidence record's host-owned non-establishment laws:
  `not_verified` is non-empty BY CONSTRUCTION — the seven host-owned atoms
  are unioned in by the constructor, never passed — and it only grows
  across producing paths (caller extras add; no path removes).

  The seven are pinned from the spec text, not from the implementation's
  constant — the constructor mutation red (delete one atom from the module
  constant) must fail these properties.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentBlueprintProtocol.{
    Blueprint,
    BlueprintFixture,
    BoundsAlgebra,
    Compatibility,
    Deployment,
    DeploymentFixture,
    Evidence,
    Reconcile
  }

  alias AgentBlueprintProtocol.Deployment.Observations
  alias AgentBlueprintProtocol.Negotiation.Support

  @seven ~w(tenancy live_policy authority effect_ownership execution billing evaluation_truth)a

  defp extras do
    gen all(names <- list_of(atom(:alphanumeric), min_length: 0, max_length: 8)) do
      names |> Enum.reject(&(&1 in @seven)) |> Enum.uniq()
    end
  end

  property "every Evidence the constructor can produce names all seven host-owned atoms" do
    check all(extra <- extras()) do
      assert {:ok, %Evidence{} = evidence} = Evidence.build(not_verified: extra)
      assert MapSet.subset?(MapSet.new(@seven), MapSet.new(evidence.not_verified))
    end
  end

  property "not_verified only grows: caller extras are unioned in, never dropped" do
    check all(extra <- extras()) do
      assert {:ok, %Evidence{} = evidence} = Evidence.build(not_verified: extra)
      assert MapSet.subset?(MapSet.new(extra), MapSet.new(evidence.not_verified))
    end
  end

  property "the bare constructor carries exactly the seven, extras append after them" do
    check all(extra <- extras(), max_runs: 50) do
      assert {:ok, %Evidence{not_verified: listed}} = Evidence.build(not_verified: extra)
      assert Enum.take(listed, 7) == @seven
      assert Enum.drop(listed, 7) == extra
    end
  end

  property "every producing path carries the seven: compatibility verification" do
    check all(_seed <- integer(), max_runs: 25) do
      deployment =
        DeploymentFixture.fixture_value([])
        |> Deployment.from_value()
        |> elem(1)

      assert {:ok, %Evidence{not_verified: not_verified}} =
               Compatibility.verify(deployment, observed())

      assert MapSet.subset?(MapSet.new(@seven), MapSet.new(not_verified))
    end
  end

  property "every producing path carries the seven: the composed reconcile pass" do
    check all(_seed <- integer(), max_runs: 10) do
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

      assert {:ok, %Evidence{not_verified: not_verified}} =
               Reconcile.reconcile(blueprint, deployment, inputs)

      # :acknowledge keeps the default pair green (its protected
      # disclosure narrowing is acknowledged, the algebra's documented
      # law) — so the seven-atom law is assertable on this path directly.
      assert MapSet.subset?(MapSet.new(@seven), MapSet.new(not_verified))
    end
  end

  defp observed do
    %Compatibility.Observed{
      identities: [
        %{
          kind: "package",
          name: "agent_blueprint_protocol",
          version: "0.1.0",
          digest: DeploymentFixture.tagged("identity")
        }
      ]
    }
  end
end
