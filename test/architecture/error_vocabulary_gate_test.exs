defmodule AgentBlueprintProtocol.Architecture.ErrorVocabularyGateTest do
  @moduledoc """
  The two-directional error-vocabulary gate: reachable codes == declared
  codes, in BOTH directions — an
  undeclared literal anywhere in lib/ is an open vocabulary (RED), and a
  declared code no site emits is dead vocabulary (RED — the defect class
  that hid the earlier surface's dead arms).

  The walk is a PER-SITE LITERAL RULE (design note F4), not a set-scan:
  every code position — a `%Error{code: X}` construction, a bare
  `{:error, X}` value, or json.ex's `throw({:abp_error, X})` plumbing —
  must be built only from literal atoms that are members of the declared
  vocabulary. Extracted builders are legal (missing_code/1's two-branch
  `if` resolves through the assignment), parameterized builders resolve
  through their call sites' literal arguments (json.ex's `guard/3`
  ceiling family and compatibility's `error/2`), and a code position
  whose expression constructs an atom dynamically (String.to_atom and
  kin — the interpolated-atom defeat) is a BUILD FAILURE.

  `Error.codes/0` is hand-maintained and never derived from this scan
  (the tautology guard); this test compares the two. The `{:ceiling,
  key}` family is declared as a family — its keys must equal Bounds' own
  limit-name set. The non-authorizing vocabulary gate lives in its own
  test (`NonAuthorizingVocabularyTest`); this gate covers closedness.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Bounds, Error}

  @atom_constructors [:to_atom, :to_existing_atom, :list_to_atom, :binary_to_atom, :concat]

  # ---- source model ------------------------------------------------------------------

  defp module_contexts do
    for path <- Path.wildcard("lib/**/*.ex") do
      quoted = path |> File.read!() |> Code.string_to_quoted!()
      funs = all_functions(quoted)
      {path, funs, positions(funs)}
    end
  end

  defp all_functions(quoted) do
    {_, acc} =
      Macro.prewalk(quoted, [], fn
        # Zero-arity heads quote their arg list as nil (not []).
        {kind, _, [{:when, _, [{name, _, args}, _guard]}, [do: body]]} = node, acc
        when kind in [:def, :defp] and (is_list(args) or is_nil(args)) ->
          {node, [function_entry(name, args, body) | acc]}

        {kind, _, [{name, _, args}, [do: body]]} = node, acc
        when kind in [:def, :defp] and (is_list(args) or is_nil(args)) ->
          {node, [function_entry(name, args, body) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  defp function_entry(name, args, body) do
    args = args || []

    %{
      name: name,
      arity: length(args),
      params: Enum.map(args, &param_name/1),
      body: body,
      assigns: body_assigns(body)
    }
  end

  defp param_name({name, _, _}) when is_atom(name), do: name
  defp param_name(_), do: nil

  defp body_assigns(body) do
    {_, acc} =
      Macro.prewalk(body, [], fn
        {:=, _, [{name, _, _}, rhs]} = node, acc when is_atom(name) ->
          {node, [{name, rhs} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  # Code positions per function scope: {scope, expr}.
  defp positions(funs) do
    Enum.flat_map(funs, fn fun ->
      {_, acc} =
        Macro.prewalk(fun.body, [], fn
          # Bare reason values and the ceiling family stay literal
          # 2-tuples in quoted AST when their elements are valid AST; an
          # error-wrapped struct positions on the struct's own code field.
          {:error, {:%, _, [_, {:%{}, _, inner_kv}]}} = node, acc ->
            record_position(node, acc, Keyword.fetch(inner_kv, :code))

          {:error, expr} = node, acc ->
            {node, [{:position, expr} | acc]}

          {:%, _, [_alias, {:%{}, _, kv}]} = node, acc ->
            record_position(node, acc, Keyword.fetch(kv, :code))

          # json.ex's internal throw plumbing: throw({:abp_error, X}) —
          # the arg parses as a keyword list or a bare tagged tuple,
          # depending on the payload's own shape.
          {:throw, _, [throw_arg]} = node, acc ->
            record_position(node, acc, abp_payload(throw_arg))

          node, acc ->
            {node, acc}
        end)

      for {:position, expr} <- Enum.reverse(acc), do: {fun, expr}
    end)
  end

  defp record_position(node, acc, {:ok, expr}), do: {node, [{:position, expr} | acc]}
  defp record_position(node, acc, :error), do: {node, acc}

  defp abp_payload(arg) when is_list(arg) do
    case Keyword.fetch(arg, :abp_error) do
      {:ok, expr} -> {:ok, expr}
      :error -> :error
    end
  end

  defp abp_payload({:abp_error, expr}), do: {:ok, expr}
  defp abp_payload(_), do: :error

  # ---- literal resolution -----------------------------------------------------------

  defp resolve(funs, expr, scope, depth \\ 0, family \\ false)

  defp resolve(_funs, expr, _scope, _depth, family) when is_atom(expr) do
    if expr in [nil, true, false], do: bucket([], family), else: bucket([expr], family)
  end

  # The ceiling family tuple: the tag is structural, the key is the payload.
  defp resolve(funs, {:ceiling, key}, scope, depth, _family) do
    resolve(funs, key, scope, depth, true)
  end

  # A bare variable: its assignment RHS in scope, else parameter
  # call-site literals.
  defp resolve(funs, {name, _, ctx}, scope, depth, family) when is_atom(ctx) or is_nil(ctx) do
    case List.keyfind(scope.assigns, name, 0) do
      {_name, rhs} when depth < 8 ->
        resolve(funs, rhs, scope, depth + 1, family)

      nil ->
        index = Enum.find_index(scope.params, &(&1 == name))

        if index == nil,
          do: bucket([], family),
          else: bucket(call_site_literals(funs, scope, index), family)
    end
  end

  defp resolve(funs, expr, scope, depth, family) do
    cond do
      dynamic_atom_construction?(expr) ->
        %{atoms: [], family: [], dynamic: true}

      callee = local_callee(funs, expr) ->
        bucket(callee_atoms(callee, funs, depth), family)

      true ->
        bucket(branch_atoms(expr, funs, scope, depth), family)
    end
  end

  # An extracted builder: the codes live in its clause bodies, with its
  # own scope (params resolve through ITS call sites).
  defp callee_atoms(callee, funs, depth) do
    callee
    |> Enum.flat_map(fn fun ->
      fun.body
      |> List.wrap()
      |> Enum.flat_map(&literal_leaves(&1, fun))
      |> Enum.flat_map(fn leaf -> leaf_atoms(leaf, funs, fun, depth) end)
    end)
    |> Enum.uniq()
  end

  defp branch_atoms(expr, funs, scope, depth) do
    expr
    |> branch_bodies()
    |> Enum.flat_map(fn body -> literal_leaves(body, scope) end)
    |> Enum.flat_map(fn leaf -> leaf_atoms(leaf, funs, scope, depth) end)
    |> Enum.uniq()
  end

  # A call to a function defined in this module: its entry (scope = the
  # callee's own assigns; parameters resolve through ITS call sites via
  # the normal variable path).
  defp local_callee(funs, {name, _, args}) when is_atom(name) and is_list(args) do
    arity = length(args)
    clauses = for f <- funs, f.name == name and f.arity == arity, do: f
    if clauses == [], do: nil, else: clauses
  end

  defp local_callee(_funs, _expr), do: nil

  # if/case/cond contribute codes only through their branch BODIES — a
  # comparison operand in a condition is a lattice atom, not a code.
  defp branch_bodies({:if, _, [_test, kw]}) when is_list(kw) do
    Enum.flat_map([kw[:do], kw[:else]], &List.wrap/1)
  end

  defp branch_bodies({:case, _, [_test, [do: clauses]]}) when is_list(clauses) do
    Enum.flat_map(clauses, fn {:->, _, [_pattern, body]} -> List.wrap(body) end)
  end

  defp branch_bodies({:cond, _, [clauses]}) when is_list(clauses) do
    Enum.flat_map(clauses, fn {:->, _, [_test, body]} -> List.wrap(body) end)
  end

  defp branch_bodies(other), do: List.wrap(other)

  defp leaf_atoms(leaf, funs, scope, depth) when depth < 8 do
    case resolve(funs, leaf, scope, depth + 1, ceiling_position?(leaf)) do
      %{atoms: atoms, family: family} -> atoms ++ family
    end
  end

  defp ceiling_position?({:ceiling, _}), do: true
  defp ceiling_position?(_), do: false

  defp bucket(list, true), do: %{atoms: [], family: list}
  defp bucket(list, false), do: %{atoms: list, family: []}

  # The literal atoms and resolvable variables of an expression subtree.
  # Keyword-pair keys, aliases, and call heads are STRUCTURE, not codes —
  # only payload positions contribute atoms.
  defp literal_leaves(expr, scope), do: walk_leaves(expr, scope, [])

  defp walk_leaves({:ceiling, key}, scope, acc) do
    case key do
      {name, _, ctx} when (is_atom(ctx) or is_nil(ctx)) and is_atom(name) ->
        case List.keyfind(scope.assigns, name, 0) do
          {_n, rhs} -> walk_leaves(rhs, scope, acc)
          nil -> [{name, [], ctx} | acc]
        end

      other ->
        walk_leaves(other, scope, acc)
    end
  end

  defp walk_leaves({:__aliases__, _, _}, _scope, acc), do: acc

  # A tagged pair (keyword entry, tagged tuple): the key is structure.
  defp walk_leaves({key, value}, scope, acc) when is_atom(key),
    do: walk_leaves(value, scope, acc)

  # A variable.
  defp walk_leaves({name, _, ctx}, scope, acc)
       when (is_atom(ctx) or is_nil(ctx)) and is_atom(name) do
    case List.keyfind(scope.assigns, name, 0) do
      {_n, rhs} -> walk_leaves(rhs, scope, acc)
      nil -> [{name, [], ctx} | acc]
    end
  end

  # A call form: arguments only — the head is not a code.
  defp walk_leaves({_, _, args}, scope, acc) when is_list(args),
    do: Enum.reduce(args, acc, &walk_leaves(&1, scope, &2))

  defp walk_leaves(node, _scope, acc) when is_atom(node) and node not in [nil, true, false],
    do: [node | acc]

  defp walk_leaves(node, scope, acc) when is_list(node),
    do: Enum.reduce(node, acc, &walk_leaves(&1, scope, &2))

  defp walk_leaves(_node, _scope, acc), do: acc

  defp dynamic_atom_construction?(expr) do
    {_, found} =
      Macro.prewalk(expr, false, fn
        {{:., _, [_, fun]}, _, _} = node, _acc when fun in @atom_constructors ->
          {node, true}

        {name, _, _} = node, acc when is_atom(name) ->
          {node, acc or sigil_form?(name)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # A sigil call (`~w(...)a`, `~a(...)`) materializes atoms at runtime
  # from string parts — invisible to the literal walk, so any sigil in a
  # code position is dynamic (fail-closed).
  defp sigil_form?(name) do
    name |> Atom.to_string() |> String.starts_with?("sigil_")
  end

  # Literal arguments supplied at the parameter's position across calls
  # to the enclosing function anywhere in the module — the
  # extracted-builder channel (guard/3's ceiling keys, error/2's codes).
  defp call_site_literals(funs, scope, index) do
    for fun <- funs,
        call <- calls_in(fun.body, scope.name, scope.arity),
        arg = Enum.at(call, index),
        is_atom(arg) and arg not in [nil, true, false],
        do: arg
  end

  defp calls_in(body, name, arity) do
    {_, acc} =
      Macro.prewalk(body, [], fn
        {^name, _, args} = node, acc when is_list(args) and length(args) == arity ->
          {node, [args | acc]}

        # A piped call `a |> name(b)` quotes as the pipe node wrapping an
        # arity-1 call — the piped argument is invisible unless the pipe
        # form is matched too.
        {:|>, _, [piped, {^name, _, args}]} = node, acc
        when is_list(args) and length(args) == arity - 1 ->
          {node, [[piped | args] | acc]}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  # ---- the gate ----------------------------------------------------------------------

  test "every code position is built only from declared literals (per-site rule)" do
    findings =
      for {path, funs, positions} <- module_contexts(),
          {scope, expr} <- positions,
          finding <- position_findings(path, funs, scope, expr) do
        finding
      end

    assert findings == [],
           "undeclared or dynamically-constructed code positions:\n" <>
             Enum.map_join(findings, "\n", &"  #{&1}")
  end

  test "every declared code is emitted somewhere (dead vocabulary reds)" do
    emitted = emitted_atoms()

    dead = for code <- Error.codes(), code not in emitted, do: code
    dead_family = for key <- Error.ceiling_keys(), key not in emitted, do: key

    assert dead == [] and dead_family == [],
           "declared but unemitted: #{inspect(dead)} / family keys #{inspect(dead_family)}"
  end

  test "the ceiling family's keys are exactly the decoder limit names (Bounds' field set)" do
    bounds_fields =
      Bounds.__struct__() |> Map.from_struct() |> Map.keys() |> Enum.reject(&(&1 == :__struct__))

    assert Enum.sort(Error.ceiling_keys()) == Enum.sort(bounds_fields)
  end

  defp emitted_atoms do
    module_contexts()
    |> Enum.flat_map(fn {_path, funs, positions} ->
      Enum.flat_map(positions, fn {scope, expr} -> emitted_from(funs, scope, expr) end)
    end)
    |> Enum.uniq()
  end

  defp emitted_from(funs, scope, expr) do
    case resolve(funs, expr, scope) do
      %{atoms: atoms, family: family} -> atoms ++ family
    end
  end

  defp position_findings(path, funs, scope, expr) do
    case resolve(funs, expr, scope) do
      %{dynamic: true} ->
        ["#{path}: dynamically-constructed code position: #{Macro.to_string(expr)}"]

      %{atoms: atoms, family: family} ->
        undeclared = for a <- atoms, not Error.declared?(a), do: a
        undeclared_family = for k <- family, not Error.declared?({:ceiling, k}), do: k

        if undeclared == [] and undeclared_family == [] do
          []
        else
          [
            "#{path}: undeclared #{inspect(undeclared)} family #{inspect(undeclared_family)} in #{Macro.to_string(expr)}"
          ]
        end
    end
  end
end
