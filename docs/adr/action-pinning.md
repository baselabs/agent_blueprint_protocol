# ADR: Pinned CI actions and toolchains

## Context

A moving action tag or toolchain selector can change the code that builds or publishes an unchanged source tree.

## Decision

Every workflow action uses a full commit SHA with its release version in a comment. Workflows install an exact Hex client version and exact Elixir, Erlang/OTP, Node.js, and Go versions. Development pins live in `.tool-versions`; compatibility lanes use explicit versions within the supported matrix. Go-based workflow tools use full source commit pins.

## Consequences

Changes to build and publication tools are explicit source changes. Version comments identify the action releases for review while the commit SHA controls execution.
