# Agent Blueprint Protocol

[![CI](https://github.com/baselabs/agent_blueprint_protocol/actions/workflows/ci.yml/badge.svg)](https://github.com/baselabs/agent_blueprint_protocol/actions/workflows/ci.yml)
[![Hex Version](https://img.shields.io/hexpm/v/agent_blueprint_protocol.svg)](https://hex.pm/packages/agent_blueprint_protocol)
[![License](https://img.shields.io/hexpm/l/agent_blueprint_protocol.svg)](https://hex.pm/packages/agent_blueprint_protocol)

Agent developers need a portable format for describing an agent's capabilities and connecting that description to a deployment. The [Blueprint](documentation/glossary.md#blueprint) format records capabilities, ports, and bounds. A [Deployment Manifest](documentation/glossary.md#deployment-manifest) binds one Blueprint release to an environment. A [Federation TaskEnvelope](documentation/glossary.md#federation-taskenvelope) carries a task record between supported transports.

Every successful verification is non-authorizing: it reports protocol facts and never grants permission to act.

## [Artifacts](documentation/glossary.md#artifact)

- **Blueprint Core** describes an agent's identity, input and output ports, capability requirements, bounds, and content digest.
- **Deployment Manifest** binds a Blueprint release to environment-specific descriptors and bounds.
- **Federation TaskEnvelope** records a task's identity, state, and terminal commitments for transport between A2A and MCP.

This excerpt comes from [`examples/echo-blueprint.json`](examples/echo-blueprint.json):

```json
{
  "blueprint_id": "example.demo/echo",
  "capability_requirements": [{"approval_trait":"none","argument_schema":{"type":"object"},"authority_trait":"none","classification_ceiling":"internal","impact_class":"ordinary","operation_family":"example.demo.read_shape","operation_kind":"read","result_schema":{"type":"object"}}],
  "ceilings": {"max_attempts":3,"max_concurrency":2,"max_cost":{"amount":1000,"currency":"USD"},"max_depth":8,"max_descendants":64,"max_elapsed_ms":60000,"max_fan_out":4,"max_tokens":100000},
  "classification_ceiling": "internal",
  "content_digest": "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8",
  "effect_intents": [{"impact_class":"ordinary","logical_operation":"record_summary","operation_kind":"mutation"}],
  "evaluation_assertions": [{"kind":"output_schema","port":"result","schema":{"type":"object"}}],
  "extensions": {"critical":{},"optional":{}},
  "input_ports": [{"classification_ceiling":"internal","name":"request","required":true,"schema":{"type":"object"}}],
  "output_contract": {"classification_ceiling":"internal","port":"result"},
  "output_ports": [{"classification_ceiling":"internal","name":"result","required":true,"schema":{"type":"object"}}],
  "producer": {"created_at":"2026-08-20T00:00:00Z","identity":"example.demo","toolchain":"example.demo.toolchain"},
  "protocol_revision": 1,
  "release_number": 1,
  "required_core_fields": [],
  "triggers": ["manual"]
}
```

Verification decodes bounded JSON, negotiates protocol support, binds related artifacts, reconciles [host](documentation/glossary.md#host) inputs, and returns evidence.

```mermaid
flowchart LR
  A[Decode] --> B[Negotiate] --> C[Bind] --> D[Reconcile] --> E[Evidence]
```

## Which package?

| Language | Package | Install |
| --- | --- | --- |
| Elixir | Hex `agent_blueprint_protocol` | `{:agent_blueprint_protocol, "~> 1.0.0-rc.1"}` |
| TypeScript | npm `@agent-blueprint-protocol/verifier` | `npm install @agent-blueprint-protocol/verifier@rc` |

From a Mix project that depends on the package, read its shipped example:

```elixir
dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
example_path = Path.join(dependency_root, "examples/echo-blueprint.json")
bytes = File.read!(example_path)
{:ok, blueprint} = AgentBlueprintProtocol.decode_blueprint(bytes)
AgentBlueprintProtocol.canonical_bytes(blueprint) == {:ok, bytes} # => true
```

First TypeScript verification, from a checkout containing the example:

```js
import { readFileSync } from "node:fs";
import { decodeBlueprint } from "@agent-blueprint-protocol/verifier";

const result = decodeBlueprint(readFileSync("examples/echo-blueprint.json"));
console.log(result.ok ? "valid" : result.error.code); // valid
```

`npm view @agent-blueprint-protocol/verifier version` shows the package version available from npm.

The conformance corpus contains 604 cases. It is a collection of inputs and expected results for implementations; see the [glossary](documentation/glossary.md#conformance-corpus).

## Documentation

- [HexDocs](https://agent-blueprint-protocol.hexdocs.pm/)
- [Quickstart](documentation/quickstart.md)
- [TypeScript guide](documentation/typescript.md)
- [Conformance guide](documentation/conformance.md)
- [Protocol specification](spec/protocol.md)
- [Stability policy](documentation/stability.md)
- [Livebook walkthroughs](docs/livebooks/abp-walkthrough.livemd): [producing artifacts](docs/livebooks/producing-artifacts.livemd), [host import](docs/livebooks/host-import.livemd), [extensions and federation](docs/livebooks/extensions-and-federation.livemd), and [conformance and attacks](docs/livebooks/conformance-and-attacks.livemd).

## Status

The 1.0 line follows its stability promise: documented APIs remain stable within the major version, and deprecations follow the [stability policy](documentation/stability.md).
Version 1.0.0-rc.1 is an unreleased candidate.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and contribution guidance.
