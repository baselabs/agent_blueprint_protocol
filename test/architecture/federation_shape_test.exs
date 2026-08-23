defmodule AgentBlueprintProtocol.Architecture.FederationShapeTest do
  @moduledoc """
  Mapping-integrity + engine-reuse gates for the federation surface
  (the federation design note's shape folds):

  - the mapping data and the envelope's field table are bijective (row
    logical_field ⇔ wire member) with the live-re-derived verdict counts
    3 native / 5 partial / 15 extension — the published table and the
    implemented codecs cannot drift apart silently;
  - `federation.ex` validates through the shared Registry engine and
    defines none of the engine's stage functions locally (the engine-reuse
    no-second-pipeline invariant, beam-enforced like Deployment's).
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{ArchitectureScan, Federation}

  @beam "_build/test/lib/agent_blueprint_protocol/ebin/Elixir.AgentBlueprintProtocol.Federation.beam"
  @source "lib/agent_blueprint_protocol/federation.ex"

  @engine_stage_names [
    "unknown_check",
    "required_check",
    "type_check",
    "constraint_check",
    "cardinality_check",
    "recursion_check",
    "hook_check",
    "spec_type",
    "spec_constraint",
    "spec_recursion",
    "kind_ok?",
    "duplicate_keys?",
    "recurse",
    "element_ok?"
  ]

  test "mapping rows and envelope members are bijective" do
    rows = Federation.mapping()
    assert length(rows) == 23

    row_fields = rows |> Enum.map(& &1.logical_field) |> MapSet.new()
    member_names = Federation.envelope_members() |> MapSet.new()

    assert row_fields == member_names,
           "every mapping row must name exactly one envelope wire member"

    assert MapSet.size(row_fields) == 23, "logical fields are unique"
  end

  test "verdict counts are the live-re-derived 3 native / 5 partial / 15 extension" do
    counts =
      Federation.mapping()
      |> Enum.group_by(& &1.verdict, & &1.logical_field)
      |> Map.new(fn {verdict, fields} -> {verdict, length(fields)} end)

    assert counts == %{native: 3, partial: 5, extension: 15}
  end

  test "every row carries both transport locations" do
    for row <- Federation.mapping() do
      assert is_binary(row.a2a_location) and row.a2a_location != ""
      assert is_binary(row.mcp_location) and row.mcp_location != ""
    end
  end

  test "federation.ex delegates validation to the generic engine" do
    census = ArchitectureScan.beam_remote_calls(@beam)

    assert {AgentBlueprintProtocol.Registry, :validate} in census,
           "Federation must validate through Registry.validate — no second pipeline"
  end

  test "federation.ex defines none of the engine's stage functions locally" do
    source = File.read!(@source)
    {:ok, ast} = Code.string_to_quoted(source)

    {_ast, defined} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [{name, _ctx, _args} | _]} = node, acc when kind in [:def, :defp] ->
          {node, [Atom.to_string(name) | acc]}

        node, acc ->
          {node, acc}
      end)

    shadowed = Enum.filter(@engine_stage_names, &(&1 in defined))

    assert shadowed == [],
           "federation.ex locally defines engine stage functions #{inspect(shadowed)}"
  end
end

defmodule AgentBlueprintProtocol.FacadeFederationTest do
  @moduledoc """
  The facade's federation rows (the carrier-codec rows): delegates only,
  with the deny-typed rim pattern.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol
  alias AgentBlueprintProtocol.{Federation, FederationFixture}

  describe "decode_federation_envelope/2" do
    test "delegates to Federation.decode with default bounds" do
      bytes = FederationFixture.bytes()

      assert {:ok, env} = AgentBlueprintProtocol.decode_federation_envelope(bytes)
      assert {:ok, ^bytes} = Federation.canonical_bytes(env)
    end

    test "tightened bounds delegate through" do
      bytes = FederationFixture.bytes()
      tiny = struct!(AgentBlueprintProtocol.Bounds.maximum(), bytes: 8)

      assert {:error, _} = AgentBlueprintProtocol.decode_federation_envelope(bytes, tiny)
    end

    test "non-binary rims deny :invalid_type" do
      for bad <- [nil, 42, []] do
        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 AgentBlueprintProtocol.decode_federation_envelope(bad)
      end
    end
  end

  describe "federation_mapping/0" do
    test "delegates to Federation.mapping" do
      assert AgentBlueprintProtocol.federation_mapping() == Federation.mapping()
      assert length(AgentBlueprintProtocol.federation_mapping()) == 23
    end
  end
end
