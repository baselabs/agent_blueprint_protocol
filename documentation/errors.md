# Error reference

This reference is for consumers handling verifier failures. It lists all 74 error codes and the eight decoder ceiling codes.

Elixir returns one `%AgentBlueprintProtocol.Error{code, subject, detail}` struct for every failure. TypeScript returns an error with the same code and subject information. A ceiling error is represented in Elixir as `{:ceiling, key}` and as `ceiling:<key>` in JSON results and TypeScript.

Subjects contain schema-defined member names and array indexes where available. They do not contain input values or unknown member names. Denials carry no free-text detail.

| Code | Check that emits it | What to do |
|---|---|---|
| attestation_malformed | Artifact member validation | Correct or remove the malformed optional member. |
| audience_mismatch | Federation commitment verification | Correct the commitment inputs. |
| base64url_invalid | Base64url decoder | Use only unpadded base64url characters. |
| base64url_padded | Base64url decoder | Remove padding from the encoded value. |
| binding_attestation_stale | Deployment binding check | Review the binding data and supplied observations. |
| binding_descriptor_mismatch | Deployment binding check | Align the descriptor with the declared binding. |
| binding_incomplete | Deployment binding check | Supply the binding inputs required by the operation. |
| bound_source_missing | Bounds intersection | Supply the named bound source. |
| bound_unit_mismatch | Bounds intersection | Use compatible units for the bound values. |
| bound_unknown | Bounds algebra validation | Use a bound name in the supported vocabulary. |
| bound_value_invalid | Bounds validation | Correct the bound's type or allowed value. |
| ceiling:bytes | Bounded JSON decoder | Reduce input below the 5,000,000-byte maximum. |
| ceiling:depth | Bounded JSON decoder | Reduce nesting below the depth maximum of 64. |
| ceiling:items | Bounded JSON decoder | Reduce array items below the per-array maximum of 10,000. |
| ceiling:key | Bounded JSON decoder | Shorten keys below the 1,000-byte maximum. |
| ceiling:members | Bounded JSON decoder | Reduce object members below the per-object maximum of 1,000. |
| ceiling:nodes | Bounded JSON decoder | Reduce the total value below the maximum of 200,000 nodes. |
| ceiling:number_lexeme | Bounded JSON decoder | Shorten the number lexeme below the 64-byte maximum. |
| ceiling:string | Bounded JSON decoder | Shorten strings below the 100,000-byte maximum. |
| compatibility_duplicate_entry | Compatibility check | Remove the duplicate build identity. |
| compatibility_entry_missing | Compatibility check | Add the missing exact build identity. |
| compatibility_identity_inexact | Compatibility check | Replace a range with an exact identity. |
| corpus_applicability_incomplete | Corpus integrity check | Consumers restore the exact released corpus files. Corpus authors complete the corpus applicability data. |
| corpus_case_id_duplicate | Corpus integrity check | Consumers restore the exact released corpus files. Corpus authors assign unique case identifiers. |
| corpus_case_invalid | Corpus case validation | Consumers restore the exact released corpus files. Corpus authors correct the case to match its schema. |
| corpus_count_mismatch | Corpus integrity check | Consumers restore the exact released corpus files. Corpus authors regenerate the corpus index. |
| corpus_empty | Corpus integrity check | Consumers restore the exact released corpus files. Corpus authors add valid cases to the corpus. |
| corpus_file_set_mismatch | Corpus integrity check | Consumers restore the exact released corpus files. Corpus authors align the files and index entries. |
| corpus_hash_mismatch | Corpus integrity check | Consumers restore the exact released corpus files. Corpus authors regenerate the index only for an intentional new corpus. |
| corpus_index_invalid | Corpus index validation | Consumers restore the exact released corpus files. Corpus authors correct or regenerate the index. |
| deployment_digest_mismatch | Blueprint-to-manifest binding check | Make the referenced Blueprint release agree. |
| digest_algorithm_unsupported | Digest parser | Use a digest algorithm supported by this revision. |
| digest_encoding_invalid | Digest parser | Correct the tagged digest encoding. |
| digest_mismatch | Digest verification | Consumers reject the received artifact and obtain the intended release. Producers recompute the digest after intentional content changes and recreate affected signatures. |
| duplicate_member | JSON decoder | Remove duplicate names from the JSON object. |
| extension_criticality_conflict | Extension negotiation | Match the registry's declared criticality. |
| extension_duplicate | Extension validation | Include the namespace only once. |
| extension_namespace_invalid | Extension validation | Correct the namespace format. |
| extension_payload_forbidden | Extension validation | Remove the payload for that namespace. |
| extension_retired | Extension negotiation | Remove the retired critical namespace. |
| extension_schema_digest_mismatch | Extension schema check | Supply the schema matching the registry entry. |
| extension_schema_unavailable | Extension schema check | Supply the required schema document. |
| extension_unknown_critical | Extension negotiation | Configure the host's registration and matching held schema for this critical namespace, or reject the artifact. Make it optional only when the producer's contract permits consumers to ignore it. |
| federation_mapping_conflict | Federation carrier codec | Correct the carrier's field placement. |
| federation_state_unmappable | Federation state codec | Use a state supported by the requested codec. |
| federation_terminal_conflict | Federation commitment verification | Correct the conflicting terminal commitment. |
| forbidden_portable_value | Portability scan | Remove the value identified by the scan. |
| integer_magnitude | Canonical encoder | Use an integer within the supported magnitude. |
| invalid_cardinality | Artifact validation | Correct the number of array items. |
| invalid_constraint | Artifact validation | Correct the value that violates its constraint. |
| invalid_encoding | Artifact validation | Use the required encoding form. |
| invalid_number | JSON decoder | Correct the number syntax. |
| invalid_syntax | JSON decoder | Correct the JSON syntax. |
| invalid_type | Artifact or API validation | Use the required JSON or argument type. |
| lifecycle_state_invalid | Deployment validation | Use a declared lifecycle state. |
| missing_ceiling | Bounds validation | Supply the required operational bound. |
| missing_required_field | Artifact validation | Add the required member. |
| no_authoritative_recovery | Effect binding check | Review the effect owner's recovery value. |
| non_canonical_bytes | Canonical byte check | Encode the artifact in canonical JSON form. |
| nonportable_content | Portability validation | Remove the value identified by the check. |
| number_not_double_expressible | JSON decoder | Use a number representable by the JSON profile. |
| predicate_nodes_exceeded | Predicate validation | Reduce the predicate tree size. |
| predicate_op_unknown | Predicate validation | Use a supported predicate operator. |
| predicate_path_unresolved | Predicate validation | Refer to a declared port path. |
| protected_bound_clamp_denied | Bounds intersection | Review the input bounds and clamp posture. |
| protocol_revision_unsupported | Revision negotiation | Use a revision in the consumer's supported set. |
| required_core_field_not_digest_covered | Required-field negotiation | Remove the evidence-only member from the list. |
| required_core_field_unsupported | Required-field negotiation | Use a core member supported by the consumer. |
| schema_complexity_exceeded | Schema validation | Simplify the schema within the supported limits. |
| schema_dialect_unknown | Schema validation | Use a supported schema dialect. |
| schema_invalid_shape | Schema validation | Correct the schema structure. |
| schema_keyword_not_allowed | Schema validation | Remove the unsupported keyword. |
| schema_keyword_value_invalid | Schema validation | Correct the keyword value. |
| schema_ref_cycle | Schema reference check | Remove the reference cycle. |
| schema_ref_unresolvable | Schema reference check | Supply a resolvable schema reference. |
| signature_algorithm_unsupported | Signature verification | Use the supported Ed25519 profile and supplied key. |
| signature_key_unsupported | Signature verification | Supply a key matching the entry's key identifier. |
| signature_malformed | Signature entry parser | Correct the signature entry structure. |
| signature_not_verified | Signature verification | Check the signature entry and supplied public key. |
| trailing_bytes | JSON decoder | Remove bytes after the JSON value. |
| unknown_bound | Decoder bounds validation | Use a declared decoder limit name. |
| unknown_member | Artifact validation | Remove the member or use a supported revision. |

The table lists every value of `AgentBlueprintProtocol.Error.codes/0` and `Error.ceiling_keys/0`.

## Next steps

- [Handle errors in application code](handling-errors.md)
- [Read the error vocabulary](../spec/protocol.md#12-error-vocabulary)
