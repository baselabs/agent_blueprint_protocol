defmodule AgentBlueprintProtocol.Error do
  @moduledoc """
    This struct represents a typed protocol error.

    Use it when matching failures returned by public protocol operations.

    This module does not authorize operations.

    ## Example

    ```elixir
    case AgentBlueprintProtocol.Json.decode("null") do
      {:error, %AgentBlueprintProtocol.Error{code: code}} -> code
      {:ok, value} -> value
    end
    ```
  """
  @moduledoc since: "1.0.0"

  defstruct [:code, :detail, subject: []]

  @codes [
    # encoding
    :base64url_invalid,
    :base64url_padded,
    # json decode
    :invalid_syntax,
    :invalid_encoding,
    :invalid_number,
    :number_not_double_expressible,
    :duplicate_member,
    :trailing_bytes,
    :unknown_bound,
    # canonicalization
    :non_canonical_bytes,
    :integer_magnitude,
    # registry engine (structure)
    :unknown_member,
    :missing_required_field,
    :invalid_type,
    :invalid_constraint,
    :invalid_cardinality,
    # digest
    :digest_algorithm_unsupported,
    :digest_encoding_invalid,
    :digest_mismatch,
    # signature + attestation
    :signature_algorithm_unsupported,
    :signature_key_unsupported,
    :signature_malformed,
    :signature_not_verified,
    :attestation_malformed,
    # schema dialect + instance
    :schema_dialect_unknown,
    :schema_keyword_not_allowed,
    :schema_keyword_value_invalid,
    :schema_complexity_exceeded,
    :schema_ref_unresolvable,
    :schema_ref_cycle,
    :schema_invalid_shape,
    # predicate
    :predicate_op_unknown,
    :predicate_path_unresolved,
    :predicate_nodes_exceeded,
    # extension envelope
    :extension_duplicate,
    :extension_namespace_invalid,
    # negotiation + evolution
    :protocol_revision_unsupported,
    :required_core_field_unsupported,
    :required_core_field_not_digest_covered,
    :extension_unknown_critical,
    :extension_criticality_conflict,
    :extension_retired,
    :extension_schema_unavailable,
    :extension_schema_digest_mismatch,
    :extension_payload_forbidden,
    # bounds algebra
    :bound_unknown,
    :missing_ceiling,
    :bound_source_missing,
    :bound_unit_mismatch,
    :bound_value_invalid,
    :protected_bound_clamp_denied,
    # deployment binding
    :deployment_digest_mismatch,
    :binding_incomplete,
    :no_authoritative_recovery,
    :binding_attestation_stale,
    :binding_descriptor_mismatch,
    :lifecycle_state_invalid,
    # compatibility
    :compatibility_identity_inexact,
    :compatibility_entry_missing,
    :compatibility_duplicate_entry,
    # portability
    :forbidden_portable_value,
    # federation
    :federation_state_unmappable,
    :federation_mapping_conflict,
    :nonportable_content,
    :audience_mismatch,
    :federation_terminal_conflict,
    # conformance corpus (the seven integrity codes + the recorded addition
    # :corpus_case_invalid — case-data structural corruption has no honest
    # home among the seven)
    :corpus_index_invalid,
    :corpus_hash_mismatch,
    :corpus_file_set_mismatch,
    :corpus_case_id_duplicate,
    :corpus_count_mismatch,
    :corpus_applicability_incomplete,
    :corpus_empty,
    :corpus_case_invalid
  ]

  # The ceiling family's keys: exactly the decoder limit names (Bounds'
  # own field set — the gate pins the parity, red-capable on either side).
  @ceiling_keys ~w(bytes depth members items nodes string key number_lexeme)a

  @spec codes() :: [code()]
  @doc """
    Returns the declared error-code vocabulary for this release.

    ## Example

        iex> Enum.member?(AgentBlueprintProtocol.Error.codes(), :invalid_type)
        true
  """
  @doc since: "1.0.0"
  def codes, do: @codes

  @spec ceiling_keys() :: [ceiling_key()]
  @doc """
    Returns the decoder limit names used by ceiling errors.

    ## Example

        iex> Enum.member?(AgentBlueprintProtocol.Error.ceiling_keys(), :bytes)
        true
  """
  @doc since: "1.0.0"
  def ceiling_keys, do: @ceiling_keys

  @spec declared?(term()) :: boolean()
  @doc """
    Reports whether a value is a declared error code or ceiling code.

    ## Example

        iex> AgentBlueprintProtocol.Error.declared?(:invalid_type)
        true
  """
  @doc since: "1.0.0"
  def declared?(code) when is_atom(code) and code != nil and code != true and code != false,
    do: code in @codes

  def declared?({:ceiling, key}) when is_atom(key), do: key in @ceiling_keys
  def declared?(_), do: false

  @typedoc """
    One of the eight decoder limit names accepted by the ceiling error family.
  """
  @type ceiling_key ::
          :bytes | :depth | :members | :items | :nodes | :string | :key | :number_lexeme
  @typedoc """
    A closed error-code union for the 1.x release line; callers may match it exhaustively.
  """
  @type code ::
          :base64url_invalid
          | :base64url_padded
          | :invalid_syntax
          | :invalid_encoding
          | :invalid_number
          | :number_not_double_expressible
          | :duplicate_member
          | :trailing_bytes
          | :unknown_bound
          | :non_canonical_bytes
          | :integer_magnitude
          | :unknown_member
          | :missing_required_field
          | :invalid_type
          | :invalid_constraint
          | :invalid_cardinality
          | :digest_algorithm_unsupported
          | :digest_encoding_invalid
          | :digest_mismatch
          | :signature_algorithm_unsupported
          | :signature_key_unsupported
          | :signature_malformed
          | :signature_not_verified
          | :attestation_malformed
          | :schema_dialect_unknown
          | :schema_keyword_not_allowed
          | :schema_keyword_value_invalid
          | :schema_complexity_exceeded
          | :schema_ref_unresolvable
          | :schema_ref_cycle
          | :schema_invalid_shape
          | :predicate_op_unknown
          | :predicate_path_unresolved
          | :predicate_nodes_exceeded
          | :extension_duplicate
          | :extension_namespace_invalid
          | :protocol_revision_unsupported
          | :required_core_field_unsupported
          | :required_core_field_not_digest_covered
          | :extension_unknown_critical
          | :extension_criticality_conflict
          | :extension_retired
          | :extension_schema_unavailable
          | :extension_schema_digest_mismatch
          | :extension_payload_forbidden
          | :bound_unknown
          | :missing_ceiling
          | :bound_source_missing
          | :bound_unit_mismatch
          | :bound_value_invalid
          | :protected_bound_clamp_denied
          | :deployment_digest_mismatch
          | :binding_incomplete
          | :no_authoritative_recovery
          | :binding_attestation_stale
          | :binding_descriptor_mismatch
          | :lifecycle_state_invalid
          | :compatibility_identity_inexact
          | :compatibility_entry_missing
          | :compatibility_duplicate_entry
          | :forbidden_portable_value
          | :federation_state_unmappable
          | :federation_mapping_conflict
          | :nonportable_content
          | :audience_mismatch
          | :federation_terminal_conflict
          | :corpus_index_invalid
          | :corpus_hash_mismatch
          | :corpus_file_set_mismatch
          | :corpus_case_id_duplicate
          | :corpus_count_mismatch
          | :corpus_applicability_incomplete
          | :corpus_empty
          | :corpus_case_invalid
          | {:ceiling, ceiling_key()}
  @typedoc """
    A member path containing names and array indices.
  """
  @type subject :: [binary() | non_neg_integer()]
  @typedoc """
    The public data type for AgentBlueprintProtocol.Error.
  """
  @type t :: %__MODULE__{
          code: code(),
          subject: subject(),
          detail: nil
        }
end
