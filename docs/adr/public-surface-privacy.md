# ADR: Public surface privacy

## Context

A public source tree and its distributable artifacts must not disclose private identities or operational topology.

## Decision

The public-surface scan checks tracked paths and history using keyed HMAC fingerprints of forbidden text. History is everything the repository can publish: its branches, tags and remote-tracking refs. Refs that local tools keep elsewhere, such as editor checkpoints, are never pushed and are not scanned. Pinned digests reveal no matching plaintext without the separately provisioned key. The package boundary and secret scan independently protect shipped files and repository history.

Private project, tool and repository names are forbidden text: no tracked public file spells them, including the guards themselves, which name them only through fingerprints. A name ruled private after history containing it was published goes into the configuration's `recent` section. Its `since` commit is the published main at the time of the ruling. Those fingerprints hold for tracked files, ref names, every commit outside the `since` ancestry, and the message of every annotated tag except the tag objects listed in `published_tags`, which are the annotated tags published at the time of the ruling. Published history, including those tag messages, is not rewritten. A missing `since` commit refuses the scan.

Publication runs the same build-free guard in both the pre-push hook and CI. The source checkout supplies the scan and its repository-fingerprint configuration; both stay outside the Hex package. Both run `elixir scripts/check_public_privacy.exs scripts/public_privacy.json`. The command requires `ABP_PUBLIC_PRIVACY_HMAC_KEY` in its environment, and CI supplies it from a repository secret. ExUnit exercises the script with a test key and canary, so builds and tests need no publication key.

## Consequences

Qualification runs only on `kci/**` pushes and always enforces the keyed history
check. The scan has no skip mode: the publication workflow enforces it before
uploads, and a missing or short privacy key fails every invocation closed.
