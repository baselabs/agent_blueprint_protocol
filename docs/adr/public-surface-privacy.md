# ADR: Public surface privacy

## Context

A public source tree and its distributable artifacts must not disclose private identities or operational topology.

## Decision

The public-surface scan checks tracked paths and history using keyed HMAC fingerprints of forbidden text. Pinned digests reveal no matching plaintext without the separately provisioned key. The package boundary and secret scan independently protect shipped files and repository history.

Publication runs the same build-free guard in both the pre-push hook and CI. The source checkout supplies the scan and its repository-fingerprint configuration; both stay outside the Hex package. Both run `elixir scripts/check_public_privacy.exs scripts/public_privacy.json`. The command requires `ABP_PUBLIC_PRIVACY_HMAC_KEY` in its environment, and CI supplies it from a repository secret. ExUnit exercises the script with a test key and canary, so builds and tests need no publication key.

## Consequences

Fork pull requests receive no repository secret, so the keyed history check skips with an explicit banner there. Maintainer branches and merged source enforce it; a fork pass is never described as having executed that private-key-dependent scan.
