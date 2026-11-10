# ADR: Three-platform support

Status: accepted (2026-11-10).

## Context

Consumers and contributors clone and execute the same bytes on Linux, macOS and Windows.

## Decision

CI exercises byte-exact checkout, compilation, tests, corpus execution, kit build, external harness and packed consumption on all three platforms. Escript calls use the escript launcher. Platform-specific filesystem probes state their exclusions explicitly.

## Consequences

Maintainer publishing, secret scanning and filtered specification extraction remain Linux tooling. The byte-preserving attributes and clone-safety rules remain mandatory.
