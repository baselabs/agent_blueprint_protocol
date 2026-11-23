# 0027: Dependency currency

Status: Accepted

## Context

Dependency declarations and lockfiles need regular registry checks so available updates do not remain invisible.

## Decision

Dependabot checks Mix, npm, and GitHub Actions weekly. Both package manifests live at the repository root, so the Mix and npm entries use `/`. Registry checks compare direct and transitive locked dependencies with available releases. Dependabot pull requests are update signals, not merge paths. Every update lands through the landing tool, which pushes `kci/<sha>` and runs full CI before `main` moves, as [continuous integration](0019-continuous-integration.md) requires. Exact pins remain exact, including the TypeScript compiler used to test the supported declaration floor.

## Consequences

Dependency updates receive the same CI gates as other changes. Newer versions outside a declared range require an explicit change to that range; a currency check does not silently widen it.
