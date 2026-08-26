# The producer guide — rendering artifacts

The documented per-artifact constructors ARE the producer surface:
compose the member value, construct, digest, serialize.

```elixir
{:ok, bytes} = AgentBlueprintProtocol.Canonicalization.encode({:object, [{"a", {:integer, 1}}]})
AgentBlueprintProtocol.Json.decode(bytes) # => {:ok, {:object, [{"a", {:integer, 1}}]}}
```

Thread `:authored_extensions` for critical namespaces whose bodies
negotiation validated against a digest-pinned host schema — the
authored channel spares those bodies the generic value-shape
heuristics while staying digest-covered.

## The round-trip guarantee

`decode → to_value → encode` is a fixed point (property-tested): the
bytes you serialize are the bytes a verifier recomputes. That is the
byte-exactness guarantee a producer relies on — no facade-level
minting functions exist or will grow (the accepted producer-surface
decision).
