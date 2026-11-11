# Federation envelopes

This guide is for implementers that exchange task state through A2A or MCP. You will learn the envelope members, carrier keys, and state codec boundaries.

A Federation TaskEnvelope is a portable record for task identity, commitments, state, and references. A carrier is its transport-specific representation in A2A task metadata or MCP task `_meta`. The profile defines the carrier and state codecs. It does not define a host's authorization or execution behavior.

## The 23 members

The table lists every member in protocol revision 1. Optional members may be absent.

| Member | Meaning |
|---|---|
| `task_identity` | Identifier for the task. |
| `idempotency_identity` | Identifier associated with the task's idempotency context. |
| `parent_execution_reference` | Optional identifier for a related parent execution. |
| `initiating_subject` | Optional identifier for the initiating subject. |
| `blueprint_digest` | Digest reference for the Blueprint. |
| `deployment_digest` | Digest reference for the Deployment Manifest. |
| `input_commitment` | Digest commitment for task input. |
| `result_schema` | Digest identifying the result schema. |
| `result_classification_ceiling` | Classification level and markers for a result. |
| `time_policy` | Protocol-defined task policy data. |
| `resource_policy` | Protocol-defined resource policy data. |
| `recovery_handle` | Identifier used to refer to the task's recovery context. |
| `issuer` | Issuer identifier. |
| `subject` | Subject identifier. |
| `audience` | Audience identifier. |
| `identity_mapping_evidence` | Data describing a correlation between identities. |
| `checkpoint_request` | Optional typed checkpoint request and digest. |
| `checkpoint_status` | Optional checkpoint state. |
| `checkpoint_commitment` | Optional digest associated with checkpoint state. |
| `terminal_state` | Optional terminal state. |
| `evidence_receipt` | Optional result and commitment data for a terminal state. |
| `compatibility_reference` | One or more named compatibility identities. |
| `authority_proof_references` | Digest references carried by the envelope. |

The decoder enforces the closed member set and the artifact rules in [protocol section 11](../spec/protocol.md#11-federation-profile).

## Carriage

The active namespace is `io.github.baselabs/federation`. Producers use these carrier keys:

| Carrier | Key |
|---|---|
| A2A task metadata | `https://baselabs.github.io/agent_blueprint_protocol/extensions/federation` |
| MCP task `_meta` | `io.github.baselabs/federation` |

The deprecated namespace remains recognized for compatibility:

| Carrier | Key |
|---|---|
| A2A task metadata | `https://example.com/extensions/federation` |
| MCP task `_meta` | `com.example/federation` |

The carrier codecs combine the extension body with native task identity and state fields. State codecs convert between protocol states and native task states; they return typed errors for states with no defined conversion. The mapping table is data available through `federation_mapping/0` in both language packages.

## Terminal commitments

The shipped conformance fixtures include a valid terminal commitment and cases that return `federation_terminal_conflict`. These fixtures demonstrate terminal commitment verification and conflict detection. See the [federation commitment cases](../priv/conformance/cases/federation-verify_commitment.json).

## Next steps

- [Inspect the mapping table](../docs/federation-mapping.md)
- [Run the conformance corpus](verifying-in-ci.md)
- [Read the federation profile](../spec/protocol.md#11-federation-profile)
