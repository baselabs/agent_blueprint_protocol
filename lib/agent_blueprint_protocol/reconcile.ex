defmodule AgentBlueprintProtocol.Reconcile do
  @moduledoc """
  The one call per import : the composed
  non-authorizing pass over a Blueprint + Deployment pair under host
  inputs. Stage order is PINNED — canonical → digest → negotiation →
  structure → portability → signatures → bind → bounds — each stage
  reject-or-annotate, never repair, the earliest defect reported.

  Stage machinery (each denies typed, subject naming its side):

  1. `canonical` — re-encode both artifacts' values (RFC 8785). A struct
     has no bytes to compare against, so this stage catches only what
     ENCODE denies: the ceiling family (`{:ceiling, :bytes}` — the
     `:canonical_bytes_exceeded` name),
     `:integer_magnitude` (a hand-built above-I-JSON integer), and the
     encode-side Json reasons. `:non_canonical_bytes` is decode-time only
     (it needs the original bytes).
  2. `digest` — recompute each artifact's content digest over its covered
     members and compare against the declared member (`:digest_mismatch`).
  3. `negotiation` — both artifacts against `Inputs.support`. Extension
     facts land as checks: a quarantined optional namespace is
     `%{surface: :extensions, verified: false}` (the unscanned
     honesty), a retained one `%{surface: :extensions, verified: true,
     detail: "retained"}`. Notices stay in the `Negotiation.Outcome` for
     standalone callers — the frozen Evidence struct has no notices field.
  4. `structure` — `Registry` validation against each artifact's table
     (the closed world, cardinalities, member checks).
  5. `portability` — the DIRECT scans under the authored channel
     re-derived from THIS import's negotiated critical extensions (F8):
     non-authored extension bodies, eligibility expressions, every core
     string, and signature key_ids (`:forbidden_portable_value`). The
     registry half of the decode pipeline is NOT re-run here — it is
     stage 4's own catch, and re-running it would make that stage's
     guard unobservable.
  6. `signatures` — every `signatures` entry verifies against
     `Inputs.keys` AND its signed `content_digest` BINDS to the
     artifact's recomputed digest: an honestly-signed statement naming a
     different digest is evidence over THAT digest, not this artifact
     (`:digest_mismatch`). Attestations need no pass here — the registry
     table denies any non-empty attestation member today (the kind
     registry is empty; the fail-closed posture).
  7. `bind` — `Deployment.verify_binding/3` under `Inputs.observations`
     (host clock, attestation age, observed descriptor digests).
  8. `bounds` — `from_blueprint`/`from_deployment`/host intersected under
     `Inputs.protected_clamp`. Every clamp lands as `Evidence.clamps` and
     as one `surface: :bounds` check whose detail is the
     `%ClampEvidence{}`; `:clamp_applied` remains the notice code for the
     notice machinery (a clamp notice cannot ride the
     negotiation Outcome — bounds runs after it).

  The result is `%Evidence{}` — never a decision; `not_verified` names
  the seven host-owned surfaces by construction (`Evidence.build/1`).
  """

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
    The host inputs reconcile needs: host policy bounds, negotiation
    support, trusted public keys, the protected-clamp posture, and the
    bind-time observations (host clock, max attestation age, observed
    descriptor digests — the binding-surface delta
    kept for parity). Observed BUILD IDENTITIES are deliberately
    NOT an input: the pinned eight-stage order has no
    compatibility stage, so carrying the field would manufacture false
    assurance — hosts call `verify_compatibility/2` for that surface (a
    recorded contract delta: its descriptive Inputs list names observed
    identities).
    Reconcile inputs are caller-supplied facts that carry no authority.
    """

    defstruct [:host_bounds, :support, :keys, :protected_clamp, :observations]

    @type t :: %__MODULE__{
            host_bounds: BoundSet.t(),
            support: Support.t(),
            keys: [PublicKey.t()],
            protected_clamp: :deny | :acknowledge,
            observations: Observations.t()
          }
  end

  @postures [:deny, :acknowledge]

  @doc """
  Run the eight-stage composed pass. Denies typed at the earliest failing
  stage; every malformed input shape (either artifact, or any Inputs
  field) denies typed without raising.
  """
  @spec reconcile(Blueprint.t(), Deployment.t(), Inputs.t()) ::
          {:ok, Evidence.t()} | {:error, Error.t()}
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
    case Enum.find_index(keys, &(not is_struct(&1, PublicKey))) do
      nil -> :ok
      index -> {:error, %Error{code: :invalid_type, subject: ["inputs", "keys", index]}}
    end
  end

  defp keys_check(_), do: {:error, %Error{code: :invalid_type, subject: ["inputs", "keys"]}}

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
        optional_extensions_retained:
          Enum.uniq(bp_outcome.optional_retained ++ dep_outcome.optional_retained)
      )
    end
  end

  # The artifact ROOT must be an object before any member-reading stage
  # runs — Blueprint/Deployment's own digest surfaces legitimately raise
  # on struct-bypassed shapes (their documented contract), so the composed
  # pass gates the root here to keep ITS never-raising contract.
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
        %{surface: :extensions, subject: [ns], verified: false, detail: nil}
      end)

    retained =
      Enum.map(outcome.optional_retained, fn ns ->
        %{surface: :extensions, subject: [ns], verified: true, detail: "retained"}
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
        {"predicate", {:object, predicate_members}} <-
          List.wrap(List.keyfind(assertion, "predicate", 0)),
        operand_name <- ["value", "values"],
        {^operand_name, operand} <- List.wrap(List.keyfind(predicate_members, operand_name, 0)),
        do: operand
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
         :ok <- verify_entries(bp_entries, keys, bp_digest),
         :ok <- verify_entries(dep_entries, keys, dep_digest) do
      {:ok,
       [
         signatures_check("blueprint", bp_entries),
         signatures_check("deployment", dep_entries)
       ]}
    end
  end

  # The check is vacuously true over zero entries ("every entry
  # verifies") — the detail says so, so a surface-level reader cannot
  # mistake an unsigned artifact for a verified one.
  defp signatures_check(subject, []) do
    %{surface: :signatures, subject: [subject], verified: true, detail: "no signatures present"}
  end

  defp signatures_check(subject, entries) do
    %{
      surface: :signatures,
      subject: [subject],
      verified: true,
      detail: "#{length(entries)} signature(s) verified"
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

  defp verify_entries(entries, keys, artifact_digest) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {entry, index}, :ok ->
      verify_one(entry, index, keys, artifact_digest)
    end)
  end

  defp verify_one(entry, index, keys, artifact_digest) do
    with {:ok, :verified} <- Signature.verify(entry, keys) |> typed_signature(index),
         {:ok, %Signature.Attributes{content_digest: %Digest{} = signed}} <-
           Signature.attributes(entry) |> typed_signature(index) do
      if Digest.equal?(signed, artifact_digest),
        do: {:cont, :ok},
        else: {:halt, {:error, %Error{code: :digest_mismatch, subject: ["signatures", index]}}}
    else
      error -> {:halt, error}
    end
  end

  defp typed_signature({:ok, value}, _index), do: {:ok, value}
  defp typed_signature({:error, reason}, index), do: {:error, signature_error(reason, index)}

  defp signature_error(reason, index),
    do: %Error{code: reason, subject: ["signatures", index]}

  defp stage_bind(deployment, blueprint, observations) do
    case Deployment.verify_binding(deployment, blueprint, observations) do
      :ok -> {:ok, [check(:bind, "deployment")]}
      {:error, reason} -> {:error, %Error{code: reason, subject: ["deployment"]}}
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
  defp typed({:error, reason}, subject), do: {:error, %Error{code: reason, subject: [subject]}}

  defp digest_of(%Digest{} = digest, _subject), do: digest

  defp revision_of(%Blueprint{} = blueprint) do
    {:object, members} = Blueprint.to_value(blueprint)

    # Post-structure the member is a validated positive integer.
    {"protocol_revision", {:integer, n}} = List.keyfind(members, "protocol_revision", 0)
    n
  end
end
