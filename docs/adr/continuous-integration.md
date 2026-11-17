# ADR: Unified continuous integration

## Context

Code, documentation, packaging, and workflow changes share executable checks. A path filter or a separate documentation workflow can omit checks that cover a change.

## Decision

`.github/workflows/ci.yml` gates every pull request and every push to `main` or a landing branch without path filters. Landing pushes a candidate to `kci/<sha>` and moves `main` only after that commit passes the full workflow. The full suite runs only in CI. Contributor checks cover changed files and their direct dependents.

## Consequences

Every candidate receives the same CI jobs, including documentation and package checks. The passing result belongs to the candidate commit before it reaches `main`.
