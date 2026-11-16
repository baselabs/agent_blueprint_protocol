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

## Triggers

A transfer conversation begins when a standards venue or foundation starts a terms discussion. The extraction job keeps submission mechanical in the
meantime.

## Capabilities not included

The following capabilities are not included in this release. Each row states the condition for reconsidering it.

| Capability | Reconsidered when |
|---|---|
| Repository extraction to its own repo | a standards-body submission opens (the extraction job keeps it a filter away) |
| Foundation donation execution | a terms discussion begins (this document is the inventory) |
| Third implementation (Rust or Go) | an external conforming implementation merges |
| Registry codegen from the canonical json | a third implementation, or an unported registry change surviving a cycle |
| CDDL validator automation | a maintained RFC 8610 validator passes the derivation gate |
| Registry public registrants (real product identities) | the portfolio products go public |
| Benchmark program | the first host-integration performance question |
| Federation completion (native wire fields revisit) | the MCP tasks extension leaves Beta |
| Attestation-kind registry activation | a second attestation consumer exists |
| Normative subset profiles (decode and verify only) | an adopter needs the formal profile |

The maintainers reassess an item when its stated condition is met.
