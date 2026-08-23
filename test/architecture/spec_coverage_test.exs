defmodule AgentBlueprintProtocol.Architecture.SpecCoverageTest do
  @moduledoc """
  Spec-coverage gate: every public function carries a `@spec`, and every
  shipped module carries a real `@moduledoc` that states the
  non-authorizing boundary.

  - Public means `def`/`defmacro`/`defdelegate` (a delegate is a public
    facade surface and must be spec'd; `defguard`/`defguardp` are
    deliberately excluded — guards have no @spec convention).
  - Arity rule for default arguments: the `@spec` on the max-arity head
    satisfies every default-collapsed arity (one spec per name, house
    style); the gate compares the spec's argument count to the head's
    formal-parameter count.
  - Module scoping is a recursive descent over defmodule bodies, so
    sibling modules in one file never read as nested.
  - The stance list is stance-assertive vocabulary only
    (`non-authorizing`, `never authorizes`, …). Domain words like
    `verify` or `evidence` are deliberately NOT on the list: they name
    what the package does, not what it refuses to do.

  Goes RED on: a public function added without a `@spec` (name+arity
  mismatch included); a module whose moduledoc is missing, false, or
  states no boundary.
  """

  use ExUnit.Case, async: true

  @stance_terms [
    "non-authorizing",
    "never authorizes",
    "never authorises",
    "never grants authority",
    "does not authorize",
    "cannot authorize",
    "authorizes nothing",
    "no authority",
    "not a decision"
  ]

  test "every public function has a matching @spec" do
    offenders =
      for file <- shipped_files(),
          {module, name, arity, kind} <- public_functions(file),
          {module, name, arity} not in specs(file) do
        {file, module, "#{kind} #{name}/#{arity}"}
      end

    assert offenders == [],
           "spec-coverage violation: public functions without a matching @spec:\n" <>
             Enum.map_join(offenders, "\n", fn {p, m, f} -> "  #{p}: #{m}.#{f}" end)
  end

  test "no use or unquote-generated public surface hides from the static walk" do
    offenders =
      for file <- shipped_files(), node <- generated_surface(ast(file)) do
        {file, node}
      end

    assert offenders == [],
           "spec-coverage violation: generated public surface in lib/ is invisible " <>
             "to the static walk (no macros, no use, no unquote heads):\n" <>
             Enum.map_join(offenders, "\n", fn {p, n} -> "  #{p}: #{n}" end)
  end

  test "every shipped module has a real moduledoc stating the boundary" do
    offenders =
      for file <- shipped_files(),
          {module, doc} <- moduledocs(file),
          missing_stance?(doc) do
        {file, module}
      end

    assert offenders == [],
           "spec-coverage violation: modules whose moduledoc is missing, false, " <>
             "or states no non-authorizing boundary:\n" <>
             Enum.map_join(offenders, "\n", fn {p, m} -> "  #{p}: #{inspect(m)}" end)
  end

  # ---- helpers ------------------------------------------------------------------

  defp shipped_files, do: Path.wildcard("lib/**/*.{ex,exs}") |> Enum.sort()

  defp ast(file), do: file |> File.read!() |> Code.string_to_quoted!(file: file)

  # Recursive descent over the module tree: a defmodule's own statements
  # only (direct @spec / public heads / @moduledoc), then each nested
  # defmodule with its properly-scoped name. Sibling modules in one file
  # are joined to the file's root, not to each other.
  defp module_tree(file) do
    walk_module(ast(file), nil)
  end

  defp walk_module({:defmodule, _, [{:__aliases__, _, segs}, [do: body]]}, parent) do
    mod = join_module(parent, segs)
    stmts = block_statements(body)
    doc = direct_moduledoc(stmts)
    children = Enum.flat_map(stmts, &walk_children(&1, mod))

    [
      {mod,
       %{
         doc: doc,
         specs: direct_specs(stmts),
         publics: direct_publics(stmts)
       }}
      | children
    ]
  end

  defp walk_module(_, _parent), do: []

  defp walk_children({:defmodule, _, [{:__aliases__, _, _}, _]} = node, mod),
    do: walk_module(node, mod)

  defp walk_children({:__block__, _, stmts}, mod),
    do: Enum.flat_map(stmts, &walk_children(&1, mod))

  defp walk_children(_, _mod), do: []

  defp specs(file) do
    for {mod, info} <- module_tree(file),
        {name, arity} <- info.specs do
      {mod, name, arity}
    end
  end

  defp public_functions(file) do
    for {mod, info} <- module_tree(file),
        {name, arity, kind} <- info.publics do
      {mod, name, arity, kind}
    end
  end

  defp moduledocs(file), do: for({mod, info} <- module_tree(file), do: {mod, info.doc})

  # `@spec name(arg1, ..., argN) :: ret`; a zero-arity spec parses with a
  # non-list third element.
  defp direct_specs(stmts) do
    for {:@, _, [{:spec, _, [raw]}]} <- stmts,
        spec = unwrap_when(raw),
        {:"::", _, [{name, _, args}, _]} <- [spec],
        is_atom(name) do
      {name, if(is_list(args), do: length(args), else: 0)}
    end
  end

  # `@spec f(x) when x: t` wraps the :: node; unwrap before matching.
  defp unwrap_when({:when, _, [inner, _guards]}), do: inner
  defp unwrap_when(other), do: other

  # A `use` injects public surface the unexpanded AST never sees; an
  # `unquote` head is a generated name the walk cannot enumerate. Neither
  # may exist under lib/.
  defp generated_surface(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {:use, _, _} = node, acc ->
          {node, ["use" | acc]}

        {kind, _, [{unquote_node, _, _}, _]} = node, acc
        when kind in [:def, :defmacro, :defdelegate] and unquote_node == :unquote ->
          {node, ["unquote head" | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  # Public heads: `def`/`defmacro`/`defdelegate` with a body (or options)
  # second element. `defguard`/`defguardp` are deliberately not collected.
  defp direct_publics(stmts) do
    for {kind, _, [head, _]} <- stmts,
        kind in [:def, :defmacro, :defdelegate],
        {name, arity} <- [head_arity(head)] |> Enum.reject(&is_nil/1) do
      {name, arity, kind}
    end
  end

  defp head_arity({:when, _, [head, _guards]}), do: head_arity(head)

  defp head_arity({name, _, args}) when is_atom(name) and is_list(args),
    do: {name, length(args)}

  defp head_arity({name, _, _}) when is_atom(name), do: {name, 0}

  defp head_arity(_), do: nil

  defp direct_moduledoc(stmts) do
    Enum.find_value(stmts, fn
      {:@, _, [{:moduledoc, _, [doc]}]} -> doc
      _ -> nil
    end)
  end

  defp block_statements({:__block__, _, stmts}), do: stmts
  defp block_statements([{:do, _} | _] = wrapped), do: block_statements(wrapped[:do])
  defp block_statements(other) when is_list(other), do: other
  defp block_statements(other), do: [other]

  defp missing_stance?(doc) do
    case doc_text(doc) do
      %{} = _non_string ->
        true

      text ->
        downcased = String.downcase(text)
        not Enum.any?(@stance_terms, &String.contains?(downcased, &1))
    end
  end

  # A moduledoc may interpolate module attributes (`#{@node_ceiling}`),
  # which parses as a binary-segment AST rather than a plain string. The
  # literal segments carry the prose; interpolations are holes.
  defp doc_text(doc) when is_binary(doc), do: doc

  defp doc_text({:<<>>, _, segments}) when is_list(segments) do
    Enum.map_join(segments, "", fn
      seg when is_binary(seg) -> seg
      _interpolation -> ""
    end)
  end

  defp doc_text(_other), do: %{}

  defp join_module(nil, segs), do: Module.concat(segs)
  defp join_module(mod, segs), do: Module.concat(mod, Module.concat(segs))
end
