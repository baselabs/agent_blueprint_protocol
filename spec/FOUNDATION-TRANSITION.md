# Foundation transition — asset inventory

What a future transfer of this protocol to a foundation or standards
venue covers, and what an unincorporated steward can and cannot
transfer. This document is an inventory, not an offer.

## Transferable as-is

- **The specification tree** (`spec/`): the normative document, the
  machine-readable grammars (CDDL and the derived JSON Schemas), the
  governance-canonical registry document, this governance pack, and
  the license copies. Extractable by a tested git filter (the
  extraction is a build-gated proof in the reference repository).
- **The conformance corpus** (`priv/conformance/`): 94 digest-bound
  cases with the applicability floor, golden artifacts, and vectors.
- **The reference implementation and the verifier** (Apache-2.0): the
  Elixir package and the second-language TypeScript verifier.
- **The gate battery and its recorded red proofs** (the requirement
  map): reproducible evidence infrastructure.

## Requires the steward's principals

- **Copyright and patent grants**: contributions are DCO-signed and
  Apache-2.0 licensed; a receiving entity takes the grant as-is. An
  unincorporated organization cannot itself hold or assign copyright —
  the named maintainer and contributors retain theirs, licensing
  perpetually under Apache-2.0.
- **Registry decision rights**: the registry process (see
  registry/OPERATIONS.md) names the steward; a transfer re-points the
  process owner, which is a policy amendment, not a data change.

## Not transferable

- **The steward's unpublished product identities.** Registered example
  namespaces are RFC 2606 example-class by design; real product
  registrations happen when those products are public, under their own
  ownership.

## Triggers

A transfer conversation opens when a venue or foundation terms
discussion begins (the recorded trigger in the campaign's decision
records). The extraction job keeps submission mechanical in the
meantime.

## The deferred-work registry

Work deliberately not done at this release, each with the trigger that
reopens it — vision accounting, not silent deferral. This registry is
the durable, shipped record; nothing on it is dropped.

| Deferred work | Reopens when |
|---|---|
| Repository extraction to its own repo | a standards-body submission opens (the extraction job keeps it a filter away) |
| Foundation donation execution | a terms discussion begins (this document is the inventory) |
| Third implementation (Rust or Go) | an external conforming implementation merges |
| Registry codegen from the canonical json | a third implementation, or an unported registry change surviving a cycle |
| CDDL validator automation | a maintained RFC 8610 validator passes the derivation gate |
| npm kit distribution | a TypeScript consumer needs dependency-manager distribution |
| Registry public registrants (real product identities) | the portfolio products go public |
| Benchmark program | the first host-integration performance question |
| Federation completion (native wire fields revisit) | MCP Tasks finalizes (ext-tasks first tagged release) |
| Attestation-kind registry activation | a second attestation consumer exists |
| Subset profiles (decode+verify only) | an adopter needs them |
| 1.0 semver/stability contract | the 0.x line has external consumers and settled dust |

Each trigger is checkable; none is a date. When one fires, the work
re-enters the queue with the same discipline as everything in the
requirement map.
