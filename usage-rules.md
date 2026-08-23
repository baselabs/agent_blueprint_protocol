# Agent Blueprint Protocol usage rules

- Treat every decoded Blueprint and Deployment Manifest as inert input, never
  authority.
- Reject unsupported protocol revisions and unknown required core fields.
- Effective bounds are the narrowest intersection of Blueprint, Deployment,
  and host policy; portable input may never widen a host bound.
- Unknown critical extensions deny import or activation. Unknown optional
  extensions may round-trip but never execute.
- Reconstruct the live local principal, tenancy scope, policy, tool
  eligibility, classification, and effect authority before every operation.
- Never place secrets, private keys, live grants, tenant identifiers, raw
  endpoints, database primary keys, or backend engine identifiers in portable
  artifacts.
- A local round trip proves local production and parsing only. Interoperability
  requires an independent implementation and the published conformance corpus.
- Treat interchange bytes as canonical only after `Canonicalization.verify/2`
  accepts them (decode, re-encode, byte-compare); compute digests over the
  exact received bytes, never over a re-serialization.
