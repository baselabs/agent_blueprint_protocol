defmodule AgentBlueprintProtocol.Architecture.CliMainShapeTest do
  @moduledoc """
  Source-shape gate for the escript entry. `AgentBlueprintProtocol.Conformance.Cli.Main`
  is the one module excluded from the coverage census (executing main/1 in-process
  would halt the test VM), so prose was its only guard — this pin makes the
  "pure delegation" constraint mechanical: exactly one function, `main/1`, whose
  body is a single `System.halt(Cli.run(argv))`. Any logic added to Main reds
  here instead of shipping unobserved; relaxing the shape is a conscious gate
  change, not an accident.
  """
  use ExUnit.Case, async: true

  @main_path "lib/agent_blueprint_protocol/conformance/cli/main.ex"

  test "cli main is exactly one pure halt delegation (shape pin)" do
    ast = @main_path |> File.read!() |> Code.string_to_quoted!(file: @main_path)

    {_ast, defs} =
      Macro.prewalk(ast, [], fn
        {kind, _, [{name, _, args} | _]} = node, acc
        when kind in [:def, :defp] and is_list(args) ->
          {node, [{kind, name, args} | acc]}

        node, acc ->
          {node, acc}
      end)

    # Exactly one def, named main, taking exactly one PLAIN variable (arity-1,
    # no destructuring — `main(argv, opts)` and `main({argv, _})` both violate
    # the escript entry contract).
    assert [{:def, :main, [{arg_name, _, nil}]}] = defs
    assert is_atom(arg_name)

    [do: halt] = main_body(ast)

    assert {{:., _, [{:__aliases__, _, [:System]}, :halt]}, _,
            [{{:., _, [{:__aliases__, _, [:Cli]}, :run]}, _, [argv]}]} = halt

    assert is_atom(elem(argv, 0))
  end

  defp main_body(ast) do
    {_ast, bodies} =
      Macro.prewalk(ast, [], fn
        {:def, _, [{:main, _, _}, body]} = node, acc -> {node, [body | acc]}
        node, acc -> {node, acc}
      end)

    [body] = bodies
    body
  end
end
