defmodule AgentBlueprintProtocol.LivebookExtractor do
  @moduledoc false

  @open_cell <<96, 96, 96, "elixir">>
  @fence <<96, 96, 96>>
  @version_pattern ~r/\A[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?\z/

  def extract(markdown, version) when is_binary(markdown) and is_binary(version) do
    with true <- Regex.match?(@version_pattern, version),
         cells when cells != [] <- code_cells(markdown),
         [install | rest] <- cells,
         true <- install == source_install(),
         false <- Enum.any?(rest, &String.contains?(&1, "Mix.install(")) do
      {:ok, runner_script(version, rest)}
    else
      _ -> {:error, :invalid_notebook}
    end
  end

  def extract(_, _), do: {:error, :invalid_notebook}

  def extract_directory(input_dir, output_dir, version) do
    paths =
      input_dir
      |> Path.join("*.livemd")
      |> Path.wildcard()
      |> Enum.sort()

    with true <- paths != [],
         :ok <- File.mkdir_p(output_dir) do
      Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, written} ->
        with {:ok, source} <- File.read(path),
             {:ok, script} <- extract(source, version),
             output = Path.join(output_dir, Path.basename(path, ".livemd") <> ".exs"),
             :ok <- File.write(output, script) do
          {:cont, {:ok, [output | written]}}
        else
          _ -> {:halt, {:error, {:invalid_notebook, path}}}
        end
      end)
      |> case do
        {:ok, written} -> {:ok, Enum.reverse(written)}
        error -> error
      end
    else
      _ -> {:error, :no_notebooks}
    end
  end

  def main(["--version", version, "--input", input_dir, "--output", output_dir]) do
    case extract_directory(input_dir, output_dir, version) do
      {:ok, paths} ->
        Enum.each(paths, &IO.puts/1)
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "Could not extract Livebook scripts: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def main(_args), do: {:error, :usage}

  defp code_cells(markdown) do
    pattern =
      "^" <>
        Regex.escape(@open_cell) <>
        "\\r?\\n(.*?)^" <>
        Regex.escape(@fence) <>
        "[ \\t]*$"

    Regex.compile!(pattern, "ms")
    |> Regex.scan(markdown, capture: :all_but_first)
    |> Enum.map(&hd/1)
    |> Enum.map(&String.trim/1)
  end

  defp source_install,
    do: ~s|Mix.install([{:agent_blueprint_protocol, "~> 1.0.0-rc.1"}])|

  defp published_install(version),
    do: ~s|Mix.install([{:agent_blueprint_protocol, "== #{version}"}])|

  defp runner_script(version, cells) do
    cell_literals = Enum.map_join(cells, ",\n", &("  " <> inspect(&1)))

    """
    #{published_install(version)}

    notebook_cells = [
    #{cell_literals}
    ]

    Enum.reduce(notebook_cells, {[], Code.env_for_eval(file: __ENV__.file)}, fn code,
                                                                                {binding, env} ->
      quoted = Code.string_to_quoted!(code, file: __ENV__.file)
      {_value, binding, env} = Code.eval_quoted_with_env(quoted, binding, env)
      {binding, env}
    end)
    """
  end
end

if "--version" in System.argv() do
  case AgentBlueprintProtocol.LivebookExtractor.main(System.argv()) do
    :ok -> :ok
    {:error, _reason} -> System.halt(1)
  end
end
