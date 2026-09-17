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

`mix quality` runs, in order: dependency audits (retirement, security
advisories, and latest-release currency), formatting, warnings-as-errors
compilation, strict Credo, the test suite with the 100% coverage
threshold, the conformance corpus and its mutation gate, the
second-language verifier agreement gate (Node >= 24 required), Dialyzer,
docs with warnings-as-errors, the specification-extraction check, the
grammar-derivation gate, the registry-equality gate, and the
release-candidate check (requirement-map completeness, the
specification's coupling to the implementation, the release identity
chain, and the reprove pass that replants every recorded red).

Prerequisites: Elixir on the enforced `~> 1.19` range (1.19 or 1.20) on
a supported OTP major — 27, 28, or 29, refused before anything compiles
by `config/config.exs` (see `docs/adr/supported-otp-set.md`) — and
Node >= 24 (the verifier agreement step invokes the TypeScript
verifier). The dev toolchain pin lives in `.tool-versions`; the four
toolchain declarations (Elixir range, supported-OTP set, dev pin, CI
lanes) move together in one commit. One test — the public-surface
privacy history scan — reads a local HMAC key
(`ABP_PUBLIC_PRIVACY_HMAC_KEY`) that maintainers provision; CI holds it
as a secret. On fork pull requests, where GitHub passes no secrets, that
test skips loudly (a `[privacy-scan] SKIPPED` banner names exactly what
did not run); every other context enforces it.

## How to propose a change

- **Bugs and divergences from the specification** — open a bug-report
  issue first if the expected behavior is unclear; otherwise a PR with
  the failing case added to the relevant gate or corpus lane.
- **Specification changes** — open a Discussion or issue describing the
  member/semantics change BEFORE the PR: core member additions require a
  protocol revision increment, corpus cases, and grammar regeneration, so
  the shape should be agreed while it is still cheap to change.
- **Extension registrations** — file a registry-request issue; the
  process and its rules live in `spec/registry/OPERATIONS.md`.
- **Documentation** — PRs welcome; every result-claiming guide example is
  mirror-tested, so examples that do not run will red the build (that is
  the point).

New to the codebase? The guides listed in `mix.exs` `groups_for_extras`
are the map; `docs/design/requirement-map.md` is the inventory of every
gate and its recorded red proof. The public roadmap is the deferred-work
registry in `spec/FOUNDATION-TRANSITION.md` — every deferred item names
the trigger that reopens it.

Review expectations: the battery runs on every PR; the maintainer reviews
against the specification and the requirement map. A green CI on a fork
PR does not include the privacy history scan (it cannot — GitHub passes
no secrets to forks); that gate runs on merge into `main` and on
maintainer branches.

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
