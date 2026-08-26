defmodule AgentBlueprintProtocol.Architecture.DocumentationMirrorTest do
  @moduledoc """
  Mirror-test gate: every result-claiming example in the documentation
  corpus is executed against the real package, line by line, in order,
  with the claimed value compared to the evaluated one — a guide
  example that would not run (wrong API shape, wrong return form,
  fabricated output) reds. A non-running example is worse than none.
  """

  use ExUnit.Case, async: true

  @guides_dir "documentation"

  test "every result-claiming guide example mirrors the real package" do
    examples = guide_examples()

    assert examples != [],
           "no result-claiming guide examples found — the mirror suite would be vacuous"

    offenders =
      for {file, index, body} <- examples,
          offence <- mirror_offences(body) do
        "#{file} (block #{index}): #{offence}"
      end

    assert offenders == [],
           "guide examples that do not mirror the package:\n" <> Enum.join(offenders, "\n")
  end

  defp guide_examples do
    for file <- Path.wildcard(Path.join(@guides_dir, "*.md")) |> Enum.sort(),
        {index, body} <- extract_blocks(File.read!(file)) do
      {file, index, body}
    end
  end

  defp extract_blocks(markdown) do
    markdown
    |> String.split(~r/```elixir\n/)
    |> Enum.drop(1)
    |> Enum.with_index()
    |> Enum.map(fn {block, index} ->
      {index, block |> String.split("```") |> hd() |> String.trim()}
    end)
    |> Enum.filter(fn {_i, body} -> body =~ ~r/#\s*=>/ end)
  end

  # Each line is either setup (no claim) or `expression # => claimed`.
  # Setup lines evaluate in a shared binding; claimed lines evaluate
  # and compare against the claimed value's own evaluation.
  defp mirror_offences(body) do
    lines = String.split(body, "\n")

    {offences, _binding} =
      Enum.reduce(lines, {[], []}, fn line, {offs, binding} ->
        mirror_line(line, {offs, binding})
      end)

    offences
  end

  defp mirror_line(line, {offs, binding}) do
    case Regex.run(~r/^(.*?)\s+#\s*=>\s*(.+)$/, line) do
      [_, expr_src, claim_src] ->
        case eval_pair(expr_src, claim_src, binding) do
          {:ok, _value, binding} ->
            {offs, binding}

          {:equal, binding} ->
            {offs, binding}

          {:drift, value} ->
            {offs ++ ["#{expr_src} evaluated to #{inspect(value)}, guide claims #{claim_src}"],
             binding}

          {:error, reason} ->
            {offs ++ ["line failed (#{reason}): #{inspect(line)}"], binding}
        end

      nil ->
        setup_line(line, {offs, binding})
    end
  end

  defp setup_line(line, {offs, binding}) do
    if String.trim(line) == "" do
      {offs, binding}
    else
      case Code.string_to_quoted(line) do
        {:ok, expr} ->
          eval_setup(expr, binding, line, offs)

        {:error, _} ->
          {offs ++ ["a setup line does not parse: #{inspect(line)}"], binding}
      end
    end
  end

  defp eval_setup(expr, binding, line, offs) do
    case safe_eval(expr, binding) do
      {_, binding} -> {offs, binding}
      {:error, reason} -> {offs ++ ["setup line failed (#{reason}): #{inspect(line)}"], binding}
    end
  end

  defp eval_pair(expr_src, claim_src, binding) do
    with {:ok, expr} <- Code.string_to_quoted(expr_src),
         {:ok, claim} <- Code.string_to_quoted(claim_src),
         {value, binding} <- safe_eval(expr, binding),
         {claimed, _} <- safe_eval(claim, []) do
      if equivalent?(value, claimed) do
        {:equal, binding}
      else
        {:drift, value}
      end
    else
      {:error, :parse} -> {:error, "does not parse"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp safe_eval(quoted, binding) do
    Code.eval_quoted(quoted, binding, eval_env())
  rescue
    e -> {:error, e}
  end

  defp eval_env do
    import AgentBlueprintProtocol
    __ENV__
  end

  # Structural equality over plain values; structs/tuples normalize to
  # comparable shapes so guide claims can stay concise.
  defp equivalent?(left, right), do: normalize(left) == normalize(right)

  defp normalize(%_{__struct__: _} = struct) do
    struct |> Map.from_struct() |> normalize()
  end

  defp normalize(%{} = map),
    do: Map.new(map, fn {k, v} -> {normalize(k), normalize(v)} end)

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)

  defp normalize(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> normalize()

  defp normalize(value), do: value
end
