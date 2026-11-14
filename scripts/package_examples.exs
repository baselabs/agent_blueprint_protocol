defmodule PackageExamples do
  @moduledoc false

  # Package-independent consumer gate. Only the archive and document paths are inputs.
  def cells(source, file) do
    ~r/^```elixir([^\r\n]*)\r?\n(.*?)^```[ \t]*$/ms
    |> Regex.scan(source, return: :index, capture: :all_but_first)
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {[{info_at, info_size}, {offset, size}], index} ->
      case source |> binary_part(info_at, info_size) |> String.trim() do
        "fragment" ->
          []

        "" ->
          [
            %{
              code: binary_part(source, offset, size),
              index: index,
              line: length(String.split(binary_part(source, 0, offset), "\n"))
            }
          ]

        info ->
          raise "#{file} block #{index}: unknown Elixir fence marking #{inspect(info)}"
      end
    end)
  end

  def run(archive, mode, files) when mode in [:doctests, :snippets] do
    scratch =
      Path.join(
        System.tmp_dir!(),
        "package-examples-#{Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)}"
      )

    File.mkdir!(scratch)

    try do
      package = Path.join(scratch, "package")
      consumer = Path.join(scratch, "consumer")
      File.mkdir!(package)
      File.mkdir!(consumer)
      {app, version} = unpack!(Path.expand(archive), package, scratch)

      File.write!(Path.join(consumer, "mix.exs"), """
      defmodule PackageExamplesConsumer.MixProject do
        use Mix.Project
        def project, do: [app: :package_examples_consumer, version: "0.0.0", deps: [{#{inspect(app)}, path: #{inspect(package)}, env: :prod}]]
        def application, do: [extra_applications: [:crypto]]
      end
      """)

      env = [{"MIX_ENV", "test"}, {"MIX_BUILD_PATH", nil}, {"MIX_DEPS_PATH", nil}]
      command!(consumer, env, ["deps.get"])

      case mode do
        :doctests ->
          File.write!(Path.join(consumer, "doctests_test.exs"), """
          ExUnit.start()
          Application.load(#{inspect(app)})
          modules = Application.spec(#{inspect(app)}, :modules)
          if modules in [nil, []], do: raise("package has no modules")
          for module <- modules do
            defmodule Module.concat([PackageDoctests, module]) do
              use ExUnit.Case
              doctest module
            end
          end
          """)

          command!(consumer, env, ["test", "doctests_test.exs"])
          IO.puts("package doctests: #{app} #{version} passed outside the checkout")

        :snippets ->
          if files == [], do: raise("no snippet documents")

          total =
            for {file, index} <- Enum.with_index(files, 1) do
              file = Path.expand(file)
              cells = cells(File.read!(file), file)
              script = Path.join(consumer, "snippets-#{index}.exs")
              File.write!(script, runner(cells, file))
              command!(consumer, env, ["run", script])
              IO.puts("package snippets #{Path.basename(file)}: #{length(cells)} blocks passed")
              length(cells)
            end

          if Enum.sum(total) == 0, do: raise("no runnable Elixir snippets")

          IO.puts(
            "package snippets: #{Enum.sum(total)} blocks in #{length(files)} documents passed outside the checkout"
          )
      end
    after
      File.rm_rf!(scratch)
    end
  end

  defp runner(cells, file) do
    """
    cells = #{inspect(cells, limit: :infinity, printable_limit: :infinity)}
    Enum.reduce(cells, {[], Code.env_for_eval(file: #{inspect(file)})}, fn cell, {binding, env} ->
      try do
        quoted = Code.string_to_quoted!(cell.code, file: #{inspect(file)}, line: cell.line)
        {_value, binding, env} = Code.eval_quoted_with_env(quoted, binding, env)
        {binding, env}
      rescue
        error -> raise "#{file} block \#{cell.index} (line \#{cell.line}): " <> Exception.format(:error, error, __STACKTRACE__)
      end
    end)
    """
  end

  defp unpack!(archive, package, scratch) do
    {:ok, entries} = :erl_tar.extract(String.to_charlist(archive), [:memory])
    metadata = entries |> List.keyfind(~c"metadata.config", 0) |> elem(1)
    contents = entries |> List.keyfind(~c"contents.tar.gz", 0) |> elem(1)
    path = Path.join(scratch, "metadata.config")
    File.write!(path, metadata)
    {:ok, terms} = :file.consult(String.to_charlist(path))
    fields = Map.new(terms)
    app = Map.fetch!(fields, "app")
    version = Map.fetch!(fields, "version")
    true = is_binary(app) and is_binary(version)

    :ok =
      :erl_tar.extract({:binary, contents}, [:compressed, {:cwd, String.to_charlist(package)}])

    {String.to_atom(app), version}
  end

  defp command!(consumer, env, args) do
    {output, status} = System.cmd("mix", args, cd: consumer, env: env, stderr_to_stdout: true)
    IO.write(output)
    if status != 0, do: raise("package consumer #{Enum.join(args, " ")}: exit #{status}")
  end
end

case System.argv() do
  ["--archive", archive, "--doctests"] -> PackageExamples.run(archive, :doctests, [])
  ["--archive", archive, "--snippets" | files] -> PackageExamples.run(archive, :snippets, files)
  _ -> :ok
end
