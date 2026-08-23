defmodule AgentBlueprintProtocol.Conformance.BlueprintTest do
  @moduledoc """
  Corpus-row classes for the `blueprint.decode` surface (the surface's
  acceptance lines): each class is red-capable against the named failure —
  the conformance corpus ports these rows into `priv/conformance`.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Blueprint, Canonicalization, Digest}
  import AgentBlueprintProtocol.BlueprintFixture, only: [base_members: 1, fixture_bytes: 1]

  @window_float {:float, 9.007_199_254_740_992e15}

  defp bytes(members), do: Canonicalization.encode(fake_digest(members)) |> elem(1)

  defp fake_digest(members) do
    {:object,
     [
       {"content_digest", {:string, Digest.to_tagged(Digest.hash(:blueprint_content, "x"))}}
       | Enum.sort(members)
     ]}
  end

  defp replace(members, name, value) do
    Enum.map(members, fn
      {^name, _} -> {name, value}
      other -> other
    end)
  end

  test "valid: the complete honest artifact" do
    assert {:ok, %Blueprint{}} = Blueprint.decode(fixture_bytes([]))
  end

  test "invalid: required member absent" do
    members = Enum.reject(base_members([]), fn {n, _} -> n == "producer" end)
    assert {:error, :missing_required_field} = Blueprint.decode(bytes(members))
  end

  test "invalid: unknown member" do
    members = base_members([]) ++ [{"mystery", {:integer, 1}}]
    assert {:error, :unknown_member} = Blueprint.decode(bytes(members))
  end

  test "invalid: enum boundary" do
    members = replace(base_members([]), "classification_ceiling", {:string, "topsecret"})
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes(members))
  end

  test "invalid: cardinality plus-one" do
    ports =
      Enum.map(1..65, fn i ->
        AgentBlueprintProtocol.BlueprintFixture.port("p#{i}")
      end)

    members = replace(base_members([]), "input_ports", {:array, ports})
    assert {:error, :invalid_cardinality} = Blueprint.decode(bytes(members))
  end

  test "invalid_type: window float in an integer-typed core field" do
    members = replace(base_members([]), "release_number", @window_float)
    assert {:error, :invalid_type} = Blueprint.decode(bytes(members))
  end

  test "digest_mismatch: tamper_meaningful_byte on a covered member" do
    honest =
      AgentBlueprintProtocol.BlueprintFixture.compute_digest(
        Enum.reject(base_members([]), fn {n, _} -> n == "content_digest" end)
      )

    tampered =
      replace(base_members([]), "release_number", {:integer, 2})
      |> AgentBlueprintProtocol.BlueprintFixture.with_digest(
        declared_digest: Digest.to_tagged(honest)
      )

    {:ok, bytes} = Canonicalization.encode(tampered)
    assert {:error, :digest_mismatch} = Blueprint.decode(bytes)
  end

  test "forbidden_portable_value: never-portable class in a core position" do
    members =
      base_members(
        toolchain: "-----" <> "BEGIN PRIVATE KEY-----\nMIIEvQ\n-----" <> "END PRIVATE KEY-----"
      )

    assert {:error, :forbidden_portable_value} = Blueprint.decode(bytes(members))
  end

  test "non_canonical_bytes: reordered serialization of an honestly digested artifact" do
    {:object, members} = AgentBlueprintProtocol.BlueprintFixture.fixture_value([])

    inner =
      members
      |> Enum.reverse()
      |> Enum.map_join(",", fn {name, value} ->
        {:ok, k} = Canonicalization.encode({:string, name})
        {:ok, v} = Canonicalization.encode(value)
        k <> ":" <> v
      end)

    assert {:error, :non_canonical_bytes} = Blueprint.decode("{" <> inner <> "}")
  end
end
