# Compose and sign a Blueprint

This guide is for Elixir producers. You will build a Blueprint from a tagged JSON object, compute its digest, sign it with an Ed25519 key, and check the encoded round trip.

The package validates and encodes artifacts. The producer creates its own Ed25519 key and signs the input returned by `Signature.signing_input/1` with Erlang's `:crypto` module.

The tagged object below uses the same member values as the shipped echo example. Its creation timestamp is a fixed example value, not a current clock reading.

Run this code in a Mix project that depends on the package, such as `iex -S mix` at the repository root.

```elixir
alias AgentBlueprintProtocol.{Blueprint, Digest, Signature}

placeholder = Digest.to_tagged(Digest.hash(:blueprint_content, "placeholder"))

value =
  {:object,
   [
     {"blueprint_id", {:string, "example.demo/echo"}},
     {"protocol_revision", {:integer, 1}},
     {"producer",
      {:object,
       [
         {"created_at", {:string, "2026-08-20T00:00:00Z"}},
         {"identity", {:string, "example.demo"}},
         {"toolchain", {:string, "example.demo.toolchain"}}
       ]}},
     {"release_number", {:integer, 1}},
     {"capability_requirements",
      {:array,
       [
         {:object,
          [
            {"approval_trait", {:string, "none"}},
            {"argument_schema", {:object, [{"type", {:string, "object"}}]}},
            {"authority_trait", {:string, "none"}},
            {"classification_ceiling", {:string, "internal"}},
            {"impact_class", {:string, "ordinary"}},
            {"operation_family", {:string, "example.demo.read_shape"}},
            {"operation_kind", {:string, "read"}},
            {"result_schema", {:object, [{"type", {:string, "object"}}]}}
          ]}
       ]}},
     {"input_ports",
      {:array,
       [
         {:object,
          [
            {"classification_ceiling", {:string, "internal"}},
            {"name", {:string, "request"}},
            {"required", {:boolean, true}},
            {"schema", {:object, [{"type", {:string, "object"}}]}}
          ]}
       ]}},
     {"output_ports",
      {:array,
       [
         {:object,
          [
            {"classification_ceiling", {:string, "internal"}},
            {"name", {:string, "result"}},
            {"required", {:boolean, true}},
            {"schema", {:object, [{"type", {:string, "object"}}]}}
          ]}
       ]}},
     {"output_contract",
      {:object,
       [
         {"classification_ceiling", {:string, "internal"}},
         {"port", {:string, "result"}}
       ]}},
     {"triggers", {:array, [{:string, "manual"}]}},
     {"ceilings",
      {:object,
       [
         {"max_attempts", {:integer, 3}},
         {"max_concurrency", {:integer, 2}},
         {"max_cost",
          {:object, [{"amount", {:integer, 1000}}, {"currency", {:string, "USD"}}]}},
         {"max_depth", {:integer, 8}},
         {"max_descendants", {:integer, 64}},
         {"max_elapsed_ms", {:integer, 60000}},
         {"max_fan_out", {:integer, 4}},
         {"max_tokens", {:integer, 100000}}
       ]}},
     {"classification_ceiling", {:string, "internal"}},
     {"effect_intents",
      {:array,
       [
         {:object,
          [
            {"impact_class", {:string, "ordinary"}},
            {"logical_operation", {:string, "record_summary"}},
            {"operation_kind", {:string, "mutation"}}
          ]}
       ]}},
     {"evaluation_assertions",
      {:array,
       [
         {:object,
          [
            {"kind", {:string, "output_schema"}},
            {"port", {:string, "result"}},
            {"schema", {:object, [{"type", {:string, "object"}}]}}
          ]}
       ]}},
     {"extensions",
      {:object, [{"critical", {:object, []}}, {"optional", {:object, []}}]}},
     {"required_core_fields", {:array, []}},
     {"content_digest", {:string, placeholder}}
   ]}

{:ok, blueprint} = Blueprint.from_value(value)
digest = Blueprint.content_digest(blueprint)

put_member = fn {:object, members}, name, member_value ->
  {:object, [{name, member_value} | Enum.reject(members, fn {key, _} -> key == name end)]}
end

value =
  blueprint
  |> Blueprint.to_value()
  |> put_member.("content_digest", {:string, Digest.to_tagged(digest)})

{:ok, blueprint} = Blueprint.from_value(value)
{public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

protected =
  {:object,
   [
     {"alg", {:string, "Ed25519"}},
     {"b64", {:boolean, false}},
     {"crit", {:array, [{:string, "b64"}]}},
     {"kid", {:string, "producer-key-1"}}
   ]}

signed_attributes =
  {:object,
   [
     {"algorithm", {:string, "Ed25519"}},
     {"content_digest", {:string, Digest.to_tagged(digest)}},
     {"created_at", {:string, "2026-08-20T00:00:00Z"}},
     {"key_id", {:string, "producer-key-1"}},
     {"purpose", {:string, "blueprint"}}
   ]}

placeholder_signature = Base.url_encode64(<<0::512>>, padding: false)

entry =
  {:object,
   [
     {"protected", protected},
     {"signed_attributes", signed_attributes},
     {"signature", {:string, placeholder_signature}}
   ]}

{:ok, signing_input} = Signature.signing_input(entry)
signature = :crypto.sign(:eddsa, :none, signing_input, [private_key, :ed25519])

entry =
  put_member.(
    entry,
    "signature",
    {:string, Base.url_encode64(signature, padding: false)}
  )

value =
  blueprint
  |> Blueprint.to_value()
  |> put_member.("signatures", {:array, [entry]})

{:ok, blueprint} = Blueprint.from_value(value)
{:ok, bytes} = Blueprint.canonical_bytes(blueprint)
{:ok, decoded} = AgentBlueprintProtocol.decode_blueprint(bytes)
{:ok, ^bytes} = Blueprint.canonical_bytes(decoded)

key = %Signature.PublicKey{
  key_id: "producer-key-1",
  algorithm: :ed25519,
  key: public_key
}

{:ok, attributes} = Signature.verify(entry, [key])
attributes.purpose
```

The final expression returns `:blueprint`. The private key stays in the producer process and is not part of the artifact.

## Next steps

- [What a Blueprint is](what-a-blueprint-is.md)
- [Handle typed errors](handling-errors.md)
- [Verify an artifact in CI](verifying-in-ci.md)
