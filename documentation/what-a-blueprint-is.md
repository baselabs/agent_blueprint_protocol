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

## The blueprint card (a derived projection)

For discovery and display contexts a small "card" can be derived from
a verified blueprint — the identity and the digest, nothing more. The
card is NOT an artifact: it asserts nothing the blueprint does not,
carries the digest precisely so any reader can bind the summary back
to the exact verified bytes, and is never conforming on its own
(partial conformance is not conformance). Derive from bytes you
verified, or treat a received card as unverified display data:

```elixir
bytes = File.read!("examples/echo-blueprint.json")
{:ok, blueprint} = AgentBlueprintProtocol.decode_blueprint(bytes)
digest = AgentBlueprintProtocol.Blueprint.content_digest(blueprint)
{:ok, {:object, members}} = AgentBlueprintProtocol.Json.decode(bytes)
{"blueprint_id", {:string, id}} = List.keyfind(members, "blueprint_id", 0)
card = %{"blueprint_id" => id, "content_digest" => AgentBlueprintProtocol.Digest.to_tagged(digest)}
card["blueprint_id"] # => "example.demo/echo"
card["content_digest"] # => "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8"
```
