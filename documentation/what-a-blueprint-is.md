# What a blueprint is

A Blueprint is the portable description of an agent capability: stable
identity, typed ports, logical capability requirements, bounds,
evidence commitments, and registered extensions — bound to one exact
release by a content digest.

## The 18-member closed world

Sixteen required members and two optional evidence envelopes. The
member grammar in the specification lists every one with its type,
cardinality, and constraints; the CDDL grammar under `spec/grammar/`
is the machine-readable form. Highlights:

- `blueprint_id` — a producer-qualified identity (`example.demo/echo`).
- `capability_requirements` — what the agent may do: operation family
  and kind, impact class, classification ceiling, authority and
  approval traits, argument/result schemas.
- `ceilings` — eight operational bounds (attempts, concurrency, cost,
  depth, descendants, elapsed time, fan-out, tokens); absent is an
  error, never infinity.
- `classification_ceiling` — the ordinal disclosure ceiling.
- `content_digest` — the release identity: the domain-separated
  digest over the digest-covered members.

## Identity is the digest

Two blueprints with identical digest-covered members and identical
canonical bytes are the same blueprint. `decode_blueprint/2` verifies
canonicality first (non-canonical bytes deny before any semantic
read), then structure, then the declared digest.

## Optional members

`signatures` (detached, verify-only JWS envelopes) and `attestations`
— both excluded from the digest input; both evidence, never
authority.
