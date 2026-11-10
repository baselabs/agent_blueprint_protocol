defmodule AgentBlueprintProtocol.Conformance.Cli do
  @moduledoc false

  alias AgentBlueprintProtocol.Conformance.{Corpus, Report, Runner}

  @metadata_path Path.expand("../../../priv/release-metadata.json", __DIR__)
  @external_resource @metadata_path
  @certified_digest @metadata_path
                    |> File.read!()
                    |> :json.decode()
                    |> Map.fetch!("corpus_digest")

  @usage "usage: agent_blueprint_protocol_conformance [--results | --serve] --corpus <dir>"

  @doc false
  @spec run([binary()]) :: 0 | 1 | 2
  def run(argv) do
    :io.setopts(:standard_io, encoding: :latin1)

    with {:ok, dir, mode} <- parse(argv),
         {:ok, map} <- read_corpus(dir),
         {:ok, corpus} <- Corpus.load(map) do
      certified = if corpus.identity == @certified_digest, do: "matches", else: "does not match"
      IO.puts(:stderr, "corpus digest #{certified} the release-certified corpus")
      emit(corpus, mode)
    else
      :usage ->
        IO.puts(:stderr, @usage)
        2

      :unreadable ->
        # Value-free by construction: no path rides the channel.
        IO.puts(
          :stderr,
          "corpus unreadable: missing, unreadable, not regular, or over the file or byte ceiling"
        )

        2

      {:error, %_{} = error} ->
        IO.puts(:stderr, "corpus integrity failure: #{inspect(error.code)}")
        2
    end
  end

  defp parse(["--corpus", dir]) when is_binary(dir) and dir != "", do: {:ok, dir, :report}

  defp parse(["--results", "--corpus", dir]) when is_binary(dir) and dir != "",
    do: {:ok, dir, :results}

  defp parse(["--serve", "--corpus", dir]) when is_binary(dir) and dir != "",
    do: {:ok, dir, :serve}

  defp parse(_), do: :usage

  defp emit(corpus, :report) do
    results = Runner.run(corpus)
    report = Report.build(corpus, results)
    {:ok, bytes} = Report.to_bytes(corpus, results)
    IO.binwrite(bytes)
    report.exit_status
  end

  defp emit(corpus, :results) do
    {:ok, bytes} = Report.results_bytes(corpus)
    IO.binwrite(bytes)
    Report.build(corpus, Runner.run(corpus)).exit_status
  end

  defp emit(corpus, :serve) do
    handshake = %{
      "protocol" => "agent-blueprint-protocol-conformance-execution",
      "version" => 1,
      "corpus_digest" => corpus.identity,
      "registry_digest" => corpus.index["registry_digest"]
    }

    case read_line() do
      {:ok, ^handshake} ->
        write_line(handshake)
        serve(corpus)

      _ ->
        2
    end
  end

  defp serve(corpus) do
    case read_line() do
      :eof ->
        0

      {:ok, %{"id" => id, "surface" => surface, "input" => input} = request}
      when map_size(request) == 3 and is_binary(id) and is_binary(surface) and is_map(input) ->
        row = %{"id" => id, "surface" => surface, "input" => input, "expected" => %{}}
        write_line(%{"id" => id, "result" => Runner.project(row, corpus.data, corpus.raws)})
        serve(corpus)

      _ ->
        2
    end
  end

  defp read_line do
    case :io.request(:standard_io, {:get_line, :latin1, ""}) do
      :eof ->
        :eof

      line when is_binary(line) and byte_size(line) <= 5_000_000 ->
        with true <- String.ends_with?(line, "\n"),
             {:ok, value} <- AgentBlueprintProtocol.Json.decode(line),
             do: {:ok, plain(value)}

      _ ->
        :invalid
    end
  end

  defp plain(:null), do: nil
  defp plain({:object, members}), do: Map.new(members, fn {k, v} -> {k, plain(v)} end)
  defp plain({:array, values}), do: Enum.map(values, &plain/1)
  defp plain({_tag, value}), do: value

  defp write_line(value) do
    bytes = IO.iodata_to_binary(:json.encode(value, &encode_value/2))
    {:ok, tagged} = AgentBlueprintProtocol.Json.decode(bytes)
    {:ok, bytes} = AgentBlueprintProtocol.Canonicalization.encode(tagged)
    IO.binwrite(bytes <> "\n")
  end

  defp encode_value(nil, _encoder), do: "null"
  defp encode_value(value, encoder), do: :json.encode_value(value, encoder)

  # Reads EVERY file under the corpus directory — dotfiles included — so the
  # loader's file-set equality sees exactly what the directory carries.
  # The read is size-capped and total-failure typed: a hostile corpus
  # directory cannot exhaust memory or crash past the exit-code contract
  # (Bounds' byte ceiling is the single resource regime, applied here at
  # the byte source rather than only at decode).

  # macOS Finder droppings are never artifact content; a stray .DS_Store
  # would shift digests and red file-set equality on any Mac.
  defp macos_artifact?(path) do
    name = Path.basename(path)
    name == ".DS_Store" or String.starts_with?(name, "._")
  end

  defp read_corpus(dir) do
    case File.lstat(dir) do
      {:error, posix} ->
        # An absent directory is an empty corpus, which the loader refuses;
        # any other failure is unreadable.
        if posix == :enoent, do: {:ok, %{}}, else: :unreadable

      {:ok, %{type: :directory}} ->
        limits = AgentBlueprintProtocol.Bounds.maximum()

        case walk(dir, dir, {%{}, 0, 0}, limits) do
          {:ok, {map, _, _}} -> {:ok, map}
          :unreadable -> :unreadable
        end

      _ ->
        :unreadable
    end
  end

  defp walk(dir, root, acc, limits) do
    case File.ls(dir) do
      {:ok, names} ->
        Enum.reduce_while(names, {:ok, acc}, fn name, {:ok, state} ->
          walk_entry(Path.join(dir, name), root, state, limits)
        end)

      _ ->
        :unreadable
    end
  end

  defp walk_entry(path, root, state, limits) do
    result =
      if macos_artifact?(path), do: {:ok, state}, else: read_entry(path, root, state, limits)

    case result do
      {:ok, next} -> {:cont, {:ok, next}}
      _ -> {:halt, :unreadable}
    end
  end

  defp read_entry(_path, _root, {_map, count, _bytes}, limits) when count >= limits.members,
    do: :unreadable

  defp read_entry(path, root, state, limits) do
    with {:ok, stat} <- File.lstat(path), do: read_type(stat, path, root, state, limits)
  end

  defp read_type(%{type: :directory}, path, root, {map, count, total}, limits),
    do: walk(path, root, {map, count + 1, total}, limits)

  defp read_type(%{type: :regular, size: size}, path, root, {map, count, total}, limits) do
    remaining = limits.bytes - total

    with true <- size <= remaining,
         {:ok, bytes} <- read_bytes(path, remaining),
         true <- byte_size(bytes) <= remaining do
      rel = path |> Path.relative_to(root) |> Path.split() |> Enum.join("/")
      {:ok, {Map.put(map, rel, bytes), count + 1, total + byte_size(bytes)}}
    else
      _ -> :unreadable
    end
  end

  defp read_type(_, _, _, _, _), do: :unreadable

  defp read_bytes(path, cap) do
    case File.open(path, [:read, :binary], &IO.binread(&1, cap + 1)) do
      {:ok, bytes} when is_binary(bytes) -> {:ok, bytes}
      {:ok, :eof} -> {:ok, ""}
      _ -> :unreadable
    end
  end
end
