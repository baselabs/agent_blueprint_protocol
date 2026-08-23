defmodule AgentBlueprintProtocol.Architecture.VerifyOnlyTest do
  @moduledoc """
  Verify-only gate (the base protocol's verify-only clause): the package NEVER signs and
  holds no key material. Enforced three ways over every shipped source
  file's AST — banned parameter names, banned `:crypto.sign` invocations
  (any signing call is categorically wrong under verify-only, which is what
  actually enforces "never signs" rather than asserting it), and banned
  key-material struct fields / module attributes. The `:crypto.sign` ban is
  additionally enforced at the BEAM level (the beam-signing test below):
  the compiled-bytecode census resolves every remote call with aliases
  already expanded and dynamic dispatch surfaced as `:erlang.apply` — a
  renamed alias, a variable-indirected module, or a constructed module
  name cannot hide a signing call. The parameter/field scans remain
  name-based (their inputs are identifiers, not calls).
  """

  use ExUnit.Case, async: true

  @banned_params [:private_key, :seed, :secret]
  @banned_fields [:private_key, :seed, :secret]

  test "no function in lib/ takes a private_key/seed/secret parameter" do
    offenders =
      for path <- shipped_files(),
          {where, name} <- parameters(path),
          name in @banned_params,
          do: {path, where, name}

    assert offenders == [],
           "verify-only violation: a shipped function accepts key material:\n" <>
             Enum.map_join(offenders, "\n", fn {p, w, n} -> "  #{p}:#{w} #{n}" end)
  end

  test "no :crypto.sign invocation exists anywhere in lib/" do
    offenders =
      for path <- shipped_files(),
          line <- crypto_sign_lines(path),
          do: {path, line}

    assert offenders == [],
           "verify-only violation: the package never signs, but a :crypto.sign call exists:\n" <>
             Enum.map_join(offenders, "\n", fn {p, l} -> "  #{p}:#{l}" end)
  end

  test "no struct field or module attribute in lib/ is named like key material" do
    offenders =
      for path <- shipped_files(),
          {line, name} <- key_material_names(path),
          do: {path, line, name}

    assert offenders == [],
           "verify-only violation: shipped source declares key-material shape:\n" <>
             Enum.map_join(offenders, "\n", fn {p, l, n} -> "  #{p}:#{l} #{n}" end)
  end

  # ---- helpers ------------------------------------------------------------------

  defp shipped_files, do: Path.wildcard("lib/**/*.{ex,exs}") |> Enum.sort()

  defp parameters(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path)

    # Collect bare variables from EVERY def/defp head shape: plain, guarded
    # (`def f(x) when g`), defaulted (`x \\ nil`), bodyless heads, and
    # do/rescue/catch blocks. Over-collection (guard variables) is
    # deliberately safe for a ban list.
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {kind, meta, [head, block]} = node, acc when kind in [:def, :defp] and is_list(block) ->
          if Keyword.has_key?(block, :do) or Keyword.has_key?(block, :rescue) or
               Keyword.has_key?(block, :catch) do
            {node, head_params(head, meta[:line], acc)}
          else
            {node, acc}
          end

        {kind, meta, [head]} = node, acc when kind in [:def, :defp] ->
          {node, head_params(head, meta[:line], acc)}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp head_params(head, line, acc) do
    {_head, vars} =
      Macro.prewalk(head, [], fn
        {name, _, nil} = node, vars when is_atom(name) -> {node, [{name, line} | vars]}
        node, vars -> {node, vars}
      end)

    params = for {name, line} <- vars, name in @banned_params, do: {line, name}
    params ++ acc
  end

  defp crypto_sign_lines(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path)

    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {{:., meta, [:crypto, :sign]}, _, _} = node, acc ->
          {node, [meta[:line] | acc]}

        {{:., meta, [{:__aliases__, _, [:crypto]}, :sign]}, _, _} = node, acc ->
          {node, [meta[:line] | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  defp key_material_names(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path)

    # defstruct accepts a flat atom list, keyword pairs, or nested lists —
    # flatten and take atom fields AND keyword keys.
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {:defstruct, meta, [fields]} = node, acc when is_list(fields) ->
          names =
            fields
            |> List.flatten()
            |> Enum.flat_map(fn
              {name, _value} when is_atom(name) -> [name]
              name when is_atom(name) -> [name]
              _other -> []
            end)
            |> Enum.filter(&(&1 in @banned_fields))
            |> Enum.map(&{meta[:line], &1})

          {node, names ++ acc}

        {:@, meta, [{name, _, _}]} = node, acc when name in @banned_fields ->
          {node, [{meta[:line], name} | acc]}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  test "no lib beam can call :crypto.sign under ANY spelling (beam census)" do
    alias AgentBlueprintProtocol.ArchitectureScan

    offenders =
      for beam <- Path.wildcard("_build/test/lib/agent_blueprint_protocol/ebin/*.beam"),
          {:crypto, :sign} <- ArchitectureScan.beam_remote_calls(beam) do
        {Path.basename(beam), :crypto, :sign}
      end

    assert offenders == [],
           "verify-only violation: a shipped beam contains a crypto:sign call site " <>
             "(aliases expand and dynamic dispatch surfaces at the BEAM level — no spelling hides): " <>
             inspect(offenders)
  end
end
