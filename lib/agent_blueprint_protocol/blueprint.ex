defmodule AgentBlueprintProtocol.Blueprint do
  @moduledoc """
  The Blueprint artifact (base §6): an immutable, portable, inert statement
  of intent, decoded and validated through the ONE generic field-registry
  engine (`AgentBlueprintProtocol.Registry`) parameterized by this module's
  18-member table.

  The decode pipeline, in order, each stage fail-closed:

  1. `Canonicalization.verify/2` on the received bytes — a non-canonical
     spelling of a byte-identical value denies `:non_canonical_bytes` BEFORE
     any semantic read or digest comparison (the canonicality
     obligation: digests are computed only over exact received bytes, and a
     re-encode-then-digest shortcut must fail this gate, never
     `verify_content`).
  2. `AgentBlueprintProtocol.Registry.validate/2` against `table/0` — closed world
     (`:unknown_member`), required members, tag-strict integer typing (the
     The window-float deny: `{:float, f}` in an integer-typed core field is
     `:invalid_type` here, because only this layer sees the decoder tag the
     wire cannot carry), enums, cardinalities, and the per-member custom
     checks (bounded schemas via `Schema`, signature envelopes via
     `Signature`, the extension envelope, the assertion operands).
  3. The portability scan (`Portability`) — full scan over the open regions
     (extension bodies, bounded-schema documents), value-shape scan over
     every other string including signature `key_id`, `:forbidden_portable_value`.
  4. The content-digest comparison — `Digest.verify_content/3` over the
     canonical bytes of the covered members (everything except
     `content_digest`, `signatures`, `attestations`), `:digest_mismatch` on
     divergence.

  `from_value/1` runs stages 2-3 without canonicality (there are no bytes):
  structure only, for values that came from `verify`-ed bytes or for
  producer-side composition — `verify_content_digest/1` is the integrity
  half and must be called separately for the compose-then-verify flow.

  `to_value/1` is the identity on the held tagged value, so
  `decode → to_value → encode` is a byte-exact fixed point (the
  quarantine round-trip depends on it).
  A Blueprint is an inert description: decoding one never authorizes an operation.
  """

  alias AgentBlueprintProtocol.{
    Bounds,
    Canonicalization,
    Digest,
    Extension,
    Json,
    Portability,
    Predicate,
    Registry,
    Schema,
    Signature
  }

  @ceiling_ports 64
  @ceiling_capabilities 64
  @ceiling_effects 64
  @ceiling_assertions 128
  @ceiling_signatures 16
  @ceiling_attestations 16
  @identifier_bytes 512

  @classification ~w(public internal confidential restricted)
  @operation_kinds ~w(read computation mutation)
  @impact_classes ~w(ordinary money authority secret)
  @approval_traits ~w(none human_required separated_human_required)
  @authority_traits ~w(none local_policy external_authority_required)
  @trigger_kinds ~w(manual schedule condition evaluation delegated)

  @assertion_kinds ~w(
    output_schema
    deterministic_predicate
    required_capability_use
    forbidden_capability_use
    grounding_presence
    policy_denial_expected
    approval_expected
    parameter_bound
    provenance_tie_out
    ceiling
  )

  @numeric_ceilings ~w(
    max_attempts
    max_concurrency
    max_depth
    max_descendants
    max_elapsed_ms
    max_fan_out
    max_tokens
  )

  # The 15 digest-covered members; the evidence trio is excluded by §8.2.
  @covered_members ~w(
    blueprint_id
    capability_requirements
    ceilings
    classification_ceiling
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
    triggers
  )

  @evidence_members ~w(content_digest signatures attestations)

  @segment ~r/\A[a-z0-9][a-z0-9._-]*\z/
  @z_form ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/
  @currency ~r/\A[A-Z]{3}\z/

  defstruct [:value]

  @type t :: %__MODULE__{value: Json.value()}
  @type reason :: Registry.reason()

  # ---- the table --------------------------------------------------------------------

  @doc """
  The 18-member field registry (base §6): data for the generic engine. Field
  order is the engine's precedence anchor for table-order stages.
  """
  @spec table() :: [Registry.spec()]
  def table do
    [
      field("blueprint_id", :string, check: &check_producer_qualified/1),
      field("capability_requirements", {:array, capability_element()},
        max_items: @ceiling_capabilities,
        unique_by: "operation_family"
      ),
      field("ceilings", {:object, %{members: ceilings_members()}}),
      field("classification_ceiling", {:enum, MapSet.new(@classification)}),
      field("effect_intents", {:array, effect_element()},
        max_items: @ceiling_effects,
        unique_by: "logical_operation"
      ),
      field("evaluation_assertions", {:array, assertion_element()},
        max_items: @ceiling_assertions,
        root_hook: &hook_assertions/1
      ),
      field("extensions", :custom, check: &Extension.envelope_ok?/1),
      field("input_ports", {:array, port_element()},
        max_items: @ceiling_ports,
        unique_by: "name"
      ),
      field("output_contract", {:object, %{members: output_contract_members()}},
        root_hook: &hook_output_contract/1
      ),
      field("output_ports", {:array, port_element()},
        max_items: @ceiling_ports,
        unique_by: "name"
      ),
      field("producer", {:object, %{members: producer_members()}}),
      field("protocol_revision", :integer, check: &check_positive/1),
      field("release_number", :integer, check: &check_positive/1),
      field("required_core_fields", {:array, %{kind: :string}},
        unique_by: :value,
        check: &check_required_core_fields/1
      ),
      field("triggers", {:array, %{kind: {:enum, MapSet.new(@trigger_kinds)}}},
        min_items: 1,
        unique_by: :value
      ),
      field("signatures", {:array, signature_element()},
        required: false,
        max_items: @ceiling_signatures
      ),
      field("attestations", {:array, %{kind: :any}},
        required: false,
        max_items: @ceiling_attestations,
        check: &check_attestations/1
      ),
      field("content_digest", :string, check: &check_tagged_digest/1)
    ]
  end

  defp field(name, kind, opts \\ []) do
    Map.new(Keyword.merge([name: name, required: true, kind: kind], opts))
  end

  defp port_element do
    %{
      kind:
        {:object,
         %{
           members: [
             field("name", :string),
             field("schema", :custom, check: &check_schema_document/1),
             field("classification_ceiling", {:enum, MapSet.new(@classification)}),
             field("required", :boolean)
           ]
         }}
    }
  end

  defp capability_element do
    %{
      kind:
        {:object,
         %{
           members: [
             field("operation_family", :string),
             field("argument_schema", :custom, check: &check_schema_document/1),
             field("result_schema", :custom, check: &check_schema_document/1),
             field("operation_kind", {:enum, MapSet.new(@operation_kinds)}),
             field("impact_class", {:enum, MapSet.new(@impact_classes)}),
             field("classification_ceiling", {:enum, MapSet.new(@classification)}),
             field("approval_trait", {:enum, MapSet.new(@approval_traits)}),
             field("authority_trait", {:enum, MapSet.new(@authority_traits)})
           ]
         }}
    }
  end

  defp effect_element do
    %{
      kind:
        {:object,
         %{
           members: [
             field("logical_operation", :string),
             field("operation_kind", {:enum, MapSet.new(@operation_kinds)}),
             field("impact_class", {:enum, MapSet.new(@impact_classes)})
           ]
         }}
    }
  end

  defp ceilings_members do
    numeric =
      Enum.map(@numeric_ceilings, fn name ->
        field(name, :integer, check: &check_positive/1)
      end)

    cost =
      field(
        "max_cost",
        {:object,
         %{
           members: [
             field("amount", :integer, check: &check_positive/1),
             field("currency", :string, check: &check_currency/1)
           ]
         }}
      )

    numeric ++ [cost]
  end

  defp producer_members do
    [
      field("identity", :string, check: &check_producer_name/1),
      field("created_at", :string, check: &check_z_form/1),
      field("toolchain", :string)
    ]
  end

  defp output_contract_members do
    [
      field("port", :string),
      field("classification_ceiling", {:enum, MapSet.new(@classification)})
    ]
  end

  defp signature_element do
    %{kind: :custom, check: &check_signature_entry/1}
  end

  # The assertion element carries the closed per-kind operand check; the
  # predicate and the cross-field references validate in the root hook,
  # where the declared port names are visible.
  defp assertion_element do
    %{kind: :custom, check: &check_assertion/1}
  end

  # ---- decode ------------------------------------------------------------------------

  @doc """
  Decode and fully verify artifact `bytes`: canonical verify → registry
  validation → portability scan → content-digest comparison. Total and
  never-raising.
  """
  @spec decode(binary(), Bounds.t() | map()) :: {:ok, t()} | {:error, reason()}
  def decode(binary, bounds \\ Bounds.maximum())

  def decode(binary, bounds) when is_binary(binary) do
    with {:ok, value} <- Canonicalization.verify(binary, bounds),
         :ok <- Registry.validate(table(), value),
         :ok <- scan(value, MapSet.new()),
         :ok <- verify_content_digest(%__MODULE__{value: value}) do
      {:ok, %__MODULE__{value: value}}
    end
  end

  # The API type boundary — the moduledoc's "total and never-raising" made
  # true at this clause too: a non-binary input denies :invalid_type instead
  # of raising FunctionClauseError (the corpus floor's json surface fix).
  def decode(_binary, _bounds), do: {:error, :invalid_type}

  @doc """
  Validate an already-decoded tagged value (stages 2-3; no canonicality —
  there are no bytes, so the canonicality ordering obligation does not apply here).
  For values that came from `verify`-ed bytes, follow with
  `verify_content_digest/1`.

  `opts` carries `:authored_extensions` — namespaces whose critical bodies
  negotiation validated against a digest-pinned host schema. Those
  bodies are the legitimate channel for encoded content and SKIP the
  portability value-shape heuristics entirely (mixed-case encoded blobs
  are the channel's payload — the authored posture alone would still deny
  them): their controls are the digest-pinned schema validation and the
  reserved-semantics denylist, both at negotiation. The default (`[]`)
  keeps the strict posture everywhere.
  """
  @spec from_value(Json.value(), map()) :: {:ok, t()} | {:error, reason()}
  def from_value(value, opts \\ %{}) when is_map(value) or is_tuple(value) do
    validated = Map.get(opts, :authored_extensions, [])

    with :ok <- authored_tied_to_value(value, validated),
         :ok <- Registry.validate(table(), value),
         :ok <- scan(value, MapSet.new(validated)) do
      {:ok, %__MODULE__{value: value}}
    end
  end

  @doc "The held tagged value — the identity, so the round-trip is byte-exact."
  @spec to_value(t()) :: Json.value()
  def to_value(%__MODULE__{value: value}), do: value

  @doc "The digest input: the artifact minus the three evidence members (§8.2)."
  @spec digest_input(t()) :: Json.value()
  def digest_input(%__MODULE__{value: {:object, members}}) do
    {:object, Enum.reject(members, fn {name, _} -> name in @evidence_members end)}
  end

  @doc "Whether `member_name` (a wire-level member name) is digest-covered."
  @spec digest_covered?(binary()) :: boolean()
  def digest_covered?(member_name) when is_binary(member_name),
    do: member_name in @covered_members

  @doc "The canonical bytes of the whole artifact."
  @spec canonical_bytes(t()) :: {:ok, binary()} | {:error, reason()}
  def canonical_bytes(%__MODULE__{value: value}), do: Canonicalization.encode(value)

  @doc "The honest content digest over the covered members' canonical bytes."
  @spec content_digest(t()) :: Digest.t() | {:error, reason()}
  def content_digest(%__MODULE__{} = blueprint) do
    with {:ok, jcs} <- Canonicalization.encode(digest_input(blueprint)) do
      Digest.hash(:blueprint_content, jcs)
    end
  end

  @doc """
  Compare the declared `content_digest` member against the recomputed
  digest over the exact received (verified) bytes' canonical form:
  `:digest_mismatch` on divergence.
  """
  @spec verify_content_digest(t()) :: :ok | {:error, reason()}
  def verify_content_digest(%__MODULE__{value: {:object, members}} = blueprint) do
    case List.keyfind(members, "content_digest", 0) do
      {"content_digest", {:string, tagged}} ->
        with {:ok, jcs} <- Canonicalization.encode(digest_input(blueprint)) do
          Digest.verify_content(:blueprint_content, jcs, tagged)
        end

      _other ->
        {:error, :invalid_type}
    end
  end

  # ---- field checks (carried in the table as data) -----------------------------------

  defp check_positive({:integer, n}) when n >= 1, do: :ok
  defp check_positive(_value), do: {:error, :invalid_constraint}

  defp check_producer_qualified({:string, s}) do
    segments = String.split(s, "/")

    if byte_size(s) <= @identifier_bytes and length(segments) == 2 and
         Enum.all?(segments, &(&1 != "" and Regex.match?(@segment, &1))),
       do: :ok,
       else: {:error, :invalid_constraint}
  end

  defp check_producer_name({:string, s}) do
    if byte_size(s) <= @identifier_bytes and Regex.match?(@segment, s),
      do: :ok,
      else: {:error, :invalid_constraint}
  end

  defp check_z_form({:string, s}) do
    # Digit shape first (cheap), then calendar reality: the regex admits
    # 2026-99-99T99:99:99Z, the calendar does not.
    if Regex.match?(@z_form, s) and match?({:ok, _, _}, DateTime.from_iso8601(s)),
      do: :ok,
      else: {:error, :invalid_constraint}
  end

  defp check_currency({:string, s}) do
    if Regex.match?(@currency, s), do: :ok, else: {:error, :invalid_constraint}
  end

  defp check_tagged_digest({:string, tagged}) do
    case Digest.from_tagged(tagged) do
      {:ok, _digest} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_schema_document(value) do
    case Schema.parse(value, Schema.dialect()) do
      {:ok, _schema} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # The purpose is the artifact's fact (the symmetric assertion): the
  # envelope parses (the closed set) AND must be "blueprint" here — a
  # deployment-purpose signature riding a Blueprint is a wrong-position
  # entry, denied as a table constraint.
  defp check_signature_entry(entry) do
    case Signature.attributes(entry) do
      {:ok, %Signature.Attributes{purpose: :blueprint}} -> :ok
      {:ok, _other_purpose} -> {:error, :invalid_constraint}
      {:error, reason} -> {:error, reason}
    end
  end

  # The attestation kind registry is empty BY DESIGN; no entry can be
  # kind-valid, so a non-empty array denies. When kinds register, this row
  # gains the envelope shape parse.
  defp check_attestations({:array, []}), do: :ok
  defp check_attestations({:array, _entries}), do: {:error, :attestation_malformed}

  defp check_required_core_fields({:array, items}) do
    if Enum.all?(items, fn
         {:string, name} -> name in @covered_members
         _not_a_string -> false
       end),
       do: :ok,
       else: {:error, :invalid_constraint}
  end

  # ---- assertion element check ---------------------------------------------------------

  # operand name => {operand kind, required?}
  @operand_specs %{
    "output_schema" => %{"port" => {:string, true}, "schema" => {:schema_document, true}},
    "deterministic_predicate" => %{"predicate" => {:any, true}},
    "required_capability_use" => %{"operation_family" => {:string, true}},
    "forbidden_capability_use" => %{"operation_family" => {:string, true}},
    "grounding_presence" => %{"dataset" => {:nonempty_string, true}},
    "policy_denial_expected" => %{"operation_family" => {:string, true}},
    "approval_expected" => %{
      "operation_family" => {:string, true},
      "approval_trait" => {{:enum, MapSet.new(@approval_traits)}, true}
    },
    "parameter_bound" => %{
      "parameter" => {:nonempty_string, true},
      "minimum" => {:optional_number, false},
      "maximum" => {:optional_number, false}
    },
    "provenance_tie_out" => %{"member" => {:string, true}},
    "ceiling" => %{
      "ceiling" => {{:enum, MapSet.new(@numeric_ceilings)}, true},
      "at_most" => {:positive_number, true}
    }
  }

  defp check_assertion({:object, members}) do
    with {:ok, kind} <- assertion_kind(members),
         :ok <- assertion_closed(members, kind) do
      assertion_operands(members, kind)
    end
  end

  defp check_assertion(_other), do: {:error, :invalid_type}

  defp assertion_kind(members) do
    case List.keyfind(members, "kind", 0) do
      {"kind", {:string, kind}} when kind in @assertion_kinds -> {:ok, kind}
      {"kind", {:string, _other}} -> {:error, :invalid_constraint}
      {"kind", _other} -> {:error, :invalid_type}
      nil -> {:error, :missing_required_field}
    end
  end

  defp assertion_closed(members, kind) do
    allowed = MapSet.new(Map.keys(Map.fetch!(@operand_specs, kind)) ++ ["kind"])

    case Enum.find(members, fn {name, _} -> not MapSet.member?(allowed, name) end) do
      nil -> :ok
      _unknown -> {:error, :unknown_member}
    end
  end

  defp assertion_operands(members, kind) do
    operands = Map.fetch!(@operand_specs, kind)

    missing =
      Enum.find(operands, fn {name, {_operand_kind, required?}} ->
        required? and List.keyfind(members, name, 0) == nil
      end)

    case missing do
      nil -> operand_types(members, operands, kind)
      {_missing, _} -> {:error, :missing_required_field}
    end
  end

  defp operand_types(members, operands, kind) do
    operands
    |> Enum.find_value(:ok, fn {name, {operand_kind, _required?}} ->
      operand_judgment(members, name, operand_kind)
    end)
    |> case do
      :ok -> at_least_one_bound(members, kind)
      {:error, _reason} = error -> error
    end
  end

  defp operand_judgment(members, name, operand_kind) do
    case List.keyfind(members, name, 0) do
      nil -> nil
      {^name, value} -> operand_result(operand_kind, value)
    end
  end

  defp operand_result(operand_kind, value) do
    case operand_type_ok?(operand_kind, value) do
      :ok -> nil
      {:error, _reason} = error -> error
    end
  end

  # parameter_bound: at least one of minimum/maximum must be present.
  defp at_least_one_bound(members, "parameter_bound") do
    has_bound =
      List.keyfind(members, "minimum", 0) != nil or List.keyfind(members, "maximum", 0) != nil

    if has_bound, do: :ok, else: {:error, :invalid_constraint}
  end

  defp at_least_one_bound(_members, _kind), do: :ok

  defp operand_type_ok?(:string, {:string, _s}), do: :ok

  defp operand_type_ok?(:nonempty_string, {:string, s}) when s != "", do: :ok

  defp operand_type_ok?(:any, value) do
    if well_formed?(value), do: :ok, else: {:error, :invalid_type}
  end

  defp operand_type_ok?(:schema_document, value), do: check_schema_document(value)

  defp operand_type_ok?(:optional_number, {:integer, _n}), do: :ok
  defp operand_type_ok?(:optional_number, {:float, _f}), do: :ok

  defp operand_type_ok?(:positive_number, {:integer, n}) when n >= 1, do: :ok
  defp operand_type_ok?(:positive_number, {:float, f}) when f >= 1, do: :ok

  defp operand_type_ok?({:enum, allowed}, {:string, s}) do
    if MapSet.member?(allowed, s), do: :ok, else: {:error, :invalid_constraint}
  end

  defp operand_type_ok?(_operand_kind, _value), do: {:error, :invalid_type}

  defp well_formed?(:null), do: true
  defp well_formed?({:boolean, b}), do: is_boolean(b)
  defp well_formed?({:integer, n}), do: is_integer(n)
  defp well_formed?({:float, f}), do: is_float(f)
  defp well_formed?({:string, s}), do: is_binary(s)
  defp well_formed?({:array, items}) when is_list(items), do: Enum.all?(items, &well_formed?/1)

  defp well_formed?({:object, members}) when is_list(members) do
    Enum.all?(members, fn
      {name, value} when is_binary(name) -> well_formed?(value)
      _other -> false
    end)
  end

  defp well_formed?(_other), do: false

  # ---- root hooks ------------------------------------------------------------------------

  defp hook_assertions(members) do
    input_names = port_names(members, "input_ports")
    output_names = port_names(members, "output_ports")
    port_names = MapSet.new(input_names ++ output_names)
    families = MapSet.new(capability_families(members))

    # One flat port namespace: an input/output name collision makes every
    # predicate root and host-side port map ambiguous.
    if Enum.any?(input_names, &(&1 in output_names)) do
      {:error, :invalid_cardinality}
    else
      assertion_hooks(members, port_names, families)
    end
  end

  defp assertion_hooks(members, port_names, families) do
    members
    |> member_array("evaluation_assertions")
    |> Enum.find_value(fn assertion ->
      pass_nil(assertion_hook_check(assertion, port_names, families))
    end)
    |> case do
      nil -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp assertion_hook_check({:object, members} = _assertion, port_names, families) do
    {"kind", {:string, kind}} = List.keyfind(members, "kind", 0)

    case kind do
      "deterministic_predicate" ->
        {"predicate", predicate} = List.keyfind(members, "predicate", 0)
        Predicate.validate(predicate, MapSet.to_list(port_names))

      "output_schema" ->
        {"port", {:string, port_name}} = List.keyfind(members, "port", 0)

        if MapSet.member?(port_names, port_name),
          do: :ok,
          else: {:error, :invalid_constraint}

      "required_capability_use" ->
        family_in(members, families)

      "approval_expected" ->
        family_in(members, families)

      "provenance_tie_out" ->
        {"member", {:string, name}} = List.keyfind(members, "member", 0)

        if name in @covered_members,
          do: :ok,
          else: {:error, :invalid_constraint}

      _non_cross_field ->
        :ok
    end
  end

  defp family_in(members, families) do
    {"operation_family", {:string, family}} = List.keyfind(members, "operation_family", 0)

    if MapSet.member?(families, family),
      do: :ok,
      else: {:error, :invalid_constraint}
  end

  defp hook_output_contract(members) do
    output_names = MapSet.new(port_names(members, "output_ports"))
    {:object, contract} = Map.get(members, "output_contract")
    {"port", {:string, port_name}} = List.keyfind(contract, "port", 0)

    if MapSet.member?(output_names, port_name),
      do: :ok,
      else: {:error, :invalid_constraint}
  end

  defp port_names(members, member_name) do
    for {:object, port_members} <- member_array(members, member_name),
        {"name", {:string, name}} <- List.wrap(List.keyfind(port_members, "name", 0)),
        do: name
  end

  defp capability_families(members) do
    for {:object, capability} <- member_array(members, "capability_requirements"),
        {"operation_family", {:string, family}} <-
          List.wrap(List.keyfind(capability, "operation_family", 0)),
        do: family
  end

  # Hooks receive the member map the engine builds; the scan walks the
  # ordered member list. Both shapes address members through here.
  defp member_value(members, name) when is_map(members), do: Map.get(members, name)

  defp member_value(members, name) when is_list(members) do
    case List.keyfind(members, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp member_array(members, name) do
    case member_value(members, name) do
      {:array, items} when is_list(items) -> items
      _other -> []
    end
  end

  # ---- the portability scan ------------------------------------------------------------------

  # The channel is tied to THIS artifact: every authored namespace must sit
  # in this value's critical region (an
  # Outcome from a different artifact, an optional/quarantined
  # namespace, or a hand-typed list all deny here instead of silently
  # waiving the scan). The composed-import helper that threads
  # negotiation's validated list mechanically is the reconcile surface.
  defp authored_tied_to_value(_value, []), do: :ok

  defp authored_tied_to_value({:object, members}, authored) do
    critical = Extension.critical_namespaces(members)

    if Enum.all?(authored, &MapSet.member?(critical, &1)),
      do: :ok,
      else: {:error, :invalid_type}
  end

  defp authored_tied_to_value(_other, _authored), do: {:error, :invalid_type}

  # Non-object values were already denied by the registry stage.
  defp scan({:object, members}, authored_ns) do
    with :ok <- scan_open_regions(members, authored_ns),
         :ok <- scan_core_strings(members) do
      scan_evidence_key_ids(members)
    end
  end

  # Extension bodies: names + strict values (host content earns no
  # identifier tolerance) — EXCEPT negotiation-validated critical
  # namespaces (the encoded-content channel: they skip the value-shape
  # heuristics; their controls are the digest-pinned schema validation and
  # the reserved-semantics denylist at negotiation). Schema documents and
  # predicate value/values operands: names + exempting values — authored
  # JSON whose values legitimately carry long identifier-shaped strings
  # legitimately.
  defp scan_open_regions(members, validated_ns) do
    {_validated_bodies, strict_bodies} =
      Enum.split_with(Extension.bodies(members), fn {ns, _body} ->
        MapSet.member?(validated_ns, ns)
      end)

    scans =
      Enum.map(strict_bodies, fn {_ns, body} -> Portability.scan(body) end) ++
        Enum.map(
          schema_documents(members) ++ predicate_operands(members),
          &Portability.scan_authored/1
        )

    scans
    |> Enum.find_value(fn
      :ok -> nil
      {:error, _reason} = error -> error
    end)
    |> case do
      nil -> :ok
      {:error, _reason} = error -> error
    end
  end

  # The arbitrary-JSON operands a deterministic_predicate carries — open
  # content in a digest-covered core position.
  defp predicate_operands(members) do
    for {:object, assertion} <- member_array(members, "evaluation_assertions"),
        {"kind", {:string, "deterministic_predicate"}} <-
          List.wrap(List.keyfind(assertion, "kind", 0)),
        {"predicate", {:object, predicate_members}} <-
          List.wrap(List.keyfind(assertion, "predicate", 0)),
        operand_name <- ["value", "values"],
        {^operand_name, operand} <-
          List.wrap(List.keyfind(predicate_members, operand_name, 0)),
        do: operand
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

  # Value shapes over every other core string. Identifier-convention
  # positions (port names, operation families, logical operations, the
  # assertion operand strings) keep the exemption; everything else is
  # strict. Schemas and predicate operands were full-scanned above.
  defp scan_core_strings(members) do
    members
    |> Enum.reject(fn {name, _} -> name in @evidence_members or name == "extensions" end)
    |> Enum.find_value(fn {name, value} -> pass_nil(core_member_scan(name, value)) end)
    |> case do
      nil -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp pass_nil(:ok), do: nil
  defp pass_nil({:error, _reason} = error), do: error

  defp core_member_scan("input_ports", value), do: identifier_positions(value, ["name"])
  defp core_member_scan("output_ports", value), do: identifier_positions(value, ["name"])

  defp core_member_scan("capability_requirements", value),
    do: identifier_positions(value, ["operation_family"])

  defp core_member_scan("effect_intents", value),
    do: identifier_positions(value, ["logical_operation"])

  defp core_member_scan("evaluation_assertions", value),
    do: identifier_positions(value, ["dataset", "member", "operation_family", "parameter"])

  defp core_member_scan(_name, value), do: Portability.scan_value(value)

  # Element objects: ONLY the named identifier members are scanned here
  # (exempting mode). Every other member is either an enum/number (no
  # strings), an open region full-scanned above (schemas, predicates —
  # strict-scanning those here would deny what the authored scan exempts),
  # or format-checked elsewhere.
  defp identifier_positions({:array, items}, names) do
    items
    |> Enum.find_value(fn element -> pass_nil(identifier_element(element, names)) end)
    |> case do
      nil -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp identifier_element({:object, members}, names) do
    members
    |> Enum.filter(fn {name, _value} -> name in names end)
    |> Enum.find_value(fn {_name, value} -> pass_nil(Portability.scan_identifier(value)) end)
    |> case do
      nil -> :ok
      {:error, _reason} = error -> error
    end
  end

  # The one free string inside an evidence entry: the envelope constrains key_id only
  # to non-empty and dot-free, and evidence members are digest-UNCOVERED —
  # a secret-shaped key there must still red.
  defp scan_evidence_key_ids(members) do
    members
    |> member_array("signatures")
    |> Enum.find_value(:ok, &evidence_key_id_result/1)
    |> case do
      :ok -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp evidence_key_id_result(entry) do
    {:ok, %Signature.Attributes{key_id: key_id}} = Signature.attributes(entry)
    key_id_scan_result(key_id)
  end

  defp key_id_scan_result(key_id) do
    case Portability.scan_value({:string, key_id}) do
      :ok -> nil
      {:error, _reason} = error -> error
    end
  end
end
