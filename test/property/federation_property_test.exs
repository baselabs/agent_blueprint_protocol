defmodule AgentBlueprintProtocol.FederationPropertyTest do
  @moduledoc """
  Properties of the federation carrier codecs (the federation design note):
  byte-stable round-trips on both transports for every state-carrying
  fixture variant, carrier-shape placement (native homes populated, native
  members never in the body), and JCS recanonicalization under member
  reordering — the transports reserialize freely, so only the canonical
  form can be load-bearing.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentBlueprintProtocol.{Canonicalization, Federation, FederationFixture}

  defp state_carrying_variant do
    # Every state-carrying fixture variant: terminal and checkpoint, with
    # and without the parent members.
    [
      [checkpoint: true],
      [terminal: true],
      [parent: true, checkpoint: true],
      [parent: true, terminal: true],
      [checkpoint: true, checkpoint_status: "input_required"],
      [terminal: true, terminal_state: "failed"],
      [terminal: true, terminal_state: "canceled"]
    ]
  end

  property "carrier round-trips are byte-stable on both transports" do
    check all(opts <- member_of(state_carrying_variant())) do
      bytes = FederationFixture.bytes(opts)
      {:ok, env} = Federation.decode(bytes)

      assert {:ok, carrier} = Federation.to_a2a_carrier(env)
      assert {:ok, back} = Federation.from_a2a_carrier(carrier)
      assert Federation.canonical_bytes(back) == {:ok, bytes}

      assert {:ok, mcp} = Federation.to_mcp_carrier(env)
      assert {:ok, back_mcp} = Federation.from_mcp_carrier(mcp)
      assert Federation.canonical_bytes(back_mcp) == {:ok, bytes}
    end
  end

  property "native members never ride the extension body, and native homes are populated" do
    check all(opts <- member_of(state_carrying_variant())) do
      {:ok, env} = Federation.decode(FederationFixture.bytes(opts))
      members = Federation.member_map(env)

      for {carrier_fn, body_home, id_home} <- [
            {&Federation.to_a2a_carrier/1, "metadata", "id"},
            {&Federation.to_mcp_carrier/1, "_meta", "taskId"}
          ] do
        {:ok, carrier} = carrier_fn.(env)
        {:object, carrier_members} = carrier

        # The native id home is populated with the task identity.
        assert List.keyfind(carrier_members, id_home, 0) == {id_home, members["task_identity"]}

        # The body under the transport's carrier key excludes every native
        # member name, whatever the variant's optional members are.
        {^body_home, {:object, [{_key, {:object, body}} | _]}} =
          List.keyfind(carrier_members, body_home, 0)

        body_names = body |> Enum.map(&elem(&1, 0)) |> MapSet.new()

        for native <- ~w(task_identity recovery_handle checkpoint_status terminal_state) do
          refute MapSet.member?(body_names, native),
                 "#{native} must ride its native home, not the body"
        end
      end
    end
  end

  property "member reordering recanonicalizes to identical bytes" do
    check all(
            opts <-
              member_of([[checkpoint: true], [terminal: true], [parent: true, terminal: true]])
          ) do
      {:ok, env} = Federation.decode(FederationFixture.bytes(opts))
      {:ok, bytes} = Federation.canonical_bytes(env)

      # The transport's Struct does not preserve member order; shuffle and
      # re-encode — JCS must converge on the same bytes.
      {:object, members} = env.value
      shuffled = Enum.shuffle(members)
      {:ok, shuffled_bytes} = Canonicalization.encode({:object, shuffled})

      assert shuffled_bytes == bytes
    end
  end
end
