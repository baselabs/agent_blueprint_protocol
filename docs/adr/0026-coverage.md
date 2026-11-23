# 0026: Complete measured coverage

Status: Accepted

## Context

The library's verification paths need executable coverage, while the escript entry module delegates to the tested CLI implementation.

## Decision

`mix.exs` requires 100% measured test coverage. The coverage configuration excludes the AgentBlueprintProtocol.Conformance.Cli.Main escript entry module and its generated modules. The exclusion applies to the entry shim, not the conformance CLI implementation or the verification library.

## Consequences

The CI quality gate rejects coverage below 100% for measured modules. CLI process and package checks exercise the executable boundary independently of the coverage exclusion.
