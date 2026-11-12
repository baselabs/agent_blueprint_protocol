# Federation envelopes

This guide is for implementers that exchange task state through Agent2Agent (A2A) or Model Context Protocol (MCP). You will learn the envelope members, carrier keys, and state codec boundaries.

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

The carrier codecs combine the extension body with native task identity and state fields. State codecs convert between protocol states and native task states; they return typed errors for states with no defined conversion. The mapping table is data available through `AgentBlueprintProtocol.federation_mapping/0` in Elixir and `federationMapping()` in TypeScript.

## Concrete carrier shapes

These reading excerpts show the native fields and active extension key. The extension body is abbreviated to one real member; use the codec to obtain a complete carrier. Formatted excerpts are not canonical artifact bytes.

```json
{
  "id": "task-7f3a2c",
  "status": {"state": "TASK_STATE_COMPLETED"},
  "metadata": {
    "https://baselabs.github.io/agent_blueprint_protocol/extensions/federation": {
      "blueprint_digest": "sha-256:UqU_xO8mUo_SEKFyllPQx5viwqjUU0jymkOUDjoSJVY"
    }
  }
}
```

```json
{
  "taskId": "task-7f3a2c",
  "status": "completed",
  "_meta": {
    "io.github.baselabs/federation": {
      "blueprint_digest": "sha-256:UqU_xO8mUo_SEKFyllPQx5viwqjUU0jymkOUDjoSJVY"
    }
  }
}
```

In `iex -S mix` with the package installed, run:

```elixir
alias AgentBlueprintProtocol.Federation
dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
{:ok, envelope} = Federation.decode(File.read!(Path.join(dependency_root, "examples/federation-envelope.json")))
{:ok, a2a} = Federation.to_a2a_carrier(envelope)
{:ok, mcp} = Federation.to_mcp_carrier(envelope)
{:ok, _a2a_round_trip} = Federation.from_a2a_carrier(a2a)
{:ok, _mcp_round_trip} = Federation.from_mcp_carrier(mcp)
{:ok, :canceled} = Federation.from_mcp_state("cancelled")
{:ok, "TASK_STATE_CANCELED"} = Federation.to_a2a_state(:canceled)
{:error, %AgentBlueprintProtocol.Error{code: :federation_state_unmappable}} =
  Federation.from_a2a_state("TASK_STATE_UNSPECIFIED")
```

The logical and A2A spelling is `canceled`; MCP uses `cancelled`. Some native states have no lossless conversion and deny. The [extensions and federation notebook](../docs/livebooks/extensions-and-federation.livemd) prints carrier excerpts, round trips, and a valid commitment fixture.

| Operation | Elixir | npm package root |
|---|---|---|
| Envelope decode / canonical bytes | `Federation.decode/2`, `canonical_bytes/1` | `decodeFederationEnvelope`, `canonicalBytes` |
| Mapping rows | `federation_mapping/0` | `federationMapping()` returning a `Result` |
| State and carrier codecs | `from_a2a_state/1`, `to_a2a_state/1`, MCP equivalents; `to_a2a_carrier/1`, `from_a2a_carrier/1`, MCP equivalents | Not exported in 1.0.1 |
| Commitment verification and receiver context | `Federation.verify_commitment/2`, `Federation.Context` | Not exported in 1.0.1 |

Do not deep-import npm implementation modules. Exposing more functions requires a code release; the [root reference](typescript.md#package-root-reference) is the supported surface.

## Terminal commitments

The public `AgentBlueprintProtocol.Federation.verify_commitment/2` function performs federation commitment verification. The shipped fixtures demonstrate a valid terminal commitment and cases that return `federation_terminal_conflict`. See the [federation commitment cases](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.1/priv/conformance/cases/federation-verify_commitment.json).

### Receiver context and returned facts

`Federation.Context` supplies receiver facts, not host execution instructions:

| Field | Contract |
|---|---|
| `keys` | Flat list of public keys when no issuer-key map is supplied. |
| `issuer_key_sets` | Optional map from issuer string to public-key list. When present it takes precedence over `keys`; an absent issuer has no keys. |
| `issuer`, `subject`, `audience` | Optional exact string comparisons. `nil` skips that comparison; mismatch returns `audience_mismatch` with the member path. |
| `created_after`, `created_before` | Optional inclusive Z-form timestamp bounds on the signed creation time. Malformed or out-of-window values deny. |
| `prior_receipts` | Previously verified facts, each with `task_identity`, `terminal_state`, and a `Digest` in `terminal_commitment`; conflicting terminal facts deny. Defaults to `[]`. |

The notebook loads `commitment-valid` from the installed `priv/conformance/cases/federation-verify_commitment.json`, decodes its envelope, converts the fixture's public keys, and calls `verify_commitment/2`. Success is `{:ok, %{task_identity: ..., terminal_state: ..., terminal_commitment: %Digest{}}}`. This fact can be retained for subsequent consistency comparisons. It does not authorize execution. The context's public keys are verification inputs; the fixture demonstrates verification only.

## Next steps

- [Inspect the mapping table](../docs/federation-mapping.md)
- [Run the conformance corpus](verifying-in-ci.md)
- [Read the federation profile](../spec/protocol.md#11-federation-profile)
