# ADR: Public surface privacy

Status: accepted (2026-11-10).

## Context

A public source tree and its distributable artifacts must not disclose private identities or operational topology.

## Decision

The public-surface scan checks tracked paths and history using keyed HMAC fingerprints of forbidden text. Pinned digests reveal no matching plaintext without the separately provisioned key. The package boundary and secret scan independently protect shipped files and repository history.

## Consequences

Fork pull requests receive no repository secret, so the keyed history check skips with an explicit banner there. Maintainer branches and merged source enforce it; a fork pass is never described as having executed that private-key-dependent scan.
