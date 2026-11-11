# Federation carrier mapping

This guide is for implementers of A2A and MCP Federation carriers. You will map envelope fields and convert native task states. A carrier is the transport-specific representation of a Federation TaskEnvelope. The normative rules are in [protocol section 11](../spec/protocol.md#11-federation-profile).

The active namespace is `io.github.baselabs/federation`. Producers use the A2A metadata URI and MCP `_meta` key below. The deprecated namespace remains recognized.

| Transport | Active carrier key | Deprecated carrier key |
|---|---|---|
| A2A task metadata | `https://baselabs.github.io/agent_blueprint_protocol/extensions/federation` | `https://example.com/extensions/federation` |
| MCP task `_meta` | `io.github.baselabs/federation` | `com.example/federation` |

## Field placement

| Envelope member | A2A carrier | MCP carrier |
|---|---|---|
| `task_identity` | `Task.id` | `Task.taskId` |
| `idempotency_identity` | Federation extension body | Federation extension body |
| `parent_execution_reference` | Federation extension body | Federation extension body |
| `initiating_subject` | Federation extension body | Federation extension body |
| `blueprint_digest` | Federation extension body | Federation extension body |
| `deployment_digest` | Federation extension body | Federation extension body |
| `input_commitment` | Federation extension body | Federation extension body |
| `result_schema` | Federation extension body | Federation extension body |
| `result_classification_ceiling` | Federation extension body | Federation extension body |
| `time_policy` | Federation extension body | Federation extension body |
| `resource_policy` | Federation extension body | Federation extension body |
| `recovery_handle` | `Task.id` | `Task.taskId` |
| `issuer` | Federation extension body | Federation extension body |
| `subject` | Federation extension body | Federation extension body |
| `audience` | Federation extension body | Federation extension body |
| `identity_mapping_evidence` | Federation extension body | Federation extension body |
| `checkpoint_request` | Federation extension body | Federation extension body |
| `checkpoint_status` | `Task.status.state` | `Task.status` |
| `checkpoint_commitment` | Federation extension body | Federation extension body |
| `terminal_state` | `Task.status.state` | `Task.status` |
| `evidence_receipt` | Federation extension body | Federation extension body |
| `compatibility_reference` | Federation extension body | Federation extension body |
| `authority_proof_references` | Federation extension body | Federation extension body |

## State codecs

The Elixir and TypeScript facades expose conversions from and to A2A and MCP task states. A state that has no defined conversion returns a typed error. Carrier decoding places the task identity, state, and extension body into the logical envelope.

The shipped conformance corpus covers state conversion and carrier decoding. Its commitment fixtures cover terminal commitment verification and receipt conflict detection.

## Next steps

- [Read the Federation guide](../documentation/federation.md)
- [Run the conformance checks](../documentation/verifying-in-ci.md)
- [Read the normative Federation profile](../spec/protocol.md#11-federation-profile)
