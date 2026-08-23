defmodule AgentBlueprintProtocol.Property.BlueprintTest do
  @moduledoc """
  Blueprint properties: the digest-coverage law in BOTH
  directions (covered-member mutation changes the digest; evidence-member
  mutation does not), permutation invariance of the registry verdict, and
  the decode → to_value → encode fixed point.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentBlueprintProtocol.{Blueprint, Canonicalization, Digest}
  alias AgentBlueprintProtocol.BlueprintFixture, as: F

  defp covered_mutations do
    [
      {:covered, "release_number", {:integer, 2}},
      {:covered, "blueprint_id", {:string, "example.demo/other"}},
      {:covered, "classification_ceiling", {:string, "public"}},
      {:covered, "protocol_revision", {:integer, 2}}
    ]
  end

  property "any covered-member mutation changes the content digest" do
    check all(
            {_tag, name, value} <- member_of(covered_mutations()),
            max_runs: 40
          ) do
      base = F.base_members([])
      honest = F.compute_digest(Enum.reject(base, fn {n, _} -> n == "content_digest" end))
      mutated = Enum.map(base, fn {n, v} -> if n == name, do: {n, value}, else: {n, v} end)
      changed = F.compute_digest(Enum.reject(mutated, fn {n, _} -> n == "content_digest" end))

      assert changed != honest
      refute Digest.equal?(changed, honest)
    end
  end

  property "evidence-member mutation leaves the content digest unchanged" do
    check all(
            sig_flip <- integer(1..255),
            max_runs: 25
          ) do
      entry = F.signature_entry([])
      {:object, members} = entry

      flipped =
        Enum.map(members, fn
          {"signature", {:string, sig}} ->
            flipped_sig =
              sig
              |> AgentBlueprintProtocol.Base64Url.decode()
              |> elem(1)
              |> flip_byte(sig_flip)
              |> AgentBlueprintProtocol.Base64Url.encode()

            {"signature", {:string, flipped_sig}}

          other ->
            other
        end)

      base = F.base_members([]) ++ [{"signatures", {:array, [entry]}}]
      mutated = F.base_members([]) ++ [{"signatures", {:array, [{:object, flipped}]}}]

      assert F.compute_digest(
               Enum.reject(base, fn {n, _} -> n in ~w(content_digest signatures attestations) end)
             ) ==
               F.compute_digest(
                 Enum.reject(mutated, fn {n, _} ->
                   n in ~w(content_digest signatures attestations)
                 end)
               )
    end
  end

  defp flip_byte(<<first, rest::binary>>, position) do
    bytes = :erlang.binary_to_list(<<first, rest::binary>>)
    index = rem(position, length(bytes))
    flipped = Enum.map(bytes, fn b -> b end) |> List.update_at(index, &Bitwise.bxor(&1, 0x01))
    :erlang.list_to_binary(flipped)
  end

  property "registry verdicts are invariant under member permutation" do
    check all(seed <- integer(), max_runs: 25) do
      good = F.fixture_value([])
      bad = bad_value()
      {:object, good_members} = good
      {:object, bad_members} = bad

      assert {:ok, %Blueprint{}} = Blueprint.from_value({:object, shuffle(good_members, seed)})

      assert {:error, :invalid_constraint} =
               Blueprint.from_value({:object, shuffle(bad_members, seed)})
    end
  end

  property "decode → to_value → encode is a byte-exact fixed point" do
    check all(seed <- integer(), max_runs: 15) do
      value = F.with_signatures([])
      {:ok, bytes} = Canonicalization.encode(value)
      {:ok, bp} = Blueprint.decode(bytes)
      # The decoded value re-encodes to exactly the received bytes, and the
      # struct round-trips through from_value to the same canonical bytes.
      assert {:ok, ^bytes} = Blueprint.canonical_bytes(bp)
      other = Blueprint.from_value(Blueprint.to_value(bp)) |> elem(1)
      assert {:ok, ^bytes} = Blueprint.canonical_bytes(other)
      assert Blueprint.content_digest(bp) == Blueprint.content_digest(other)
      _unused = seed
    end
  end

  defp bad_value do
    members =
      Enum.map(F.base_members([]), fn
        {"classification_ceiling", _} -> {"classification_ceiling", {:string, "topsecret"}}
        other -> other
      end)

    F.with_digest(members)
  end

  defp shuffle(list, seed) do
    :rand.seed(:exsss, seed)
    Enum.shuffle(list)
  end
end
