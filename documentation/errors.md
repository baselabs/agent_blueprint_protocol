# The error guide — every code, what it means, what the host does

The error vocabulary is a closed typed set: `%Error{code, subject,
detail}`. An implementation MUST NOT emit an undeclared code; every
declared code is reachable. Deny is the fail-closed outcome — never a
repair, never a silent skip.

The full table (code | raised when | subject | host action) ships in
the specification's error-vocabulary section; this guide groups the
codes by the decision the host makes.

## Reject the artifact

Bytes and structure: `invalid_syntax`, `invalid_encoding`,
`invalid_number`, `number_not_double_expressible`, `integer_magnitude`,
`duplicate_member`, `trailing_bytes`, `non_canonical_bytes`,
`base64url_invalid`, `base64url_padded`.

Closed worlds: `unknown_member`, `missing_required_field`,
`invalid_type`, `invalid_constraint`, `invalid_cardinality`,
`lifecycle_state_invalid`.

Digests and tamper: `digest_algorithm_unsupported`,
`digest_encoding_invalid`, `digest_mismatch`,
`deployment_digest_mismatch`, `attestation_malformed`.

Evolution: `protocol_revision_unsupported` (both directions),
`required_core_field_unsupported`,
`required_core_field_not_digest_covered` (an evidence-only member
laundered into a requirement is a tamper blind spot),
`extension_schema_unavailable`,
`extension_schema_digest_mismatch`.

## Reject the import (reconcile halts)

Signature surface: `signature_algorithm_unsupported`,
`signature_key_unsupported`, `signature_malformed`,
`signature_not_verified`. Binding: `binding_incomplete`,
`binding_attestation_stale`, `binding_descriptor_mismatch`,
`no_authoritative_recovery`. Compatibility:
`compatibility_identity_inexact`, `compatibility_entry_missing`,
`compatibility_duplicate_entry`.

## Deny or opt in (policy)

`protected_bound_clamp_denied` — a protected bound narrows; the host
opts into the acknowledge posture or rejects.

## Reject the artifact (extension + schema surface)

Extension registry: `extension_duplicate`,
`extension_namespace_invalid`, `extension_unknown_critical` (also for
reserved namespaces declared critical), `extension_criticality_conflict`,
`extension_retired`, `extension_payload_forbidden`. Schema documents:
`schema_dialect_unknown`, `schema_keyword_not_allowed`,
`schema_keyword_value_invalid`, `schema_complexity_exceeded`,
`schema_ref_unresolvable`, `schema_ref_cycle`, `schema_invalid_shape`.

## Reject the artifact (bounds + predicates + portability)

Bounds families: `bound_unknown`, `bound_source_missing`,
`bound_unit_mismatch`, `bound_value_invalid`, `missing_ceiling`,
`unknown_bound`. Predicates: `predicate_op_unknown`,
`predicate_path_unresolved`, `predicate_nodes_exceeded`. Portability:
`forbidden_portable_value`, `nonportable_content` (an authority-shaped
claim riding portable content).

## Quarantine-class (retained, never executed)

Unknown optional extensions round-trip byte-exactly and are typed as
unscanned: they confer no portability claim (see the portability
guide).

## Federation

`federation_state_unmappable`, `federation_mapping_conflict`,
`federation_terminal_conflict`, `audience_mismatch` — receipts and
crossings deny, never degrade silently.

## Operator-only (never a wire condition)

The `corpus_*` family — `corpus_index_invalid`, `corpus_hash_mismatch`,
`corpus_file_set_mismatch`, `corpus_case_id_duplicate`,
`corpus_count_mismatch`, `corpus_applicability_incomplete`,
`corpus_empty`, `corpus_case_invalid` — loader and index integrity
failures in the conformance tooling. If you see one, fix the corpus;
no host artifact produces them.
