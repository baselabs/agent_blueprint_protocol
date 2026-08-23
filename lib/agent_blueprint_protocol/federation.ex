defmodule AgentBlueprintProtocol.Federation do
  @moduledoc """
  The federation profile: the 23-member TaskEnvelope, the
  lossy-aware A2A/MCP state codecs, and the carrier placement laws — the
  executable half of the field-by-field mapping published as
  `federation_mapping/0` data.

  The envelope is a closed world: one wire member per logical field of the
  protocol's federation seam, decoded through the shared `Registry` engine
  under this module's field table. Transport clients and wire I/O stay with
  host adapters; the carriers built here are pure JSON shapes — the
  Task-level placement on each transport (`Task.metadata[a2a_uri]` on A2A,
  `_meta[namespace]` on MCP; the `_meta` key grammar forbids a URI key, so
  the two transports key the same JCS object differently).

  Placement verdicts (live-re-derived against the pinned sources; see
  docs/federation-mapping.md): `task_identity`/`recovery_handle` map to the
  task id on both transports (a divergent handle is unmappable —
  `:federation_mapping_conflict`), the observed state maps to
  `status.state`, and everything else rides the extension body. A Task
  always carries a status, so an envelope with no observed state has no
  Task image — message-context payloads are host-adapter territory (rows
  3/7 document the Message-level homes).

  Lossy-state rules: A2A `TASK_STATE_UNSPECIFIED` denies at intake;
  `to_mcp` denies `:rejected` (terminal with no MCP counterpart) and
  `:submitted`/`:auth_required` (no MCP counterpart) with
  `:federation_state_unmappable` — never a silent degrade. Cancellation is
  a request, never a terminal receipt: no codec path synthesizes a terminal
  member from a cancel request or acknowledgment.

  This is a NEW surface, so failures are `%Error{}` records from day one
  ("the only failure shape"; the older decode
  surfaces' bare atoms are the recorded migration).
  Federation receipts are evidence records — verification never authorizes anything.
  Federation receipts are evidence records — verification never authorizes anything.
  """

  alias AgentBlueprintProtocol.{
    Bounds,
    Canonicalization,
    Digest,
    Error,
    ExtensionRegistry,
    Json,
    Portability,
    Registry,
    Signature
  }

  defstruct [:value]

  @type t :: %__MODULE__{value: Json.value()}

  defmodule Context do
    @moduledoc """
    The receiving context `verify_commitment/2` compares a receipt
    against: trusted keys, the issuer/subject/audience pins (each `nil` =
    the receiver does not pin that member), and the previously-verified
    terminal facts for conflict detection.

    Key attribution: `issuer_key_sets` (when non-nil) takes precedence
    over the flat `keys` pool — the receipt's claimed `issuer` member
    selects the pool for the signature attempt, so org-B's key never
    verifies a receipt claiming org-A for receivers expressing the
    stricter model. An empty map trusts no issuer (deny-all, never a
    fallback). The claim is proven signed by the binding step after the
    attempt; a false claim only ever narrows to the wrong or empty pool.

    Freshness: `created_after`/`created_before` are RFC 3339 Z-form
    bounds on the SIGNED `created_at` (inclusive both ends; the receiver
    supplies the window, the package never invents a clock). Checked
    after conflict detection — integrity and consistency outrank
    receiver policy.
    Verification context is caller-supplied data that carries no authority.
    Verification context is caller-supplied data that carries no authority.
    """

    alias AgentBlueprintProtocol.Signature

    defstruct [
      :keys,
      :issuer,
      :subject,
      :audience,
      :issuer_key_sets,
      :created_after,
      :created_before,
      prior_receipts: []
    ]

    @type receipt_fact :: %{
            required(:task_identity) => binary(),
            required(:terminal_state) => binary(),
            required(:terminal_commitment) => Digest.t()
          }

    @type t :: %__MODULE__{
            keys: [Signature.PublicKey.t()],
            issuer: binary() | nil,
            subject: binary() | nil,
            audience: binary() | nil,
            issuer_key_sets: %{optional(binary()) => [Signature.PublicKey.t()]} | nil,
            created_after: binary() | nil,
            created_before: binary() | nil,
            prior_receipts: [receipt_fact()]
          }
  end

  @identifier_bytes 512
  @segment ~r/\A[a-z0-9][a-z0-9._-]*\z/

  # Wire-enum sources are STRING lists (the engine's enum kind matches
  # the tagged {:string, _} values); the logical atom set lives separately.
  @classification ~w(public internal confidential restricted)
  @regulated_markers ~w(pci phi)
  @claim_kinds ~w(correlation binding authority)
  @checkpoint_kinds ~w(input_required auth_required)
  @checkpoint_statuses ~w(submitted working input_required auth_required)
  @terminal_states ~w(completed failed canceled rejected)
  @terminal_atoms ~w(completed failed canceled rejected)a

  @native_members ~w(task_identity recovery_handle checkpoint_status terminal_state)

  @a2a_to_logical %{
    "TASK_STATE_SUBMITTED" => :submitted,
    "TASK_STATE_WORKING" => :working,
    "TASK_STATE_COMPLETED" => :completed,
    "TASK_STATE_FAILED" => :failed,
    "TASK_STATE_CANCELED" => :canceled,
    "TASK_STATE_INPUT_REQUIRED" => :input_required,
    "TASK_STATE_REJECTED" => :rejected,
    "TASK_STATE_AUTH_REQUIRED" => :auth_required
  }

  @logical_to_a2a Map.new(@a2a_to_logical, fn {k, v} -> {v, k} end)

  @mcp_to_logical %{
    "working" => :working,
    "input_required" => :input_required,
    "completed" => :completed,
    "failed" => :failed,
    "cancelled" => :canceled
  }

  @logical_to_mcp %{
    working: "working",
    input_required: "input_required",
    completed: "completed",
    failed: "failed",
    canceled: "cancelled"
  }

  defmodule Mapping.Row do
    @moduledoc """
    One row of the published field-by-field mapping: the logical field
    (bijective with an envelope wire member), the A2A location, the MCP
    Tasks location, and the verdict (`:native` | `:partial` |
    `:extension`) re-derived against the pinned live sources.
    A mapping row is published data that carries no authority.
    A mapping row is published data that carries no authority.
    """

    defstruct [:index, :logical_field, :a2a_location, :mcp_location, :verdict]

    @type verdict :: :native | :partial | :extension

    @type t :: %__MODULE__{
            index: pos_integer(),
            logical_field: binary(),
            a2a_location: binary(),
            mcp_location: binary(),
            verdict: verdict()
          }
  end

  # The 23-row mapping, re-derived 2026-08-22 against the pinned live
  # sources (a2a.proto @ A2A 1.0.0 shasum fc18e7c2…; ext-tasks draft
  # tasks.md 52dd1973… / schema.ts edb18b6e… / spec.types.ts 4070c34b…).
  # Compiled-in data: a content change is a code release, registry
  # precedent. Citations are the LIVE line numbers of the pinned files.
  defp mapping_rows do
    [
      {1, "task_identity", "Task.id (a2a.proto:170)", "Task.taskId (mcp-schema.ts:47)", :native},
      {2, "idempotency_identity",
       "none — Message.message_id (a2a.proto:262) is a message id, not an idempotency key",
       "none", :extension},
      {3, "parent_execution_reference",
       "Message.reference_task_ids (a2a.proto:276), Task.context_id (a2a.proto:173) — a reference, not a parent execution",
       "none", :partial},
      {4, "initiating_subject",
       "none — SecurityScheme/SecurityRequirement (a2a.proto:496-517) are transport-level",
       "none — transport auth", :extension},
      {5, "blueprint_digest", "none", "none", :extension},
      {6, "deployment_digest", "none", "none", :extension},
      {7, "input_commitment",
       "Message.parts[].data (a2a.proto:233), Part.metadata (a2a.proto:236) — a payload home, not a digest commitment",
       "request params", :partial},
      {8, "result_schema",
       "Part.media_type (a2a.proto:241), AgentSkill.output_modes (a2a.proto:450) — media type is not a schema identity",
       "CompletedTask.result {[key: string]: unknown} (mcp-schema.ts:135)", :extension},
      {9, "result_classification_ceiling", "none", "none", :extension},
      {10, "time_policy", "SendMessageConfiguration (a2a.proto:143-161) has no time bound",
       "Task.ttlMs (mcp-schema.ts:82) — a storage TTL, NOT an execution bound", :partial},
      {11, "resource_policy", "none", "none", :extension},
      {12, "recovery_handle", "Task.id + GetTask (a2a.proto:45)",
       "taskId + tasks/get (mcp-tasks.md Task Polling)", :native},
      {13, "issuer", "transport-level only (SecurityScheme)", "transport auth", :extension},
      {14, "subject", "none", "none", :extension},
      {15, "audience", "none", "none", :extension},
      {16, "identity_mapping_evidence", "none", "none", :extension},
      {17, "checkpoint_request",
       "TASK_STATE_INPUT_REQUIRED (a2a.proto:201) + TaskStatus.message — free-form, not typed",
       "status input_required + inputRequests: InputRequest union (mcp-schema.ts:111-119, mcp-spec.types.ts:545)",
       :partial},
      {18, "checkpoint_status", "TaskStatus.state (a2a.proto:213)",
       "Task.status (mcp-schema.ts:31-36)", :native},
      {19, "checkpoint_commitment", "none",
       "tasks/update inputResponses (mcp-schema.ts:232-246) carries responses, no commitment digest",
       :extension},
      {20, "terminal_state", "TASK_STATE_COMPLETED/FAILED/CANCELED/REJECTED (a2a.proto:194-205)",
       "completed/failed/cancelled (mcp-schema.ts:31-36) — lossy both directions", :partial},
      {21, "evidence_receipt",
       "AgentCardSignature (a2a.proto:455-467) signs the AgentCard, not a task result", "none",
       :extension},
      {22, "compatibility_reference",
       "AgentCard.version (a2a.proto:374-376) — a version string, not an exact build identity",
       "none", :extension},
      {23, "authority_proof_references", "transport-level only", "transport auth", :extension}
    ]
  end

  @doc """
  The 23-row field-by-field A2A/MCP Tasks mapping as data (the
  published table in `docs/federation-mapping.md` mirrors these rows).
  """
  @spec mapping() :: [Mapping.Row.t()]
  def mapping do
    Enum.map(mapping_rows(), fn {index, logical_field, a2a, mcp, verdict} ->
      %Mapping.Row{
        index: index,
        logical_field: logical_field,
        a2a_location: a2a,
        mcp_location: mcp,
        verdict: verdict
      }
    end)
  end

  @doc "The envelope's closed world: the 23 wire member names, table order."
  @spec envelope_members() :: [binary()]
  def envelope_members, do: Enum.map(table(), & &1.name)

  # ---- terminal commitment + verify_commitment ------------------------------------

  @doc """
  The Terminal Commitment: the domain-separated digest over exactly the
  seven named components — task identity, terminal state, result digest,
  result classification, compatibility reference, authority-proof
  references, checkpoint-history commitment. Two receipts for one task
  identity diverge in commitment iff they diverge in any component, which
  is why equivocation needs no separate code.
  """
  @spec terminal_commitment(t()) :: {:ok, Digest.t()} | {:error, Error.t()}
  def terminal_commitment(%__MODULE__{value: {:object, _} = value}) do
    members = value |> member_value_map()

    with :ok <- string_member(members, "task_identity"),
         :ok <- string_member(members, "terminal_state"),
         {:ok, receipt_members} <- receipt_of(members),
         {:ok, result_digest} <- receipt_fetch(receipt_members, "result_digest"),
         {:ok, history} <-
           receipt_fetch(receipt_members, "checkpoint_history_commitment") do
      ordered =
        [
          {"task_identity", members["task_identity"]},
          {"terminal_state", members["terminal_state"]},
          {"result_digest", result_digest},
          {"result_classification_ceiling", members["result_classification_ceiling"]},
          {"compatibility_reference", members["compatibility_reference"]},
          {"authority_proof_references", members["authority_proof_references"]},
          {"checkpoint_history_commitment", history}
        ]

      # The components are engine-validated tagged values; encode cannot
      # fail here (an impossible match would raise loudly, not silently).
      {:ok, jcs} = Canonicalization.encode({:object, ordered})
      {:ok, Digest.hash(:federation_envelope, jcs)}
    end
  end

  def terminal_commitment(_),
    do: {:error, %Error{code: :invalid_type, subject: ["federation_envelope"]}}

  @doc """
  Verify a terminal receipt against the receiving context. Facts, never a
  decision — correlation grants nothing, so the success value carries the
  task identity and terminal commitment and nothing else.

  The numbered steps (design note §4): terminal members present → JWS
  verify → the BINDING step (the signed `content_digest` must name THIS
  envelope's covered bytes — an honestly-signed statement naming a
  different digest is evidence over THAT digest, not this envelope) →
  terminal-commitment recompute → issuer/subject/audience comparison →
  conflict against prior receipts for the same task identity.
  """
  @spec verify_commitment(t(), Context.t()) ::
          {:ok, Context.receipt_fact()}
          | {:error, Error.t()}
  def verify_commitment(%__MODULE__{value: {:object, _} = value}, %Context{} = context) do
    members = member_value_map(value)

    with :ok <- string_member(members, "task_identity"),
         :ok <- string_member(members, "terminal_state"),
         {:ok, receipt_members} <- receipt_of(members),
         {:ok, signature} <- receipt_fetch(receipt_members, "signature"),
         {:ok, pool, attributed?} <- resolve_pool(members, context),
         :ok <- signature_check(signature, pool, attributed?),
         :ok <- binding_check(value, signature),
         {:ok, commitment} <- terminal_commitment(%__MODULE__{value: value}),
         :ok <- commitment_check(receipt_members, commitment),
         :ok <- context_compare(members, context),
         :ok <- conflict_check(members, commitment, context),
         :ok <- freshness_check(signature, context) do
      {:string, task_identity} = members["task_identity"]
      {:string, terminal_state} = members["terminal_state"]

      {:ok,
       %{
         task_identity: task_identity,
         terminal_state: terminal_state,
         terminal_commitment: commitment
       }}
    end
  end

  def verify_commitment(%__MODULE__{}, _),
    do: {:error, %Error{code: :invalid_type, subject: ["federation_envelope"]}}

  def verify_commitment(_, _),
    do: {:error, %Error{code: :invalid_type, subject: ["federation_envelope"]}}

  defp member_value_map({:object, members}), do: Map.new(members)

  # Forged-struct rims: the table guarantees these members on the wire
  # path, so absence/type violations here are typed denials, never raises.
  defp string_member(members, name) do
    case members[name] do
      {:string, _} -> :ok
      nil -> {:error, %Error{code: :missing_required_field, subject: [name]}}
      _other -> {:error, %Error{code: :invalid_type, subject: [name]}}
    end
  end

  defp receipt_fetch(receipt_members, name) do
    case List.keyfind(receipt_members, name, 0) do
      {^name, value} -> {:ok, value}
      nil -> {:error, %Error{code: :missing_required_field, subject: ["evidence_receipt", name]}}
    end
  end

  defp receipt_string(receipt_members, name) do
    case List.keyfind(receipt_members, name, 0) do
      {^name, {:string, tagged}} ->
        {:ok, tagged}

      {^name, _other} ->
        {:error, %Error{code: :invalid_type, subject: ["evidence_receipt", name]}}

      nil ->
        {:error, %Error{code: :missing_required_field, subject: ["evidence_receipt", name]}}
    end
  end

  defp receipt_of(members) do
    case members["evidence_receipt"] do
      {:object, receipt_members} -> {:ok, receipt_members}
      nil -> {:error, %Error{code: :missing_required_field, subject: ["evidence_receipt"]}}
      _other -> {:error, %Error{code: :invalid_type, subject: ["evidence_receipt"]}}
    end
  end

  defp signature_check(signature, pool, attributed?) do
    case Signature.verify(signature, pool) do
      {:ok, :verified} ->
        :ok

      # The key-miss class under attribution names the issuer (WHERE
      # attribution failed), so the operator looks at the key sets.
      # Envelope and algorithm failures keep the signature subject —
      # they are not attribution outcomes, whatever the pool size.
      {:error, :signature_key_unsupported} when attributed? ->
        {:error, %Error{code: :signature_key_unsupported, subject: ["issuer"]}}

      {:error, reason} ->
        {:error, %Error{code: reason, subject: ["evidence_receipt", "signature"]}}
    end
  end

  # Pool resolution: returns {:ok, pool, attributed?} (the flag drives
  # the key-miss relabel); the flat pool is used only when
  # issuer_key_sets is nil; nil pools deny typed. The whole map is
  # validated up front (binary keys, list pools — not just the claimed
  # issuer's entry); the malformed-set denial carries a STATIC subject
  # (an error is not an echo channel); a forged absent/non-string issuer
  # selects the literal empty pool — never a keyed lookup on a garbage
  # claim.
  defp resolve_pool(_members, %Context{issuer_key_sets: nil, keys: keys}) when is_list(keys),
    do: {:ok, keys, false}

  defp resolve_pool(_members, %Context{issuer_key_sets: nil, keys: _not_a_list}),
    do: {:error, %Error{code: :invalid_type, subject: ["keys"]}}

  # Precedence is strictest-wins and structural: this clause ignores the
  # flat pool entirely (a cross-attribution that slipped through `keys`
  # must deny when sets are expressed).
  defp resolve_pool(members, %Context{issuer_key_sets: sets}) when is_map(sets) do
    with :ok <- valid_sets?(sets) do
      case members["issuer"] do
        {:string, claimed} -> {:ok, Map.get(sets, claimed, []), true}
        _forged -> {:ok, [], true}
      end
    end
  end

  defp resolve_pool(_members, %Context{issuer_key_sets: _not_a_map}),
    do: {:error, %Error{code: :invalid_type, subject: ["issuer_key_sets"]}}

  defp valid_sets?(sets) do
    if Enum.all?(sets, fn {key, pool} -> is_binary(key) and is_list(pool) end),
      do: :ok,
      else: {:error, %Error{code: :invalid_type, subject: ["issuer_key_sets"]}}
  end

  # Freshness: both bounds receiver-supplied Z-form, INCLUSIVE, over the
  # SIGNED created_at; malformed pins deny typed. Runs after conflict
  # detection so a stale AND equivocating receipt still reports the
  # conflict — integrity and consistency outrank receiver policy.
  @z_form ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/

  defp freshness_check(signature, context) do
    with {:ok, after_dt} <- pin(context.created_after, "created_after"),
         {:ok, before_dt} <- pin(context.created_before, "created_before") do
      {:ok, attrs} = Signature.attributes(signature)

      {:ok, stamped, _offset} = DateTime.from_iso8601(attrs.created_at)

      in_window? =
        (after_dt == nil or DateTime.compare(stamped, after_dt) != :lt) and
          (before_dt == nil or DateTime.compare(stamped, before_dt) != :gt)

      if in_window?,
        do: :ok,
        else:
          {:error,
           %Error{
             code: :invalid_constraint,
             subject: ["evidence_receipt", "signature", "created_at"]
           }}
    end
  end

  # The SAME double gate as the signed member: the Z-form regex rejects
  # offsets and fractions that DateTime.from_iso8601 alone accepts (an
  # offset-bearing pin would silently shift the bound).
  defp pin(nil, _name), do: {:ok, nil}

  defp pin(value, name) when is_binary(value) do
    if Regex.match?(@z_form, value) and match?({:ok, _, _}, DateTime.from_iso8601(value)) do
      {:ok, elem(DateTime.from_iso8601(value), 1)}
    else
      {:error, %Error{code: :invalid_type, subject: [name]}}
    end
  end

  defp pin(_not_binary, name), do: {:error, %Error{code: :invalid_type, subject: [name]}}

  # The F1 binding: the JWS is verified over its own input only; THIS step
  # pins it to the envelope. The covered bytes are the envelope minus the
  # signature entry itself.
  defp binding_check(value, signature) do
    # signature_check already ran Signature.verify to success over the same
    # entry, so attributes cannot fail here — an impossible match raises
    # loudly rather than masking a second opinion.
    {:ok, attrs} = Signature.attributes(signature)

    # The purpose member exists to prevent cross-surface signature lifting
    # (the symmetric cross-surface gap, closed
    # by review): a signature minted for a blueprint or deployment never
    # verifies a federation receipt, whatever digest it names.
    if attrs.purpose != :federation_envelope do
      {:error, %Error{code: :invalid_constraint, subject: ["evidence_receipt", "signature"]}}
    else
      {:ok, expected} = covered_digest(value)

      if Digest.equal?(attrs.content_digest, expected),
        do: :ok,
        else: {:error, %Error{code: :digest_mismatch, subject: ["evidence_receipt", "signature"]}}
    end
  end

  defp covered_digest(value) do
    {:ok, jcs} = Canonicalization.encode(covered_body(value))
    {:ok, Digest.hash(:federation_envelope, jcs)}
  end

  defp covered_body({:object, members}) do
    {:object,
     Enum.map(members, fn
       {"evidence_receipt", {:object, receipt}} ->
         inner = Enum.reject(receipt, fn {n, _} -> n == "signature" end)
         {"evidence_receipt", {:object, inner}}

       other ->
         other
     end)}
  end

  defp commitment_check(receipt_members, recomputed) do
    with {:ok, tagged} <- receipt_string(receipt_members, "terminal_commitment"),
         {:ok, declared} <- Digest.from_tagged(tagged) do
      if Digest.equal?(declared, recomputed),
        do: :ok,
        else:
          {:error,
           %Error{code: :digest_mismatch, subject: ["evidence_receipt", "terminal_commitment"]}}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, %Error{code: reason, subject: ["evidence_receipt", "terminal_commitment"]}}
    end
  end

  # One code for the triple; the subject path names the
  # diverging member. A `nil` pin skips that member entirely.
  defp context_compare(members, context) do
    pins = [
      {"issuer", context.issuer},
      {"subject", context.subject},
      {"audience", context.audience}
    ]

    pins
    |> Enum.find(fn
      {_member, nil} -> false
      {member, pin} -> members[member] != {:string, pin}
    end)
    |> case do
      nil -> :ok
      {member, _pin} -> {:error, %Error{code: :audience_mismatch, subject: [member]}}
    end
  end

  defp conflict_check(members, commitment, context) do
    # Both members passed string_member in verify_commitment's with-chain;
    # an impossible match here raises loudly on a forged intermediate.
    {:string, task_identity} = members["task_identity"]
    {:string, terminal_state} = members["terminal_state"]

    divergent? = fn prior ->
      prior.task_identity == task_identity and
        (prior.terminal_state != terminal_state or
           not Digest.equal?(prior.terminal_commitment, commitment))
    end

    with :ok <- valid_priors?(context.prior_receipts) do
      case Enum.find(context.prior_receipts, divergent?) do
        nil ->
          :ok

        _prior ->
          {:error, %Error{code: :federation_terminal_conflict, subject: ["evidence_receipt"]}}
      end
    end
  end

  # Receiver-supplied state gets the same typed-denial rim as every other
  # Context field (the never-raise posture is uniform).
  defp valid_priors?(priors) when is_list(priors) do
    facts? = fn
      %{task_identity: id, terminal_state: state, terminal_commitment: %Digest{}}
      when is_binary(id) and is_binary(state) ->
        true

      _ ->
        false
    end

    if Enum.all?(priors, facts?),
      do: :ok,
      else: {:error, %Error{code: :invalid_type, subject: ["prior_receipts"]}}
  end

  defp valid_priors?(_not_a_list),
    do: {:error, %Error{code: :invalid_type, subject: ["prior_receipts"]}}

  # ---- the field table (23 members, bijective with the mapping rows) --------

  defp field(name, kind, opts \\ []) do
    Map.new(Keyword.merge([name: name, required: true, kind: kind], opts))
  end

  defp table do
    [
      field("task_identity", :string, check: &check_identifier/1),
      field("idempotency_identity", :string, check: &check_identifier/1),
      field("parent_execution_reference", :string,
        required: false,
        check: &check_identifier/1,
        root_hook: &hook_parent/1
      ),
      field("initiating_subject", :string, required: false, check: &check_identifier/1),
      field("blueprint_digest", :custom, check: &check_tagged_digest/1),
      field("deployment_digest", :custom, check: &check_tagged_digest/1),
      field("input_commitment", :custom, check: &check_tagged_digest/1),
      field("result_schema", :custom, check: &check_tagged_digest/1),
      field("result_classification_ceiling", classification_element()),
      field(
        "time_policy",
        {:object, %{members: [field("elapsed_ms", :integer, check: &check_positive/1)]}}
      ),
      field(
        "resource_policy",
        {:object,
         %{
           members: [
             field("attempts", :integer, check: &check_positive/1),
             field("concurrency", :integer, check: &check_positive/1),
             field("tokens", :integer, check: &check_positive/1),
             field("cost", :integer, check: &check_positive/1)
           ]
         }}
      ),
      field("recovery_handle", :string, check: &check_identifier/1),
      field("issuer", :string, check: &check_identifier/1),
      field("subject", :string, check: &check_identifier/1),
      field("audience", :string, check: &check_identifier/1),
      field("identity_mapping_evidence", identity_evidence_element()),
      field(
        "checkpoint_request",
        {:object,
         %{
           members: [
             field("kind", {:enum, MapSet.new(@checkpoint_kinds)}),
             field("request_digest", :custom, check: &check_tagged_digest/1)
           ]
         }},
        required: false
      ),
      field("checkpoint_status", {:enum, MapSet.new(@checkpoint_statuses)},
        required: false,
        root_hook: &hook_checkpoint/1
      ),
      field("checkpoint_commitment", :custom,
        required: false,
        check: &check_tagged_digest/1,
        root_hook: &hook_checkpoint/1
      ),
      field("terminal_state", {:enum, MapSet.new(@terminal_states)},
        required: false,
        root_hook: &hook_terminal/1
      ),
      field(
        "evidence_receipt",
        {:object,
         %{
           members: [
             field("result_digest", :custom, check: &check_tagged_digest/1),
             field("checkpoint_history_commitment", :custom, check: &check_tagged_digest/1),
             field("terminal_commitment", :custom, check: &check_tagged_digest/1),
             field("signature", :custom, check: &check_signature_shape/1)
           ]
         }},
        required: false,
        root_hook: &hook_terminal/1
      ),
      field(
        "compatibility_reference",
        {:array,
         %{
           kind:
             {:object,
              %{
                members: [
                  field("name", :string, check: &check_identifier/1),
                  field("identity", :string, check: &check_nonempty/1)
                ]
              }}
         }},
        min_items: 1,
        unique_by: "name"
      ),
      field(
        "authority_proof_references",
        {:array, %{kind: :custom, check: &check_tagged_digest/1}}
      )
    ]
  end

  defp classification_element do
    {:object,
     %{
       members: [
         field("level", {:enum, MapSet.new(@classification)}),
         field("markers", {:array, %{kind: {:enum, MapSet.new(@regulated_markers)}}},
           unique_by: :value
         )
       ]
     }}
  end

  defp identity_evidence_element do
    {:object,
     %{
       members: [
         field(
           "claims",
           {:array,
            %{
              kind:
                {:object,
                 %{
                   members: [
                     field("kind", {:enum, MapSet.new(@claim_kinds)}),
                     field("value", :string, check: &check_nonempty/1)
                   ]
                 }}
            }},
           min_items: 1,
           unique_by: "value"
         )
       ]
     }}
  end

  # ---- member checks ---------------------------------------------------------

  defp check_identifier({:string, s}) do
    if byte_size(s) <= @identifier_bytes and Regex.match?(@segment, s),
      do: :ok,
      else: {:error, :invalid_constraint}
  end

  defp check_nonempty({:string, s}) when s != "", do: :ok

  # Total like the neighbouring checks: an empty string (or a non-string
  # value on a hand-built envelope) denies typed, never raises. Found by
  # the second-language verifier's parity battery — the missing clause
  # crashed decode on `{"value": ""}` (probed live 2026-08-23).
  defp check_nonempty(_empty_or_mistyped), do: {:error, :invalid_constraint}

  defp check_positive({:integer, n}) when n >= 1, do: :ok
  defp check_positive(_), do: {:error, :invalid_constraint}

  defp check_tagged_digest({:string, tagged}) do
    case Digest.from_tagged(tagged) do
      {:ok, _digest} -> :ok
      {:error, _reason} -> {:error, :invalid_constraint}
    end
  end

  defp check_tagged_digest(_), do: {:error, :invalid_type}

  # The receipt's JWS entry must at least parse as the §8.3 envelope; its
  # cryptographic facts are verify_commitment's to establish.
  defp check_signature_shape(entry) do
    case Signature.signing_input(entry) do
      {:ok, _input} -> :ok
      {:error, _reason} -> {:error, :invalid_constraint}
    end
  end

  # ---- root hooks (cross-field rules + terminal-supersedes) ---------------------

  defp hook_parent(members) do
    if Map.has_key?(members, "parent_execution_reference") and
         not Map.has_key?(members, "initiating_subject"),
       do: {:error, :invalid_constraint},
       else: :ok
  end

  defp hook_checkpoint(members) do
    status = Map.has_key?(members, "checkpoint_status")
    commitment = Map.has_key?(members, "checkpoint_commitment")

    cond do
      status != commitment -> {:error, :invalid_constraint}
      status and Map.has_key?(members, "terminal_state") -> {:error, :invalid_constraint}
      true -> :ok
    end
  end

  defp hook_terminal(members) do
    terminal = Map.has_key?(members, "terminal_state")
    receipt = Map.has_key?(members, "evidence_receipt")

    if terminal != receipt, do: {:error, :invalid_constraint}, else: :ok
  end

  # ---- decode -------------------------------------------------------------------

  @doc """
  Decode and fully verify envelope `bytes`: canonical verify → registry
  validation → the federation portability pass. Total and never-raising;
  failures are `%Error{}` records.
  """
  @spec decode(binary(), Bounds.t() | map()) :: {:ok, t()} | {:error, Error.t()}
  def decode(binary, bounds \\ Bounds.maximum())

  def decode(binary, bounds) when is_binary(binary) do
    with {:ok, value} <- Canonicalization.verify(binary, bounds),
         :ok <- Registry.validate(table(), value),
         :ok <- scan(value) do
      {:ok, %__MODULE__{value: value}}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, %Error{code: reason, subject: []}}
    end
  end

  def decode(_, _), do: {:error, %Error{code: :invalid_type, subject: ["federation_envelope"]}}

  @doc """
  Validate an already-decoded tagged value (registry walk + portability
  pass; no canonicality — there are no bytes). The codec reconstruction
  path; values from the wire go through `decode/2`.
  """
  @spec from_value(Json.value()) :: {:ok, t()} | {:error, Error.t()}
  def from_value({:object, _} = value) do
    with :ok <- bounded_shape(value),
         :ok <- Registry.validate(table(), value),
         :ok <- scan(value) do
      {:ok, %__MODULE__{value: value}}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, %Error{code: reason, subject: []}}
    end
  end

  def from_value(_), do: {:error, %Error{code: :invalid_type, subject: ["federation_envelope"]}}

  # The codec-reconstruction path skips the decoder (there are no bytes),
  # so the decoder's ceilings and UTF-8 gate are re-imposed HERE — a short-
  # circuiting walk bounded by the ceilings themselves: a hostile carrier
  # body cannot buy unbounded validate/scan work the decode lane would
  # have refused, and non-UTF-8 string bytes (which the JSON decoder
  # rejects, but a hand-built carrier map can carry) deny typed instead of
  # crashing the later digest encodes.
  defp bounded_shape(value) do
    limits = Bounds.maximum()
    zero = %{members: 0, items: 0, nodes: 0, string: 0, depth: 0}

    case shape_walk(value, zero, limits) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  defp shape_walk(value, acc, limits) do
    with :ok <- ceiling(acc, limits) do
      case value do
        {:object, members} when is_list(members) ->
          acc = bump(acc, members: length(members), nodes: 1, depth: 1)
          walk_members(members, acc, limits)

        {:array, items} when is_list(items) ->
          acc = bump(acc, items: length(items), nodes: 1, depth: 1)
          walk_items(items, acc, limits)

        {:string, s} ->
          string_step(s, bump(acc, nodes: 1, string: byte_size(s), depth: 1), limits)

        _leaf ->
          ceiling(bump(acc, nodes: 1), limits)
      end
    end
  end

  defp string_step(s, acc, limits) do
    if String.valid?(s),
      do: ceiling(acc, limits),
      else: {:error, %Error{code: :invalid_encoding, subject: ["federation_envelope"]}}
  end

  defp walk_members([], _acc, _limits), do: :ok

  defp walk_members([{_name, value} | rest], acc, limits) do
    with :ok <- shape_walk(value, acc, limits) do
      walk_members(rest, acc, limits)
    end
  end

  defp walk_items([], _acc, _limits), do: :ok

  defp walk_items([item | rest], acc, limits) do
    with :ok <- shape_walk(item, acc, limits) do
      walk_items(rest, acc, limits)
    end
  end

  defp bump(acc, kw) do
    Enum.reduce(kw, acc, fn {key, add}, map -> Map.update!(map, key, &(&1 + add)) end)
  end

  defp ceiling(acc, limits) do
    checks = [
      {:members, limits.members},
      {:items, limits.items},
      {:nodes, limits.nodes},
      {:string, limits.string},
      {:depth, limits.depth}
    ]

    case Enum.find(checks, fn {key, max} -> Map.fetch!(acc, key) > max end) do
      nil -> :ok
      {key, _max} -> {:error, %Error{code: {:ceiling, key}, subject: ["federation_envelope"]}}
    end
  end

  @doc """
  The canonical bytes of the whole envelope (the raw `Canonicalization`
  result, matching `Blueprint.canonical_bytes/1` — the encode-error shape
  is that layer's to report).
  """
  @spec canonical_bytes(t()) :: {:ok, binary()} | {:error, term()}
  def canonical_bytes(%__MODULE__{value: value}), do: Canonicalization.encode(value)

  @doc "The envelope's members as a map (wire names → tagged values)."
  @spec member_map(t()) :: %{optional(binary()) => Json.value()}
  def member_map(%__MODULE__{value: {:object, members}}), do: Map.new(members)

  # ---- the federation portability pass (mode map) --------------------------------

  @identifier_scanned ~w(task_identity idempotency_identity parent_execution_reference
                         initiating_subject recovery_handle issuer subject audience)

  defp scan({:object, members}) do
    Enum.reduce_while(members, :ok, fn
      {"identity_mapping_evidence", {:object, inner}}, _ ->
        wrap_step(scan_claims(inner))

      {"compatibility_reference", {:array, items}}, _ ->
        wrap_step(scan_compatibility(items))

      {"evidence_receipt", {:object, receipt}}, _ ->
        wrap_step(scan_receipt(receipt))

      {name, value}, _ when name in @identifier_scanned ->
        pass(Portability.scan_identifier(value), [name])

      _member, _ ->
        {:cont, :ok}
    end)
  end

  # The receipt's signature entry carries key ids in two positions (the
  # protected header's kid and the signed key_id — equal by the JWS shape
  # check). They are named-label positions scanned STRICT (exemption off):
  # a PEM block or hex secret riding a key id denies like any other value
  # position. The signature blob itself is deliberately unscanned — it is
  # opaque cryptographic material by nature, and every honest signature is
  # entropy-dense; it never survives verification without the key.
  defp scan_receipt(receipt) do
    # The table guarantees the signature entry whenever the receipt member
    # is present (this clause only fires then); an impossible match raises.
    {"signature", {:object, entry}} = List.keyfind(receipt, "signature", 0)
    scan_key_ids(key_id_positions(entry))
  end

  defp scan_key_ids(positions) do
    Enum.reduce_while(positions, :ok, fn {position, value}, _ ->
      scan_key_id(position, value)
    end)
  end

  defp scan_key_id(position, value) do
    case Portability.scan_value(value) do
      :ok ->
        {:cont, :ok}

      {:error, _reason} ->
        {:halt,
         {:error,
          %Error{
            code: :forbidden_portable_value,
            subject: ["evidence_receipt", "signature", position]
          }}}
    end
  end

  defp key_id_positions(entry) do
    with {"protected", {:object, protected_members}} <- List.keyfind(entry, "protected", 0),
         {"signed_attributes", {:object, attr_members}} <-
           List.keyfind(entry, "signed_attributes", 0),
         {"kid", value} <- List.keyfind(protected_members, "kid", 0),
         {"key_id", key_value} <- List.keyfind(attr_members, "key_id", 0) do
      [{"kid", value}, {"key_id", key_value}]
    else
      _malformed -> []
    end
  end

  defp scan_claims([{"claims", {:array, items}}]) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {claim, index}, _ -> claim_scan(claim, index) end)
  end

  # Correlation grants nothing — an authority-shaped claim is
  # nonportable content, denied with the claim's schema path.
  defp claim_scan({:object, pairs}, index) do
    claim_map = Map.new(pairs)

    if Map.get(claim_map, "kind") == {:string, "authority"} do
      {:halt,
       {:error,
        %Error{
          code: :nonportable_content,
          subject: ["identity_mapping_evidence", "claims", index]
        }}}
    else
      claim_value_scan(Map.get(claim_map, "value"), index)
    end
  end

  defp claim_value_scan(value, index) do
    case Portability.scan_value(value) do
      :ok ->
        {:cont, :ok}

      {:error, _reason} ->
        {:halt,
         {:error,
          %Error{
            code: :forbidden_portable_value,
            subject: ["identity_mapping_evidence", "claims", index]
          }}}
    end
  end

  defp scan_compatibility(items) do
    items
    |> Enum.reduce_while(:ok, fn {:object, pairs}, _ ->
      case Portability.scan_value(Map.get(Map.new(pairs), "identity")) do
        :ok ->
          {:cont, :ok}

        {:error, _reason} ->
          {:halt,
           {:error,
            %Error{
              code: :forbidden_portable_value,
              subject: ["compatibility_reference", "identity"]
            }}}
      end
    end)
  end

  defp wrap_step(:ok), do: {:cont, :ok}
  defp wrap_step({:error, %Error{} = error}), do: {:halt, {:error, error}}

  defp pass(:ok, _subject), do: {:cont, :ok}

  defp pass({:error, _reason}, subject),
    do: {:halt, {:error, %Error{code: :forbidden_portable_value, subject: subject}}}

  # ---- state codecs: lossy-aware by construction ----------------------------------

  @doc """
  An A2A `TaskState` spelling into the logical state. The nine proto
  values map 8-up; `TASK_STATE_UNSPECIFIED` denies
  `:federation_state_unmappable` (never a guess), and an unknown spelling
  denies `:invalid_constraint`.
  """
  @spec from_a2a_state(binary()) :: {:ok, atom()} | {:error, Error.t()}
  def from_a2a_state(spelling) when is_binary(spelling) do
    cond do
      Map.has_key?(@a2a_to_logical, spelling) -> {:ok, @a2a_to_logical[spelling]}
      spelling == "TASK_STATE_UNSPECIFIED" -> unmappable(["status", "state"])
      true -> {:error, %Error{code: :invalid_constraint, subject: ["status", "state"]}}
    end
  end

  def from_a2a_state(_), do: {:error, %Error{code: :invalid_type, subject: ["status", "state"]}}

  @doc "The logical state into its A2A spelling (all eight map; there is no logical UNSPECIFIED)."
  @spec to_a2a_state(atom()) :: {:ok, binary()} | {:error, Error.t()}
  def to_a2a_state(logical) when is_atom(logical) do
    case Map.fetch(@logical_to_a2a, logical) do
      {:ok, spelling} -> {:ok, spelling}
      :error -> {:error, %Error{code: :invalid_type, subject: ["status", "state"]}}
    end
  end

  def to_a2a_state(_), do: {:error, %Error{code: :invalid_type, subject: ["status", "state"]}}

  @doc "An MCP task status into the logical state (all five map upward; `cancelled` folds to `:canceled`)."
  @spec from_mcp_state(binary()) :: {:ok, atom()} | {:error, Error.t()}
  def from_mcp_state(spelling) when is_binary(spelling) do
    case Map.fetch(@mcp_to_logical, spelling) do
      {:ok, logical} -> {:ok, logical}
      :error -> {:error, %Error{code: :invalid_constraint, subject: ["status"]}}
    end
  end

  def from_mcp_state(_), do: {:error, %Error{code: :invalid_type, subject: ["status"]}}

  @doc """
  The logical state into its MCP spelling — the lossy edge: `:rejected`
  (terminal with no MCP counterpart) and `:submitted`/`:auth_required` (no
  counterpart) deny `:federation_state_unmappable` rather than silently
  degrading.
  """
  @spec to_mcp_state(atom()) :: {:ok, binary()} | {:error, Error.t()}
  def to_mcp_state(logical) when is_atom(logical) do
    case Map.fetch(@logical_to_mcp, logical) do
      {:ok, spelling} -> {:ok, spelling}
      :error -> unmappable(["status"])
    end
  end

  def to_mcp_state(_), do: {:error, %Error{code: :invalid_type, subject: ["status"]}}

  defp unmappable(subject),
    do: {:error, %Error{code: :federation_state_unmappable, subject: subject}}

  # ---- carriers: the placement laws, per transport ----------------------------------

  @doc "The A2A-side carrier key: the registry entry's `a2a_uri` (A2A's own URI-keyed metadata convention)."
  @spec a2a_carrier_key() :: binary()
  def a2a_carrier_key, do: registered_entry().a2a_uri

  @doc "The MCP-side carrier key: the registry namespace (the `_meta` key grammar forbids a URI key)."
  @spec mcp_carrier_key() :: binary()
  def mcp_carrier_key, do: registered_entry().namespace

  defp registered_entry do
    {:ok, entry} = ExtensionRegistry.entry("com.example/federation")
    entry
  end

  @doc """
  The Task-level A2A carrier: `id`, `status.state`, and the extension body
  under `metadata[a2a_carrier_key/0]`. Native members never ride the body.
  Requires an observed state (a Task always has one) and
  `recovery_handle == task_identity` (the task id IS the handle on both
  transports — a divergent handle is unmappable).
  """
  @spec to_a2a_carrier(t()) :: {:ok, Json.value()} | {:error, Error.t()}
  def to_a2a_carrier(%__MODULE__{} = envelope) do
    with :ok <- recovery_matches(envelope),
         {:ok, logical} <- observed_state(envelope),
         {:ok, spelling} <- to_a2a_state(logical) do
      members = member_map(envelope)
      body = Enum.reject(members, fn {name, _} -> name in @native_members end)

      {:ok,
       {:object,
        [
          {"id", members["task_identity"]},
          {"status", {:object, [{"state", {:string, spelling}}]}},
          {"metadata", {:object, [{a2a_carrier_key(), {:object, body}}]}}
        ]}}
    end
  end

  def to_a2a_carrier(_),
    do: {:error, %Error{code: :invalid_type, subject: ["federation_envelope"]}}

  @doc """
  Rebuild the envelope from an A2A Task carrier: the native homes supply
  `task_identity`/`recovery_handle`/the observed state, the body supplies
  the rest, and a native member appearing in the body denies
  `:federation_mapping_conflict` (a double placement exists only for
  tampering to exploit).
  """
  @spec from_a2a_carrier(Json.value()) :: {:ok, t()} | {:error, Error.t()}
  def from_a2a_carrier({:object, _} = carrier) do
    with {:ok, id} <- carrier_string(carrier, "id", ["id"]),
         {:ok, state_raw} <- carrier_state(carrier, "state", ["status", "state"]),
         {:ok, logical} <- from_a2a_state(state_raw),
         {:ok, body} <- carrier_body(carrier, "metadata", a2a_carrier_key()),
         :ok <- no_double_placement(body) do
      rebuild(id, logical, body)
    end
  end

  def from_a2a_carrier(_), do: {:error, %Error{code: :invalid_type, subject: ["carrier"]}}

  @doc """
  The Task-level MCP carrier: `taskId`, `status`, and the extension body
  under `_meta[mcp_carrier_key/0]` (the flat `Result & Task` merge the
  CreateTaskResult shape defines). Requires an observed state; the lossy
  states deny before placement.
  """
  @spec to_mcp_carrier(t()) :: {:ok, Json.value()} | {:error, Error.t()}
  def to_mcp_carrier(%__MODULE__{} = envelope) do
    with :ok <- recovery_matches(envelope),
         {:ok, logical} <- observed_state(envelope),
         {:ok, spelling} <- to_mcp_state(logical) do
      members = member_map(envelope)
      body = Enum.reject(members, fn {name, _} -> name in @native_members end)

      {:ok,
       {:object,
        [
          {"taskId", members["task_identity"]},
          {"status", {:string, spelling}},
          {"_meta", {:object, [{mcp_carrier_key(), {:object, body}}]}}
        ]}}
    end
  end

  def to_mcp_carrier(_),
    do: {:error, %Error{code: :invalid_type, subject: ["federation_envelope"]}}

  @doc "Rebuild the envelope from an MCP Task carrier (the upward state mapping; `cancelled` folds to `:canceled`)."
  @spec from_mcp_carrier(Json.value()) :: {:ok, t()} | {:error, Error.t()}
  def from_mcp_carrier({:object, _} = carrier) do
    with {:ok, id} <- carrier_string(carrier, "taskId", ["taskId"]),
         {:ok, state_raw} <- carrier_string(carrier, "status", ["status"]),
         {:ok, logical} <- from_mcp_state(state_raw),
         {:ok, body} <- carrier_body(carrier, "_meta", mcp_carrier_key()),
         :ok <- no_double_placement(body) do
      rebuild(id, logical, body)
    end
  end

  def from_mcp_carrier(_), do: {:error, %Error{code: :invalid_type, subject: ["carrier"]}}

  # ---- carrier plumbing -----------------------------------------------------------

  # Wire spellings of the logical states (the enum values of the two state
  # members) — an explicit map, never String.to_atom, so a forged struct's
  # unknown spelling denies instead of crashing.
  @wire_to_logical %{
    "submitted" => :submitted,
    "working" => :working,
    "input_required" => :input_required,
    "auth_required" => :auth_required,
    "completed" => :completed,
    "failed" => :failed,
    "canceled" => :canceled,
    "rejected" => :rejected
  }

  # The task id IS the recovery handle on both transports; a divergent
  # handle is unmappable, denied rather than silently dropped.
  defp recovery_matches(envelope) do
    members = member_map(envelope)

    case {members["task_identity"], members["recovery_handle"]} do
      {{:string, id}, {:string, id}} ->
        :ok

      {_other, _} ->
        {:error, %Error{code: :federation_mapping_conflict, subject: ["recovery_handle"]}}
    end
  end

  defp observed_state(envelope) do
    members = member_map(envelope)

    cond do
      Map.has_key?(members, "terminal_state") ->
        wire_to_logical(members["terminal_state"], "terminal_state")

      Map.has_key?(members, "checkpoint_status") ->
        wire_to_logical(members["checkpoint_status"], "checkpoint_status")

      true ->
        # A Task always carries a status; an envelope with no observed state
        # is a message-context payload, not a Task image.
        {:error, %Error{code: :invalid_constraint, subject: ["status", "state"]}}
    end
  end

  defp wire_to_logical({:string, s}, member) do
    case Map.fetch(@wire_to_logical, s) do
      {:ok, logical} -> {:ok, logical}
      :error -> {:error, %Error{code: :invalid_constraint, subject: [member]}}
    end
  end

  defp wire_to_logical(_, member), do: {:error, %Error{code: :invalid_type, subject: [member]}}

  defp rebuild(id, logical, body) do
    {state_member, state_value} =
      if logical in @terminal_atoms,
        do: {"terminal_state", {:string, Atom.to_string(logical)}},
        else: {"checkpoint_status", {:string, Atom.to_string(logical)}}

    members =
      [
        {"task_identity", {:string, id}},
        {"recovery_handle", {:string, id}},
        {state_member, state_value}
      ] ++ elem(body, 1)

    from_value({:object, members})
  end

  defp carrier_string({:object, members}, name, subject) do
    case List.keyfind(members, name, 0) do
      {^name, {:string, s}} -> {:ok, s}
      {^name, _} -> {:error, %Error{code: :invalid_type, subject: subject}}
      nil -> {:error, %Error{code: :missing_required_field, subject: subject}}
    end
  end

  defp carrier_state({:object, members}, name, subject) do
    case List.keyfind(members, "status", 0) do
      {"status", {:object, inner}} ->
        carrier_string({:object, inner}, name, subject)

      {"status", _} ->
        {:error, %Error{code: :invalid_type, subject: subject}}

      nil ->
        {:error, %Error{code: :missing_required_field, subject: ["status"]}}
    end
  end

  defp carrier_body({:object, members}, envelope_member, key) do
    case List.keyfind(members, envelope_member, 0) do
      {^envelope_member, {:object, inner}} ->
        case List.keyfind(inner, key, 0) do
          {^key, {:object, _} = body} -> {:ok, body}
          {^key, _} -> {:error, %Error{code: :invalid_type, subject: [envelope_member, key]}}
          nil -> {:error, %Error{code: :missing_required_field, subject: [envelope_member, key]}}
        end

      {^envelope_member, _} ->
        {:error, %Error{code: :invalid_type, subject: [envelope_member]}}

      nil ->
        {:error, %Error{code: :missing_required_field, subject: [envelope_member]}}
    end
  end

  defp no_double_placement({:object, body}) do
    case Enum.find(body, fn {name, _} -> name in @native_members end) do
      nil -> :ok
      {name, _} -> {:error, %Error{code: :federation_mapping_conflict, subject: [name]}}
    end
  end
end
