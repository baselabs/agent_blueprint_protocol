# Frequently asked questions

This guide is for people evaluating Agent Blueprint Protocol. You will get short answers to common questions about its purpose, packages, and conformance.

## What is this?

Agent Blueprint Protocol (ABP) defines portable JSON artifacts and verification results for describing agent capabilities, inputs, outputs, and bounds.

## Is it stable?

The current package version is `1.0.0-rc.2`. Treat it as a release candidate, not a final 1.0 release.

## How is it different from an A2A Agent Card?

An A2A Agent Card describes an agent's discovery information and skills. A Blueprint describes protocol-defined capabilities and constraints. The federation profile defines how its task envelope can travel through A2A metadata.

## How is it different from an MCP server manifest?

An MCP server exposes tools and related capabilities through MCP. A Blueprint describes an agent's protocol-defined contract independently of a server. The federation profile defines MCP task metadata carriage.

## How is it different from OASF?

OASF is a schema framework for agent metadata and skills. ABP defines a closed artifact vocabulary, verification rules, and a conformance corpus.

## Does verification grant permissions?

No. A successful result is typed evidence about protocol checks. The consuming host makes its own decisions.

## How do I create a Blueprint?

Use the Elixir `Blueprint.from_value/2` API to construct a tagged JSON value, compute its digest, and encode it. The [compose and sign guide](compose-and-sign.md) shows the complete path.

## Which package should I install?

Elixir projects use [`agent_blueprint_protocol` on Hex](https://hex.pm/packages/agent_blueprint_protocol). TypeScript projects use [`@agent-blueprint-protocol/verifier` on npm](https://www.npmjs.com/package/@agent-blueprint-protocol/verifier).

## How do I prove my implementation conforms?

Run the published conformance corpus and compare the results document with the expected projections. The [CI guide](verifying-in-ci.md) covers both packages and the third-party harness.

## Next steps

- [Quickstart](quickstart.md)
- [Architecture](architecture.md)
- [Conformance guide](conformance.md)
