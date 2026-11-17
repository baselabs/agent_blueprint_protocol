# ADR: Unified continuous integration

## Context

Code, documentation, packaging, and workflow changes share executable checks. A path filter or a separate documentation workflow can omit checks that cover a change.

## Decision

`.github/workflows/ci.yml` starts only on pushes to `kci/**`, without path
filters. Landing pushes a candidate to `kci/<sha>` and moves `main` only
after `qualified` succeeds. That final job always runs, needs every other
job, and refuses failed, cancelled, skipped, or missing results. Pull requests,
default-branch pushes, tags, and dispatches start no qualification run.

The `toolchain` job runs the shared `scripts/toolchain.sh` reader once.
Every runtime and compatibility lane comes from its `.tool-versions`
outputs. BEAM selection is strict, and each runtime setup is followed by an
installed-version check using that same script. Dependency fetches require
`--check-locked`; the complete quality gate includes both dependency audits.

All jobs use pinned GitHub-hosted labels, measured timeouts, and pinned
actions. Checkout persists no credentials. This public repository's builds
and tests run only in CI, never on the owner's Mac or the build box.

## Consequences

Every candidate receives the same CI jobs, including documentation and package checks. The passing result belongs to the candidate commit before it reaches `main`.
