defmodule AgentBlueprintProtocol.Architecture.DeploymentEngineShapeTest do
  @moduledoc """
  Engine-reuse gate for the Deployment table (the engine-reuse spec + the
  acceptance line: "Deployment = the 19-member table on the SAME engine — no
  second pipeline"). Two checkable assertions:

  - `deployment.ex`'s decode path DOES delegate to the generic engine (its
    beam remote-calls `Registry.validate`);
  - its source defines NONE of the engine's stage functions locally, public
    or private (a copied walk would shadow the engine's pinned precedence —
    the drift the engine exists to prevent). Checked against the parsed AST:
    the beam's exports table lists public functions only, so a private
    copied stage would otherwise hide (found by the planted-red mutation
    during the surface's build).

  Planted-red proof (the reuse tripwire): inlining a copied `defp type_check/2`
  into `deployment.ex` reds the second assertion.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.ArchitectureScan

  @beam "_build/test/lib/agent_blueprint_protocol/ebin/Elixir.AgentBlueprintProtocol.Deployment.beam"
  @source "lib/agent_blueprint_protocol/deployment.ex"

  # The engine's stage/kind vocabulary — locally defining any of these in an
  # artifact module is the "second pipeline" smell.
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

  test "deployment.ex delegates validation to the generic engine" do
    census = ArchitectureScan.beam_remote_calls(@beam)

    assert {AgentBlueprintProtocol.Registry, :validate} in census,
           "Deployment must validate through Registry.validate — no second pipeline"
  end

  test "deployment.ex defines none of the engine's stage functions locally" do
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
           "deployment.ex locally defines engine stage functions #{inspect(shadowed)} — the engine's pinned precedence must not be forked"
  end
end
