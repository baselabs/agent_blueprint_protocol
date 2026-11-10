defmodule AgentBlueprintProtocol.Conformance.Cli do
  @moduledoc """
  The conformance CLI : `--corpus <dir>` is REQUIRED
  — no default, so a vacuous run is impossible — and the exit status is the
  agreement verdict:

  - `0` complete agreement;
  - `1` any disagreement;
  - `2` usage error or corpus integrity failure.

  This module and its `Main` entry are the ONLY filesystem touchers in the
  package (the `no_file_access` architecture gate carves out exactly these
  beams). Everything downstream of reading the directory is the pure
  loader/runner/report.
  The CLI reports conformance facts; it never authorizes anything.
  """

  alias AgentBlueprintProtocol.Conformance.{Corpus, Report, Runner}

  @metadata_path Path.expand("../../../priv/release-metadata.json", __DIR__)
  @external_resource @metadata_path
  @certified_digest @metadata_path
                    |> File.read!()
                    |> :json.decode()
                    |> Map.fetch!("corpus_digest")

  @usage "usage: agent_blueprint_protocol_conformance --corpus <dir>"

  @doc """
  Runs the CLI over `argv`. Returns the exit status (never halts — the
  escript entry owns `System.halt/1`).
  """
  @spec run([binary()]) :: 0 | 1 | 2
  def run(argv) do
    with {:ok, dir} <- parse(argv),
         {:ok, map} <- read_corpus(dir),
         {:ok, corpus} <- Corpus.load(map),
         :ok <- reader_inputs(corpus) do
      certified = if corpus.identity == @certified_digest, do: "matches", else: "does not match"
      IO.puts(:stderr, "corpus digest #{certified} the release-certified corpus")
      results = Runner.run(corpus)
      report = Report.build(corpus, results)

      # The report shape is fixed and fully canonicalizable, so encoding
      # cannot fail; a mismatch here is an internal invariant and escapes
      # loudly rather than laundering into an exit code.
      {:ok, bytes} = Report.to_bytes(corpus, results)
      IO.binwrite(bytes)
      report.exit_status
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

  defp reader_inputs(%Corpus{cases: files}) do
    readable? = Enum.all?(files, fn {_, rows} -> Enum.all?(rows, &reader_input?/1) end)
    if readable?, do: :ok, else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
  end

  defp reader_input?(%{"surface" => surface, "input" => input})
       when surface in ["negotiation.negotiate", "extension.resolve"] do
    case Map.get(input, "support") do
      nil ->
        true

      support when is_map(support) ->
        fields_shape?(support, [
          {"revisions", &is_list/1},
          {"core_fields", &is_list/1},
          {"schemas", &is_map/1},
          {"registry", &registry_shape?/1}
        ])

      _ ->
        false
    end
  end

  defp reader_input?(%{"surface" => "bounds_algebra.intersect", "input" => input}) do
    Enum.all?(["blueprint", "deployment", "host"], fn key ->
      fields_shape?(input, [{key, &bound_map_shape?/1}])
    end)
  end

  defp reader_input?(_), do: true

  defp fields_shape?(map, fields),
    do:
      Enum.all?(fields, fn {key, predicate} ->
        not Map.has_key?(map, key) or predicate.(map[key])
      end)

  defp registry_shape?(map) when is_map(map),
    do: Enum.all?(map, fn {_, entry} -> is_map(entry) end)

  defp registry_shape?(_), do: false

  defp bound_map_shape?(map) when is_map(map) do
    Enum.all?(map, fn
      {_, %{"ordinal" => _} = value} -> fields_shape?(value, [{"markers", &is_list/1}])
      _ -> true
    end)
  end

  defp bound_map_shape?(_), do: false

  defp parse(["--corpus", dir]) when is_binary(dir) and dir != "", do: {:ok, dir}
  defp parse(_), do: :usage

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
