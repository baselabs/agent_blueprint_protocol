# ADR: Dependency currency

## Context

Dependency declarations and lockfiles need regular registry checks so available updates do not remain invisible.

## Decision

Dependabot checks Mix, npm, and GitHub Actions weekly. Both package manifests live at the repository root, so the Mix and npm entries use `/`. Registry checks compare direct and transitive locked dependencies with available releases. Updates within declared ranges land with the checks covering their consumers. Exact pins remain exact, including the TypeScript compiler used to test the supported declaration floor.

## Consequences

Dependency updates receive the same CI gates as other changes. Newer versions outside a declared range require an explicit change to that range; a currency check does not silently widen it.
