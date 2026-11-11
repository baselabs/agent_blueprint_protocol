# Glossary

These definitions summarize terms used by the public guides. The protocol specification is normative.

## Blueprint

A JSON artifact that identifies an agent and describes its ports, capability requirements, bounds, and extensions. A Blueprint Core is the protocol's defined member set for this artifact.

## Artifact

A protocol-defined JSON value together with its canonical bytes.

## Deployment Manifest

A JSON artifact that binds one Blueprint release to descriptors and bounds for an environment.

## Federation TaskEnvelope

A JSON artifact that records a task's identity, state, and terminal commitments for carriage through a supported task transport.

## Verification

Applying the protocol's decoding and validation rules to artifact bytes. A successful result reports protocol facts; it does not grant permission to act.

## Host

An application that consumes protocol results in its own runtime. The host remains responsible for its local decisions.

## Evidence

A structured result containing checks, bounds information, and surfaces that the verifier did not establish.

## Conformance corpus

A set of JSON files that defines verifier inputs, expected outcomes, and integrity metadata. Implementations use the corpus to compare their results with the published cases.

## Execution adapter

A program that implements the line-based process exchange in the [execution protocol](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/execution.md).

## Results document

A canonical JSON document containing the corpus identity and a result projection for each case.

## Verification-semantics version

The release identity field that marks changes to computed outcomes for previously certified inputs. It is separate from the wire protocol revision and package version.

## Protocol revision

The number that identifies an artifact vocabulary and its wire rules.

## Package version

The Semantic Versioning identity of the published Hex or npm package.
