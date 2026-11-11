defmodule AgentBlueprintProtocol.WalkthroughTest do
  @moduledoc """
  Evaluates every Livebook notebook against the repository source. Each
  notebook starts with one pinned Mix.install cell, which this harness skips
  after checking its exact requirement. Every other Elixir cell runs in order
  with a notebook-local binding, and its result must equal the persisted output.
  """

  use ExUnit.Case, async: false

  @notebook_dir Path.expand("../docs/livebooks", __DIR__)
  setup_all do
    notebooks =
      @notebook_dir
      |> Path.join("*.livemd")
      |> Path.wildcard()
      |> Enum.sort()

    assert notebooks != [], "docs/livebooks must contain at least one notebook"

    evaluated =
      Map.new(notebooks, fn path ->
        cells = notebook_cells(File.read!(path))
        {path, %{cells: cells, results: evaluate_notebook(path, cells)}}
      end)

    %{notebooks: evaluated}
  end

  test "each notebook begins with one exact install cell", %{notebooks: notebooks} do
    version = Mix.Project.config()[:version]
    expected = ~s|Mix.install([{:agent_blueprint_protocol, "~> #{version}"}])|

    for {path, %{cells: cells}} <- notebooks do
      assert [install | _] = cells
      assert install.code == expected, "#{path}: first Elixir cell must pin the current package"
      assert Enum.count(cells, &String.contains?(&1.code, "Mix.install(")) == 1
    end
  end

  test "every evaluated cell has a pinned output that matches its value", %{
    notebooks: notebooks
  } do
    for {path, %{results: results}} <- notebooks do
      assert results != [], "#{path}: notebook has no evaluated cells"

      for %{line: line, heading: heading, value: value, output: output} <- results do
        assert is_binary(output) and output != "",
               "#{path}: cell at line #{line} under #{inspect(heading)} has no persisted output"

        {pinned, _binding} = Code.eval_string(output, [], file: path)

        assert value == pinned,
               "#{path}: cell at line #{line} under #{inspect(heading)} evaluated to " <>
                 "#{inspect(value, pretty: true)} but prints #{output}"
      end
    end
  end

  defp evaluate_notebook(path, cells) do
    [install | evaluated] = cells
    version = Mix.Project.config()[:version]
    assert install.code == ~s|Mix.install([{:agent_blueprint_protocol, "~> #{version}"}])|

    {results, _binding, _env} =
      Enum.reduce(evaluated, {[], [], Code.env_for_eval(file: path)}, fn cell,
                                                                         {results, binding,
                                                                          env_in} ->
        quoted = Code.string_to_quoted!(cell.code, file: path, line: cell.line)

        {value, binding, env_out} = Code.eval_quoted_with_env(quoted, binding, env_in)

        {[Map.put(cell, :value, value) | results], binding, env_out}
      end)

    Enum.reverse(results)
  end

  defp notebook_cells(text) do
    {cells, _heading, _state} =
      text
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reduce({[], nil, :prose}, &step/2)

    Enum.reverse(cells)
  end

  defp step({<<96, 96, 96>>, _line}, {cells, heading, {:code, start, body}}) do
    cell = %{heading: heading, line: start, code: join(body), output: nil}
    {[cell | cells], heading, :after_code}
  end

  defp step({line, _number}, {cells, heading, {:code, start, body}}),
    do: {cells, heading, {:code, start, [line | body]}}

  defp step({<<96, 96, 96>>, _line}, {[cell | rest], heading, {:output, body}}),
    do: {[%{cell | output: join(body)} | rest], heading, :prose}

  defp step({line, _number}, {cells, heading, {:output, body}}),
    do: {cells, heading, {:output, [line | body]}}

  defp step({<<96, 96, 96>>, _line}, {cells, heading, :after_output_marker}),
    do: {cells, heading, {:output, []}}

  defp step({"<!-- livebook:{\"output\":true} -->", _line}, {cells, heading, :after_code}),
    do: {cells, heading, :after_output_marker}

  defp step({"", _line}, {cells, heading, state})
       when state in [:after_code, :after_output_marker],
       do: {cells, heading, state}

  defp step({<<96, 96, 96, "elixir">>, line}, {cells, heading, _state}),
    do: {cells, heading, {:code, line + 1, []}}

  defp step({"## " <> heading, _line}, {cells, _current, _state}),
    do: {cells, heading, :prose}

  defp step({_line, _number}, {cells, heading, _state}),
    do: {cells, heading, :prose}

  defp join(reversed_lines),
    do: reversed_lines |> Enum.reverse() |> Enum.join("\n") |> String.trim()
end
