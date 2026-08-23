defmodule AgentBlueprintProtocol.Architecture.SchemaShapeTest do
  @moduledoc """
  Structural tripwire for the bounded dialect's DoS/SSRF posture (base §6.2
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

  test "red-capability: the census catches every evasion form a name scan cannot" do
    # Three planted evasion forms — renamed aliases, variable-indirected
    # module calls, and full dynamic apply with a constructed module name.
    # A text scan for spellings sees only `C.` and `m.`; the beam census
    # resolves all three to their targets, so the exact-set test above
    # would red on each by construction.
    planted = """
    defmodule Planted.Evasion do
      alias :crypto, as: C
      alias Regex, as: R

      def renamed(x), do: C.sign(:eddsa, :none, x, [])
      def regexed(s), do: R.run(~r/a/, s)

      def variable_indirected(x) do
        m = :crypto
        m.sign(:eddsa, :none, x, [])
      end

      def fully_dynamic(prefix) do
        mod = String.to_atom(prefix <> "pto")
        apply(mod, :sign, [:eddsa, :none, <<>>, []])
      end

      def runtime_dynamic(m), do: apply(m, :sign, [])
    end
    """

    dir = Path.join(System.tmp_dir!(), "abp-planted-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "planted.ex"), planted)

    {_, 0} =
      System.cmd("elixirc", ["-o", dir, Path.join(dir, "planted.ex")],
        cd: dir,
        stderr_to_stdout: true
      )

    beam = Path.join(dir, "Elixir.Planted.Evasion.beam")
    census = ArchitectureScan.beam_remote_calls(beam)

    assert {:crypto, :sign} in census,
           "renamed-alias or variable-indirected :crypto.sign not seen"

    assert {Regex, :run} in census, "renamed Regex not seen"

    # a CONSTANT-constructed module name folds at compile time into the
    # direct crypto call already caught above; a module from an ARGUMENT
    # stays dynamic and surfaces as the banned :erlang.apply, and runtime
    # atom construction compiles to the banned :erlang.binary_to_atom
    assert {:erlang, :apply} in census, "runtime apply not seen"
    assert {:erlang, :binary_to_atom} in census, "constructed module name not seen"

    # and the same exact-set rule applied to the planted census reds:
    # none of the planted targets are members of the frozen allowlist
    for target <- [:crypto, Regex] do
      assert target not in @allowed_modules
    end

    File.rm_rf!(dir)
  end
end
