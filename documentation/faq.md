# Frequently asked questions

This guide is for people evaluating Agent Blueprint Protocol. You will get short answers to common questions about its purpose, packages, and conformance.

## What is this?

Agent Blueprint Protocol (ABP) defines portable JSON artifacts and verification results for describing agent capabilities, inputs, outputs, and bounds.

## Is it stable?

The packages follow Semantic Versioning, and the [stability policy](stability.md) lists the surfaces that stay stable within 1.x. This documentation describes package version `1.0.0-rc.3`.

## How is it different from an A2A Agent Card?

An Agent2Agent (A2A) Agent Card describes an agent's discovery information and skills. A Blueprint describes protocol-defined capabilities and constraints. The federation profile defines how its task envelope can travel through A2A metadata.

## How is it different from an MCP server manifest?

A Model Context Protocol (MCP) server exposes tools and related capabilities through MCP. A Blueprint describes an agent's protocol-defined contract independently of a server. The federation profile defines MCP task metadata carriage.

## How is it different from OASF?

The Open Agentic Schema Framework (OASF) is a schema framework for agent metadata and skills. ABP defines a closed artifact vocabulary, verification rules, and a conformance corpus.

## Does verification grant permissions?

No. A successful result is typed evidence about protocol checks. The consuming host makes its own decisions.

## How do I create a Blueprint?

Build a tagged JSON value, pass it to `AgentBlueprintProtocol.Blueprint.from_value/2`, compute its digest, and encode it. The [compose and sign guide](compose-and-sign.md) shows the complete path.

## Which package should I install?

Elixir projects use [`agent_blueprint_protocol` on Hex](https://hex.pm/packages/agent_blueprint_protocol). TypeScript projects use [`@agent-blueprint-protocol/verifier` on npm](https://www.npmjs.com/package/@agent-blueprint-protocol/verifier).

## How do I check an implementation against the corpus?

Run it through the external harness with the published corpus. The [conformance guide](conformance.md) covers adapters, results, claims, and what a pass does and does not establish.

## Next steps

- [Quickstart](quickstart.md)
- [Architecture](architecture.md)
- [Conformance guide](conformance.md)
