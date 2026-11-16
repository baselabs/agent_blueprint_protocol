# Foundation transition: asset inventory

What a future transfer of this protocol to a foundation or standards
venue covers, and what the steward can and cannot
transfer. This document is an inventory, not an offer.

## Transferable as-is

- **The specification tree** (`spec/`): the normative document, the
  machine-readable grammars (CDDL and the derived JSON Schemas), the
  governance-canonical registry document, this governance pack, and
  the license copies. Extractable by a tested git filter (the
  extraction is a build-gated proof in the reference repository).
- **The conformance corpus** (`priv/conformance/`): 626 digest-bound
  cases with the applicability floor, golden artifacts, and vectors.
- **The reference implementation and the verifier** (Apache-2.0): the
  Elixir package and the second-language TypeScript verifier.
- **Verification materials**: the shipped conformance corpus, execution
  protocol, and certified per-case results.

## Requires the steward's principals

- **License and sign-off**: contributions are DCO-signed and
  Apache-2.0 licensed; a receiving entity takes the license as-is. BaseLabs Holdings and contributors retain their copyrights, licensing
  perpetually under Apache-2.0.
- **Registry decision rights**: the registry process (see
  registry/OPERATIONS.md) names the steward; a transfer re-points the
  process owner, which is a policy amendment, not a data change.

## Not transferable

- **The steward's unpublished product identities.** Registered example
  namespaces are RFC 2606 example-class by design; real product
  registrations happen when those products are public, under their own
  ownership.
