defmodule AgentBlueprintProtocol.Architecture.ConstantTimeCompareShapeTest do
  @moduledoc """
  Structural tripwire for the constant-time comparison in `Digest.equal?/2`.

  The byte loop must consume EVERY byte pair and test the accumulated XOR
  once at the end. An early exit on the first differing byte is functionally
  identical — no output assertion can detect it — and quietly reintroduces
  the timing oracle the loop exists to prevent. This gate whitelists the
  exact AST shape of the two `xor_zero?` clauses (tail-accumulate; a single
  final accumulator test), so any value-conditional edit to the comparison
  reds the build. The public-shape pre-checks in `equal?/2` itself (length,
  algorithm) may short-circuit and are not restricted.

  Renaming the loop's variables updates this test with the rename; that
  coupling is the point — the shape IS the safety property.
  """

  use ExUnit.Case, async: true

  @source Path.expand("../../lib/agent_blueprint_protocol/digest.ex", __DIR__)

  test "the byte loop is exactly tail-accumulate with a single final test" do
    assert [recursive, base] = function_bodies(ast(), :xor_zero?)

    assert {:xor_zero?, _,
            [
              _,
              _,
              {{:., _, [{:__aliases__, _, [:Bitwise]}, :bor]}, _,
               [
                 {{:., _, [{:__aliases__, _, [:Bitwise]}, :bxor]}, _, [_, _]},
                 _
               ]}
            ]} = recursive

    assert {:==, _, [_, 0]} = base
  end

  test "equal? reaches the digest bytes only through the accumulating loop" do
    [equal_body] = function_bodies(ast(), :equal?)

    {_body, calls} =
      Macro.prewalk(equal_body, [], fn
        {name, _, args} = node, acc when is_atom(name) and is_list(args) ->
          {node, [name | acc]}

        node, acc ->
          {node, acc}
      end)

    assert :xor_zero? in calls
  end

  # ---- helpers ------------------------------------------------------------------

  defp ast do
    @source |> File.read!() |> Code.string_to_quoted!()
  end

  # The [do: body] blocks of every def/defp named `name`, in source order.
  defp function_bodies(ast, name) do
    {_ast, bodies} =
      Macro.prewalk(ast, [], fn
        {kind, _, [{^name, _, _}, [do: body]]} = node, acc when kind in [:def, :defp] ->
          {node, [body | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(bodies)
  end
end
