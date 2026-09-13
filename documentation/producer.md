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

## Signing an artifact (the producer recipe)

The package verifies and never signs — so signing is a few lines with
`:crypto` in your producer toolchain. What is signed is the RFC 7797
§3 detached preimage: `BASE64URL(JCS(protected_header)) || "." ||
JCS(signed_attributes)`. The recipe, mirror-tested against the shipped
verifier:

```elixir
{:ok, blueprint} = AgentBlueprintProtocol.decode_blueprint(File.read!("examples/echo-blueprint.json"))
digest = AgentBlueprintProtocol.Blueprint.content_digest(blueprint)
{public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
protected = {:object, [{"alg", {:string, "EdDSA"}}, {"b64", {:boolean, false}}, {"crit", {:array, [{:string, "b64"}]}}, {"kid", {:string, "example-demo-1"}}]}
signed_attributes = {:object, [{"algorithm", {:string, "Ed25519"}}, {"content_digest", {:string, AgentBlueprintProtocol.Digest.to_tagged(digest)}}, {"created_at", {:string, "2026-08-21T00:00:00Z"}}, {"key_id", {:string, "example-demo-1"}}, {"purpose", {:string, "blueprint"}}]}
protected_bytes = AgentBlueprintProtocol.Canonicalization.encode(protected) |> elem(1)
attributes_bytes = AgentBlueprintProtocol.Canonicalization.encode(signed_attributes) |> elem(1)
preimage = AgentBlueprintProtocol.Base64Url.encode(protected_bytes) <> "." <> attributes_bytes
signature = :crypto.sign(:eddsa, :ed25519, preimage, [private_key, :ed25519])
envelope = {:object, [{"protected", protected}, {"signed_attributes", signed_attributes}, {"signature", {:string, AgentBlueprintProtocol.Base64Url.encode(signature)}}]}
key = %AgentBlueprintProtocol.Signature.PublicKey{key_id: "example-demo-1", algorithm: :ed25519, key: public_key}
AgentBlueprintProtocol.Signature.verify(envelope, [key]) # => {:ok, :verified}
```

The `envelope` value is what you attach as the artifact's `signatures`
member (digest excluded, so signing never changes the digest it
covers).

Rules the verifier enforces (each is a typed denial otherwise): the
protected header is the exact four members in any order (serialized by
JCS); `kid` equals the signed `key_id`; `key_id` is dot-free (RFC 7797
§5.2); `created_at` is Z-form whole seconds; the signature is unpadded
base64url (86 chars for Ed25519). Because `content_digest` and
`purpose` are inside the signed bytes, a signature cannot be lifted
onto a different artifact. Any `b64=false`-aware JOSE library can
produce the same envelope — the constraint is the preimage form above,
not this code.
