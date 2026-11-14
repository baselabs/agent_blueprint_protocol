defmodule PackageLivebooks do
  @moduledoc false

  # Standalone, package-independent gate:
  # elixir scripts/extract_livebooks.exs --archive package.tar notebook.livemd ...
  # Uses only the archive, notebook files, and the running Elixir/OTP toolchain.
  @cell ~r/^```elixir\r?\n(.*?)^```[ \t]*$/ms

  def extract(markdown, app, package, notebook) do
    cells =
      @cell
      |> Regex.scan(markdown, return: :index, capture: :all_but_first)
      |> Enum.with_index(1)
      |> Enum.map(fn {[{offset, size}], index} ->
        code = binary_part(markdown, offset, size)
        line = markdown |> binary_part(0, offset) |> String.split("\n") |> length()
        %{code: code, index: index, line: line}
      end)

    with true <- cells != [],
         {:ok, installs} <- install_cells(cells, notebook),
         [install] <- installs do
      rewritten =
        Enum.map(cells, fn cell ->
          if cell.index == install,
            do: %{cell | code: "Mix.install([{#{inspect(app)}, path: #{inspect(package)}}])"},
            else: cell
        end)

      {:ok, runner(rewritten, notebook)}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, "#{notebook} cell 1: expected exactly one standalone Mix.install cell"}
    end
  end

  def run(archive, notebooks) when notebooks != [] do
    scratch =
      Path.join(
        System.tmp_dir!(),
        "package-livebooks-#{Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)}"
      )

    File.mkdir!(scratch)

    try do
      package = Path.join(scratch, "package")
      consumer = Path.join(scratch, "consumer")
      installs = Path.join(scratch, "installs")
      File.mkdir!(package)
      File.mkdir!(consumer)
      {name, version, app} = unpack!(Path.expand(archive), package, scratch)
      IO.puts("package Livebooks: #{name} #{version}")

      for {notebook, index} <- Enum.with_index(notebooks, 1) do
        notebook = Path.expand(notebook)
        source = File.read!(notebook)

        script =
          case extract(source, app, package, notebook) do
            {:ok, script} -> script
            {:error, reason} -> raise reason
          end

        path = Path.join(scratch, "notebook-#{index}.exs")
        File.write!(path, script)

        {output, status} =
          System.cmd(elixir(), [path],
            cd: consumer,
            stderr_to_stdout: true,
            env: [
              {"MIX_ENV", "prod"},
              {"MIX_INSTALL_DIR", installs},
              {"MIX_BUILD_PATH", nil},
              {"MIX_DEPS_PATH", nil},
              {"PATH",
               Path.join(List.to_string(:code.root_dir()), "bin") <>
                 path_separator() <> System.get_env("PATH", "")}
            ]
          )

        IO.write(output)
        if status != 0, do: raise("#{notebook}: exit #{status}")
        IO.puts("package Livebook #{Path.basename(notebook)}: passed")
      end

      IO.puts("package Livebooks: #{length(notebooks)} notebooks passed outside the checkout")
      :ok
    after
      File.rm_rf!(scratch)
    end
  end

  def main(["--archive", archive | notebooks]) when notebooks != [] do
    run(archive, notebooks)
  end

  def main(_args), do: raise("usage: --archive package.tar notebook.livemd ...")

  defp unpack!(archive, package, scratch) do
    {:ok, entries} = :erl_tar.extract(String.to_charlist(archive), [:memory])
    metadata = entries |> List.keyfind(~c"metadata.config", 0) |> elem(1)
    contents = entries |> List.keyfind(~c"contents.tar.gz", 0) |> elem(1)
    path = Path.join(scratch, "metadata.config")
    File.write!(path, metadata)
    {:ok, terms} = :file.consult(String.to_charlist(path))
    fields = Map.new(terms)
    name = Map.fetch!(fields, "name")
    version = Map.fetch!(fields, "version")
    app = Map.fetch!(fields, "app")
    true = is_binary(name) and is_binary(version) and is_binary(app)

    :ok =
      :erl_tar.extract({:binary, contents}, [:compressed, {:cwd, String.to_charlist(package)}])

    {name, version, String.to_atom(app)}
  end

  defp install_cells(cells, notebook) do
    Enum.reduce_while(cells, {:ok, []}, fn cell, {:ok, installs} ->
      case Code.string_to_quoted(cell.code, file: notebook, line: cell.line) do
        {:ok, quoted} ->
          {_ast, calls} =
            Macro.prewalk(quoted, 0, fn
              {{:., _, [{:__aliases__, _, [:Mix]}, :install]}, _, _} = node, count ->
                {node, count + 1}

              node, count ->
                {node, count}
            end)

          cond do
            calls == 0 ->
              {:cont, {:ok, installs}}

            calls == 1 and standalone_install?(quoted) ->
              {:cont, {:ok, [cell.index | installs]}}

            true ->
              {:halt,
               {:error, "#{notebook} cell #{cell.index}: expected a standalone Mix.install cell"}}
          end

        {:error, reason} ->
          {:halt, {:error, "#{notebook} cell #{cell.index}: #{inspect(reason)}"}}
      end
    end)
  end

  defp standalone_install?({{:., _, [{:__aliases__, _, [:Mix]}, :install]}, _, [_deps | _opts]}),
    do: true

  defp standalone_install?(_quoted), do: false

  defp runner(cells, notebook) do
    """
    notebook = #{inspect(notebook)}
    cells = #{inspect(cells, limit: :infinity, printable_limit: :infinity)}

    Enum.reduce(cells, {[], Code.env_for_eval(file: notebook)}, fn cell, {binding, env} ->
      try do
        quoted = Code.string_to_quoted!(cell.code, file: notebook, line: cell.line)
        {_value, binding, env} = Code.eval_quoted_with_env(quoted, binding, env)
        {binding, env}
      rescue
        error ->
          IO.puts(:stderr, "notebook \#{notebook} cell \#{cell.index} (line \#{cell.line}): " <> Exception.format(:error, error, __STACKTRACE__))
          System.halt(1)
      catch
        kind, reason ->
          IO.puts(:stderr, "notebook \#{notebook} cell \#{cell.index} (line \#{cell.line}): " <> Exception.format(kind, reason, __STACKTRACE__))
          System.halt(1)
      end
    end)
    """
  end

  defp elixir do
    executable = if match?({:win32, _}, :os.type()), do: "elixir.bat", else: "elixir"
    Path.expand("../../../bin/" <> executable, Path.dirname(List.to_string(:code.which(Kernel))))
  end

  defp path_separator, do: if(match?({:win32, _}, :os.type()), do: ";", else: ":")
end

if "--archive" in System.argv(), do: PackageLivebooks.main(System.argv())
