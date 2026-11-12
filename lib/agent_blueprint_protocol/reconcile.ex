defmodule AgentBlueprintProtocol.Reconcile do
  @moduledoc """
  This module runs the composed verification pass for a Blueprint and Deployment pair.

  Use it when an application needs one Evidence result for a pair and host inputs.

  This module does not authorize operations.

  ## Example

  ```elixir
  dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
  {:ok, blueprint} =
    AgentBlueprintProtocol.Blueprint.decode(
      File.read!(Path.join(dependency_root, "examples/echo-blueprint.json"))
    )
  {:ok, deployment} =
    AgentBlueprintProtocol.Deployment.decode(
      File.read!(Path.join(dependency_root, "examples/echo-deployment.json"))
    )
  {:ok, host_bounds} = AgentBlueprintProtocol.BoundsAlgebra.from_deployment(deployment)
  support = %AgentBlueprintProtocol.Negotiation.Support{revisions: MapSet.new([1]), core_fields: MapSet.new([])}
  inputs = %AgentBlueprintProtocol.Reconcile.Inputs{
    host_bounds: host_bounds,
    support: support,
    keys: [],
    protected_clamp: :acknowledge,
    observations: %AgentBlueprintProtocol.Deployment.Observations{}
  }
  match?(
    {:ok, %AgentBlueprintProtocol.Evidence{}},
    AgentBlueprintProtocol.reconcile(blueprint, deployment, inputs)
  )
  ```
  """
  @moduledoc since: "1.0.0"

  alias AgentBlueprintProtocol.{
    Blueprint,
    BoundsAlgebra,
    Deployment,
    Digest,
    Error,
    Evidence,
    Extension,
    Negotiation,
    Portability,
    Registry,
    Signature
  }

  alias AgentBlueprintProtocol.BoundsAlgebra.{BoundSet, ClampEvidence, Result, Sources}
  alias AgentBlueprintProtocol.Deployment.Observations
  alias AgentBlueprintProtocol.Negotiation.Support
  alias AgentBlueprintProtocol.Signature.PublicKey

  defmodule Inputs do
    @moduledoc """
    This struct carries the host inputs used by reconcile.

    Use it when assembling values for a reconcile call.

    This module does not authorize operations.

    ## Example

    ```elixir
    {:ok, host_bounds} = AgentBlueprintProtocol.BoundsAlgebra.BoundSet.new(%{max_tokens: 1000})
    support = %AgentBlueprintProtocol.Negotiation.Support{revisions: MapSet.new([1]), core_fields: MapSet.new([])}
    %AgentBlueprintProtocol.Reconcile.Inputs{
      host_bounds: host_bounds,
      support: support,
      keys: [],
      protected_clamp: :acknowledge,
      observations: %AgentBlueprintProtocol.Deployment.Observations{}
    }
    ```
    """
    @moduledoc since: "1.0.0"

    defstruct [:host_bounds, :support, :keys, :protected_clamp, :observations]

    @typedoc """
    The public data type for AgentBlueprintProtocol.Reconcile.Inputs.
    """
    @type t :: %__MODULE__{
            host_bounds: BoundSet.t(),
            support: Support.t(),
            keys: [PublicKey.t()],
            protected_clamp: :deny | :acknowledge,
            observations: Observations.t()
          }
  end

  @postures [:deny, :acknowledge]

  @spec reconcile(Blueprint.t(), Deployment.t(), Inputs.t()) ::
          {:ok, Evidence.t()} | {:error, Error.t()}
  @doc """
  Runs the composed verification pass for a Blueprint and Deployment pair.

  ## Example

  ```elixir
  match?(
    {:error, %AgentBlueprintProtocol.Error{}},
    AgentBlueprintProtocol.Reconcile.reconcile(nil, nil, nil)
  )
  ```
  """
  @doc since: "1.0.0"
  def reconcile(%Blueprint{} = blueprint, %Deployment{} = deployment, %Inputs{} = inputs) do
    with :ok <- check_inputs(inputs) do
      run_stages(blueprint, deployment, inputs)
    end
  end

  def reconcile(%Blueprint{}, %Deployment{}, _),
    do: {:error, %Error{code: :invalid_type, subject: ["inputs"]}}

  def reconcile(%Blueprint{}, _, _),
    do: {:error, %Error{code: :invalid_type, subject: ["deployment"]}}

  def reconcile(_, _, _), do: {:error, %Error{code: :invalid_type, subject: ["blueprint"]}}

  defp check_inputs(%Inputs{} = inputs) do
    with :ok <- struct_field(inputs, :support, Support, "support"),
         :ok <- struct_field(inputs, :observations, Observations, "observations"),
         :ok <- struct_field(inputs, :host_bounds, BoundSet, "host_bounds"),
         :ok <- keys_check(inputs.keys) do
      posture_check(inputs.protected_clamp)
    end
  end

  defp struct_field(inputs, field, module, name) do
    if is_struct(Map.get(inputs, field), module),
      do: :ok,
      else: {:error, %Error{code: :invalid_type, subject: ["inputs", name]}}
  end

  defp keys_check(keys) when is_list(keys) do
    case invalid_key_index(keys, 0) do
      nil -> :ok
      index -> {:error, %Error{code: :invalid_type, subject: ["inputs", "keys", index]}}
    end
  end

  defp keys_check(_), do: {:error, %Error{code: :invalid_type, subject: ["inputs", "keys"]}}

  defp invalid_key_index([], _index), do: nil
  defp invalid_key_index([%PublicKey{} | rest], index), do: invalid_key_index(rest, index + 1)
  defp invalid_key_index(_, index), do: index

  defp posture_check(posture) when posture in @postures, do: :ok

  defp posture_check(_),
    do: {:error, %Error{code: :invalid_type, subject: ["inputs", "protected_clamp"]}}

  # ---- the staged pipeline -------------------------------------------------------------

  defp run_stages(blueprint, deployment, inputs) do
    with {:ok, canonical} <- stage_canonical(blueprint, deployment),
         {:ok, digest, bp_digest, dep_digest} <- stage_digest(blueprint, deployment),
         {:ok, negotiation, bp_outcome, dep_outcome} <-
           stage_negotiation(blueprint, deployment, inputs.support),
         {:ok, structure} <- stage_structure(blueprint, deployment),
         {:ok, portability} <- stage_portability(blueprint, deployment, bp_outcome, dep_outcome),
         {:ok, signatures} <-
           stage_signatures(blueprint, deployment, inputs.keys, bp_digest, dep_digest),
         {:ok, bind} <- stage_bind(deployment, blueprint, inputs.observations),
         {:ok, bounds, effective, clamps} <- stage_bounds(blueprint, deployment, inputs) do
      Evidence.build(
        protocol_revision: revision_of(blueprint),
        blueprint_digest: bp_digest,
        deployment_digest: dep_digest,
        checks:
          canonical ++
            digest ++ negotiation ++ structure ++ portability ++ signatures ++ bind ++ bounds,
        effective_bounds: effective,
        clamps: clamps,
        not_verified: [
          :signature_created_at,
          :lifecycle_state
        ],
        optional_extensions_retained:
          Enum.uniq(bp_outcome.optional_retained ++ dep_outcome.optional_retained)
      )
    end
  end

  # The artifact ROOT must be an object before any member-reading stage
  # runs; the composed pass gates the root before reading artifact members.
  defp stage_canonical(blueprint, deployment) do
    with :ok <- object_root(Blueprint.to_value(blueprint), "blueprint"),
         {:ok, _} <- Blueprint.canonical_bytes(blueprint) |> typed("blueprint"),
         :ok <- object_root(Deployment.to_value(deployment), "deployment"),
         {:ok, _} <- Deployment.canonical_bytes(deployment) |> typed("deployment") do
      {:ok, [check(:canonical, "blueprint"), check(:canonical, "deployment")]}
    end
  end

  defp object_root({:object, members}, _subject) when is_list(members), do: :ok

  defp object_root(_forged, subject),
    do: {:error, %Error{code: :invalid_type, subject: [subject]}}

  defp stage_digest(blueprint, deployment) do
    with :ok <- Blueprint.verify_content_digest(blueprint) |> typed("blueprint"),
         :ok <- Deployment.verify_content_digest(deployment) |> typed("deployment"),
         %Digest{} = bp_digest <- Blueprint.content_digest(blueprint) |> digest_of("blueprint"),
         %Digest{} = dep_digest <-
           Deployment.content_digest(deployment) |> digest_of("deployment") do
      {:ok,
       [
         %{surface: :digest, subject: ["blueprint"], verified: true, detail: bp_digest},
         %{surface: :digest, subject: ["deployment"], verified: true, detail: dep_digest}
       ], bp_digest, dep_digest}
    end
  end

  defp stage_negotiation(blueprint, deployment, support) do
    with {:ok, bp_outcome} <- Negotiation.negotiate(blueprint, support) |> typed("blueprint"),
         {:ok, dep_outcome} <- Negotiation.negotiate(deployment, support) |> typed("deployment") do
      checks = [
        check(:negotiation, "blueprint"),
        check(:negotiation, "deployment")
      ]

      {:ok, checks ++ extension_checks(bp_outcome) ++ extension_checks(dep_outcome), bp_outcome,
       dep_outcome}
    end
  end

  defp extension_checks(outcome) do
    quarantined =
      Enum.map(outcome.quarantined_extensions, fn ns ->
        %{surface: :extensions, subject: [ns], verified: false, detail: :quarantined}
      end)

    retained =
      Enum.map(outcome.optional_retained, fn ns ->
        %{surface: :extensions, subject: [ns], verified: false, detail: :retained}
      end)

    quarantined ++ retained
  end

  defp stage_structure(blueprint, deployment) do
    with :ok <-
           Registry.validate(Blueprint.table(), Blueprint.to_value(blueprint))
           |> typed("blueprint"),
         :ok <-
           Registry.validate(Deployment.table(), Deployment.to_value(deployment))
           |> typed("deployment") do
      {:ok, [check(:structure, "blueprint"), check(:structure, "deployment")]}
    end
  end

  # The portability stage runs the DIRECT scans under the authored channel
  # re-derived from THIS import's negotiated critical extensions — NOT
  # `from_value/2` (its registry half would re-run `stage_structure`'s
  # checks, making that stage's guard unobservable). The per-position scan
  # MODES mirror each artifact's own decode-side composition exactly (the
  # F8 re-derivation): authored regions (blueprint schema documents and
  # predicate operands; deployment eligibility expressions) scan
  # names+exempting-values; the blueprint's five identifier member tables
  # scan exempting over their named members; every other position scans
  # strict; signature key_ids (the one free string inside evidence
  # members) scan strict. Unparseable signature entries are the registry
  # stage's deny, not this scan's.
  defp stage_portability(blueprint, deployment, bp_outcome, dep_outcome) do
    with :ok <-
           scan_artifact(
             Blueprint.to_value(blueprint),
             bp_outcome.critical_extensions,
             :blueprint
           )
           |> typed("blueprint"),
         :ok <-
           scan_artifact(
             Deployment.to_value(deployment),
             dep_outcome.critical_extensions,
             :deployment
           )
           |> typed("deployment") do
      {:ok, [check(:portability, "blueprint"), check(:portability, "deployment")]}
    end
  end

  @evidence_names ~w(signatures attestations content_digest deployment_digest)

  defp scan_artifact({:object, members}, authored, kind) do
    authored_ns = MapSet.new(authored)

    scans =
      extension_body_scans(members, authored_ns) ++
        authored_scans(members, kind) ++
        core_string_scans(members, kind) ++
        evidence_key_id_scans(members)

    Enum.find_value(scans, :ok, fn
      :ok -> nil
      {:error, _reason} = error -> error
    end)
  end

  defp extension_body_scans(members, authored_ns) do
    for {ns, body} <- Extension.bodies(members),
        not MapSet.member?(authored_ns, ns),
        do: Portability.scan(body)
  end

  # Authored JSON per artifact kind (blueprint.ex / deployment.ex's own
  # open-region compositions, mirrored).
  defp authored_scans(members, :blueprint) do
    (schema_documents(members) ++ predicate_operands(members))
    |> Enum.map(&Portability.scan_authored/1)
  end

  defp authored_scans(members, :deployment), do: eligibility_scans(members)

  # Post-structure the deployment's eligibility member is a present
  # validated object; this private reader fails loud on the impossible.
  defp eligibility_scans(members) do
    {"eligibility", {:object, expressions}} = List.keyfind(members, "eligibility", 0)

    Enum.map(expressions, fn {_name, value} -> Portability.scan_authored(value) end)
  end

  defp core_string_scans(members, :blueprint) do
    members
    |> Enum.reject(fn {name, _} -> name in @evidence_names or name == "extensions" end)
    |> Enum.map(fn {name, value} -> blueprint_core_scan(name, value) end)
  end

  defp core_string_scans(members, :deployment) do
    members
    |> Enum.reject(fn {name, _} ->
      name in @evidence_names or name in ~w(extensions eligibility)
    end)
    |> Enum.map(fn {_name, value} -> Portability.scan_value(value) end)
  end

  # The blueprint's identifier member tables: ONLY the named members scan
  # (exempting mode); every other member is an enum/number, an open
  # region handled above, or format-checked elsewhere (blueprint.ex's own
  # table, mirrored).
  defp blueprint_core_scan(name, value) when name in ~w(input_ports output_ports),
    do: identifier_positions(value, ["name"])

  defp blueprint_core_scan("capability_requirements", value),
    do: identifier_positions(value, ["operation_family"])

  defp blueprint_core_scan("effect_intents", value),
    do: identifier_positions(value, ["logical_operation"])

  defp blueprint_core_scan("evaluation_assertions", value),
    do: identifier_positions(value, ~w(dataset member operation_family parameter))

  defp blueprint_core_scan(_name, value), do: Portability.scan_value(value)

  # Post-structure every array element is a validated object; a
  # non-object element fails loud on the impossible shape.
  defp identifier_positions({:array, items}, names) do
    items
    |> Enum.find_value(fn {:object, element_members} when is_list(element_members) ->
      named_identifier_scan(element_members, names)
    end)
    |> case do
      nil -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp named_identifier_scan(element_members, names) do
    element_members
    |> Enum.filter(fn {name, _} -> name in names end)
    |> Enum.find_value(fn {_name, value} ->
      case Portability.scan_identifier(value) do
        :ok -> nil
        {:error, _reason} = error -> error
      end
    end)
  end

  defp schema_documents(members) do
    port_schemas(members, "input_ports") ++
      port_schemas(members, "output_ports") ++
      capability_schemas(members) ++
      assertion_schemas(members)
  end

  defp port_schemas(members, member_name) do
    for {:object, port_members} <- member_array(members, member_name),
        {"schema", schema} <- List.wrap(List.keyfind(port_members, "schema", 0)),
        do: schema
  end

  defp capability_schemas(members) do
    for {:object, capability} <- member_array(members, "capability_requirements"),
        name <- ["argument_schema", "result_schema"],
        {^name, schema} <- List.wrap(List.keyfind(capability, name, 0)),
        do: schema
  end

  defp assertion_schemas(members) do
    for {:object, assertion} <- member_array(members, "evaluation_assertions"),
        {"kind", {:string, "output_schema"}} <- List.wrap(List.keyfind(assertion, "kind", 0)),
        {"schema", schema} <- List.wrap(List.keyfind(assertion, "schema", 0)),
        do: schema
  end

  # The arbitrary-JSON operands a deterministic_predicate carries — open
  # content in a digest-covered core position (blueprint.ex's own rule).
  defp predicate_operands(members) do
    for {:object, assertion} <- member_array(members, "evaluation_assertions"),
        {"kind", {:string, "deterministic_predicate"}} <-
          List.wrap(List.keyfind(assertion, "kind", 0)),
        {"predicate", predicate} <- List.wrap(List.keyfind(assertion, "predicate", 0)),
        do: predicate
  end

  # Post-structure these members are present validated arrays; anything
  # else fails loud on the impossible shape.
  defp member_array(members, name) do
    {^name, {:array, items}} = List.keyfind(members, name, 0)
    items
  end

  defp evidence_key_id_scans(members) do
    case List.keyfind(members, "signatures", 0) do
      {"signatures", {:array, entries}} when is_list(entries) ->
        entries
        |> Enum.map(&key_id_of/1)
        |> Enum.concat()
        |> Enum.map(&Portability.scan_value({:string, &1}))

      _absent ->
        []
    end
  end

  # Post-structure every signatures entry parses (the registry's element
  # check runs the same `Signature.attributes`); this reader fails loud on
  # the impossible shape.
  defp key_id_of(entry) do
    {:ok, %Signature.Attributes{key_id: key_id}} = Signature.attributes(entry)
    [key_id]
  end

  defp stage_signatures(blueprint, deployment, keys, bp_digest, dep_digest) do
    with {:ok, bp_entries} <- signature_entries(blueprint),
         {:ok, dep_entries} <- signature_entries(deployment),
         :ok <- verify_entries(bp_entries, keys, bp_digest, "blueprint"),
         :ok <- verify_entries(dep_entries, keys, dep_digest, "deployment") do
      {:ok,
       [
         signatures_check("blueprint", bp_entries),
         signatures_check("deployment", dep_entries)
       ]}
    end
  end

  # An empty signature list establishes no signature fact.
  defp signatures_check(subject, []) do
    %{surface: :signatures, subject: [subject], verified: false, detail: :no_signatures_present}
  end

  defp signatures_check(subject, entries) do
    %{
      surface: :signatures,
      subject: [subject],
      verified: true,
      detail: %Evidence.Signatures{
        key_ids:
          Enum.map(entries, fn entry ->
            {:ok, attrs} = Signature.attributes(entry)
            attrs.key_id
          end)
          |> Enum.uniq()
      }
    }
  end

  defp signature_entries(%Blueprint{} = blueprint),
    do: read_signature_member(Blueprint.to_value(blueprint))

  defp signature_entries(%Deployment{} = deployment),
    do: read_signature_member(Deployment.to_value(deployment))

  defp read_signature_member({:object, members}) do
    # Absent member = no signatures (legitimate); post-structure the
    # registry stage has pinned the array shape, so anything else fails
    # loud on the impossible.
    case List.keyfind(members, "signatures", 0) do
      nil -> {:ok, []}
      {"signatures", {:array, entries}} -> {:ok, entries}
    end
  end

  defp verify_entries(entries, keys, artifact_digest, side) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {entry, index}, :ok ->
      verify_one(entry, index, keys, artifact_digest, side)
    end)
  end

  defp verify_one(entry, index, keys, artifact_digest, side) do
    case Signature.verify(entry, keys) |> typed_signature(index, side) do
      {:ok, %Signature.Attributes{content_digest: %Digest{} = signed}} ->
        if Digest.equal?(signed, artifact_digest),
          do: {:cont, :ok},
          else:
            {:halt,
             {:error, %Error{code: :digest_mismatch, subject: [side, "signatures", index]}}}

      error ->
        {:halt, error}
    end
  end

  defp typed_signature({:ok, value}, _index, _side), do: {:ok, value}

  defp typed_signature({:error, reason}, index, side),
    do: {:error, signature_error(reason, index, side)}

  defp signature_error(reason, index, side),
    do: %{reason | subject: [side, "signatures", index] ++ reason.subject}

  defp stage_bind(deployment, blueprint, observations) do
    case Deployment.verify_binding(deployment, blueprint, observations) do
      :ok ->
        {:object, members} = Deployment.to_value(deployment)
        {"tool_bindings", {:array, bindings}} = List.keyfind(members, "tool_bindings", 0)

        names =
          for {:object, entry} <- bindings,
              {"logical_operation", {:string, name}} <- entry,
              do: name

        staleness? =
          bindings != [] and observations.now != nil and
            observations.max_attestation_age_ms != nil

        descriptors? = names != [] and Enum.all?(names, &Map.has_key?(observations.observed, &1))
        checks = [{:binding_staleness, staleness?}, {:binding_descriptors, descriptors?}]
        checked = for {surface, true} <- checks, do: surface
        skipped = for {surface, false} <- checks, do: surface

        detail = %Evidence.Binding{
          checked: [:release_binding, :binding_completeness, :effect_recovery] ++ checked,
          not_verified: skipped
        }

        {:ok,
         [%{surface: :bind, subject: ["deployment"], verified: skipped == [], detail: detail}]}

      {:error, reason} ->
        {:error, %{reason | subject: ["deployment"] ++ reason.subject}}
    end
  end

  defp stage_bounds(blueprint, deployment, inputs) do
    with {:ok, bp_bounds} <- BoundsAlgebra.from_blueprint(blueprint),
         {:ok, dep_bounds} <- BoundsAlgebra.from_deployment(deployment),
         {:ok, %Result{effective: effective, clamps: clamps}} <-
           BoundsAlgebra.intersect(%Sources{
             blueprint: bp_bounds,
             deployment: dep_bounds,
             host: inputs.host_bounds,
             protected_clamp: inputs.protected_clamp
           }) do
      clamp_checks =
        Enum.map(clamps, fn %ClampEvidence{} = clamp ->
          %{surface: :bounds, subject: [to_string(clamp.field)], verified: true, detail: clamp}
        end)

      {:ok, [check(:bounds, "bounds")] ++ clamp_checks, effective, clamps}
    end
  end

  # ---- small helpers -------------------------------------------------------------------

  defp check(surface, subject),
    do: %{surface: surface, subject: [subject], verified: true, detail: nil}

  defp typed(:ok, _subject), do: :ok
  defp typed({:ok, value}, _subject), do: {:ok, value}

  defp typed({:error, reason}, subject),
    do: {:error, %{reason | subject: [subject] ++ reason.subject}}

  defp digest_of(%Digest{} = digest, _subject), do: digest

  defp revision_of(%Blueprint{} = blueprint) do
    {:object, members} = Blueprint.to_value(blueprint)

    # Post-structure the member is a validated positive integer.
    {"protocol_revision", {:integer, n}} = List.keyfind(members, "protocol_revision", 0)
    n
  end
end
