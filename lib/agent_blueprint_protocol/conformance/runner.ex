defmodule AgentBlueprintProtocol.Conformance.Runner do
  @moduledoc """
    This module runs loaded conformance cases against the reference implementation.

    Use it when comparing expected case outcomes with implementation results.

    This module does not authorize operations.

    ## Example

    ```elixir
    files =
      Path.wildcard("priv/conformance/**/*")
      |> Enum.filter(&File.regular?/1)
      |> Map.new(fn path ->
        {Path.relative_to(path, "priv/conformance"), File.read!(path)}
      end)
    {:ok, corpus} = AgentBlueprintProtocol.Conformance.Corpus.load(files)
    match?(results when is_list(results), AgentBlueprintProtocol.Conformance.Runner.run(corpus))
    ```
  """
  @moduledoc since: "1.0.0"

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
    Predicate,
    Reconcile,
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

  @typedoc """
    The result for one conformance case.
  """
  @type result :: %{case_id: binary(), agree: boolean()}

  @spec run(Corpus.t()) :: [{binary(), [result()]}] | {:error, Error.t()}
  @doc """
    Runs the cases in a loaded conformance corpus.

    ## Example

    ```elixir
    files =
      Path.wildcard("priv/conformance/**/*")
      |> Enum.filter(&File.regular?/1)
      |> Map.new(fn path ->
        {Path.relative_to(path, "priv/conformance"), File.read!(path)}
      end)

    {:ok, corpus} = AgentBlueprintProtocol.Conformance.Corpus.load(files)
    match?(results when is_list(results), AgentBlueprintProtocol.Conformance.Runner.run(corpus))
    ```
  """
  @doc since: "1.0.0"
  def run(%Corpus{cases: cases, data: data, raws: raws})
      when is_list(cases) and is_map(data) and not is_struct(data) and is_map(raws) and
             not is_struct(raws) do
    if cases_ok?(cases),
      do: run_cases(cases, data, raws),
      else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
  end

  def run(_), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp cases_ok?([]), do: true

  defp cases_ok?([{path, rows} | rest]) when is_binary(path),
    do: cases_rows_ok?(rows) and cases_ok?(rest)

  defp cases_ok?(_), do: false
  defp cases_rows_ok?([]), do: true
  defp cases_rows_ok?([row | rest]), do: case_shape?(row) and cases_rows_ok?(rest)
  defp cases_rows_ok?(_), do: false

  defp run_cases(cases, data, raws) do
    Enum.map(cases, fn {path, file_cases} ->
      results =
        Enum.map(file_cases, fn case_obj ->
          {_actual, agree} = execute(case_obj, data, raws)
          %{case_id: case_obj["id"], agree: agree}
        end)

      {path, results}
    end)
  end

  @doc false
  @spec execute(map(), map(), map()) :: {term(), boolean()}
  def execute(case_obj, data, raws)
      when is_map(case_obj) and is_map(data) and not is_struct(data) and is_map(raws) and
             not is_struct(raws) do
    if case_shape?(case_obj),
      do: execute_case(case_obj, data, raws),
      else: {{:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}, false}
  end

  def execute(_, _, _), do: {{:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}, false}

  defp case_shape?(case_obj) when is_map(case_obj) and not is_struct(case_obj),
    do:
      plain_map?(Map.get(case_obj, "input", %{})) and
        plain_map?(Map.get(case_obj, "expected", %{}))

  defp case_shape?(_), do: false

  defp plain_map?(value), do: is_map(value) and not is_struct(value) and plain_value?(value, 0)
  defp plain_value?(_, depth) when depth > 64, do: false

  defp plain_value?(value, depth) when is_map(value) and not is_struct(value),
    do:
      Enum.all?(value, fn {key, member} -> is_binary(key) and plain_value?(member, depth + 1) end)

  defp plain_value?(value, depth) when is_list(value), do: plain_list?(value, depth)

  defp plain_value?(value, _),
    do: is_binary(value) or is_number(value) or is_atom(value) or is_tuple(value)

  defp plain_list?([], _), do: true

  defp plain_list?([value | rest], depth),
    do: plain_value?(value, depth + 1) and plain_list?(rest, depth)

  defp plain_list?(_, _), do: false

  defp execute_case(case_obj, data, raws) do
    input = Map.get(case_obj, "input", %{})
    {strict, expected} = Map.pop(Map.get(case_obj, "expected", %{}), "strict_signature")
    actual = dispatch(case_obj["surface"], input, data, raws)
    {actual, agrees?(expected, actual) and strict_agrees?(case_obj["surface"], strict, input)}
  end

  # A signature.verify case may pin the strict signature predicate's
  # verdict on its 64 signature bytes; any other surface, a non-boolean,
  # or an entry without 64 decodable signature bytes disagrees.
  defp strict_agrees?(_surface, nil, _input), do: true

  defp strict_agrees?("signature.verify", want, input) when is_boolean(want) do
    with {:ok, entry_text} <- fetch_binary(input, "entry"),
         {:ok, {:object, members}} <- Json.decode(entry_text),
         {"signature", {:string, body}} <- List.keyfind(members, "signature", 0),
         {:ok, <<_::512>> = signature} <- Base64Url.decode(body) do
      Signature.strict_signature?(signature) == want
    else
      _no_signature_bytes -> false
    end
  end

  defp strict_agrees?(_surface, _want, _input), do: false

  @doc false
  @spec project(map(), map(), map()) :: map()
  def project(case_obj, data, raws) when is_map(case_obj) and is_map(data) and is_map(raws) do
    if case_shape?(case_obj), do: project_case(case_obj, data, raws), else: invalid_projection()
  end

  def project(_, _, _), do: invalid_projection()

  defp invalid_projection, do: %{"verdict" => "invalid", "code" => "invalid_type"}

  defp project_case(case_obj, data, raws) do
    {actual, _agree} = execute(case_obj, data, raws)
    result = project_result(actual, case_obj["surface"])

    if case_obj["surface"] == "signature.verify" do
      with entry_text when is_binary(entry_text) <- case_obj["input"]["entry"],
           {:ok, {:object, members}} <- Json.decode(entry_text),
           {"signature", {:string, body}} <- List.keyfind(members, "signature", 0),
           {:ok, <<_::512>> = bytes} <- Base64Url.decode(body) do
        Map.put(result, "strict_signature", Signature.strict_signature?(bytes))
      else
        _ -> result
      end
    else
      result
    end
  end

  defp project_result({:ok, fields}, "base64url.decode"),
    do: %{"verdict" => "valid", "decoded" => Base64Url.encode(fields["decoded"])}

  defp project_result({:ok, fields}, "canonicalization.encode"),
    do: %{"verdict" => "valid", "encoded" => Base64Url.encode(fields["encoded"])}

  defp project_result({:ok, %{"canonical" => bytes}}, "federation.decode"),
    do: %{"verdict" => "valid", "canonical" => Base64Url.encode(bytes)}

  defp project_result({:ok, fields}, _surface), do: Map.put(fields, "verdict", "valid")

  defp project_result({:error, %Error{} = error}, "reconcile"),
    do: %{"verdict" => "invalid", "code" => project_code(error), "subject" => error.subject}

  defp project_result({:error, error}, _surface),
    do: %{"verdict" => "invalid", "code" => project_code(error)}

  defp dispatch_predicate(input) do
    with {:ok, predicate} <- tagged_field(input, "predicate"),
         ports when is_list(ports) <- input["port_names"],
         :ok <- Predicate.validate(predicate, ports) do
      case input["mode"] do
        "validate" -> {:ok, %{"valid" => true}}
        "evaluate" -> evaluate_predicate(predicate, input["ports"])
        _ -> {:error, %Error{code: :invalid_type}}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, %Error{code: :invalid_type}}
    end
  end

  defp evaluate_predicate(predicate, ports) when is_map(ports) do
    with {:ok, value} <-
           Predicate.evaluate(predicate, Map.new(ports, fn {k, v} -> {k, to_tagged(v)} end)),
         do: {:ok, %{"value" => value}}
  end

  defp evaluate_predicate(_, _), do: {:error, %Error{code: :invalid_type}}

  defp dispatch_reconcile(input) do
    with {:ok, bp_text} <- fetch_binary(input, "blueprint"),
         {:ok, dep_text} <- fetch_binary(input, "deployment"),
         {:ok, bp} <- Canonicalization.verify(bp_text),
         {:ok, dep} <- Canonicalization.verify(dep_text),
         host when is_map(host) <- input["inputs"],
         {:ok, support} <- build_support(host),
         {:ok, keys} <- build_keys(Map.put_new(host, "keys", [])),
         {:ok, host_bounds} <- bound_set(host, "host_bounds"),
         observations when is_map(observations) <- Map.get(host, "observations", %{}),
         {:ok, now} <- reconcile_time(observations["now"]) do
      obs = %Deployment.Observations{
        now: now,
        max_attestation_age_ms: observations["max_attestation_age_ms"],
        observed: Map.get(observations, "observed", %{})
      }

      inputs = %Reconcile.Inputs{
        host_bounds: host_bounds,
        support: support,
        keys: keys,
        protected_clamp: clamp_posture(host),
        observations: obs
      }

      with {:ok, evidence} <-
             Reconcile.reconcile(%Blueprint{value: bp}, %Deployment{value: dep}, inputs),
           do: {:ok, %{"evidence" => evidence_plain(evidence)}}
    else
      {:error, _} = error -> error
      _ -> {:error, %Error{code: :invalid_type}}
    end
  end

  defp evidence_plain(%Digest{} = value), do: Digest.to_tagged(value)

  defp evidence_plain(%BoundsAlgebra.BoundSet{} = value) do
    {:ok, values} = BoundsAlgebra.BoundSet.to_map(value)
    evidence_plain(values)
  end

  defp evidence_plain(%MapSet{} = values),
    do: values |> Enum.sort() |> Enum.map(&evidence_plain/1)

  defp evidence_plain(%_{} = value), do: value |> Map.from_struct() |> evidence_plain()

  defp evidence_plain(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), evidence_plain(v)} end)

  defp evidence_plain(value) when is_list(value), do: Enum.map(value, &evidence_plain/1)
  defp evidence_plain(value) when value in [true, false, nil], do: value
  defp evidence_plain(value) when is_atom(value), do: Atom.to_string(value)
  defp evidence_plain(value), do: value

  # --- agreement ---------------------------------------------------------------

  defp agrees?(%{"verdict" => "invalid"} = expected, actual) do
    case actual do
      {:error, reason} ->
        project_code(reason) == expected["code"] and
          (not Map.has_key?(expected, "subject") or reason.subject == expected["subject"])

      _ ->
        false
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

  # Typed failures project to one code string, including the ceiling family.
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
      surface == "reconcile" -> dispatch_reconcile(input)
      surface == "predicate" -> dispatch_predicate(input)
      surface in @byte_surfaces -> dispatch_bytes(surface, input, data, raws)
      surface in @artifact_surfaces -> dispatch_artifact(surface, input, data, raws)
      surface in @negotiation_surfaces -> dispatch_negotiation(surface, input, data, raws)
      surface in @bound_surfaces -> dispatch_bounds(surface, input, data, raws)
      surface in @late_surfaces -> dispatch_late(surface, input, data, raws)
      true -> {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
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
        {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
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
        {:ok, %Signature.Attributes{}} -> {:ok, %{"verified" => true}}
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

  defp reconcile_time(nil), do: {:ok, nil}

  defp reconcile_time(value) do
    if is_binary(value) and Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/, value) and
         parse_time(value) != nil,
       do: {:ok, parse_time(value)},
       else: {:error, %Error{code: :invalid_type, subject: ["now"]}}
  end

  defp parse_time(binary) when is_binary(binary) do
    case DateTime.from_iso8601(binary) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_time(_), do: nil

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
        {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
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
        {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
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
      :error -> {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
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
          _ -> {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
        end

      true ->
        {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
    end
  end

  defp decode_input_b64(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
    end
  end

  defp fetch_binary(input, key) when is_map(input) and not is_struct(input) do
    case Map.get(input, key) do
      bytes when is_binary(bytes) -> {:ok, bytes}
      _ -> {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
    end
  end

  defp fetch_binary(_, _), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp bounds_overrides(input) do
    case Map.get(input, "bounds") do
      nil ->
        {:ok, %{}}

      overrides when is_map(overrides) and not is_struct(overrides) ->
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
        {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
    end
  end

  defp fetch_domain(input) do
    case Map.fetch(@digest_domains, input["domain"]) do
      {:ok, domain} -> {:ok, domain}
      :error -> {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
    end
  end

  defp schema_input(input, data) do
    cond do
      is_binary(input["schema_file"]) ->
        stored_schema(Map.get(data, input["schema_file"]))

      is_map(input["schema"]) ->
        {:ok, to_tagged(input["schema"])}

      true ->
        {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
    end
  end

  defp stored_schema(nil), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp stored_schema(schema) when is_map(schema) do
    if plain_map?(schema),
      do: {:ok, to_tagged(schema)},
      else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
  end

  defp stored_schema(schema), do: {:ok, schema}

  defp dialect_input(input) do
    case input["dialect"] do
      nil -> {:ok, Schema.dialect()}
      dialect when is_binary(dialect) -> {:ok, dialect}
      _ -> {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
    end
  end

  defp tagged_field(input, key) do
    case Map.fetch(input, key) do
      :error -> {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
      {:ok, value} -> {:ok, to_tagged(value)}
    end
  end

  defp build_keys(input) do
    case Map.get(input, "keys") do
      keys when is_list(keys) -> build_key_list(keys)
      _ -> {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
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
        {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
    end
  end

  defp build_key(_), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp build_support(input) do
    # A malformed nested member denies typed — a non-map "support" must not
    # crash the runner (BadMapError past the
    # verdict machinery).
    case Map.get(input, "support") do
      nil -> do_build_support(%{})
      support_input when is_map(support_input) -> do_build_support(support_input)
      _ -> {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
    end
  end

  defp do_build_support(support_input) do
    revisions = Map.get(support_input, "revisions", [1])
    core_fields = Map.get(support_input, "core_fields", [])

    registry_input = Map.get(support_input, "registry", %{})
    schemas_input = Map.get(support_input, "schemas", %{})

    if is_list(revisions) and is_list(core_fields) and plain_map?(registry_input) and
         Enum.all?(registry_input, fn {_, entry} -> plain_map?(entry) end) and
         plain_map?(schemas_input) do
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
    else
      {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
    end
  end

  defp atomize_criticality("critical"), do: :critical
  defp atomize_criticality(_), do: :optional

  defp atomize_state("reserved"), do: :reserved
  defp atomize_state("deprecated"), do: :deprecated
  defp atomize_state("retired"), do: :retired
  defp atomize_state(_), do: :active

  defp bound_set(input, key) do
    case Map.get(input, key) do
      map when is_map(map) and not is_struct(map) ->
        entries =
          Enum.reduce_while(Map.to_list(map), {:ok, %{}}, fn {name, value}, {:ok, acc} ->
            add_bound_entry(name, value, acc)
          end)

        case entries do
          {:ok, map} -> BoundsAlgebra.BoundSet.new(map)
          error -> error
        end

      _ ->
        {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
    end
  end

  defp add_bound_entry(name, value, acc) do
    case Map.fetch(@bound_name_atoms, name) do
      {:ok, atom} -> {:cont, {:ok, Map.put(acc, atom, descope_value(value))}}
      :error -> {:halt, {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}}
    end
  end

  # Scope values arrive as %{"ordinal" => s, "markers" => [...]}; obligation
  # ordinals as bare strings; costs as %{"amount" => n, "currency" => c}.
  defp descope_value(%{"ordinal" => ordinal, "markers" => markers}) when is_list(markers) do
    %{
      ordinal: lattice_atom(ordinal),
      markers: markers |> Enum.map(&lattice_atom/1) |> MapSet.new()
    }
  end

  defp descope_value(%{"ordinal" => ordinal} = value) when not is_map_key(value, "markers"),
    do: %{ordinal: lattice_atom(ordinal), markers: MapSet.new()}

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
        {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
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
      {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
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
      :invalid -> {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
      _ -> {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
    end
  end

  defp build_issuer_key_sets(ctx) do
    case Map.get(ctx, "issuer_key_sets") do
      nil ->
        {:ok, nil}

      sets when is_map(sets) and not is_struct(sets) ->
        sets
        |> Enum.reduce_while({:ok, %{}}, fn {issuer, key_list}, {:ok, acc} ->
          add_issuer_keys(issuer, key_list, acc)
        end)

      _ ->
        {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
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
        {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
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
      {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
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
