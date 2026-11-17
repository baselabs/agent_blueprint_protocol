# ADR: Pinned CI actions and toolchains

## Context

A moving action tag or toolchain selector can change the code that builds or publishes an unchanged source tree.

## Decision

Every workflow action uses a full commit SHA with its release version in a comment.
Checkout persists no credentials. Workflows install an exact Hex client version.
The shared `scripts/toolchain.sh` reader supplies every Elixir, Erlang/OTP,
Node.js, and Go version from `.tool-versions`, including compatibility lanes.
BEAM selection uses `version-type: strict`, and the same script refuses an
installed runtime that differs from the requested version. Go-based workflow
tools use full source commit pins.

## Consequences

Changes to build and publication tools are explicit source changes. Version comments identify the action releases for review while the commit SHA controls execution.
