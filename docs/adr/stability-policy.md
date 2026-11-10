# ADR: Stability policy

Status: accepted (2026-11-10).

## Context

Two distributions share artifact identities and need an explicit compatibility contract.

## Decision

Both packages use one Semantic Versioning line. The stability policy freezes the pinned Elixir census, package-root TypeScript API, documented CLI modes and formats, errors, wire revisions and registry lifecycle. Deprecations arrive in a minor and removals wait for the next major; namespaces do not retire within a major.

## Consequences

Corpus growth is additive within a semantics version. Security maintenance and runtime/platform support are stated separately from protocol revision.
