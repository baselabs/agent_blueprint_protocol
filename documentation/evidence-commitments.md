# Evidence commitments and the EU AI Act

For high-risk systems, the EU AI Act (Regulation (EU) 2024/1689)
requires automatic logging of events over the system's lifetime
(Article 12) and requires deployers to keep those logs for at least six
months (Article 26). Article 25(4) requires a provider and the third
parties that supply it tools, services, components, or processes to set
out, by written agreement, the information and assistance the provider
needs to meet its obligations. The application dates of these
high-risk obligations were moved by Regulation (EU) 2026/1744, the
Digital Omnibus on AI; check the consolidated text of Regulation (EU)
2024/1689 on EUR-Lex for the dates that currently apply. Procurement
practice is converging on machine-readable conformity claims (the EU's
model contractual clauses for AI procurement are the reference shape).

What a Blueprint offers on that surface is structure, not compliance:

- **The claims are machine-checkable.** An artifact's capability
  requirements, operational bounds, classification ceilings, effect
  intents, and evaluation assertions are typed, registry-validated,
  digest-covered members — not prose in a PDF. A due-diligence
  reviewer can verify the exact bytes a producer signed.
- **The evidence surface is named honestly.** A reconcile result is an
  Evidence record whose `not_verified` set is non-empty by
  construction — tenancy, live policy, authority, effect ownership,
  execution, billing, and evaluation truth are structurally never
  claimed by this protocol. A compliance narrative cannot quote a
  green verification as more than it is.
- **Bounds are pre-declared logging triggers.** The ceilings members
  (cost, elapsed time, attempts, fan-out, descendants, tokens) are the
  operational envelope a logging system watches; the deployment
  manifest's evaluation binding names the evaluation corpus by digest.

The honest boundary: this protocol does not log anything, satisfy an
article, or certify a system. Logging systems do the logging, and
conformity assessment stays with the bodies that perform it. A
blueprint makes the producer's claims verifiable so the human and
regulatory machinery has exact, signed inputs to work from.

For the discovery-side counterpart — how a registry's trust manifest
relates to blueprint identity — see the [ARD mapping](../docs/ard-mapping.md).
