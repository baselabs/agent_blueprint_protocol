# Contributing to the Agent Blueprint Protocol

Contributions are accepted under the Developer Certificate of Origin:
commit with `git commit -s`. No CLA. Licensing is Apache-2.0 (see the
specification tree's IPR statement for the patent posture).

## The verification battery

Every change runs the full battery; a change is done when the battery
is green end-to-end and the gates it touches carry red proofs.

```bash
mix deps.get
mix quality
```

`mix quality` runs, in order: dependency audits, formatting,
warnings-as-errors compilation, strict Credo, the test suite with the
100% coverage threshold, the conformance corpus and its mutation gate,
the second-language verifier agreement gate (Node >= 24 required),
Dialyzer, docs with warnings-as-errors, the specification-extraction
check, the grammar-derivation gate, the registry-equality gate, and
the release-candidate check (requirement-map completeness, the
specification's coupling to the implementation, the release identity
chain, and the reprove pass that replants every recorded red).

Prerequisites: Elixir 1.20.x on OTP 29.x and Node >= 24 (the verifier
agreement step invokes the TypeScript verifier). One test — the
public-surface privacy history scan — reads a local HMAC key
(`ABP_PUBLIC_PRIVACY_HMAC_KEY`) that maintainers provision; CI holds it
as a secret.

## What every gate owes

Every build-failing gate in this repository carries a recorded red
proof in `docs/design/requirement-map.md` (the exact mutation, the
command, the verbatim failing output), and the release-candidate
reprove replants the acceptance spine on every run. New gates arrive
with their red quoted, never asserted.

## Specification changes

The specification tree (`spec/`) is the normative document set;
identity changes (corpus, registry, specification text) must
regenerate `priv/release-metadata.json` (`mix run --no-start
scripts/generate_release_metadata.exs`) so the release identity chain
stays honest. Fenced specification examples are corpus cases — bind
them (`corpus:<case-id>`) or they red.
