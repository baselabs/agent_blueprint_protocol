defmodule AgentBlueprintProtocol.Architecture.SchemaShapeTest do
  @moduledoc """
  Structural tripwire for the bounded dialect's DoS/SSRF posture (protocol §2.2
  row: "a regex-bearing or network-fetching schema is a
  denial-of-service and SSRF surface in a portable artifact").

  Enforced at the BEAM level, not by name scanning:
  `ArchitectureScan.beam_remote_calls/1` censuses every remote call the
  compiled module can make — aliases are expanded at compile time (a
  renamed alias cannot hide), compiler BIF rewrites are visible
  (`Map.has_key?` arrives as `:maps.find`), and dynamic dispatch surfaces
  as `:erlang.apply` which the gate bans. The allowlist is
  TWO-DIRECTIONAL and exact: an unknown module (regex engine, network
  client, anything not enumerated) reds, and a module dropping OUT of use
  reds the frozen set. There is no spelling to evade — `Regex`, `:re`,
  `:httpc` are simply not in the set.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.ArchitectureScan

  @beam "_build/test/lib/agent_blueprint_protocol/ebin/Elixir.AgentBlueprintProtocol.Schema.beam"

  # The exact, frozen set of modules the schema validator may call:
  # collection machinery, strings/lists, the struct/exception runtime, the
  # compiler's own call-site support, and the maps/erlang BIFs the stdlib
  # rewrites down to. No I/O, no regex, no network, no crypto.
  @allowed_modules [
    ArgumentError,
    Enum,
    Kernel,
    List,
    MapSet,
    Range,
    String,
    :elixir_erl_pass,
    :erlang,
    :maps
  ]

  # Reach-mechanisms banned even inside allowlisted modules: dynamic
  # dispatch and atom construction close the apply/constructed-module-name
  # evasion; process/port spawning closes sideways execution.
  @banned_calls [
    {:erlang, :apply},
    {:erlang, :spawn},
    {:erlang, :spawn_link},
    {:erlang, :spawn_request},
    {:erlang, :open_port},
    {:erlang, :binary_to_atom},
    {:erlang, :binary_to_existing_atom},
    {String, :to_atom},
    {String, :to_existing_atom}
  ]

  test "schema.ex's beam calls exactly the frozen module set — nothing else is reachable" do
    census = ArchitectureScan.beam_remote_calls(@beam)

    used_modules = census |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
    expected = Enum.sort(@allowed_modules)

    assert used_modules == expected,
           "schema module-set drift.\nunexpected: #{inspect(used_modules -- expected)}\n" <>
             "missing: #{inspect(expected -- used_modules)}"
  end

  test "no banned reach-mechanism (apply / atom construction / spawn) exists in the beam" do
    census = ArchitectureScan.beam_remote_calls(@beam)

    assert Enum.filter(census, &(&1 in @banned_calls)) == [],
           "banned dynamic-dispatch or atom-construction call in the schema beam"
  end
end
