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
