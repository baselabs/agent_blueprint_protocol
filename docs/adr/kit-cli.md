# ADR: Installed kit commands and corpus selection

## Context

The installed npm kit carries a certified corpus. The core verifier CLI and Elixir escript also support explicit corpus execution without depending on an installed kit layout.

## Decision

The npm package exposes two bin names, `agent-blueprint-protocol` and `verifier`, both targeting `dist/kit/cli.mjs`. The kit entry point supplies the embedded corpus only when invoked with no arguments, then delegates to the compiled verifier CLI. Explicit arguments pass through unchanged.

The core TypeScript CLI requires an explicit corpus selection for corpus execution, as does the Elixir escript. The npm kit additionally supports `--artifact <file>` to decode a Blueprint, Deployment Manifest, or Federation TaskEnvelope; the escript remains a conformance command. The embedded-corpus default belongs to kit assembly, not to either core corpus runner.

## Consequences

Both npm command names execute the same implementation. A no-argument kit run verifies actual embedded corpus bytes, while a no-argument core corpus run is a usage error. Artifact decoding reports protocol validity and grants no authority.
