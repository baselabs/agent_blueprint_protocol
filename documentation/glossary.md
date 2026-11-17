# Glossary

This guide is for readers of the protocol and its examples. It defines the terms used across the documentation.

These definitions summarize public guides. The [protocol specification](../spec/protocol.md) is normative.

## Blueprint

A JSON artifact that identifies an agent and describes its ports, capability requirements, bounds, and extensions. Blueprint Core is the protocol-defined member set for this artifact.

## Artifact

A protocol-defined JSON value together with its canonical bytes.

## Deployment Manifest

A JSON artifact that records environment-specific bindings and bounds for one Blueprint release.

## Federation TaskEnvelope

A JSON artifact that records task identity, state, commitments, and references for carriage through a supported task transport.

## Verification

Applying the protocol's decoding and validation rules to artifact bytes. A successful result reports protocol facts and does not grant permission to act.

## Host

An application that consumes protocol results in its own runtime and makes its own local decisions.

## Evidence

A structured result containing checks, bounds information, and surfaces the verifier did not establish.

## Evidence commitment

A digest of protocol-defined evidence content that lets a verifier compare the received content with the value named by the commitment.

## Federation carrier

An Agent2Agent (A2A) task-metadata or Model Context Protocol (MCP) `_meta` representation that carries a Federation TaskEnvelope.

## Federation state codec

A conversion between a protocol state and the corresponding native A2A or MCP task state.

## Terminal commitment

A digest commitment associated with terminal Federation evidence. `AgentBlueprintProtocol.Federation.verify_commitment/2` performs federation commitment verification. The shipped fixtures demonstrate valid and conflicting terminal commitments.

## Decoder ceiling

A named maximum for a decoder input property such as byte length, nesting depth, or member count.

## Conformance corpus

A set of JSON files that defines verifier inputs, expected outcomes, and integrity metadata. Implementations use it to compare results with the published cases.

## Execution adapter

A program that implements the line-based process exchange in the [execution protocol](../spec/conformance/execution.md).

## Results document

A canonical JSON document containing the corpus identity and a result projection for each case.

## Verification-semantics version

The release identity field that marks changes to computed outcomes for previously certified inputs. It is separate from the wire protocol revision and package version.

## Census

The conformance corpus digest and extension-registry digest that a release certifies. See [protocol section 7](../spec/protocol.md#verification-semantics-and-census-normative).

## Protocol revision

The number that identifies an artifact vocabulary and its wire rules.

## Package version

The Semantic Versioning identity of the published Hex or npm package.

## Terms in JSON

These excerpts connect the terms to the installed examples. `protocol_revision` selects the Blueprint vocabulary, `release_number` identifies its release, and `content_digest` commits to its digest-covered content. The Manifest's `blueprint_release` names that exact Blueprint release. The separate Federation example records a completed task and digest commitments; its Blueprint and Deployment digests refer to that example's own artifacts.

These are reading excerpts, not complete artifacts or canonical wire bytes. A terminal state or a matching digest grants no host authority. See the [gallery](examples.md) for full artifacts and [federation guide](federation.md) for commitment verification.

```json
{
  "echo-blueprint.json": {
    "blueprint_id": "example.demo/echo",
    "protocol_revision": 1,
    "release_number": 1,
    "content_digest": "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8"
  },
  "echo-deployment.json": {
    "blueprint_release": {
      "blueprint_id": "example.demo/echo",
      "content_digest": "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8",
      "release_number": 1
    }
  },
  "federation-envelope.json": {
    "task_identity": "task-7f3a2c",
    "terminal_state": "completed",
    "input_commitment": "sha-256:8Y14oMoIRWfn2QpbNC53tl0Tj1Cwly6fE-lyVdNvUFw",
    "blueprint_digest": "sha-256:UqU_xO8mUo_SEKFyllPQx5viwqjUU0jymkOUDjoSJVY",
    "deployment_digest": "sha-256:TYZzBKU6fPfMSOS8baiol9713E1x8oPzO-Mkuc1YLhE"
  }
}
```

Run this in a project with the [Hex dependency installed](quickstart.md). It decodes the complete installed artifacts, then checks every member shown above against those bytes.

```elixir
json = ~S"""
{
  "echo-blueprint.json": {
    "blueprint_id": "example.demo/echo",
    "protocol_revision": 1,
    "release_number": 1,
    "content_digest": "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8"
  },
  "echo-deployment.json": {
    "blueprint_release": {
      "blueprint_id": "example.demo/echo",
      "content_digest": "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8",
      "release_number": 1
    }
  },
  "federation-envelope.json": {
    "task_identity": "task-7f3a2c",
    "terminal_state": "completed",
    "input_commitment": "sha-256:8Y14oMoIRWfn2QpbNC53tl0Tj1Cwly6fE-lyVdNvUFw",
    "blueprint_digest": "sha-256:UqU_xO8mUo_SEKFyllPQx5viwqjUU0jymkOUDjoSJVY",
    "deployment_digest": "sha-256:TYZzBKU6fPfMSOS8baiol9713E1x8oPzO-Mkuc1YLhE"
  }
}
"""

decoders = %{
  "echo-blueprint.json" => &AgentBlueprintProtocol.decode_blueprint/1,
  "echo-deployment.json" => &AgentBlueprintProtocol.decode_deployment/1,
  "federation-envelope.json" => &AgentBlueprintProtocol.decode_federation_envelope/1
}

for {name, excerpt} <- :json.decode(json) do
  directory = Application.app_dir(:agent_blueprint_protocol, "priv/examples")
  bytes = File.read!(Path.join(directory, name))
  {:ok, _artifact} = Map.fetch!(decoders, name).(bytes)
  true = Map.take(:json.decode(bytes), Map.keys(excerpt)) == excerpt
end
```

## Next steps

- [Read the protocol](../spec/protocol.md)
- [Explore the examples](examples.md)
