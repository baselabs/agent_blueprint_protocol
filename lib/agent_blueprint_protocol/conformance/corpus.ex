defmodule AgentBlueprintProtocol.Conformance.Corpus do
  @moduledoc """
    This module loads and validates a conformance corpus.

    Use it when preparing cases for the Runner or Report modules.

    This module does not authorize operations.

    ## Example

    ```elixir
    corpus_root = Application.app_dir(:agent_blueprint_protocol, "priv/conformance")
    files =
      Path.wildcard(Path.join(corpus_root, "**/*"))
      |> Enum.filter(&File.regular?/1)
      |> Map.new(fn path ->
        {Path.relative_to(path, corpus_root), File.read!(path)}
      end)
    match?({:ok, %AgentBlueprintProtocol.Conformance.Corpus{}}, AgentBlueprintProtocol.Conformance.Corpus.load(files))
    ```
  """
  @moduledoc since: "1.0.0"

  alias AgentBlueprintProtocol.{Canonicalization, Digest, Error, ExtensionRegistry, Json}

  @index_format "agent-blueprint-protocol-conformance-corpus-index"
  @case_file_format "agent-blueprint-protocol-conformance-cases"

  @enforce_keys [:index, :index_bytes, :cases, :data, :raws, :case_ids, :identity]
  defstruct [:index, :index_bytes, :cases, :data, :raws, :case_ids, :identity]

  @typedoc """
    The public data type for AgentBlueprintProtocol.Conformance.Corpus.
  """
  @type t :: %__MODULE__{}

  # --- the pinned floor (spec: Corpus applicability floor, 18 x 31) ----------

  @surfaces [
    "reconcile",
    "predicate",
    "json.decode",
    "canonicalization.encode",
    "base64url.decode",
    "digest.tagged",
    "signature.verify",
    "schema.validate_instance",
    "blueprint.decode",
    "deployment.decode",
    "negotiation.negotiate",
    "extension.resolve",
    "bounds.new",
    "bounds_algebra.intersect",
    "portability.scan",
    "compatibility.verify",
    "federation.decode",
    "federation.verify_commitment"
  ]

  @classes [
    "valid",
    "boundary_near",
    "exact_bound",
    "maximum_plus_one",
    "invalid_encoding",
    "invalid_duplicate",
    "invalid_type",
    "invalid_constraint",
    "invalid_cardinality",
    "unknown_member",
    "tamper_meaningful_byte",
    "digest_mismatch",
    "signature_invalid",
    "revision_above_max",
    "revision_below_min",
    "required_field_unsupported",
    "required_field_not_covered",
    "extension_unknown_critical",
    "extension_unknown_optional_roundtrip",
    "extension_criticality_conflict",
    "extension_schema_unavailable",
    "extension_deprecated_retained",
    "bound_widening_operational",
    "bound_widening_protected",
    "forbidden_portable_value",
    "compatibility_range_rejected",
    "binding_stale",
    "federation_state_unmappable",
    "federation_terminal_conflict",
    "audience_mismatch",
    "terminal_equivocation"
  ]

  @floor %{
    "reconcile" => %{
      required:
        ~w(valid invalid_type digest_mismatch revision_above_max unknown_member forbidden_portable_value signature_invalid binding_stale bound_widening_protected),
      n_a: "byte codecs, schema and federation checks have their own surfaces"
    },
    "predicate" => %{
      required:
        ~w(valid invalid_type invalid_constraint invalid_cardinality maximum_plus_one exact_bound),
      n_a: "artifact, signature, bounds and federation checks do not reach predicates"
    },
    "json.decode" => %{
      required:
        ~w(valid boundary_near exact_bound maximum_plus_one invalid_encoding invalid_duplicate invalid_type),
      n_a:
        "all artifact/negotiation/signature/bounds/federation classes - no such semantics reach the byte decoder"
    },
    "canonicalization.encode" => %{
      required:
        ~w(valid boundary_near exact_bound maximum_plus_one invalid_encoding tamper_meaningful_byte),
      n_a: "decode-side and artifact-layer classes - encoder consumes the tagged algebra only"
    },
    "base64url.decode" => %{
      required: ~w(valid invalid_encoding exact_bound),
      n_a: "all others - pure codec"
    },
    "digest.tagged" => %{
      required: ~w(valid invalid_encoding digest_mismatch tamper_meaningful_byte),
      n_a: "artifact/negotiation classes - digest layer sees bytes + tags only"
    },
    "signature.verify" => %{
      required:
        ~w(valid signature_invalid tamper_meaningful_byte invalid_encoding invalid_constraint),
      n_a: "bounds/federation/artifact classes - verification sees JWS inputs only"
    },
    "schema.validate_instance" => %{
      required: ~w(valid invalid_type invalid_constraint maximum_plus_one invalid_cardinality),
      n_a: "signature/digest/federation classes - instance validation is schema-local"
    },
    "blueprint.decode" => %{
      required:
        ~w(valid unknown_member invalid_type invalid_constraint invalid_cardinality maximum_plus_one forbidden_portable_value tamper_meaningful_byte),
      n_a:
        "federation/compatibility classes - deployment-side; revision classes owned by negotiation surface"
    },
    "deployment.decode" => %{
      required:
        ~w(valid unknown_member invalid_type invalid_constraint invalid_cardinality maximum_plus_one forbidden_portable_value tamper_meaningful_byte digest_mismatch binding_stale compatibility_range_rejected),
      n_a: "federation state classes - no task semantics"
    },
    "negotiation.negotiate" => %{
      required:
        ~w(valid revision_above_max revision_below_min required_field_unsupported required_field_not_covered extension_unknown_critical extension_criticality_conflict extension_schema_unavailable invalid_constraint invalid_cardinality),
      n_a: "byte/signature classes - negotiation consumes decoded headers"
    },
    "extension.resolve" => %{
      required:
        ~w(valid extension_unknown_critical extension_unknown_optional_roundtrip extension_criticality_conflict extension_deprecated_retained forbidden_portable_value invalid_constraint),
      n_a: "revision classes - owned by negotiation"
    },
    "bounds.new" => %{
      required: ~w(valid exact_bound maximum_plus_one invalid_type),
      n_a: "artifact classes - parse-ceiling struct only"
    },
    "bounds_algebra.intersect" => %{
      required:
        ~w(valid bound_widening_operational bound_widening_protected invalid_type invalid_constraint),
      n_a: "byte/signature classes - algebra consumes typed bound sets"
    },
    "portability.scan" => %{
      required: ~w(valid forbidden_portable_value),
      n_a: "all others - single-purpose guard"
    },
    "compatibility.verify" => %{
      required: ~w(valid compatibility_range_rejected invalid_constraint),
      n_a: "byte classes"
    },
    "federation.decode" => %{
      required:
        ~w(valid federation_state_unmappable unknown_member invalid_type forbidden_portable_value),
      n_a: "bounds classes - envelope carries commitments, not bound sets"
    },
    "federation.verify_commitment" => %{
      required:
        ~w(valid audience_mismatch federation_terminal_conflict terminal_equivocation signature_invalid),
      n_a: "decode classes - consumes decoded commitments"
    }
  }

  @spec surfaces() :: [binary()]
  @doc """
    Returns the known conformance surface names.

    ## Example

    ```elixir
    AgentBlueprintProtocol.Conformance.Corpus.surfaces()
    ```
  """
  @doc since: "1.0.0"
  def surfaces, do: @surfaces

  @spec classes() :: [binary()]
  @doc """
    Returns the known conformance case classes.

    ## Example

    ```elixir
    AgentBlueprintProtocol.Conformance.Corpus.classes()
    ```
  """
  @doc since: "1.0.0"
  def classes, do: @classes

  @spec floor() :: %{binary() => %{required: [binary()], n_a: binary()}}
  @doc """
    Returns the conformance corpus applicability floor.

    ## Example

    ```elixir
    AgentBlueprintProtocol.Conformance.Corpus.floor()
    ```
  """
  @doc since: "1.0.0"
  def floor, do: @floor

  @spec load(%{binary() => binary()}) :: {:ok, t()} | {:error, Error.t()}
  @doc """
    Loads and validates the conformance files supplied as a path-to-bytes map.

    ## Example

    ```elixir
    corpus_root = Application.app_dir(:agent_blueprint_protocol, "priv/conformance")
    files =
      Path.wildcard(Path.join(corpus_root, "**/*"))
      |> Enum.filter(&File.regular?/1)
      |> Map.new(fn path ->
        {Path.relative_to(path, corpus_root), File.read!(path)}
      end)

    match?({:ok, %AgentBlueprintProtocol.Conformance.Corpus{}}, AgentBlueprintProtocol.Conformance.Corpus.load(files))
    ```
  """
  @doc since: "1.0.0"
  def load(map) when is_map(map), do: load_census(map, :conformance)
  def load(_), do: {:error, %Error{code: :corpus_index_invalid, subject: ["index"]}}

  @doc false
  @spec load_prior_census(%{binary() => binary()}) :: {:ok, t()} | {:error, Error.t()}
  def load_prior_census(map) when is_map(map), do: load_census(map, :prior_census)

  def load_prior_census(_),
    do: {:error, %Error{code: :corpus_index_invalid, subject: ["index"]}}

  defp load_census(map, mode) when is_map(map) do
    with {:ok, index_bytes} <- fetch_index(map),
         {:ok, index} <- decode_index(index_bytes),
         :ok <- verify_structure(index),
         :ok <- verify_canonical_bytes(index, index_bytes),
         :ok <- verify_corpus_digest(index),
         :ok <- maybe_verify_registry_digest(mode, index),
         :ok <- verify_nonempty(index),
         {:ok, files} <- ordered_files(index),
         {:ok, cases, data, raws} <- load_files(files, map),
         :ok <- verify_file_set(files, map),
         :ok <- verify_hashes(files, map),
         :ok <- verify_counts(index, cases),
         :ok <- verify_case_ids(cases),
         :ok <- verify_case_validity(cases),
         :ok <- verify_applicability(index, cases, mode),
         :ok <- verify_raw_bindings(raws, cases) do
      {:ok,
       %__MODULE__{
         index: index,
         index_bytes: index_bytes,
         cases: cases,
         data: data,
         raws: raws,
         case_ids: case_id_set(cases),
         identity: Digest.to_tagged(corpus_digest_of(index))
       }}
    end
  end

  # The registry binding is a corpus-PROVENANCE check (a conformance census
  # certifies against the registry state of its release); the prior-census
  # mode suspends it and the compatibility gate owns divergence instead.
  defp maybe_verify_registry_digest(:conformance, index), do: verify_registry_digest(index)
  defp maybe_verify_registry_digest(:prior_census, _index), do: :ok

  # --- index -------------------------------------------------------------------

  defp fetch_index(map) do
    case Map.get(map, "index.json") do
      bytes when is_binary(bytes) -> {:ok, bytes}
      _ -> index_error()
    end
  end

  defp decode_index(bytes) do
    case Json.decode(bytes) do
      {:ok, {:object, _} = value} -> {:ok, to_plain(value)}
      _ -> index_error()
    end
  end

  defp index_error(subject \\ ["index"]),
    do: {:error, %Error{code: :corpus_index_invalid, subject: subject}}

  defp case_error(subject \\ ["cases"]),
    do: {:error, %Error{code: :corpus_case_invalid, subject: subject}}

  defp verify_structure(index) do
    with :ok <- verify_structure_scalars(index),
         :ok <- verify_structure_files(index["files"]) do
      verify_structure_applicability(index["applicability"])
    end
  end

  defp verify_structure_scalars(index) do
    cond do
      index["format"] != @index_format ->
        index_error()

      not is_integer(index["protocol_revision"]) or index["protocol_revision"] < 1 ->
        index_error()

      not is_integer(index["total_cases"]) ->
        index_error(["index", "total_cases"])

      not is_list(index["public_key_fingerprints"]) ->
        index_error()

      not is_binary(index["registry_digest"]) ->
        index_error(["index", "registry_digest"])

      not is_binary(index["corpus_digest"]) ->
        index_error(["index", "corpus_digest"])

      true ->
        :ok
    end
  end

  defp verify_structure_files(files) do
    files_ok? =
      is_list(files) and Enum.all?(files, &file_entry_ok?/1) and
        length(Enum.uniq_by(files, & &1["path"])) == length(files) and
        Enum.all?(files, &path_allowed?(&1["path"]))

    if files_ok?, do: :ok, else: index_error(["index", "files"])
  end

  defp verify_structure_applicability(applicability) do
    if is_map(applicability),
      do: :ok,
      else: index_error(["index", "applicability"])
  end

  defp file_entry_ok?(%{"path" => p, "sha256_base64url" => h, "cases" => c})
       when is_binary(p) and is_binary(h) and is_integer(c) and c >= 0,
       do: true

  defp file_entry_ok?(_), do: false

  defp path_allowed?(path) when is_binary(path) do
    allowed = fn prefix, ext ->
      String.starts_with?(path, prefix <> "/") and String.ends_with?(path, ext)
    end

    allowed.("cases", ".json") or allowed.("schemas", ".json") or
      allowed.("vectors", ".json") or allowed.("raw", ".raw")
  end

  defp verify_canonical_bytes(index, index_bytes) do
    case Canonicalization.encode(to_tagged(index)) do
      {:ok, ^index_bytes} -> :ok
      _ -> index_error()
    end
  end

  defp verify_corpus_digest(index) do
    if Digest.to_tagged(corpus_digest_of(index)) == index["corpus_digest"],
      do: :ok,
      else: index_error(["index", "corpus_digest"])
  end

  defp corpus_digest_of(index) do
    without = Map.delete(index, "corpus_digest")
    {:ok, jcs} = Canonicalization.encode(to_tagged(without))
    Digest.hash(:corpus_index, jcs)
  end

  defp verify_registry_digest(index) do
    if Digest.to_tagged(ExtensionRegistry.digest()) == index["registry_digest"],
      do: :ok,
      else: index_error(["index", "registry_digest"])
  end

  defp verify_nonempty(index) do
    if index["total_cases"] == 0,
      do: {:error, %Error{code: :corpus_empty, subject: ["index", "total_cases"]}},
      else: :ok
  end

  defp ordered_files(%{"files" => files}), do: {:ok, Enum.sort_by(files, & &1["path"])}

  # --- file loading -------------------------------------------------------------

  defp load_files(files, map) do
    Enum.reduce_while(files, {:ok, [], %{}, %{}}, fn entry, {:ok, cases, data, raws} ->
      case load_one_file(entry, map) do
        {:cases, file_cases} ->
          {:cont, {:ok, [{entry["path"], file_cases} | cases], data, raws}}

        {:raw, bytes} ->
          {:cont, {:ok, cases, data, Map.put(raws, entry["path"], bytes)}}

        {:data, value} ->
          {:cont, {:ok, cases, Map.put(data, entry["path"], value), raws}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> finalize_loaded_files()
  end

  defp load_one_file(entry, map) do
    path = entry["path"]

    case {Map.get(map, path), classify_file(path)} do
      {bytes, _} when not is_binary(bytes) ->
        {:error, %Error{code: :corpus_file_set_mismatch, subject: ["index", "files"]}}

      {bytes, :cases} ->
        case decode_case_file(bytes) do
          {:ok, file_cases} -> {:cases, file_cases}
          :error -> case_error()
        end

      {bytes, :raw} ->
        {:raw, bytes}

      {bytes, :data} ->
        case Json.decode(bytes) do
          {:ok, value} -> {:data, to_plain(value)}
          _ -> case_error()
        end
    end
  end

  defp classify_file(path) do
    cond do
      String.starts_with?(path, "cases/") -> :cases
      String.starts_with?(path, "raw/") -> :raw
      true -> :data
    end
  end

  defp finalize_loaded_files({:ok, cases, data, raws}), do: {:ok, Enum.reverse(cases), data, raws}
  defp finalize_loaded_files(error), do: error

  defp decode_case_file(bytes) do
    case Json.decode(bytes) do
      {:ok, {:object, members} = value} ->
        plain = to_plain(value)

        with {:string, @case_file_format} <- member(members, "format"),
             {:array, _} <- member(members, "cases") do
          {:ok, plain["cases"]}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp member(members, key) do
    case List.keyfind(members, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  # --- file-set + hashes ---------------------------------------------------------

  defp verify_file_set(files, map) do
    declared = files |> Enum.map(& &1["path"]) |> MapSet.new()
    present = map |> Map.keys() |> Enum.reject(&(&1 == "index.json")) |> MapSet.new()

    if MapSet.equal?(declared, present),
      do: :ok,
      else: {:error, %Error{code: :corpus_file_set_mismatch, subject: ["index", "files"]}}
  end

  defp verify_hashes(files, map) do
    Enum.reduce_while(files, :ok, fn entry, :ok ->
      bytes = Map.fetch!(map, entry["path"])

      if sha256_b64(bytes) == entry["sha256_base64url"],
        do: {:cont, :ok},
        else: {:halt, {:error, %Error{code: :corpus_hash_mismatch, subject: ["index", "files"]}}}
    end)
  end

  # --- counts --------------------------------------------------------------------

  defp verify_counts(%{"total_cases" => total, "files" => files}, cases) do
    per_file = Map.new(cases, fn {path, list} -> {path, length(list)} end)

    files
    |> Enum.reduce_while({:ok, 0}, fn entry, {:ok, acc} ->
      path = entry["path"]

      cond do
        String.starts_with?(path, "cases/") and Map.get(per_file, path) == entry["cases"] ->
          {:cont, {:ok, acc + entry["cases"]}}

        not String.starts_with?(path, "cases/") and entry["cases"] == 0 ->
          {:cont, {:ok, acc}}

        true ->
          {:halt,
           {:error, %Error{code: :corpus_count_mismatch, subject: ["index", "total_cases"]}}}
      end
    end)
    |> case do
      {:ok, ^total} -> :ok
      _ -> {:error, %Error{code: :corpus_count_mismatch, subject: ["index", "total_cases"]}}
    end
  end

  # --- case ids + case validity -----------------------------------------------------

  defp verify_case_ids(cases) do
    all_ids = cases |> Enum.flat_map(&elem(&1, 1)) |> Enum.map(& &1["id"])

    if Enum.all?(all_ids, &is_binary/1) and length(all_ids) == MapSet.size(MapSet.new(all_ids)),
      do: :ok,
      else: {:error, %Error{code: :corpus_case_id_duplicate, subject: ["cases"]}}
  end

  defp verify_case_validity(cases) do
    all = cases |> Enum.flat_map(&elem(&1, 1))
    by_id = Map.new(all, &{&1["id"], &1})

    shape_ok? =
      Enum.all?(all, fn case_obj ->
        # A verdict-only valid expectation agrees with any ok-map — the
        # vacuous green; a valid case must
        # pin at least one projection field.
        is_map(case_obj) and is_binary(case_obj["id"]) and
          case_obj["surface"] in @surfaces and
          case_obj["class"] in @classes and
          is_map(case_obj["input"]) and is_map(case_obj["expected"]) and
          not (case_obj["expected"]["verdict"] == "valid" and map_size(case_obj["expected"]) == 1)
      end)

    if shape_ok?, do: verify_tampers(all, by_id), else: case_error()
  end

  # A tamper case's verbatim artifact must byte-equal the re-derived
  # base-with-one-meaningful-byte-flip on the ADDRESSED target. The target
  # names where the case carries its bytes; base and tamper case resolve
  # through the SAME target, so the audit binds to the addressed artifact.
  defp verify_tampers(all, by_id) do
    Enum.reduce_while(all, :ok, fn case_obj, :ok ->
      case check_one_tamper(case_obj, Map.get(case_obj, "tamper"), by_id) do
        :ok -> {:cont, :ok}
        :invalid -> {:halt, case_error(["cases", "tamper"])}
      end
    end)
  end

  defp check_one_tamper(_case_obj, nil, _by_id), do: :ok

  defp check_one_tamper(case_obj, tamper, by_id),
    do: do_check_tamper(case_obj, tamper, by_id)

  defp do_check_tamper(case_obj, tamper, by_id) do
    with %{"base_case" => base_id} when is_binary(base_id) <- tamper,
         byte_index when is_integer(byte_index) and byte_index >= 0 <- tamper["byte_index"],
         xor when is_integer(xor) and xor > 0 <- tamper["xor"],
         %{} = base <- Map.get(by_id, base_id),
         {:ok, base_bytes} <- tamper_target_bytes(base, tamper),
         {:ok, verbatim_bytes} <- tamper_target_bytes(case_obj, tamper) do
      if derive_tampered(base_bytes, byte_index, xor) == verbatim_bytes, do: :ok, else: :invalid
    else
      _ -> :invalid
    end
  end

  defp derive_tampered(base_bytes, index, xor) do
    size = byte_size(base_bytes)

    if index < size do
      <<pre::binary-size(^index), byte, post::binary>> = base_bytes
      pre <> <<Bitwise.bxor(byte, xor)>> <> post
    else
      :error
    end
  end

  defp tamper_target_bytes(case_obj, %{"target" => target}) do
    resolve_target(case_obj["input"], target)
  end

  defp tamper_target_bytes(case_obj, _), do: resolve_target(case_obj["input"], nil)

  defp resolve_target(input, target) when is_map(input) do
    case target do
      nil -> default_target(input)
      "input.text" -> text_target(input)
      "input.base64url" -> b64_target(input)
      "input.entry" -> named_target(input, "entry")
      _ -> :error
    end
  end

  # A surface-specific byte-bearing key (e.g. signature.verify's JWS entry).
  defp named_target(input, key) do
    if is_binary(input[key]), do: {:ok, input[key]}, else: :error
  end

  defp default_target(input) do
    cond do
      is_binary(input["text"]) -> {:ok, input["text"]}
      is_binary(input["base64url"]) -> b64_decode(input["base64url"])
      true -> :error
    end
  end

  defp text_target(input) do
    if is_binary(input["text"]), do: {:ok, input["text"]}, else: :error
  end

  defp b64_target(input) do
    if is_binary(input["base64url"]), do: b64_decode(input["base64url"]), else: :error
  end

  defp b64_decode(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> :error
    end
  end

  # --- applicability (against the compiled-in floor) ----------------------------------

  defp verify_applicability(%{"applicability" => applicability}, cases, :conformance) do
    with :ok <- verify_applicability_shape(applicability),
         :ok <- verify_floor_required(applicability) do
      verify_observed(applicability, observed_counts(cases))
    end
  end

  # Prior-census mode: the census's applicability map is checked against the
  # census's OWN cases (both directions) instead of the compiled floor — a
  # released census was authored against the floor of its release.
  defp verify_applicability(%{"applicability" => applicability}, cases, :prior_census) do
    verify_observed_census(applicability, observed_counts(cases))
  end

  defp verify_observed_census(applicability, observed) do
    marked_ok? =
      applicability
      |> Enum.all?(fn {surface, leaves} ->
        is_binary(surface) and is_map(leaves) and
          Enum.all?(leaves, fn {class, mark} ->
            observed_leaf_ok?(mark, Map.get(observed, {surface, class}, 0))
          end)
      end)

    unmarked_ok? =
      observed
      |> Enum.all?(fn {{surface, class}, _count} ->
        case applicability do
          %{^surface => %{^class => _mark}} -> true
          _ -> false
        end
      end)

    if marked_ok? and unmarked_ok?, do: :ok, else: applicability_error()
  end

  defp applicability_error,
    do:
      {:error,
       %Error{code: :corpus_applicability_incomplete, subject: ["index", "applicability"]}}

  defp verify_applicability_shape(applicability) do
    surface_ok? =
      MapSet.equal?(MapSet.new(Map.keys(applicability)), MapSet.new(@surfaces)) and
        Enum.all?(@surfaces, fn surface ->
          leaves = Map.get(applicability, surface)
          is_map(leaves) and MapSet.equal?(MapSet.new(Map.keys(leaves)), MapSet.new(@classes))
        end)

    if surface_ok?, do: :ok, else: applicability_error()
  end

  defp verify_floor_required(applicability) do
    ok? =
      Enum.all?(@floor, fn {surface, %{required: required}} ->
        leaves = Map.get(applicability, surface)
        Enum.all?(required, &required_leaf_ok?(leaves[&1]))
      end)

    if ok?, do: :ok, else: applicability_error()
  end

  defp required_leaf_ok?(n) when is_integer(n) and n >= 1, do: true
  defp required_leaf_ok?(_), do: false

  defp observed_counts(cases) do
    cases
    |> Enum.flat_map(&elem(&1, 1))
    |> Enum.reduce(%{}, fn case_obj, acc ->
      Map.update(acc, {case_obj["surface"], case_obj["class"]}, 1, &(&1 + 1))
    end)
  end

  defp verify_observed(applicability, observed) do
    ok? =
      Enum.all?(@surfaces, fn surface ->
        leaves = Map.fetch!(applicability, surface)

        Enum.all?(@classes, fn class ->
          observed_leaf_ok?(Map.fetch!(leaves, class), Map.get(observed, {surface, class}, 0))
        end)
      end)

    if ok?, do: :ok, else: applicability_error()
  end

  defp observed_leaf_ok?(n, observed_count) when is_integer(n), do: observed_count == n

  defp observed_leaf_ok?(%{"n_a" => reason}, observed_count),
    do: is_binary(reason) and reason != "" and observed_count == 0

  defp observed_leaf_ok?(_, _), do: false

  # --- raw bindings ---------------------------------------------------------------------

  defp verify_raw_bindings(raws, cases) do
    cases
    |> Enum.flat_map(&elem(&1, 1))
    |> Enum.reduce_while(:ok, fn case_obj, :ok ->
      case check_raw_binding(case_obj, raws) do
        :ok -> {:cont, :ok}
        :invalid -> {:halt, case_error()}
      end
    end)
  end

  defp check_raw_binding(
         %{"input" => %{"raw_file" => raw_path, "sha256_base64url" => ref_hash}},
         raws
       ) do
    case Map.get(raws, raw_path) do
      bytes when is_binary(bytes) ->
        if sha256_b64(bytes) == ref_hash, do: :ok, else: :invalid

      _ ->
        :invalid
    end
  end

  defp check_raw_binding(_case_obj, _raws), do: :ok

  # --- projections -------------------------------------------------------------------------

  defp to_plain({:object, members}),
    do: members |> Enum.map(fn {k, v} -> {k, to_plain(v)} end) |> Map.new()

  defp to_plain({:array, items}), do: Enum.map(items, &to_plain/1)
  defp to_plain({:string, s}), do: s
  defp to_plain({:integer, n}), do: n
  defp to_plain({:float, n}), do: n
  defp to_plain({:boolean, b}), do: b
  defp to_plain(:null), do: nil

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

  defp case_id_set(cases) do
    cases |> Enum.flat_map(&elem(&1, 1)) |> Enum.map(& &1["id"]) |> MapSet.new()
  end

  defp sha256_b64(bytes), do: Base.url_encode64(:crypto.hash(:sha256, bytes), padding: false)
end
