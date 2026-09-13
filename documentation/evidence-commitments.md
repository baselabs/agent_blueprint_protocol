# Evidence commitments and the EU AI Act

The AI Act became fully applicable August 2, 2026. For high-risk
systems, Article 12 requires automatic logging of events over the
system's lifetime, with deployer retention of at least six months, and
Article 26 flows deployer due-diligence duties down to providers and
suppliers. Procurement practice is converging on machine-readable
conformity claims (the EU's model contractual clauses for AI
procurement are the reference shape).

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
article, or certify a system. Logging systems do the logging (the
IETF's in-progress agent audit-trail work — hash-chained records
explicitly mapped to Article 12, SOC 2, and ISO/IEC 42001 — is the
candidate substrate); certification remains the registrar's. A
blueprint makes the producer's claims verifiable so the human and
regulatory machinery has exact, signed inputs to work from.

For the discovery-side counterpart — how a registry's trust manifest
relates to blueprint identity — see the [ARD mapping](../docs/ard-mapping.md).
