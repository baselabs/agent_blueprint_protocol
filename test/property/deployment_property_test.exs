defmodule AgentBlueprintProtocol.Property.DeploymentTest do
  @moduledoc """
  Deployment properties: the digest-coverage law in BOTH directions
  (covered-member mutation changes the deployment digest; evidence-member
  mutation does not), permutation invariance of the registry verdict, and
  the decode → to_value → encode fixed point.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentBlueprintProtocol.{Canonicalization, Deployment, Digest}

  import AgentBlueprintProtocol.DeploymentFixture,
    only: [base_members: 1, fixture_value: 1, with_digest: 1]

  property "covered-member mutation changes the deployment digest; evidence-member mutation does not" do
    members = Enum.sort(base_members([]))

    covered =
      Enum.reject(members, fn {n, _} -> n in ~w(deployment_digest signatures attestations) end)

    check all(index <- StreamData.integer(0..(length(covered) - 1))) do
      mutated =
        covered
        |> List.update_at(index, fn {n, _v} -> {n, {:integer, -1}} end)

      refute compute(mutated) == compute(covered)
    end

    assert compute(covered ++ [{"signatures", {:array, []}}]) == compute(covered)
    assert compute(covered ++ [{"attestations", {:array, []}}]) == compute(covered)
  end

  property "the registry verdict is invariant under member permutation" do
    check all(shuffle? <- StreamData.boolean()) do
      members = base_members([])
      ordered = if shuffle?, do: Enum.shuffle(members), else: members
      value = with_digest(ordered)
      assert {:ok, %Deployment{}} = Deployment.from_value(value)
    end
  end

  property "decode → to_value → encode → decode is a fixed point" do
    {:ok, bytes} = Canonicalization.encode(fixture_value([]))
    {:ok, deployment} = Deployment.decode(bytes)

    {:ok, round_tripped} = deployment |> Deployment.to_value() |> Canonicalization.encode()
    assert {:ok, ^round_tripped} = Canonicalization.encode(Deployment.to_value(deployment))
    assert Deployment.decode(round_tripped) == {:ok, deployment}
  end

  defp compute(members) do
    covered =
      Enum.reject(members, fn {n, _} -> n in ~w(deployment_digest signatures attestations) end)

    {:ok, jcs} = Canonicalization.encode({:object, Enum.sort(covered)})
    Digest.hash(:deployment_content, jcs)
  end
end
