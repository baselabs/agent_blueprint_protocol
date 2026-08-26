defmodule AgentBlueprintProtocol.Conformance.Runner do
  @moduledoc """
  The pure case executor over a loaded corpus: dispatches each
  case against the package's PUBLIC module surface — the runner adds no
  protocol capability of its own — and compares the result to the case's
  expectation.

  Expectations are CODE-LEVEL and shape-agnostic: an invalid case names the
  expected error code (`"ceiling:<key>"` renders the parameterized family),
  and every failure — bare atom or `%Error{}` — projects to the same code
  string before comparison. A valid case names per-surface projection fields;
  byte-bearing projections compare by base64url fallback (the expected value
  decodes to the actual bytes).

  The `federation.decode` surface includes the carrier/state codecs (the
  settled ruling: `federation_state_unmappable` is emitted by the codecs, not
  by envelope decode). The `extension.resolve` surface runs Negotiation's
  extension region walk over minimal artifact values — that walk is where
  every extension-class code is emitted on the live substrate.
  The runner executes corpus cases and reports outcomes; it never authorizes anything.
  The runner executes corpus cases and reports outcomes; it never authorizes anything.
  """

  alias AgentBlueprintProtocol.{
    Base64Url,
    Blueprint,
    Bounds,
    BoundsAlgebra,
    Canonicalization,
    Compatibility,
    Deployment,
    Digest,
    Error,
    ExtensionRegistry,
    Federation,
    Json,
    Negotiation,
    Portability,
    Schema,
    Signature
  }

  alias AgentBlueprintProtocol.Conformance.Corpus

  @bounds_keys %{
    "bytes" => :bytes,
    "depth" => :depth,
    "members" => :members,
    "items" => :items,
    "nodes" => :nodes,
    "string" => :string,
    "key" => :key,
    "number_lexeme" => :number_lexeme
  }

  # Compile-time string→atom maps: no runtime atom creation anywhere in the
  # runner (the architecture gate's rule, by precedent).
  @bound_name_atoms Map.new(BoundsAlgebra.names(), &{Atom.to_string(&1), &1})

  @logical_states %{
    "submitted" => :submitted,
    "working" => :working,
    "completed" => :completed,
    "failed" => :failed,
    "canceled" => :canceled,
    "rejected" => :rejected,
    "input_required" => :input_required,
    "auth_required" => :auth_required
  }

  @digest_domains %{
    "blueprint_content" => :blueprint_content,
    "deployment_content" => :deployment_content,
    "federation_envelope" => :federation_envelope,
    "signature" => :signature,
    "extension_schema" => :extension_schema,
    "extension_registry" => :extension_registry,
    "conformance_report" => :conformance_report,
    "corpus_index" => :corpus_index
  }

  @type result :: %{case_id: binary(), agree: boolean()}

  @doc "Executes every loaded case; `%{case_id, agree}` per case, per file."
  @spec run(Corpus.t()) :: [{binary(), [result()]}]
  def run(%Corpus{cases: cases, data: data, raws: raws}) do
    Enum.map(cases, fn {path, file_cases} ->
      results =
        Enum.map(file_cases, fn case_obj ->
          {_actual, agree} = execute(case_obj, data, raws)
          %{case_id: case_obj["id"], agree: agree}
        end)

      {path, results}
    end)
  end

  @doc """
  Executes one case and returns `{actual, agree?}` — the same dispatch and
  agreement machinery `run/1` uses. Tooling surface (the corpus generator,
  the second-language mirror's cross-checks); hosts use `run/1`.
  """
  @spec execute(map(), map(), map()) :: {term(), boolean()}
  def execute(case_obj, data, raws) do
    input = Map.get(case_obj, "input", %{})
    expected = Map.get(case_obj, "expected", %{})
    actual = dispatch(case_obj["surface"], input, data, raws)
    {actual, agrees?(expected, actual)}
  end

  # --- agreement ---------------------------------------------------------------

  defp agrees?(%{"verdict" => "invalid"} = expected, actual) do
    case actual do
      {:error, reason} -> project_code(reason) == expected["code"]
      _ -> false
    end
  end

  defp agrees?(%{"verdict" => "valid"} = expected, actual) do
    projections = Map.delete(expected, "verdict")

    # A verdict-only valid expectation agrees with ANY ok-map — the vacuous
    # green an adversarial pass caught. Valid cases
    # must pin at least one projection; the loader enforces the same rule
    # at authoring so such a case cannot ship.
    if map_size(projections) == 0 do
      false
    else
      valid_projections_agree?(projections, actual)
    end
  end

  defp agrees?(_expected, _actual), do: false

  defp valid_projections_agree?(projections, {:ok, projection}) when is_map(projection) do
    Enum.all?(projections, fn {key, want} ->
      compare(want, Map.get(projection, key, :no_projection))
    end)
  end

  defp valid_projections_agree?(_projections, _actual), do: false

  # Every failure shape projects to one code string: bare atoms, %Error{}
  # records, and the parameterized ceiling family.
  defp project_code(%Error{} = error), do: project_code(error.code)
  defp project_code({:ceiling, key}), do: "ceiling:" <> Atom.to_string(key)
  defp project_code(code) when is_atom(code), do: Atom.to_string(code)

  defp compare(_want, :no_projection), do: false

  defp compare(want, got) when is_binary(want) and is_binary(got) do
    want == got or byte_fallback(want, got)
  end

  defp compare(want, got), do: want == got

  defp byte_fallback(want, got) do
    case Base.url_decode64(want, padding: false) do
      {:ok, decoded} -> decoded == got
      :error -> false
    end
  end

  # --- dispatch ------------------------------------------------------------------

  # Slim router over the family dispatchers (one per surface family, so no
  # single multi-clause function carries the whole table's complexity).
  @byte_surfaces ~w(json.decode canonicalization.encode base64url.decode digest.tagged)

  @artifact_surfaces ~w(blueprint.decode deployment.decode signature.verify schema.validate_instance)
  @negotiation_surfaces ~w(negotiation.negotiate extension.resolve)
  @bound_surfaces ~w(bounds.new bounds_algebra.intersect)

  @late_surfaces ~w(portability.scan compatibility.verify federation.decode federation.verify_commitment)

  @federation_codec_keys ~w(from_a2a_state to_a2a_state from_mcp_state to_mcp_state from_a2a_carrier from_mcp_carrier)

  # The protected lattices are atom-typed in the algebra; JSON case inputs
  # carry strings, so they convert through this compile-time map (an
  # off-lattice string passes through and the algebra denies it — the runner
  # does not pre-filter judgment).
  @lattice_atoms Map.new(
                   ~w(public internal confidential restricted none local_policy external_authority_required human_required separated_human_required ordinary money authority secret summary detail full pci phi)a,
                   &{Atom.to_string(&1), &1}
                 )

  defp dispatch(surface, input, data, raws) do
    cond do
      surface in @byte_surfaces -> dispatch_bytes(surface, input, data, raws)
      surface in @artifact_surfaces -> dispatch_artifact(surface, input, data, raws)
      surface in @negotiation_surfaces -> dispatch_negotiation(surface, input, data, raws)
      surface in @bound_surfaces -> dispatch_bounds(surface, input, data, raws)
      surface in @late_surfaces -> dispatch_late(surface, input, data, raws)
      true -> {:error, :invalid_type}
    end
  end

  defp dispatch_bytes("json.decode", input, _data, raws) do
    with {:ok, overrides} <- bounds_overrides(input),
         {:ok, bytes} <- input_bytes(input, raws),
         {:ok, value} <- Json.decode(bytes, overrides) do
      {:ok, %{"value" => to_plain(value)}}
    end
  end

  defp dispatch_bytes("canonicalization.encode", input, _data, raws) do
    with {:ok, bytes} <- input_bytes(input, raws),
         {:ok, value} <- Json.decode(bytes, Bounds.maximum()),
         {:ok, overrides} <- bounds_overrides(input),
         {:ok, encoded} <- Canonicalization.encode(value, overrides) do
      {:ok, %{"encoded" => encoded}}
    end
  end

  defp dispatch_bytes("base64url.decode", input, _data, _raws) do
    with {:ok, segment} <- fetch_binary(input, "base64url"),
         {:ok, decoded} <- Base64Url.decode(segment) do
      {:ok, %{"decoded" => decoded}}
    end
  end

  defp dispatch_bytes("digest.tagged", input, _data, raws) do
    cond do
      is_binary(input["tagged"]) ->
        case Digest.from_tagged(input["tagged"]) do
          {:ok, digest} -> {:ok, %{"tagged" => Digest.to_tagged(digest)}}
          error -> error
        end

      is_binary(input["text"]) and is_binary(input["declared"]) ->
        verify_tagged_content(input, raws)

      true ->
        {:error, :invalid_type}
    end
  end

  defp verify_tagged_content(input, raws) do
    with {:ok, bytes} <- input_bytes(input, raws),
         {:ok, domain} <- fetch_domain(input) do
      case Digest.verify_content(domain, bytes, input["declared"]) do
        :ok -> {:ok, %{"verified" => true}}
        error -> error
      end
    end
  end

  defp dispatch_artifact("blueprint.decode", input, _data, raws) do
    with {:ok, overrides} <- bounds_overrides(input),
         {:ok, bytes} <- input_bytes(input, raws) do
      case Blueprint.decode(bytes, overrides) do
        {:ok, %Blueprint{} = blueprint} -> project_artifact(blueprint)
        error -> error
      end
    end
  end

  defp dispatch_artifact("deployment.decode", input, _data, raws) do
    with {:ok, overrides} <- bounds_overrides(input),
         {:ok, bytes} <- input_bytes(input, raws),
         {:ok, %Deployment{} = deployment} <- Deployment.decode(bytes, overrides) do
      project_deployment(deployment, input)
    end
  end

  defp dispatch_artifact("signature.verify", input, _data, _raws) do
    with {:ok, entry_text} <- fetch_binary(input, "entry"),
         {:ok, entry} <- Json.decode(entry_text),
         {:ok, keys} <- build_keys(input) do
      case Signature.verify(entry, keys) do
        {:ok, :verified} -> {:ok, %{"verified" => true}}
        error -> error
      end
    end
  end

  defp dispatch_artifact("schema.validate_instance", input, data, _raws) do
    with {:ok, schema} <- schema_input(input, data),
         {:ok, instance} <- tagged_field(input, "instance"),
         {:ok, dialect} <- dialect_input(input) do
      case Schema.validate_instance(schema, instance, dialect) do
        :ok -> {:ok, %{"valid" => true}}
        error -> error
      end
    end
  end

  # The floor's deployment.decode row covers the binding classes too: when a
  # case carries binding observations + the bound blueprint, the dispatch
  # additionally runs verify_binding (the live emitter of binding_stale).
  defp project_deployment(deployment, %{"binding" => binding}) do
    with {:ok, blueprint_bytes} <- fetch_binary(binding, "blueprint"),
         {:ok, %Blueprint{} = blueprint} <- Blueprint.decode(blueprint_bytes) do
      obs = %Deployment.Observations{
        now: binding["now"] && parse_time(binding["now"]),
        max_attestation_age_ms: binding["max_attestation_age_ms"],
        observed: %{}
      }

      case Deployment.verify_binding(deployment, blueprint, obs) do
        :ok -> project_artifact(deployment)
        error -> error
      end
    end
  end

  defp project_deployment(deployment, _input), do: project_artifact(deployment)

  defp parse_time(binary) do
    case DateTime.from_iso8601(binary) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp dispatch_negotiation("negotiation.negotiate", input, _data, _raws) do
    with {:ok, artifact} <- tagged_field(input, "artifact"),
         {:ok, support} <- build_support(input) do
      project_negotiation(Negotiation.negotiate(artifact, support))
    end
  end

  defp dispatch_negotiation("extension.resolve", input, _data, _raws) do
    with {:ok, artifact} <- tagged_field(input, "artifact"),
         {:ok, support} <- build_support(input) do
      project_negotiation(Negotiation.negotiate(artifact, support))
    end
  end

  defp dispatch_bounds("bounds.new", input, _data, _raws) do
    with {:ok, overrides} <- bounds_overrides(input) do
      case Bounds.new(overrides) do
        {:ok, bounds} ->
          {:ok,
           %{
             "bounds" =>
               bounds
               |> Map.from_struct()
               |> Enum.into(%{}, fn {k, v} -> {Atom.to_string(k), v} end)
           }}

        error ->
          error
      end
    end
  end

  defp dispatch_bounds("bounds_algebra.intersect", input, _data, _raws) do
    with {:ok, blueprint} <- bound_set(input, "blueprint"),
         {:ok, deployment} <- bound_set(input, "deployment"),
         {:ok, host} <- bound_set(input, "host"),
         {:ok, result} <-
           BoundsAlgebra.intersect(%BoundsAlgebra.Sources{
             blueprint: blueprint,
             deployment: deployment,
             host: host,
             protected_clamp: clamp_posture(input)
           }) do
      project_intersection(result)
    end
  end

  defp project_intersection(%BoundsAlgebra.Result{effective: effective, clamps: clamps}) do
    with {:ok, effective_map} <- BoundsAlgebra.BoundSet.to_map(effective) do
      {:ok,
       %{
         "effective" =>
           Enum.into(effective_map, %{}, fn {k, v} ->
             {Atom.to_string(k), project_bound_value(v)}
           end),
         "clamp_count" => length(clamps)
       }}
    end
  end

  defp dispatch_late("portability.scan", input, _data, raws) do
    with {:ok, bytes} <- input_bytes(input, raws),
         {:ok, value} <- Json.decode(bytes, Bounds.maximum()) do
      case Portability.scan(value) do
        :ok -> {:ok, %{"clean" => true}}
        error -> error
      end
    end
  end

  defp dispatch_late("compatibility.verify", input, _data, raws) do
    with {:ok, bytes} <- input_bytes(input, raws),
         {:ok, deployment} <- Deployment.decode(bytes),
         {:ok, observed} <- build_observed(input) do
      case Compatibility.verify(deployment, observed) do
        {:ok, _evidence} -> {:ok, %{"verified" => true}}
        error -> error
      end
    end
  end

  defp dispatch_late("federation.decode", input, _data, raws) do
    cond do
      is_binary(input["text"]) or is_binary(input["base64url"]) or input["non_binary"] == true ->
        decode_federation_envelope(input, raws)

      Enum.any?(Map.keys(input), &(&1 in @federation_codec_keys)) ->
        dispatch_federation_codec(input)

      true ->
        {:error, :invalid_type}
    end
  end

  defp dispatch_late("federation.verify_commitment", input, _data, _raws) do
    with {:ok, envelope_text} <- fetch_binary(input, "envelope"),
         {:ok, envelope} <- Federation.decode(envelope_text),
         {:ok, context} <- build_context(input) do
      case Federation.verify_commitment(envelope, context) do
        {:ok, fact} -> {:ok, %{"task_identity" => fact.task_identity}}
        error -> error
      end
    end
  end

  defp dispatch_federation_codec(input) do
    cond do
      is_binary(input["from_a2a_state"]) ->
        Federation.from_a2a_state(input["from_a2a_state"])

      is_binary(input["to_a2a_state"]) ->
        to_logical_state(&Federation.to_a2a_state/1, input["to_a2a_state"])

      is_binary(input["from_mcp_state"]) ->
        Federation.from_mcp_state(input["from_mcp_state"])

      is_binary(input["to_mcp_state"]) ->
        to_logical_state(&Federation.to_mcp_state/1, input["to_mcp_state"])

      is_map(input["from_a2a_carrier"]) ->
        Federation.from_a2a_carrier(to_tagged(input["from_a2a_carrier"]))

      is_map(input["from_mcp_carrier"]) ->
        Federation.from_mcp_carrier(to_tagged(input["from_mcp_carrier"]))

      true ->
        {:error, :invalid_type}
    end
    |> project_codec()
  end

  # Codec successes carry bare atoms/binaries/envelope structs; valid
  # expectations compare per-key maps, so project uniformly.
  defp project_codec({:ok, value}) when is_atom(value),
    do: {:ok, %{"value" => Atom.to_string(value)}}

  defp project_codec({:ok, value}) when is_binary(value), do: {:ok, %{"value" => value}}

  defp project_codec({:ok, %Federation{}}), do: {:ok, %{"decoded" => true}}
  defp project_codec(other), do: other

  defp decode_federation_envelope(input, raws) do
    with {:ok, overrides} <- bounds_overrides(input),
         {:ok, bytes} <- input_bytes(input, raws),
         {:ok, %Federation{} = envelope} <- Federation.decode(bytes, overrides),
         {:ok, canonical} <- Federation.canonical_bytes(envelope) do
      {:ok, %{"canonical" => canonical}}
    end
  end

  defp to_logical_state(codec, spelling) do
    case Map.fetch(@logical_states, spelling) do
      {:ok, logical} -> codec.(logical)
      :error -> {:error, :invalid_type}
    end
  end

  # --- input builders ---------------------------------------------------------------

  defp input_bytes(input, raws) do
    cond do
      # API-type-violation marker: JSON case files can only carry binaries,
      # so the corpus names a non-binary input explicitly (the decode
      # surfaces' invalid_type cells).
      input["non_binary"] == true ->
        {:ok, 123}

      is_binary(input["text"]) ->
        {:ok, input["text"]}

      is_binary(input["base64url"]) ->
        decode_input_b64(input["base64url"])

      is_binary(input["raw_file"]) ->
        case Map.get(raws, input["raw_file"]) do
          bytes when is_binary(bytes) -> {:ok, bytes}
          _ -> {:error, :invalid_type}
        end

      true ->
        {:error, :invalid_type}
    end
  end

  defp decode_input_b64(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :invalid_type}
    end
  end

  defp fetch_binary(input, key) do
    case Map.get(input, key) do
      bytes when is_binary(bytes) -> {:ok, bytes}
      _ -> {:error, :invalid_type}
    end
  end

  defp bounds_overrides(input) do
    case Map.get(input, "bounds") do
      nil ->
        {:ok, %{}}

      overrides when is_map(overrides) ->
        {:ok,
         Enum.reduce(overrides, %{}, fn {key, value}, acc ->
           case Map.fetch(@bounds_keys, key) do
             {:ok, atom_key} -> Map.put(acc, atom_key, value)
             # An unknown key passes through so Bounds.new denies it
             # (:unknown_bound) — the runner does not pre-filter judgment.
             :error -> Map.put(acc, key, value)
           end
         end)}

      _ ->
        {:error, :invalid_type}
    end
  end

  defp fetch_domain(input) do
    case Map.fetch(@digest_domains, input["domain"]) do
      {:ok, domain} -> {:ok, domain}
      :error -> {:error, :invalid_type}
    end
  end

  defp schema_input(input, data) do
    cond do
      is_binary(input["schema_file"]) ->
        case Map.get(data, input["schema_file"]) do
          nil -> {:error, :invalid_type}
          schema when is_map(schema) -> {:ok, to_tagged(schema)}
          schema -> {:ok, schema}
        end

      is_map(input["schema"]) ->
        {:ok, to_tagged(input["schema"])}

      true ->
        {:error, :invalid_type}
    end
  end

  defp dialect_input(input) do
    case input["dialect"] do
      nil -> {:ok, Schema.dialect()}
      dialect when is_binary(dialect) -> {:ok, dialect}
      _ -> {:error, :invalid_type}
    end
  end

  defp tagged_field(input, key) do
    case Map.get(input, key) do
      nil -> {:error, :invalid_type}
      value -> {:ok, to_tagged(value)}
    end
  end

  defp build_keys(input) do
    case Map.get(input, "keys") do
      keys when is_list(keys) -> build_key_list(keys)
      _ -> {:error, :invalid_type}
    end
  end

  defp build_key_list(keys) do
    keys
    |> Enum.reduce_while({:ok, []}, fn key_entry, {:ok, acc} ->
      case build_key(key_entry) do
        {:ok, key} -> {:cont, {:ok, [key | acc]}}
        error -> {:halt, error}
      end
    end)
    |> finalize_keys()
  end

  defp finalize_keys({:ok, list}), do: {:ok, Enum.reverse(list)}
  defp finalize_keys(error), do: error

  defp build_key(%{"key_id" => id, "key" => encoded})
       when is_binary(id) and is_binary(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, <<_::256>> = key} ->
        {:ok, %Signature.PublicKey{key_id: id, algorithm: :ed25519, key: key}}

      _ ->
        {:error, :invalid_type}
    end
  end

  defp build_key(_), do: {:error, :invalid_type}

  defp build_support(input) do
    # A malformed nested member denies typed — a non-map "support" must not
    # crash the runner (BadMapError past the
    # verdict machinery).
    case Map.get(input, "support") do
      nil -> do_build_support(%{})
      support_input when is_map(support_input) -> do_build_support(support_input)
      _ -> {:error, :invalid_type}
    end
  end

  defp do_build_support(support_input) do
    revisions = Map.get(support_input, "revisions", [1])
    core_fields = Map.get(support_input, "core_fields", [])

    registry =
      support_input
      |> Map.get("registry", %{})
      |> Enum.into(%{}, fn {ns, entry} ->
        {ns,
         %ExtensionRegistry{
           namespace: ns,
           owner: Map.get(entry, "owner", "corpus"),
           criticality: atomize_criticality(Map.get(entry, "criticality")),
           state: atomize_state(Map.get(entry, "state")),
           schema_digest: Map.get(entry, "schema_digest"),
           a2a_uri: Map.get(entry, "a2a_uri", "https://example.com/extensions/#{ns}"),
           promoted_at_revision: Map.get(entry, "promoted_at_revision")
         }}
      end)

    schemas =
      support_input
      |> Map.get("schemas", %{})
      |> Enum.into(%{}, fn {ns, schema} -> {ns, to_tagged(schema)} end)

    {:ok,
     %Negotiation.Support{
       revisions: MapSet.new(revisions),
       core_fields: MapSet.new(core_fields),
       registry: registry,
       schemas: schemas
     }}
  end

  defp atomize_criticality("critical"), do: :critical
  defp atomize_criticality(_), do: :optional

  defp atomize_state("reserved"), do: :reserved
  defp atomize_state("deprecated"), do: :deprecated
  defp atomize_state("retired"), do: :retired
  defp atomize_state(_), do: :active

  defp bound_set(input, key) do
    case Map.get(input, key) do
      map when is_map(map) ->
        entries =
          Enum.reduce_while(Map.to_list(map), {:ok, %{}}, fn {name, value}, {:ok, acc} ->
            add_bound_entry(name, value, acc)
          end)

        case entries do
          {:ok, map} -> BoundsAlgebra.BoundSet.new(map)
          error -> error
        end

      _ ->
        {:error, :invalid_type}
    end
  end

  defp add_bound_entry(name, value, acc) do
    case Map.fetch(@bound_name_atoms, name) do
      {:ok, atom} -> {:cont, {:ok, Map.put(acc, atom, descope_value(value))}}
      :error -> {:halt, {:error, :invalid_type}}
    end
  end

  # Scope values arrive as %{"ordinal" => s, "markers" => [...]}; obligation
  # ordinals as bare strings; costs as %{"amount" => n, "currency" => c}.
  defp descope_value(%{"ordinal" => ordinal} = value) do
    %{
      ordinal: lattice_atom(ordinal),
      markers: value |> Map.get("markers", []) |> Enum.map(&lattice_atom/1) |> MapSet.new()
    }
  end

  defp descope_value(%{"amount" => amount, "currency" => currency}),
    do: %{amount: amount, currency: currency}

  defp descope_value(binary) when is_binary(binary), do: lattice_atom(binary)
  defp descope_value(other), do: other

  defp lattice_atom(value) do
    case Map.fetch(@lattice_atoms, value) do
      {:ok, atom} -> atom
      :error -> value
    end
  end

  defp clamp_posture(%{"protected_clamp" => "acknowledge"}), do: :acknowledge
  defp clamp_posture(_), do: :deny

  # Scope bound values carry a MapSet of markers — project as a sorted list
  # so expectations are plain JSON.
  defp project_bound_value(%{ordinal: _, markers: %MapSet{} = markers} = value) do
    %{
      "ordinal" => project_bound_value(value.ordinal),
      "markers" => Enum.sort(MapSet.to_list(markers))
    }
  end

  defp project_bound_value(%{amount: _, currency: _} = value) do
    %{"amount" => value.amount, "currency" => value.currency}
  end

  defp project_bound_value(other) when is_atom(other), do: Atom.to_string(other)
  defp project_bound_value(other), do: other

  defp build_observed(input) do
    case Map.get(input, "observed") do
      %{"identities" => identities} when is_list(identities) ->
        # A malformed identity element denies typed, never raises (the
        # prior-receipts pattern) — found by the second-language
        # verifier's parity battery; the bare pattern-match crashed the
        # runner on a non-map element (probed live 2026-08-23).
        observed_identities(identities)

      _ ->
        {:error, :invalid_type}
    end
  end

  defp observed_identities(identities) do
    identities
    |> Enum.map(fn
      %{"kind" => k, "name" => n, "version" => v, "digest" => d} ->
        %{kind: k, name: n, version: v, digest: d}

      _malformed ->
        :invalid
    end)
    |> finalize_observed()
  end

  defp finalize_observed(mapped) do
    if :invalid in mapped do
      {:error, :invalid_type}
    else
      {:ok, %Compatibility.Observed{identities: mapped}}
    end
  end

  defp build_context(input) do
    ctx =
      case Map.get(input, "context") do
        nil -> %{}
        ctx when is_map(ctx) -> ctx
        _ -> :invalid
      end

    # An absent keys member on a CONTEXT is the empty pool (legitimate);
    # signature.verify keeps its own stricter input contract.
    with true <- is_map(ctx) || :invalid,
         {:ok, keys} <- build_keys(Map.put_new(ctx, "keys", [])),
         {:ok, issuer_key_sets} <- build_issuer_key_sets(ctx),
         {:ok, receipts} <- prior_receipts(ctx) do
      {:ok,
       %Federation.Context{
         keys: keys,
         issuer: ctx["issuer"],
         subject: ctx["subject"],
         audience: ctx["audience"],
         issuer_key_sets: issuer_key_sets,
         created_after: ctx["created_after"],
         created_before: ctx["created_before"],
         prior_receipts: receipts
       }}
    else
      :invalid -> {:error, :invalid_type}
      _ -> {:error, :invalid_type}
    end
  end

  defp build_issuer_key_sets(ctx) do
    case Map.get(ctx, "issuer_key_sets") do
      nil ->
        {:ok, nil}

      sets when is_map(sets) ->
        sets
        |> Enum.reduce_while({:ok, %{}}, fn {issuer, key_list}, {:ok, acc} ->
          add_issuer_keys(issuer, key_list, acc)
        end)

      _ ->
        {:error, :invalid_type}
    end
  end

  defp add_issuer_keys(issuer, key_list, acc) do
    case build_keys(%{"keys" => key_list}) do
      {:ok, keys} -> {:cont, {:ok, Map.put(acc, issuer, keys)}}
      error -> {:halt, error}
    end
  end

  defp prior_receipts(ctx) do
    case Map.get(ctx, "prior_receipts", []) do
      # A present-but-non-list prior_receipts denies typed — Enum.map would
      # raise Protocol.UndefinedError (the same
      # never-raising class as build_observed's fix).
      list when is_list(list) ->
        list |> Enum.map(&parse_receipt/1) |> finalize_receipts()

      _not_a_list ->
        {:error, :invalid_type}
    end
  end

  defp parse_receipt(receipt) do
    with %{"task_identity" => id, "terminal_state" => state, "commitment" => tagged}
         when is_binary(id) and is_binary(state) and is_binary(tagged) <- receipt,
         {:ok, digest} <- Digest.from_tagged(tagged) do
      %{task_identity: id, terminal_state: state, terminal_commitment: digest}
    else
      _ -> :invalid
    end
  end

  defp finalize_receipts(receipts) do
    if :invalid in receipts do
      {:error, :invalid_type}
    else
      {:ok, receipts}
    end
  end

  # --- projections ---------------------------------------------------------------------

  # A decoded artifact's content digest is already verified — the error
  # arm is unreachable and a mismatch escapes loudly as an internal
  # invariant rather than laundering into a verdict.
  defp project_artifact(%Blueprint{} = artifact) do
    %Digest{} = digest = Blueprint.content_digest(artifact)
    {:ok, %{"digest" => Digest.to_tagged(digest)}}
  end

  defp project_artifact(%Deployment{} = artifact) do
    %Digest{} = digest = Deployment.content_digest(artifact)
    {:ok, %{"digest" => Digest.to_tagged(digest)}}
  end

  defp project_negotiation({:ok, %Negotiation.Outcome{} = outcome}) do
    {:ok,
     %{
       "revision" => outcome.protocol_revision,
       "critical" => Enum.sort(outcome.critical_extensions),
       "quarantined" => Enum.sort(outcome.quarantined_extensions),
       # JSON-shaped: notice atoms stringify here so in-process comparisons
       # and the serialized report agree (the verifier twin emits strings).
       "notices" => outcome.notices |> Enum.sort() |> Enum.map(&Atom.to_string/1)
     }}
  end

  defp project_negotiation({:error, _} = error), do: error

  # --- tagged algebra ------------------------------------------------------------------

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
end
