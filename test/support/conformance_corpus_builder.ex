defmodule AgentBlueprintProtocol.ConformanceTest.Builder do
  @moduledoc """
  Test-fixture authoring for the conformance corpus: builds a floor-valid
  `%{path => binary}` corpus map from a case list, exactly as the shipped
  corpus is authored (canonical JCS index bytes, per-file hashes, applicability
  derived from the cases, the pinned registry digest, the corpus digest).

  Test-only. The LOADER owns verification; this builder only produces bytes —
  if the builder's formula drifts from the loader's, the loader reds (that is
  the check working, not a nuisance).
  """

  alias AgentBlueprintProtocol.{Canonicalization, Digest, ExtensionRegistry, Json}
  alias AgentBlueprintProtocol.Conformance.Corpus

  @index_format "agent-blueprint-protocol-conformance-corpus-index"
  @case_file_format "agent-blueprint-protocol-conformance-cases"

  # One trivial case per REQUIRED floor cell: the smallest corpus the loader
  # can accept. Inputs/expectations are opaque to the loader (the Runner owns
  # execution), so a uniform invalid-expectation body suffices.
  def minimal_cases do
    for {surface, %{required: required}} <- Corpus.floor(),
        class <- required,
        do: %{
          "id" => "minimal-" <> String.replace(surface, ".", "-") <> "-" <> class,
          "surface" => surface,
          "class" => class,
          # The scalar tail exercises the builder's tagged/plain projections
          # (float, boolean, null) — inert to the loader, covered in build.
          "input" => %{"scalar_tail" => [1.5, true, nil]},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        }
  end

  @doc """
  Build a floor-valid corpus map over `cases` (raws: %{path => bytes};
  data: %{path => plain_map} for schemas/ and vectors/ files, written as
  canonical JSON with zero cases).
  """
  def build(cases, raws \\ %{}, opts \\ []) do
    data_files =
      opts
      |> Keyword.get(:data, %{})
      |> Enum.map(fn {path, value} -> {path, value} end)
      |> Enum.map(fn {path, value} ->
        {:ok, bytes} = encode_canonical(to_tagged(value))
        {path, bytes, 0}
      end)
      |> Enum.sort_by(&elem(&1, 0))

    build_with_files(cases, raws, data_files, opts)
  end

  defp build_with_files(cases, raws, data_files, opts) do
    case_files =
      cases
      |> Enum.group_by(& &1["surface"], & &1)
      |> Enum.map(fn {surface, file_cases} ->
        path = "cases/" <> String.replace(surface, ".", "-") <> ".json"
        body = %{"format" => @case_file_format, "cases" => Enum.sort_by(file_cases, & &1["id"])}
        {:ok, bytes} = encode_canonical(to_tagged(body))
        {path, bytes, length(file_cases)}
      end)
      |> Enum.sort_by(&elem(&1, 0))

    raw_files =
      raws
      |> Enum.map(fn {path, bytes} -> {path, bytes, 0} end)
      |> Enum.sort_by(&elem(&1, 0))

    files =
      (case_files ++ raw_files ++ data_files)
      |> Enum.map(fn {path, bytes, count} ->
        %{"path" => path, "sha256_base64url" => sha(bytes), "cases" => count}
      end)

    index =
      %{
        "format" => @index_format,
        "protocol_revision" => 1,
        # Scalar-typed authoring extras ride through build + update round-trips.
        "float_extra" => Keyword.get(opts, :float_extra, 1.5),
        "bool_extra" => Keyword.get(opts, :bool_extra, false),
        "null_extra" => Keyword.get(opts, :null_extra, nil),
        "files" => files,
        "total_cases" => length(cases),
        "public_key_fingerprints" => Keyword.get(opts, :public_key_fingerprints, []),
        "applicability" => applicability(cases),
        "registry_digest" =>
          Keyword.get(opts, :registry_digest, Digest.to_tagged(ExtensionRegistry.digest()))
      }
      |> Map.put("corpus_digest", "sha-256:pending")

    {:ok, index_bytes} =
      index
      |> put_corpus_digest()
      |> to_tagged()
      |> encode_canonical()

    map = %{"index.json" => index_bytes}

    (case_files ++ raw_files ++ data_files)
    |> Enum.reduce(map, fn {path, bytes, _}, acc -> Map.put(acc, path, bytes) end)
  end

  @doc "Rewrite one file's bytes and re-sync its index hash + the corpus digest."
  def resync_file(map, path, bytes) do
    update_index(map, fn index ->
      files = Enum.map(index["files"], &resync_entry(&1, path, bytes))
      Map.put(index, "files", files)
    end)
    |> Map.put(path, bytes)
  end

  @doc "Apply `fun` to the decoded index and re-canonicalize it (`redigest: false` keeps a deliberately-stale corpus_digest)."
  def update_index(map, fun, opts \\ []) do
    {:ok, index} = Json.decode(Map.fetch!(map, "index.json"))

    index =
      index
      |> to_plain()
      |> fun.()
      |> then(fn index ->
        if Keyword.get(opts, :redigest, true), do: put_corpus_digest(index), else: index
      end)

    {:ok, bytes} = encode_canonical(to_tagged(index))
    Map.put(map, "index.json", bytes)
  end

  # --- applicability derivation ---------------------------------------------

  defp applicability(cases) do
    floor = Corpus.floor()

    counts =
      Enum.reduce(cases, %{}, fn case_obj, acc ->
        Map.update(acc, {case_obj["surface"], case_obj["class"]}, 1, &(&1 + 1))
      end)

    Map.new(floor, fn {surface, %{required: required, n_a: reason}} ->
      leaves =
        Corpus.classes()
        |> Enum.sort()
        |> Map.new(&surface_leaf(&1, required, reason, counts, surface))

      {surface, leaves}
    end)
  end

  defp surface_leaf(class, required, reason, counts, surface) do
    if class in required,
      do: {class, Map.get(counts, {surface, class}, 0)},
      else: {class, %{"n_a" => reason}}
  end

  # A top-level string member's value from a tagged object (generator parity).
  def member_string({:object, members}, name) do
    case List.keyfind(members, name, 0) do
      {^name, {:string, v}} -> v
      _ -> nil
    end
  end

  # --- digest + encoding ------------------------------------------------------

  defp put_corpus_digest(index) do
    without = Map.delete(index, "corpus_digest")
    {:ok, jcs} = encode_canonical(to_tagged(without))
    Map.put(without, "corpus_digest", Digest.to_tagged(Digest.hash(:corpus_index, jcs)))
  end

  defp resync_entry(%{"path" => path} = entry, path, bytes),
    do: Map.put(entry, "sha256_base64url", sha(bytes))

  defp resync_entry(entry, _path, _bytes), do: entry

  defp sha(bytes), do: Base.url_encode64(:crypto.hash(:sha256, bytes), padding: false)

  defp encode_canonical(value), do: Canonicalization.encode(value)

  # --- plain <-> tagged (string-keyed maps in, tagged algebra out) ------------

  defp to_tagged(value) do
    cond do
      is_map(value) ->
        {:object,
         value |> Enum.map(fn {k, v} -> {k, to_tagged(v)} end) |> Enum.sort_by(&elem(&1, 0))}

      is_list(value) ->
        {:array, Enum.map(value, &to_tagged/1)}

      is_integer(value) ->
        {:integer, value}

      is_boolean(value) ->
        {:boolean, value}

      is_binary(value) ->
        {:string, value}

      is_float(value) ->
        {:float, value}

      true ->
        :null
    end
  end

  defp to_plain({:object, members}),
    do: members |> Enum.map(fn {k, v} -> {k, to_plain(v)} end) |> Map.new()

  defp to_plain({:array, items}), do: Enum.map(items, &to_plain/1)
  defp to_plain({:string, s}), do: s
  defp to_plain({:integer, n}), do: n
  defp to_plain({:float, n}), do: n
  defp to_plain({:boolean, b}), do: b
  defp to_plain(:null), do: nil
end
