defmodule AgentBlueprintProtocol.Deployment do
  @moduledoc """
  The Deployment Manifest artifact (base §7, re-derived 2026-08-22): binds
  exactly ONE Blueprint release digest to one local environment — portable
  as a shape, resolved values local. Decoded and validated through the ONE
  generic field-registry engine (`AgentBlueprintProtocol.Registry`)
  parameterized by this module's 19-member table : the table, the
  scan's open regions, and the digest domain are the only deltas from the
  Blueprint pipeline.

  The decode pipeline, in order, each stage fail-closed:

  1. `Canonicalization.verify/2` — non-canonical spellings deny
     `:non_canonical_bytes` before any semantic read (the canonicality ordering).
  2. `AgentBlueprintProtocol.Registry.validate/2` against `table/0` — closed world
     (`:unknown_member`), 16 required members, tag-strict integer typing,
     enums, cardinalities (tool_bindings ≤ 128, data_bindings ≤ 64,
     build_identities ≥ 1 and ≤ 128 — an empty identity manifest pins
     nothing and is the silent-fallback space the base red case names), the
     exact-only build-identity versions (`:compatibility_identity_inexact`
     on any range vocabulary), and the per-member custom checks (tagged
     digests, Z-form timestamps, the lifecycle temporal rules
     `:lifecycle_state_invalid`, the `as_of` total rule).
  3. The portability scan — extension bodies and eligibility expressions
     are the open regions (`Portability.scan` / `scan_authored`); every
     other string position — including every `adapter_identity` and
     `profile_identity` — is value-shape scanned strict: a network URI, PEM
     armour, a JWS shape, or raw-key entropy denies
     `:forbidden_portable_value` (the base's never-portable list, red in
     deployment positions).
  4. The content-digest comparison over the covered members' canonical
     bytes under the `:deployment_content` domain — everything except
     `deployment_digest`, `signatures`, `attestations`.

  ## The binding surface

  `binds?/2` is digest equality AND NOTHING ELSE (base §7's binding rule):
  the declared release digest against the paired Blueprint's RECOMPUTED
  content digest — never the declared member — via constant-time compare.
  Total over the deployment side: malformed deployment input answers
  `false`. (A hand-built malformed `%Blueprint{}` raises in `Blueprint`'s own
  digest surface — that module's contract, not this one's.)

  `verify_binding/3` is the six-stage deny set, order pinned (the second-language
  verifier contract):

  1. release digest equality → `:deployment_digest_mismatch`
  2. release identity → `:binding_incomplete` (the deployment names a
     different `blueprint_id`/`release_number` than the Blueprint it digests)
  3. tool-binding completeness → `:binding_incomplete` (a bound
     `logical_operation` absent from the Blueprint's capability families
     AND effect intents)
  4. mutation/recovery → `:no_authoritative_recovery` (a binding whose
     operation resolves to `mutation` under `recovery: "none"`; a name in
     both sources with disagreeing kinds takes the stricter reading)
  5. attestation staleness → `:binding_attestation_stale` (`age > max` or a
     FUTURE `attested_at` — the host's clock is authoritative; fail-closed)
  6. observed rug-pull → `:binding_descriptor_mismatch` (the host's
     observed descriptor digest vs the attested one)

  Stages 5-6 run only on the host observations that feed them: `now: nil`
  skips EVERY staleness judgment including the future-deny; an empty
  `observed` map skips the rug-pull. That is the host's governance choice —
  the parameters ARE host policy (the base's stale-binding and rug-pull red
  cases are host-observation cases); decode-time integrity is never
  skippable.

  ## Honest limits

  Eligibility expressions are host policy DSLs: member names are
  denylist-scanned (`tenant_id`, `user_id`, … deny at any depth) but
  VALUES carry the authored exemption — a resolved principal UUID passes
  every scan mode (shape-exempt; undecidable-by-scan — necessary, not
  sufficient, same posture as extension bodies). Timestamps are Z-form
  whole-second RFC3339: sub-second attestations are unrepresentable, so
  `max_attestation_age_ms` is effectively second-granular.
  A Deployment Manifest is an inert binding description — it never authorizes execution.
  A Deployment Manifest is an inert binding description — it never authorizes execution.
  """

  alias AgentBlueprintProtocol.{
    Blueprint,
    Bounds,
    Canonicalization,
    Digest,
    Extension,
    Json,
    Portability,
    Registry,
    Signature
  }

  @ceiling_tool_bindings 128
  @ceiling_data_bindings 64
  @ceiling_build_identities 128
  @ceiling_signatures 16
  @ceiling_attestations 16
  @identifier_bytes 512

  @classification ~w(public internal confidential restricted)
  @authority_traits ~w(none local_policy external_authority_required)
  @approval_traits ~w(none human_required separated_human_required)
  @impact_classes ~w(ordinary money authority secret)
  @disclosure_steps ~w(none summary detail full)
  @custody_modes ~w(host_managed external_kms holder_edge)
  @build_kinds ~w(package build adapter extension)
  @lifecycle_states ~w(draft active retired)
  @as_of_modes ~w(required none)

  @numeric_ceilings ~w(
    max_attempts
    max_concurrency
    max_depth
    max_descendants
    max_elapsed_ms
    max_fan_out
    max_tokens
  )

  # The 16 digest-covered members; the evidence trio is excluded by §8.2.
  @covered_members ~w(
    authority_requirement
    blueprint_release
    build_identities
    data_bindings
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
    tool_bindings
  )

  @evidence_members ~w(deployment_digest signatures attestations)

  @segment ~r/\A[a-z0-9][a-z0-9._-]*\z/
  @z_form ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/
  @currency ~r/\A[A-Z]{3}\z/
  @exact_charset ~r/\A[A-Za-z0-9.+-]+\z/

  defstruct [:value]

  @type t :: %__MODULE__{value: Json.value()}
  @type reason :: Registry.reason()

  # ---- observations -------------------------------------------------------------------

  defmodule Observations do
    @moduledoc """
    The host-supplied inputs to `verify_binding/3`'s observation-gated
    stages: the host clock, the host's maximum tolerable attestation age,
    and the currently OBSERVED descriptor digests by logical operation.
    Absent inputs skip exactly their stages — see `Deployment`'s moduledoc.
    Observed facts are host-supplied records that carry no authority.
    Observed facts are host-supplied records that carry no authority.
    """

    defstruct now: nil, max_attestation_age_ms: nil, observed: %{}

    @type t :: %__MODULE__{
            now: DateTime.t() | nil,
            max_attestation_age_ms: pos_integer() | nil,
            observed: %{optional(binary()) => binary()}
          }
  end

  # ---- the table --------------------------------------------------------------------

  @doc """
  The 19-member field registry (base §7, re-derived): data for the generic
  engine. Field order is the engine's precedence anchor for table-order
  stages.
  """
  @spec table() :: [Registry.spec()]
  def table do
    [
      field("authority_requirement", {:object, %{members: identity_profile_members()}}),
      field("blueprint_release", {:object, %{members: release_members()}}),
      field("build_identities", {:array, build_identity_element()},
        min_items: 1,
        max_items: @ceiling_build_identities,
        unique_by: "name"
      ),
      field("data_bindings", {:array, data_binding_element()},
        max_items: @ceiling_data_bindings,
        unique_by: "logical_dataset"
      ),
      field("effect_owner", {:object, %{members: effect_owner_members()}}),
      field("eligibility", {:object, %{members: eligibility_members()}}),
      field("evaluation_binding", {:object, %{members: evaluation_members()}}),
      field("extensions", :custom, check: &Extension.envelope_ok?/1),
      field("host_bounds", {:object, %{members: host_bounds_members()}}),
      field("lifecycle", {:object, %{members: lifecycle_members()}}, check: &check_lifecycle/1),
      field("model_policy", {:object, %{members: model_policy_members()}}),
      field("protocol_revision", :integer, check: &check_positive/1),
      field("required_core_fields", {:array, %{kind: :string}},
        unique_by: :value,
        check: &check_required_core_fields/1
      ),
      field(
        "scope_projection",
        {:object,
         %{members: [field("adapter_identity", :string, check: &check_identity_string/1)]}}
      ),
      field("signer_custody", {:enum, MapSet.new(@custody_modes)}),
      field("tool_bindings", {:array, tool_binding_element()},
        max_items: @ceiling_tool_bindings,
        unique_by: "logical_operation"
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
      field("deployment_digest", :string, check: &check_tagged_digest/1)
    ]
  end

  defp field(name, kind, opts \\ []),
    do: Map.new(Keyword.merge([name: name, required: true, kind: kind], opts))

  defp identity_string(name), do: field(name, :string, check: &check_identity_string/1)

  defp identity_profile_members do
    [
      identity_string("adapter_identity"),
      identity_string("profile_identity")
    ]
  end

  defp release_members do
    [
      field("blueprint_id", :string, check: &check_producer_qualified/1),
      field("release_number", :integer, check: &check_positive/1),
      field("content_digest", :string, check: &check_tagged_digest/1)
    ]
  end

  defp build_identity_element do
    %{
      kind:
        {:object,
         %{
           members: [
             field("kind", {:enum, MapSet.new(@build_kinds)}),
             identity_string("name"),
             field("version", :string, check: &check_exact_version/1),
             field("digest", :string, check: &check_tagged_digest/1)
           ]
         }}
    }
  end

  defp data_binding_element do
    %{
      kind:
        {:object,
         %{
           members: [
             field("logical_dataset", :string, check: &check_identity_string/1),
             field("classification_ceiling", {:enum, MapSet.new(@classification)}),
             field("as_of", {:object, %{members: as_of_members()}}, check: &check_as_of/1)
           ]
         }}
    }
  end

  defp as_of_members do
    [
      field("mode", {:enum, MapSet.new(@as_of_modes)}),
      field("max_age_ms", :custom)
    ]
  end

  defp effect_owner_members do
    [
      identity_string("adapter_identity"),
      field(
        "idempotency",
        {:object,
         %{
           members: [
             field("key_derivation", {:enum, MapSet.new(["host"])}),
             field("recovery", {:enum, MapSet.new(["authoritative", "none"])})
           ]
         }}
      )
    ]
  end

  defp eligibility_members do
    [
      field("owner", :custom, check: &check_expression/1),
      field("beneficiary", :custom, check: &check_expression/1),
      field("runtime_principal", :custom, check: &check_expression/1)
    ]
  end

  defp evaluation_members do
    [
      identity_string("adapter_identity"),
      field(
        "corpus",
        {:object,
         %{
           members: [
             field("name", :string, check: &check_identity_string/1),
             field("digest", :string, check: &check_tagged_digest/1)
           ]
         }}
      )
    ]
  end

  defp host_bounds_members do
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

    protected = [
      field("classification_ceiling", {:enum, MapSet.new(@classification)}),
      field("authority_trait", {:enum, MapSet.new(@authority_traits)}),
      field("approval_trait", {:enum, MapSet.new(@approval_traits)}),
      field("effect_impact_ceiling", {:enum, MapSet.new(@impact_classes)}),
      field("disclosure_ceiling", {:enum, MapSet.new(@disclosure_steps)})
    ]

    # Name order, pinned for the second-language verifier: sorting the spec MAPS would
    # order by Erlang term shape, not member name.
    Enum.sort_by(numeric ++ [cost] ++ protected, & &1[:name])
  end

  defp lifecycle_members do
    [
      field("state", {:enum, MapSet.new(@lifecycle_states)}),
      field("activated_at", :string, required: false, check: &check_z_form/1),
      field("retired_at", :string, required: false, check: &check_z_form/1)
    ]
  end

  defp model_policy_members do
    [
      field("allowed_model_roles", {:array, %{kind: :string}},
        unique_by: :value,
        check: &check_role_strings/1
      ),
      field("max_tokens", :integer, check: &check_positive/1),
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
    ]
  end

  defp tool_binding_element do
    %{
      kind:
        {:object,
         %{
           members: [
             field("logical_operation", :string, check: &check_identity_string/1),
             identity_string("adapter_identity"),
             field("descriptor_digest", :string, check: &check_tagged_digest/1),
             field("schema_digest", :string, check: &check_tagged_digest/1),
             field("attested_at", :string, check: &check_z_form/1)
           ]
         }}
    }
  end

  defp signature_element, do: %{kind: :custom, check: &check_signature_entry/1}

  # ---- decode ----------------------------------------------------------------------

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

  # The API type boundary — the never-raising posture at this clause too: a
  # non-binary input denies :invalid_type instead of raising
  # FunctionClauseError (the corpus floor's json surface fix, applied
  # symmetrically to the artifact decoders).
  def decode(_binary, _bounds), do: {:error, :invalid_type}

  @doc """
  Validate an already-decoded tagged value (stages 2-3; no canonicality —
  there are no bytes, so the canonicality ordering obligation does not apply here).
  For values that came from verified bytes, follow with
  `verify_content_digest/1` — this function does NOT check the declared
  digest. `opts` carries `:authored_extensions` — namespaces
  whose critical bodies negotiation validated against a digest-pinned host
  schema (the validated-extension channel). Those bodies skip the portability value-shape
  heuristics; the channel is tied to THIS artifact's critical region, and
  the default (`[]`) keeps the strict posture everywhere.
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

  # ---- the digest surface -----------------------------------------------------------

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
  def content_digest(%__MODULE__{} = deployment) do
    with {:ok, jcs} <- Canonicalization.encode(digest_input(deployment)) do
      Digest.hash(:deployment_content, jcs)
    end
  end

  @doc """
  Compare the declared `deployment_digest` member against the recomputed
  digest over the exact received (verified) bytes' canonical form:
  `:digest_mismatch` on divergence.
  """
  @spec verify_content_digest(t()) :: :ok | {:error, reason()}
  def verify_content_digest(%__MODULE__{value: {:object, members}} = deployment) do
    case List.keyfind(members, "deployment_digest", 0) do
      {"deployment_digest", {:string, tagged}} ->
        with {:ok, jcs} <- Canonicalization.encode(digest_input(deployment)) do
          Digest.verify_content(:deployment_content, jcs, tagged)
        end

      _other ->
        {:error, :invalid_type}
    end
  end

  # ---- the binding surface ------------------------------------------------------------

  @doc """
  The one bound release, parsed: `%{blueprint_id, release_number,
  content_digest}` with the digest as a `Digest.t()`. Total: a malformed or
  absent release denies `:invalid_type` (or the digest's own reason).
  """
  @spec bound_release(t()) ::
          {:ok,
           %{blueprint_id: binary(), release_number: pos_integer(), content_digest: Digest.t()}}
          | {:error, reason()}
  def bound_release(%__MODULE__{value: {:object, members}} = deployment) do
    with {:ok, _} <- bound_tool_bindings(deployment) do
      release_of(members)
    end
  end

  def bound_release(_not_an_object_root), do: {:error, :invalid_type}

  defp release_of(members) do
    case List.keyfind(members, "blueprint_release", 0) do
      {"blueprint_release", {:object, release}} ->
        with {:string, id} <- member_of(release, "blueprint_id"),
             {:integer, n} when n >= 1 <- member_of(release, "release_number"),
             {:string, tagged} <- member_of(release, "content_digest"),
             {:ok, digest} <- Digest.from_tagged(tagged) do
          {:ok, %{blueprint_id: id, release_number: n, content_digest: digest}}
        else
          {:error, reason} -> {:error, reason}
          _malformed -> {:error, :invalid_type}
        end

      _other ->
        {:error, :invalid_type}
    end
  end

  @doc """
  Digest equality and nothing else (base §7's binding rule): the declared
  release digest against the paired Blueprint's RECOMPUTED content digest —
  never its declared member. Total over the deployment side: malformed
  deployment input answers `false` (a hand-built malformed `%Blueprint{}`
  raises in `Blueprint`'s own digest surface — its contract).
  """
  @spec binds?(t(), Blueprint.t()) :: boolean()
  def binds?(%__MODULE__{} = deployment, %Blueprint{} = blueprint) do
    with {:ok, release} <- bound_release(deployment),
         %Digest{} = expected <- Blueprint.content_digest(blueprint) do
      Digest.equal?(release.content_digest, expected)
    else
      _undecidable -> false
    end
  end

  @doc """
  The bind-time deny set (order pinned; see the moduledoc): stage 0 validates
  the deployment's own shape — a non-object root, DUPLICATE root members
  (first-wins reads must never decide a binding), or a malformed
  `tool_bindings` member DENIES before any cross-artifact judgment. Stages
  5-6 are observation-gated — absent host inputs skip exactly their stages.
  """
  @spec verify_binding(t(), Blueprint.t(), Observations.t()) :: :ok | {:error, reason()}
  def verify_binding(%__MODULE__{} = deployment, %Blueprint{} = blueprint, %Observations{} = obs) do
    with {:ok, bindings} <- bound_tool_bindings(deployment),
         :ok <- stage_release_digest(deployment, blueprint),
         :ok <- stage_release_identity(deployment, blueprint),
         :ok <- stage_completeness(bindings, blueprint),
         :ok <- stage_recovery(deployment, bindings, blueprint),
         :ok <- stage_staleness(bindings, obs) do
      stage_rug_pull(bindings, obs)
    end
  end

  defp stage_release_digest(deployment, blueprint) do
    with {:ok, release} <- bound_release(deployment),
         %Digest{} = expected <- Blueprint.content_digest(blueprint) do
      if Digest.equal?(release.content_digest, expected),
        do: :ok,
        else: {:error, :deployment_digest_mismatch}
    else
      _undecidable -> {:error, :invalid_type}
    end
  end

  defp stage_release_identity(deployment, blueprint) do
    with {:ok, release} <- bound_release(deployment),
         {:string, id} <- member_of(blueprint_members(blueprint), "blueprint_id"),
         {:integer, n} <- member_of(blueprint_members(blueprint), "release_number") do
      if release.blueprint_id == id and release.release_number == n,
        do: :ok,
        else: {:error, :binding_incomplete}
    else
      _undecidable -> {:error, :invalid_type}
    end
  end

  defp stage_completeness(bindings, blueprint) do
    known = MapSet.union(blueprint_families(blueprint), blueprint_effects(blueprint))

    Enum.find_value(bindings, :ok, fn entry ->
      if MapSet.member?(known, operation_of(entry)),
        do: nil,
        else: {:error, :binding_incomplete}
    end)
  end

  defp operation_of(entry), do: member_string(entry, "logical_operation")

  defp stage_recovery(deployment, bindings, blueprint) do
    case recovery_mode(deployment) do
      {:ok, "none"} -> recovery_scan(bindings, blueprint)
      {:ok, "authoritative"} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp recovery_scan(bindings, blueprint) do
    families = blueprint_family_kinds(blueprint)
    effects = blueprint_effect_kinds(blueprint)

    Enum.find_value(bindings, :ok, fn entry ->
      op = operation_of(entry)

      if mutation?(Map.get(families, op), Map.get(effects, op)),
        do: {:error, :no_authoritative_recovery},
        else: nil
    end)
  end

  defp stage_staleness(_bindings, %Observations{now: nil}), do: :ok

  defp stage_staleness(_bindings, %Observations{now: now}) when not is_struct(now, DateTime),
    do: {:error, :invalid_type}

  # A present-but-non-integer max age is a fail-OPEN hole (integer-vs-binary
  # term comparison always false — the bound would silently not apply), so
  # the shape denies.
  defp stage_staleness(_bindings, %Observations{
         now: _now,
         max_attestation_age_ms: age
       })
       when age != nil and not is_integer(age),
       do: {:error, :invalid_type}

  defp stage_staleness(bindings, %Observations{} = obs) do
    Enum.find_value(bindings, :ok, fn entry ->
      staleness_judgment(member_string(entry, "attested_at"), obs)
    end)
  end

  defp staleness_judgment(attested, %Observations{now: now} = obs) do
    case DateTime.from_iso8601(attested) do
      {:ok, at, 0} -> age_judgment(at, now, obs.max_attestation_age_ms)
      _malformed -> {:error, :invalid_type}
    end
  end

  defp age_judgment(at, now, max_age) do
    cond do
      DateTime.compare(at, now) == :gt ->
        {:error, :binding_attestation_stale}

      max_age != nil and DateTime.diff(now, at, :millisecond) > max_age ->
        {:error, :binding_attestation_stale}

      true ->
        nil
    end
  end

  defp stage_rug_pull(_bindings, %Observations{observed: observed}) when observed == %{},
    do: :ok

  defp stage_rug_pull(bindings, %Observations{observed: observed}) do
    attested = attested_descriptors(bindings)

    observed
    # Observed operations the deployment does not bind are the host's
    # wider tool surface, not this binding's concern.
    |> Enum.filter(fn {op, _digest} -> Map.has_key?(attested, op) end)
    |> Enum.find_value(:ok, fn {op, observed_tagged} ->
      rug_pull_judgment(Map.fetch!(attested, op), observed_tagged)
    end)
  end

  defp rug_pull_judgment(_attested, observed_tagged) when not is_binary(observed_tagged),
    do: {:error, :invalid_type}

  defp rug_pull_judgment(attested, observed_tagged) do
    case Digest.from_tagged(observed_tagged) do
      {:ok, observed} ->
        if Digest.equal?(observed, attested),
          do: nil,
          else: {:error, :binding_descriptor_mismatch}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A hand-built malformed %Blueprint{} raises in Blueprint's own digest
  # surface (its module's contract); this clause assumes its public shape.
  defp blueprint_members(%Blueprint{} = blueprint) do
    {:object, members} = Blueprint.to_value(blueprint)
    members
  end

  defp blueprint_families(blueprint) do
    for {:object, capability} <-
          member_array(blueprint_members(blueprint), "capability_requirements"),
        {"operation_family", {:string, family}} <-
          List.wrap(List.keyfind(capability, "operation_family", 0)),
        do: family,
        into: MapSet.new()
  end

  defp blueprint_effects(blueprint) do
    for {:object, effect} <- member_array(blueprint_members(blueprint), "effect_intents"),
        {"logical_operation", {:string, operation}} <-
          List.wrap(List.keyfind(effect, "logical_operation", 0)),
        do: operation,
        into: MapSet.new()
  end

  defp blueprint_family_kinds(blueprint) do
    for {:object, capability} <-
          member_array(blueprint_members(blueprint), "capability_requirements"),
        {"operation_family", {:string, family}} <-
          List.wrap(List.keyfind(capability, "operation_family", 0)),
        {"operation_kind", {:string, kind}} <-
          List.wrap(List.keyfind(capability, "operation_kind", 0)),
        do: {family, kind},
        into: %{}
  end

  defp blueprint_effect_kinds(blueprint) do
    for {:object, effect} <- member_array(blueprint_members(blueprint), "effect_intents"),
        {"logical_operation", {:string, operation}} <-
          List.wrap(List.keyfind(effect, "logical_operation", 0)),
        {"operation_kind", {:string, kind}} <-
          List.wrap(List.keyfind(effect, "operation_kind", 0)),
        do: {operation, kind},
        into: %{}
  end

  # The stricter reading wins: a name resolving through EITHER source to
  # mutation is a mutation for the recovery contract.
  defp mutation?(family_kind, effect_kind),
    do: family_kind == "mutation" or effect_kind == "mutation"

  # The one total reader every binding stage consumes (malformed
  # tool_bindings must DENY, never silently
  # discard as if unbound — a non-array member, a non-object entry, a
  # non-string operand, or an unparsable descriptor digest is a malformed
  # deployment, not an empty binding set).
  # Stage 0: the deployment's own shape is total and fail-closed — a
  # non-object root, a DUPLICATE root member (first-wins reads must never
  # decide a binding), or a malformed tool_bindings member denies before
  # any cross-artifact judgment.
  defp bound_tool_bindings(%__MODULE__{value: {:object, members}}) when is_list(members) do
    names = Enum.map(members, fn {name, _} -> name end)

    if length(names) == length(Enum.uniq(names)) do
      tool_bindings_of(members)
    else
      {:error, :invalid_type}
    end
  end

  defp bound_tool_bindings(_not_an_object_root), do: {:error, :invalid_type}

  defp tool_bindings_of(members) do
    case member_of(members, "tool_bindings") do
      nil -> {:ok, []}
      {:array, entries} when is_list(entries) -> entries_ok(entries)
      _not_an_array -> {:error, :invalid_type}
    end
  end

  defp entries_ok(entries) do
    case Enum.find_value(entries, :ok, &entry_judgment/1) do
      :ok -> {:ok, Enum.filter(entries, &match?({:object, _}, &1))}
      {:error, _reason} = error -> error
    end
  end

  defp entry_judgment({:object, members}) do
    with {:string, _op} <- member_of(members, "logical_operation"),
         {:string, _at} <- member_of(members, "attested_at"),
         {:string, tagged} <- member_of(members, "descriptor_digest"),
         {:ok, _digest} <- Digest.from_tagged(tagged) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _malformed_member -> {:error, :invalid_type}
    end
  end

  defp entry_judgment(_not_an_object), do: {:error, :invalid_type}

  # Pre-validated by stage 0: every entry carries string operands and a
  # parsable descriptor digest.
  defp attested_descriptors(bindings) do
    Enum.reduce(bindings, %{}, fn entry, acc ->
      {:string, op} = member_of(entry, "logical_operation")
      {:string, tagged} = member_of(entry, "descriptor_digest")
      {:ok, digest} = Digest.from_tagged(tagged)
      Map.put(acc, op, digest)
    end)
  end

  defp recovery_mode(deployment) do
    case member_of(deployment_members(deployment), "effect_owner") do
      {:object, owner} -> recovery_of(owner)
      _malformed -> {:error, :invalid_type}
    end
  end

  defp recovery_of(owner) do
    case member_of(owner, "idempotency") do
      {:object, idempotency} -> recovery_value(member_of(idempotency, "recovery"))
      _malformed -> {:error, :invalid_type}
    end
  end

  defp recovery_value({:string, mode}) when mode in ["authoritative", "none"], do: {:ok, mode}
  defp recovery_value(_malformed), do: {:error, :invalid_type}

  defp deployment_members(%__MODULE__{value: {:object, members}}), do: members

  defp member_of({:object, members}, name) when is_list(members),
    do: member_of(members, name)

  defp member_of(members, name) when is_list(members) do
    case List.keyfind(members, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp member_array(members, name) do
    case member_of(members, name) do
      {:array, entries} when is_list(entries) -> entries
      _other -> []
    end
  end

  # Pre-validated by stage 0: the named operand is a string on every entry.
  defp member_string(entry, name) do
    {:string, value} = member_of(entry, name)
    value
  end

  # ---- field checks (carried in the table as data) -----------------------------------

  defp check_positive({:integer, n}) when n >= 1, do: :ok
  defp check_positive(_value), do: {:error, :invalid_constraint}

  defp check_currency({:string, s}) do
    if Regex.match?(@currency, s), do: :ok, else: {:error, :invalid_constraint}
  end

  defp check_producer_qualified({:string, s}) do
    segments = String.split(s, "/")

    if byte_size(s) <= @identifier_bytes and length(segments) == 2 and
         Enum.all?(segments, &(&1 != "" and Regex.match?(@segment, &1))),
       do: :ok,
       else: {:error, :invalid_constraint}
  end

  defp check_identity_string({:string, s}) do
    if s != "" and byte_size(s) <= @identifier_bytes,
      do: :ok,
      else: {:error, :invalid_constraint}
  end

  defp check_z_form({:string, s}) do
    # Digit shape first (cheap), then calendar reality.
    if Regex.match?(@z_form, s) and match?({:ok, _, _}, DateTime.from_iso8601(s)),
      do: :ok,
      else: {:error, :invalid_constraint}
  end

  defp check_tagged_digest({:string, tagged}) do
    case Digest.from_tagged(tagged) do
      {:ok, _digest} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_role_strings({:array, roles}) do
    if Enum.all?(roles, &match?({:string, s} when s != "", &1)),
      do: :ok,
      else: {:error, :invalid_constraint}
  end

  # The attestation kind registry is empty BY DESIGN, identical to
  # Blueprint: no entry can be kind-valid, so a non-empty array denies.
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

  # A signature entry's PURPOSE is this artifact's fact: the envelope
  # parses (the closed set) AND must be "deployment" here — a
  # blueprint-purpose signature riding a Deployment is a wrong-position
  # entry, denied as a table constraint. Blueprint asserts its own symmetric
  # half.
  defp check_signature_entry(entry) do
    case Signature.attributes(entry) do
      {:ok, %Signature.Attributes{purpose: :deployment}} -> :ok
      {:ok, _other_purpose} -> {:error, :invalid_constraint}
      {:error, reason} -> {:error, reason}
    end
  end

  # An eligibility expression: any non-empty JSON object — the host's policy
  # DSL, held verbatim and name-denylist-scanned (see the scan). "No
  # constraint" must be an explicit host act, never a decode default.
  defp check_expression({:object, members}) when members != [], do: :ok
  defp check_expression(_other), do: {:error, :invalid_constraint}

  # The as_of total rule: exactly (required + positive age) or (none + null)
  # — the contradictory spellings are not requirements. A MISSING max_age_ms
  # defers to the member recursion (:missing_required_field), and a bad mode
  # defers to its enum — one reason per defect, no collisions.
  # Non-object as_of shapes deny at the member kind's type stage first.
  defp check_as_of({:object, members}) do
    as_of_judgment(member_of(members, "mode"), member_of(members, "max_age_ms"))
  end

  defp as_of_judgment({:string, "required"}, age), do: required_age(age)
  defp as_of_judgment({:string, "none"}, age), do: none_age(age)
  defp as_of_judgment(_bad_mode, _age), do: :ok

  defp required_age(nil), do: :ok
  defp required_age(:null), do: {:error, :invalid_constraint}
  defp required_age({:integer, n}) when n >= 1, do: :ok
  defp required_age({:integer, _non_positive}), do: {:error, :invalid_constraint}
  defp required_age(_wrong_tag), do: {:error, :invalid_type}

  defp none_age(:null), do: :ok
  defp none_age(nil), do: :ok
  defp none_age({:integer, _carried}), do: {:error, :invalid_constraint}
  defp none_age(_wrong_tag), do: {:error, :invalid_type}

  # The lifecycle temporal rules (the closed state enum itself denies at the
  # member recursion; this check owns the state/timestamp coupling).
  defp check_lifecycle({:object, members}) do
    state = member_of(members, "state")
    activated = member_of(members, "activated_at")
    retired = member_of(members, "retired_at")

    case state do
      {:string, "draft"} ->
        if activated == nil and retired == nil, do: :ok, else: {:error, :lifecycle_state_invalid}

      {:string, "active"} ->
        if activated != nil and retired == nil, do: :ok, else: {:error, :lifecycle_state_invalid}

      {:string, "retired"} ->
        retired_lifecycle(activated, retired)

      _unknown_or_malformed ->
        # The member recursion denies unknown states and malformed tags.
        :ok
    end
  end

  defp retired_lifecycle({:string, activated}, {:string, retired}) do
    # Z-form whole-second strings sort lexicographically = chronologically.
    if activated <= retired, do: :ok, else: {:error, :lifecycle_state_invalid}
  end

  defp retired_lifecycle(_missing_or_malformed, _other),
    do: {:error, :lifecycle_state_invalid}

  # The exact-only version pin: the protocol rejects the RANGE VOCABULARY
  # (base: "version ranges and silent fallback fail"), not semver semantics
  # — prerelease/build suffixes are exact pins. The charset rule is TOTAL:
  # every range operator (~ ^ = < > | , ! and whitespace) sits outside the
  # strict-semver character set [A-Za-z0-9.+-], so one class denies npm/cargo
  # tildes, pip/Composer equals, OR-lists, comparators, and spans alike.
  # A dot-separated RELEASE segment that is exactly x/X/* is a wildcard.
  defp check_exact_version({:string, version}) do
    release =
      version |> String.split("-", parts: 2) |> hd() |> String.split("+", parts: 2) |> hd()

    segments = String.split(release, ".")

    cond do
      version == "" ->
        {:error, :compatibility_identity_inexact}

      not Regex.match?(@exact_charset, version) ->
        {:error, :compatibility_identity_inexact}

      String.downcase(version) in ["*", "latest"] ->
        {:error, :compatibility_identity_inexact}

      Enum.any?(segments, &(&1 in ["x", "X", "*"])) ->
        {:error, :compatibility_identity_inexact}

      true ->
        :ok
    end
  end

  # ---- the portability scan ------------------------------------------------------------

  # The authored channel is tied to THIS artifact (the authored-channel rule, mirrored):
  # every authored namespace must sit in this value's critical region.
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

  # Open regions: extension bodies (names + strict values, except
  # negotiation-validated critical namespaces — their controls are the
  # digest-pinned schema validation and the reserved-semantics denylist, both
  # at negotiation) and eligibility expressions (names strict, values under
  # the authored exemption — a policy DSL naming roles legitimately carries
  # identifier-shaped strings, the same posture as schema documents).
  defp scan_open_regions(members, validated_ns) do
    {_validated_bodies, strict_bodies} =
      Enum.split_with(Extension.bodies(members), fn {ns, _body} ->
        MapSet.member?(validated_ns, ns)
      end)

    scans =
      Enum.map(strict_bodies, fn {_ns, body} -> Portability.scan(body) end) ++
        Enum.map(eligibility_values(members), &Portability.scan_authored/1)

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

  # The registry stage guarantees the eligibility member is a validated
  # object of non-empty expression objects; the scan runs only after it.
  defp eligibility_values(members) do
    {:object, expressions} = member_of(members, "eligibility")

    Enum.map(expressions, fn {_name, {:object, _inner} = expression} -> expression end)
  end

  # Value shapes over every other core string, recursively — every string
  # inside tool_bindings/data_bindings/build_identities (logical operations,
  # dataset names, identity names, AND the adapter identities beside them) is
  # strict-scanned: the raw-key heuristic's separator floor (43+ pure-b64url
  # chars) leaves the dotted/underscore identifier conventions clean, and no
  # member of this artifact is exempt — a raw endpoint hides nowhere.
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

  # Eligibility is an open region — full scan_authored above.
  defp core_member_scan("eligibility", _value), do: :ok

  defp core_member_scan(_name, value), do: Portability.scan_value(value)

  # The one free string inside an evidence entry: evidence members are
  # digest-UNCOVERED — a secret-shaped key there must still red.
  defp scan_evidence_key_ids(members) do
    members
    |> member_array("signatures")
    |> Enum.find_value(:ok, &evidence_key_id_result/1)
    |> case do
      :ok -> :ok
      {:error, _reason} = error -> error
    end
  end

  # Unparseable entries already denied at the table's element check; the
  # scan sees only entries with a parsed key_id.
  defp evidence_key_id_result(entry) do
    {:ok, %Signature.Attributes{key_id: key_id}} = Signature.attributes(entry)

    case Portability.scan_value({:string, key_id}) do
      :ok -> :ok
      {:error, _reason} = error -> error
    end
  end
end
