# Handle errors

This guide is for Elixir and TypeScript consumers. You will learn the shared error shape, how to match the error code, and how to keep TypeScript handling exhaustive.

Every fallible Elixir operation returns the same `%AgentBlueprintProtocol.Error{}` struct on failure. It has `code`, `subject`, and `detail` fields.

`code` is one of the closed error codes or `{:ceiling, key}` for a decoder limit. `subject` is a path of schema-defined names and array indexes. It never includes input values or unknown member names. `detail` is `nil` on denials.

## Match the error code

In a Mix project that depends on the package, run:

```elixir
alias AgentBlueprintProtocol.Error

case AgentBlueprintProtocol.decode_blueprint(~s({"unknown":true})) do
  {:ok, blueprint} ->
    {:ok, blueprint}

  {:error, %Error{code: {:ceiling, key}, subject: subject}} ->
    {:decoder_limit, key, subject}

  {:error, %Error{code: code, subject: subject}} ->
    {:denied, code, subject}
end
```

Use `subject` to find the relevant part of the artifact. Read [the complete error reference](errors.md) for all codes and their emitting checks.

## Handle a TypeScript `ErrorCode`

The npm package exports a closed `ErrorCode` union for all of 1.x. The following switch lists every code and uses `assertNever` to catch any omission at compile time.

Compile this function in a TypeScript project that installs the npm package.

```ts
import type { ErrorCode } from "@agent-blueprint-protocol/verifier";

function assertNever(code: never): never {
  throw new Error(`Unhandled ErrorCode: ${code}`);
}

export function errorAction(code: ErrorCode): string {
  switch (code) {
    case "attestation_malformed":
    case "audience_mismatch":
    case "base64url_invalid":
    case "base64url_padded":
    case "binding_attestation_stale":
    case "binding_descriptor_mismatch":
    case "binding_incomplete":
    case "bound_source_missing":
    case "bound_unit_mismatch":
    case "bound_unknown":
    case "bound_value_invalid":
    case "ceiling:bytes":
    case "ceiling:depth":
    case "ceiling:items":
    case "ceiling:key":
    case "ceiling:members":
    case "ceiling:nodes":
    case "ceiling:number_lexeme":
    case "ceiling:string":
    case "compatibility_duplicate_entry":
    case "compatibility_entry_missing":
    case "compatibility_identity_inexact":
    case "corpus_applicability_incomplete":
    case "corpus_case_id_duplicate":
    case "corpus_case_invalid":
    case "corpus_count_mismatch":
    case "corpus_empty":
    case "corpus_file_set_mismatch":
    case "corpus_hash_mismatch":
    case "corpus_index_invalid":
    case "deployment_digest_mismatch":
    case "digest_algorithm_unsupported":
    case "digest_encoding_invalid":
    case "digest_mismatch":
    case "duplicate_member":
    case "extension_criticality_conflict":
    case "extension_duplicate":
    case "extension_namespace_invalid":
    case "extension_payload_forbidden":
    case "extension_retired":
    case "extension_schema_digest_mismatch":
    case "extension_schema_unavailable":
    case "extension_unknown_critical":
    case "federation_mapping_conflict":
    case "federation_state_unmappable":
    case "federation_terminal_conflict":
    case "forbidden_portable_value":
    case "integer_magnitude":
    case "invalid_cardinality":
    case "invalid_constraint":
    case "invalid_encoding":
    case "invalid_number":
    case "invalid_syntax":
    case "invalid_type":
    case "lifecycle_state_invalid":
    case "missing_ceiling":
    case "missing_required_field":
    case "no_authoritative_recovery":
    case "non_canonical_bytes":
    case "nonportable_content":
    case "number_not_double_expressible":
    case "predicate_nodes_exceeded":
    case "predicate_op_unknown":
    case "predicate_path_unresolved":
    case "protected_bound_clamp_denied":
    case "protocol_revision_unsupported":
    case "required_core_field_not_digest_covered":
    case "required_core_field_unsupported":
    case "schema_complexity_exceeded":
    case "schema_dialect_unknown":
    case "schema_invalid_shape":
    case "schema_keyword_not_allowed":
    case "schema_keyword_value_invalid":
    case "schema_ref_cycle":
    case "schema_ref_unresolvable":
    case "signature_algorithm_unsupported":
    case "signature_key_unsupported":
    case "signature_malformed":
    case "signature_not_verified":
    case "trailing_bytes":
    case "unknown_bound":
    case "unknown_member":
      return "Review the error reference and correct the reported input.";
    default:
      return assertNever(code);
  }
}
```

## Common responses

| Code | What to do |
|---|---|
| `unknown_member` | Remove or rename the member to match the selected revision. |
| `missing_required_field` | Add the required member shown by the artifact schema. |
| `invalid_type` | Use the JSON type required for the reported member. |
| `non_canonical_bytes` | Encode the JSON using the protocol's canonical form. |
| `digest_mismatch` | Recompute the digest from the canonical artifact content. |
| `protocol_revision_unsupported` | Use a revision supported by the consumer. |
| `extension_unknown_critical` | Use a registered critical namespace or mark the value optional. |
| `extension_criticality_conflict` | Match the registered criticality. |
| `signature_key_unsupported` | Supply the public key identified by the signature entry. |
| `signature_not_verified` | Check the signature entry and the supplied public key. |
| `forbidden_portable_value` | Remove the value identified by the portability check. |
| `protected_bound_clamp_denied` | Review the bound inputs and the chosen clamp posture. |
| `ceiling:<key>` | Reduce the input size or choose a valid decoder limit. |

## Next steps

- [Complete error reference](errors.md)
- [Read evidence results](reading-evidence.md)
- [Read protocol section 12](../spec/protocol.md#12-error-vocabulary)
