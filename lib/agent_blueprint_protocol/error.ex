defmodule AgentBlueprintProtocol.Error do
  @moduledoc """
  The typed failure record: `code` + `subject` + optional
  `detail`. This is the failure shape of the bounds-algebra surface; the
  decode surfaces still return bare reason atoms and migrate here with the
  composed import (a recorded contract delta).

  `subject` is a schema-derived path built from the protocol's own member
  names and array indices — never from input values — so an error is not an
  echo channel. `detail` is populated only for
  `:protected_bound_clamp_denied`, the one code base §Evolution
  (`:155-156`) requires to carry values; every other code carries a code
  and a subject and nothing else.
  An error is a typed failure fact, not a decision.
  An error is a typed failure fact, not a decision.
  """

  defstruct [:code, :subject, :detail]

  # The IMPLEMENTED error vocabulary (the two-directional gate): every
  # code lib/ emits TODAY, in all three
  # shapes — %Error{code: X} records, the bare {:error, :X} atoms the
  # decode surfaces still return (their %Error{} migration is the
  # recorded delta), and the {:ceiling, key} parameterized family, declared AS
  # a family (@ceiling_keys — the decoder limit names, not protocol
  # vocabulary; pinned to Bounds' field set by the gate). Hand-maintained;
  # NEVER derived from the architecture scan (the tautology guard). The
  # The design's 79-code target vocabulary reconciles here.
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

  @doc "The declared implemented vocabulary (hand-maintained; see `@codes`)."
  @spec codes() :: [code()]
  def codes, do: @codes

  @doc "The declared `{:ceiling, key}` family keys (the decoder limit names)."
  @spec ceiling_keys() :: [atom()]
  def ceiling_keys, do: @ceiling_keys

  @doc "Whether `code` is a declared member of the implemented vocabulary."
  @spec declared?(term()) :: boolean()
  def declared?(code) when is_atom(code) and code != nil and code != true and code != false,
    do: code in @codes

  def declared?({:ceiling, key}) when is_atom(key), do: key in @ceiling_keys
  def declared?(_), do: false

  @type code :: atom() | {:ceiling, atom()}
  @type subject :: [binary() | non_neg_integer()]
  @type t :: %__MODULE__{
          code: code(),
          subject: subject(),
          detail: nil | AgentBlueprintProtocol.BoundsAlgebra.ClampEvidence.t()
        }
end
