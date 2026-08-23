defmodule AgentBlueprintProtocol.Negotiation do
  @moduledoc """
  Negotiation: the evolution gate an importing host runs
  after canonical verification, before any semantic read. In a standalone
  pass it runs immediately after canonical verification; in the composed
  import (`Reconcile.reconcile/3`) the pinned stage order is
  `canonical → digest → negotiation → structure → portability →
  signatures → bind → bounds` — the digest stage runs BEFORE negotiation
  (the supersession of the "integrity last" ordering).

  Negotiate reads ONLY protocol machinery — `protocol_revision`,
  `required_core_fields`, the `extensions` envelope — never semantic
  members. Malformed machinery values reuse `Blueprint`'s decode reason
  rules so both entry points agree (absent → `:missing_required_field`,
  wrong tag → `:invalid_type`, revision < 1 → `:invalid_constraint`; the
  retired `:protocol_revision_invalid` stays retired). Internal
  precedence is PINNED: revision → required_core_fields → extensions —
  an artifact failing several stages reports the earliest.

  Revision support is an explicit SET (`Support.revisions`, never ranges);
  a miss denies `:protocol_revision_unsupported` (above-max and below-min
  are the same miss). `Outcome.protocol_revision` is the artifact's own,
  exact — never negotiated down.

  `required_core_fields` runs three fail-closed checks in order: known
  (`:required_core_field_unsupported`) → digest-covered
  (`:required_core_field_not_digest_covered`) → supported by this
  consumer (`:required_core_field_unsupported`).

  Extensions run the positional state machine (criticality match before
  state handling for LIVE states; reserved/retired labels check state
  first — held and dead labels do not enforce criticality; every
  state × position cell decided):

  | registry state    | artifact critical            | artifact optional              |
  |-------------------|------------------------------|--------------------------------|
  | unregistered      | deny `:extension_unknown_critical` | QUARANTINE (byte-exact, noticed) |
  | criticality mismatch | deny `:extension_criticality_conflict` | deny `:extension_criticality_conflict` |
  | active matching   | supported                    | retained, executable            |
  | deprecated        | supported + notice           | retained + notice               |
  | retired           | deny `:extension_retired`    | retained + notice               |
  | reserved          | deny `:extension_unknown_critical` | retained + notice            |

  Quarantined namespaces round-trip byte-exactly and are NEVER claimed
  scanned-or-portable beyond what the structural denylists check.

  Critical bodies validate ONLY against a host-supplied schema whose
  digest matches the registry's pin: none supplied (or the registry entry
  has none authored) → `:extension_schema_unavailable`; digest mismatch →
  `:extension_schema_digest_mismatch`; match → `Schema.validate_instance`
  over the body. Validated critical namespaces are the legitimate channel
  for encoded content — thread them into `Blueprint.from_value/2`'s
  `:authored_extensions` option.

  A reserved-semantics denylist runs over ALL extension bodies (any
  depth, camelCase twins included): bound-shaped member names deny
  `:extension_payload_forbidden` — the bound-vocabulary smuggling the
  portability scan cannot see.

  `negotiate/2` also accepts `%Blueprint{}` (reads `to_value`): a struct
  from `from_value` carries no integrity proof — outcomes derive from the
  given content.
  Negotiation reports what a support posture accepts; it never authorizes an operation.
  Negotiation reports what a support posture accepts; it never authorizes an operation.
  """

  alias AgentBlueprintProtocol.{
    Blueprint,
    Canonicalization,
    Deployment,
    Digest,
    ExtensionRegistry,
    Json,
    Schema
  }

  @all_core_members ~w(
    blueprint_id
    capability_requirements
    ceilings
    classification_ceiling
    content_digest
    effect_intents
    evaluation_assertions
    extensions
    input_ports
    output_contract
    output_ports
    producer
    protocol_revision
    release_number
    required_core_fields
    signatures
    attestations
    triggers
  )

  @deployment_core_members ~w(
    authority_requirement
    blueprint_release
    build_identities
    data_bindings
    deployment_digest
    effect_owner
    eligibility
    evaluation_binding
    extensions
    host_bounds
    lifecycle
    model_policy
    protocol_revision
    required_core_fields
    scope_projection
    signer_custody
    signatures
    attestations
    tool_bindings
  )

  @evidence_members ~w(content_digest signatures attestations)
  @deployment_evidence_members ~w(deployment_digest signatures attestations)

  # The protected families plus the eight ceilings, snake and camel — a
  # legitimate extension body has no member shaped like a core bound.
  # Kebab/upper/case-collapsed spellings are the same reserved name; homoglyph spellings remain the accepted residual of
  # any name list.
  defp reserved_shape(name) do
    name |> String.downcase() |> String.replace("-", "_")
  end

  # Stored as NORMALIZED forms (snake + folded): the input-side
  # reserved_shape/1 converges kebab/SCREAMING/camel spellings onto
  # these at compare time.
  @reserved_names MapSet.new([
                    "approval_trait",
                    "approvaltrait",
                    "authority_trait",
                    "authoritytrait",
                    "classification_ceiling",
                    "classificationceiling",
                    "disclosure_ceiling",
                    "disclosureceiling",
                    "effect_impact_ceiling",
                    "effectimpactceiling",
                    "max_attempts",
                    "max_concurrency",
                    "max_cost",
                    "max_depth",
                    "max_descendants",
                    "max_elapsed_ms",
                    "max_fan_out",
                    "max_tokens",
                    "maxattempts",
                    "maxconcurrency",
                    "maxcost",
                    "maxdepth",
                    "maxdescendants",
                    "maxelapsedms",
                    "maxfanout",
                    "maxtokens"
                  ])

  defmodule Support do
    @moduledoc """
    The consumer's negotiation posture: the revision SET it supports, the
    core fields it implements, an optional HOST-PINNED registry view
    (`%{namespace => ExtensionRegistry.t()}` layered over the compiled
    registry — hosts may supply lifecycle states, never remove compiled
    entries), and the host-supplied schemas for critical namespaces
    (`%{namespace => schema_document}`).
    A support posture is a consumer's declaration that carries no authority.
    A support posture is a consumer's declaration that carries no authority.
    """

    alias AgentBlueprintProtocol.ExtensionRegistry

    defstruct revisions: MapSet.new(), core_fields: MapSet.new(), registry: %{}, schemas: %{}

    @type t :: %__MODULE__{
            revisions: MapSet.t(integer()),
            core_fields: MapSet.t(binary()),
            registry: %{optional(binary()) => ExtensionRegistry.t()},
            schemas: %{optional(binary()) => Json.value()}
          }
  end

  defmodule Outcome do
    @moduledoc """
    The negotiation result: the exact artifact revision, the honored
    required-core-field list, the supported critical / retained optional /
    quarantined namespaces, and typed notices (reason atoms — the typed
    Error notices are the Evidence surface).
    The outcome lists facts about revisions and extensions — it is not a decision.
    The outcome lists facts about revisions and extensions — it is not a decision.
    """

    defstruct [
      :protocol_revision,
      :required_core_fields,
      :critical_extensions,
      :optional_retained,
      :quarantined_extensions,
      :notices
    ]

    @type t :: %__MODULE__{
            protocol_revision: integer(),
            required_core_fields: [binary()],
            critical_extensions: [binary()],
            optional_retained: [binary()],
            quarantined_extensions: [binary()],
            notices: [atom()]
          }
  end

  @type reason ::
          :protocol_revision_unsupported
          | :missing_required_field
          | :invalid_type
          | :invalid_constraint
          | :required_core_field_unsupported
          | :required_core_field_not_digest_covered
          | :extension_unknown_critical
          | :extension_criticality_conflict
          | :extension_retired
          | :extension_schema_unavailable
          | :extension_schema_digest_mismatch
          | :extension_payload_forbidden
          | Schema.schema_reason()
          | Schema.instance_reason()

  @spec negotiate(Blueprint.t() | Deployment.t() | Json.value(), Support.t()) ::
          {:ok, Outcome.t()} | {:error, reason()}
  def negotiate(%Blueprint{} = blueprint, support),
    do: negotiate(Blueprint.to_value(blueprint), support)

  def negotiate(%Deployment{} = deployment, support),
    do: negotiate(Deployment.to_value(deployment), support)

  def negotiate(value, %Support{} = support) do
    # Revision stays FIRST (the pinned order — a max+1 artifact reports
    # its revision reason before any other defect, including an undecidable
    # kind); the vocabulary follows and feeds the fields check.
    with {:ok, revision} <- revision_check(value, support),
         {:ok, vocabulary} <- vocabulary_of(value),
         :ok <- required_fields_check(value, support, vocabulary),
         {:ok, extensions} <- extensions_check(value, support) do
      {:ok,
       %Outcome{
         protocol_revision: revision,
         required_core_fields: required_fields_of(value),
         critical_extensions: extensions.critical,
         optional_retained: extensions.retained,
         quarantined_extensions: extensions.quarantined,
         notices: extensions.notices
       }}
    end
  end

  # The artifact kind resolves through MACHINERY only (content
  # digests are protocol machinery): which digest member the value carries
  # selects the vocabulary the required-fields checks run against. Neither
  # member is an absent-machinery deny; both is an undecidable kind.
  defp vocabulary_of(value) do
    deployment = member_of(value, "deployment_digest")
    blueprint = member_of(value, "content_digest")

    cond do
      tagged_string?(deployment) and tagged_string?(blueprint) ->
        {:error, :invalid_type}

      tagged_string?(deployment) ->
        {:ok, {@deployment_core_members, @deployment_evidence_members}}

      tagged_string?(blueprint) ->
        {:ok, {@all_core_members, @evidence_members}}

      # A present-but-malformed digest member is malformed machinery (the
      # same wrong-tag convention as every other machinery member), and an
      # absent one is the missing-machinery deny.
      deployment != nil or blueprint != nil ->
        {:error, :invalid_type}

      true ->
        {:error, :missing_required_field}
    end
  end

  defp tagged_string?(value), do: match?({:string, _tagged}, value)

  # ---- revision (first in the pinned order) -----------------------------------

  defp revision_check(value, support) do
    case member_of(value, "protocol_revision") do
      {:integer, revision} when is_integer(revision) -> revision_verdict(revision, support)
      nil -> {:error, :missing_required_field}
      _malformed_tag -> {:error, :invalid_type}
    end
  end

  defp revision_verdict(revision, support) do
    cond do
      revision < 1 -> {:error, :invalid_constraint}
      not MapSet.member?(support.revisions, revision) -> {:error, :protocol_revision_unsupported}
      true -> {:ok, revision}
    end
  end

  # ---- required_core_fields (second) --------------------------------------------

  defp required_fields_check(value, support, vocabulary) do
    case member_of(value, "required_core_fields") do
      {:array, items} ->
        Enum.find_value(items, :ok, fn
          {:string, name} -> field_judgment(name, support, vocabulary)
          _malformed -> {:error, :invalid_type}
        end)
        |> case do
          :ok -> :ok
          {:error, _reason} = error -> error
        end

      nil ->
        {:error, :missing_required_field}

      _malformed ->
        {:error, :invalid_type}
    end
  end

  defp field_judgment(name, support, {core_members, evidence_members}) do
    cond do
      name not in core_members -> {:error, :required_core_field_unsupported}
      name in evidence_members -> {:error, :required_core_field_not_digest_covered}
      not MapSet.member?(support.core_fields, name) -> {:error, :required_core_field_unsupported}
      true -> nil
    end
  end

  defp required_fields_of(value) do
    {:array, items} = member_of(value, "required_core_fields")
    for {:string, name} <- items, do: name
  end

  # ---- extensions (third) ---------------------------------------------------------

  defp extensions_check(value, support) do
    case member_of(value, "extensions") do
      {:object, regions} ->
        with :ok <- regions_well_formed(regions) do
          critical = region_namespaces(regions, "critical")
          optional = region_namespaces(regions, "optional")
          extensions_flow(regions, critical, optional, support)
        end

      nil ->
        {:error, :missing_required_field}

      _malformed ->
        {:error, :invalid_type}
    end
  end

  # Both regions present, both objects — anything else is malformed
  # machinery (untrusted bytes reach negotiate BEFORE from_value's shape
  # validation, so the typed deny is load-bearing here).
  defp regions_well_formed(regions) do
    names = Enum.map(regions, fn {name, _} -> name end)

    if Enum.sort(names) == ["critical", "optional"] and
         Enum.all?(regions, fn {_n, v} -> match?({:object, _}, v) end) do
      :ok
    else
      {:error, :invalid_type}
    end
  end

  defp extensions_flow(regions, critical, optional, support) do
    with :ok <- reserved_semantics_check(regions),
         {:ok, acc} <-
           walk_critical(critical, regions, support, %{
             critical: [],
             retained: [],
             quarantined: [],
             notices: []
           }),
         {:ok, acc} <- walk_optional(optional, regions, support, acc) do
      # Wire order for the mirror: the walkers prepend, so reverse the
      # accumulators once at the boundary.
      {:ok,
       %{
         acc
         | critical: Enum.reverse(acc.critical),
           retained: Enum.reverse(acc.retained),
           quarantined: Enum.reverse(acc.quarantined),
           notices: Enum.reverse(acc.notices)
       }}
    end
  end

  defp region_namespaces(regions, name) do
    for {^name, {:object, namespaces}} <- List.wrap(List.keyfind(regions, name, 0)),
        {ns, _body} <- namespaces,
        do: ns
  end

  defp region_body(regions, name, namespace) do
    {^name, {:object, namespaces}} = List.keyfind(regions, name, 0)
    {^namespace, body} = List.keyfind(namespaces, namespace, 0)
    body
  end

  # The host-pinned view is LIFECYCLE-ONLY over compiled entries: state may
  # be supplied (the pinning posture and the test seam), but criticality
  # and the schema digest pin are the registry's alone — a host cannot
  # re-classify or re-pin what the release compiled in. Entries for
  # namespaces the registry does not carry pass through as given (the
  # host-supplied registration surface).
  defp resolve_entry(namespace, support) do
    case Map.fetch(support.registry, namespace) do
      {:ok, override} ->
        case compiled_or_self(namespace, override) do
          {:ok, entry} -> {:ok, entry}
          :malformed_override -> ExtensionRegistry.entry(namespace)
        end

      :error ->
        ExtensionRegistry.entry(namespace)
    end
  end

  # A malformed host override (not an entry struct, or out-of-vocabulary
  # atoms) falls back to the compiled entry — the host's own config error
  # must never raise the gate.
  defp compiled_or_self(namespace, %ExtensionRegistry{} = override) do
    if override.criticality in [:critical, :optional] and
         override.state in [:reserved, :active, :deprecated, :retired] do
      case ExtensionRegistry.entry(namespace) do
        {:ok, compiled} -> {:ok, %{compiled | state: override.state}}
        :error -> {:ok, override}
      end
    else
      :malformed_override
    end
  end

  defp compiled_or_self(_namespace, _not_an_entry), do: :malformed_override

  defp walk_critical([], _regions, _support, acc), do: {:ok, acc}

  defp walk_critical([ns | rest], regions, support, acc) do
    case critical_judgment(ns, regions, support) do
      :ok -> walk_critical(rest, regions, support, %{acc | critical: [ns | acc.critical]})
      {:deprecated, :ok} -> walk_critical(rest, regions, support, deprecated_notice(ns, acc))
      {:error, _reason} = error -> error
    end
  end

  defp critical_judgment(ns, regions, support) do
    case resolve_entry(ns, support) do
      :error ->
        {:error, :extension_unknown_critical}

      {:ok, entry} ->
        critical_body_judgment(ns, entry, regions, support)
    end
  end

  defp critical_body_judgment(ns, entry, regions, support) do
    with :ok <- critical_state_check(entry),
         :ok <- criticality_check(entry, :critical),
         body = region_body(regions, "critical", ns),
         :ok <- critical_body_check(entry, body, support, ns) do
      case entry.state do
        :deprecated -> {:deprecated, :ok}
        _live -> :ok
      end
    end
  end

  defp deprecated_notice(ns, acc) do
    %{
      acc
      | critical: [ns | acc.critical],
        notices: [:extension_deprecated | acc.notices]
    }
  end

  defp walk_optional([], _regions, _support, acc), do: {:ok, acc}

  defp walk_optional([ns | rest], regions, support, acc) do
    case optional_judgment(ns, support) do
      {:retain, notice} ->
        acc = %{acc | retained: [ns | acc.retained], notices: [notice | acc.notices]}
        walk_optional(rest, regions, support, acc)

      :ok ->
        walk_optional(rest, regions, support, %{acc | retained: [ns | acc.retained]})

      {:quarantine} ->
        acc = %{
          acc
          | quarantined: [ns | acc.quarantined],
            notices: [:extension_unknown_optional_retained | acc.notices]
        }

        walk_optional(rest, regions, support, acc)

      {:error, _reason} = error ->
        error
    end
  end

  # Held and dead labels do not enforce criticality at the optional
  # position — old artifacts retain regardless of classification.
  defp optional_judgment(ns, support) do
    case resolve_entry(ns, support) do
      :error ->
        {:quarantine}

      {:ok, entry} ->
        optional_state_judgment(entry)
    end
  end

  defp optional_state_judgment(entry) do
    case entry.state do
      :retired -> {:retain, :extension_retired}
      s when s in [:reserved, :unknown] -> {:retain, :extension_unknown_optional_retained}
      :deprecated -> deprecated_optional(entry)
      :active -> criticality_check(entry, :optional)
    end
  end

  defp deprecated_optional(entry) do
    case criticality_check(entry, :optional) do
      :ok -> {:retain, :extension_deprecated}
      error -> error
    end
  end

  # Criticality match governs LIVE states only (active/deprecated): the
  # deprecated x mismatch cell is conflict-deny, not notice. Held and dead
  # labels do not enforce criticality — denying old artifacts over a
  # retired namespace's classification would freeze the registry.
  defp criticality_check(entry, position) do
    if entry.criticality == position,
      do: :ok,
      else: {:error, :extension_criticality_conflict}
  end

  defp critical_state_check(entry) do
    case entry.state do
      :retired -> {:error, :extension_retired}
      :reserved -> {:error, :extension_unknown_critical}
      _live -> :ok
    end
  end

  defp critical_body_check(entry, body, support, namespace) do
    with :ok <- schema_available(entry),
         {:ok, schema} <- schema_of(support, namespace),
         :ok <- digest_check(entry, schema) do
      Schema.validate_instance(schema, body, Schema.dialect())
    end
  end

  defp schema_available(entry) do
    if entry.schema_digest != nil,
      do: :ok,
      else: {:error, :extension_schema_unavailable}
  end

  defp schema_of(support, namespace) do
    case Map.fetch(support.schemas, namespace) do
      {:ok, schema} -> {:ok, schema}
      :error -> {:error, :extension_schema_unavailable}
    end
  end

  # The pin: JCS of the parsed document (Schema.parse keeps the document
  # verbatim in `.root`) under the extension-schema domain — the same
  # contract the registry author used.
  defp digest_check(entry, schema) do
    with {:ok, parsed} <- Schema.parse(schema, Schema.dialect()),
         {:ok, jcs} <- Canonicalization.encode(parsed.root) do
      tagged = Digest.to_tagged(Digest.hash(:extension_schema, jcs))

      if tagged == entry.schema_digest,
        do: :ok,
        else: {:error, :extension_schema_digest_mismatch}
    end
  end

  # ---- reserved-semantics denylist ---------------------------------------------------

  defp reserved_semantics_check(regions) do
    regions
    |> Enum.any?(fn {_name, {:object, namespaces}} ->
      Enum.any?(namespaces, fn {_ns, body} -> bound_shaped_name?(body) end)
    end)
    |> then(fn found -> if found, do: {:error, :extension_payload_forbidden}, else: :ok end)
  end

  defp bound_shaped_name?(value), do: bound_shaped_walk(value)

  defp bound_shaped_walk({:object, members}) when is_list(members) do
    Enum.any?(members, fn {name, value} ->
      MapSet.member?(@reserved_names, reserved_shape(name)) or bound_shaped_walk(value)
    end)
  end

  defp bound_shaped_walk({:array, items}) when is_list(items),
    do: Enum.any?(items, &bound_shaped_walk/1)

  defp bound_shaped_walk(_leaf), do: false

  # ---- shared member access -----------------------------------------------------------

  defp member_of({:object, members}, name) do
    case List.keyfind(members, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp member_of(_other, _name), do: nil
end
