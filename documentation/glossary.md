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

A program that implements the line-based process exchange in the [execution protocol](https://github.com/baselabs/agent_blueprint_protocol/blob/main/spec/conformance/execution.md).

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

## Next steps

- [Read the protocol](../spec/protocol.md)
- [Explore the examples](examples.md)
