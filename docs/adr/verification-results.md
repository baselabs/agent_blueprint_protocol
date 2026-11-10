# ADR: Failure records and evidence

Status: accepted (2026-11-10).

## Context

A denial must be typed and value-free, and a skipped check cannot establish verification.

## Decision

Fallible Elixir operations use the Error record; decoder ceilings use its parameterized family. Public TypeScript operations expose the same code set through Result. Evidence marks verification true only when the check ran for everything it covers. Empty signatures and partial descriptor/freshness observations remain explicitly unverified.

## Consequences

Signature verification returns its verified attributes. Distinct verifying key ids are evidence. Reconcile always names the host-owned surfaces and the unchecked lifecycle and time facts.
