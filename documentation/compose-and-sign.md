# Compose and sign artifacts

This guide produces a signed Blueprint and matching Deployment Manifest, verifies them together, and saves canonical files for CI. Use `iex -S mix` in a project with the [Hex dependency installed](quickstart.md), or run the [complete producer Livebook](../docs/livebooks/producing-artifacts.livemd). No checkout is required. Paste each parenthesized block as one IEx expression, in order, so only its final summary is displayed and generated keys stay in memory.

## Before composing

| JSON | Elixir tagged value |
|---|---|
| `null` | `:null` |
| `true` | `{:boolean, true}` |
| `3` / `1.5` | `{:integer, 3}` / `{:float, 1.5}` |
| `"hello"` | `{:string, "hello"}` |
| `[3]` | `{:array, [{:integer, 3}]}` |
| `{"ready": true}` | `{:object, [{"ready", {:boolean, true}}]}` |

Objects use ordered member lists so the decoder can retain order and reject duplicates before canonical encoding; an Elixir map is not a tagged JSON object. `Json.decode/1` converts ordinary JSON to this representation.

`from_value/2` constructs a structurally valid, portable draft, even while its declared digest still belongs to an earlier value. Compute the new digest, insert it, encode canonical bytes, and decode those bytes to check the completed artifact. Then sign its digest. Signatures are excluded from the content digest, so attaching one does not change it.

The template supplies every required member. Producers edit their identity, release number, ports, schemas, capabilities, effects, assertions, ceilings, and extensions to describe their own contract. The Manifest must identify that exact Blueprint release; its adapters, bindings, build identities, policies, timestamps, and host bounds describe the intended environment. This lesson changes only release number and model tokens, keeping the other fixture values coherent.

Formatted JSON is for reading. Artifact decoding requires canonical bytes, including no added trailing newline. Decode ordinary JSON with `Json.decode/1` and encode the tagged value with `Canonicalization.encode/1`; content changes also require recomputing the artifact digest and recreating affected signatures.

## 1. Construct a Blueprint draft and finish its digest

Load the installed template, change the release number, and compute/insert the digest before canonical encoding. The original declared digest is only a draft value after editing; `from_value/2` does not verify it. In a new artifact, a well-formed placeholder serves the same purpose until replaced.

```elixir
package_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
alias AgentBlueprintProtocol.{Blueprint, Canonicalization, Digest, Json}

put_member = fn {:object, members}, name, value ->
  {:object, List.keystore(members, name, 0, {name, value})}
end

replace_path = fn replace_path, {:object, members}, [name | rest], value ->
  if rest == [] do
    put_member.({:object, members}, name, value)
  else
    {^name, nested} = List.keyfind(members, name, 0)
    updated = replace_path.(replace_path, nested, rest, value)
    put_member.({:object, members}, name, updated)
  end
end

blueprint_path = Path.join(package_root, "examples/echo-blueprint.json")
{:ok, blueprint_value} = File.read!(blueprint_path) |> Json.decode()
{:ok, original_blueprint} = Blueprint.from_value(blueprint_value)
original_digest = original_blueprint |> Blueprint.content_digest() |> Digest.to_tagged()

blueprint_value = put_member.(blueprint_value, "release_number", {:integer, 2})
{:ok, blueprint_draft} = Blueprint.from_value(blueprint_value)
blueprint_digest = blueprint_draft |> Blueprint.content_digest() |> Digest.to_tagged()

blueprint_value =
  put_member.(blueprint_value, "content_digest", {:string, blueprint_digest})

{:ok, blueprint_bytes} = Canonicalization.encode(blueprint_value)
{:ok, blueprint} = AgentBlueprintProtocol.decode_blueprint(blueprint_bytes)
{:ok, ^blueprint_bytes} = AgentBlueprintProtocol.canonical_bytes(blueprint)

%{
  release_number: 2,
  digest_changed: original_digest != blueprint_digest,
  digest: blueprint_digest,
  canonical_byte_size: byte_size(blueprint_bytes)
}
```

## 2. Produce the matching Manifest

Bind it to the new release and digest, change the model token limit, then compute and insert `deployment_digest`. Keep the variables from stage 1.

```elixir
alias AgentBlueprintProtocol.Deployment

deployment_path = Path.join(package_root, "examples/echo-deployment.json")
{:ok, deployment_value} = File.read!(deployment_path) |> Json.decode()

deployment_value =
  replace_path.(
    replace_path,
    deployment_value,
    ["blueprint_release", "release_number"],
    {:integer, 2}
  )
  |> then(
    &replace_path.(
      replace_path,
      &1,
      ["blueprint_release", "content_digest"],
      {:string, blueprint_digest}
    )
  )
  |> then(&replace_path.(replace_path, &1, ["model_policy", "max_tokens"], {:integer, 40_000}))

{:ok, deployment_draft} = Deployment.from_value(deployment_value)
deployment_digest = deployment_draft |> Deployment.content_digest() |> Digest.to_tagged()

deployment_value =
  put_member.(deployment_value, "deployment_digest", {:string, deployment_digest})

{:ok, deployment_bytes} = Canonicalization.encode(deployment_value)
{:ok, deployment} = AgentBlueprintProtocol.decode_deployment(deployment_bytes)

%{
  digest: deployment_digest,
  binds_changed_release: Deployment.binds?(deployment, blueprint),
  canonical_byte_size: byte_size(deployment_bytes)
}
```

## 3. Sign both artifacts and reconcile them

Generate a throwaway key in memory. The Blueprint uses purpose `blueprint`; the Manifest uses `deployment`. `Signature.signing_input/1` supplies the exact bytes to sign. `Signature.attributes/1` only parses; `Signature.verify/2` returns cryptographically verified attributes. Standalone verification must also compare purpose and content digest with the intended artifact.

```elixir
alias AgentBlueprintProtocol.{Base64Url, Signature}
alias AgentBlueprintProtocol.Signature.PublicKey

{public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

protected =
  {:object,
   [
     {"alg", {:string, "Ed25519"}},
     {"b64", {:boolean, false}},
     {"crit", {:array, [{:string, "b64"}]}},
     {"kid", {:string, "example-producer-key"}}
   ]}

signed_attributes =
  {:object,
   [
     {"algorithm", {:string, "Ed25519"}},
     {"content_digest", {:string, blueprint_digest}},
     {"created_at", {:string, "2026-08-20T00:00:00Z"}},
     {"key_id", {:string, "example-producer-key"}},
     {"purpose", {:string, "blueprint"}}
   ]}

entry_with = fn header, signature_bytes ->
  {:object,
   [
     {"protected", header},
     {"signed_attributes", signed_attributes},
     {"signature", {:string, Base64Url.encode(signature_bytes)}}
   ]}
end

unsigned_entry = entry_with.(protected, <<0::512>>)
{:ok, signing_input} = Signature.signing_input(unsigned_entry)
signature_bytes = :crypto.sign(:eddsa, :none, signing_input, [private_key, :ed25519])
entry = entry_with.(protected, signature_bytes)

public_key_record = %PublicKey{
  key_id: "example-producer-key",
  algorithm: :ed25519,
  key: public_key
}

{:ok, signed_bytes} =
  blueprint
  |> Blueprint.to_value()
  |> put_member.("signatures", {:array, [entry]})
  |> Canonicalization.encode()

{:ok, signed_blueprint} = AgentBlueprintProtocol.decode_blueprint(signed_bytes)
{:ok, ^signed_bytes} = AgentBlueprintProtocol.canonical_bytes(signed_blueprint)

%{
  signature_verifies:
    match?({:ok, %Signature.Attributes{}}, Signature.verify(entry, [public_key_record])),
  digest_unchanged:
    Digest.to_tagged(Blueprint.content_digest(signed_blueprint)) == blueprint_digest,
  canonical_round_trip: true
}

{:ok, blueprint_attributes} = Signature.verify(entry, [public_key_record])
true = blueprint_attributes.purpose == :blueprint
true = Digest.to_tagged(blueprint_attributes.content_digest) == blueprint_digest
{:ok, compact} = Signature.to_compact(entry)
[_, "", _] = String.split(compact, ".")

deployment_attributes =
  signed_attributes
  |> put_member.("content_digest", {:string, deployment_digest})
  |> put_member.("purpose", {:string, "deployment"})

deployment_entry =
  entry
  |> put_member.("signed_attributes", deployment_attributes)
  |> put_member.("signature", {:string, Base64Url.encode(<<0::512>>)})

{:ok, deployment_input} = Signature.signing_input(deployment_entry)
deployment_signature = :crypto.sign(:eddsa, :none, deployment_input, [private_key, :ed25519])

deployment_entry =
  put_member.(deployment_entry, "signature", {:string, Base64Url.encode(deployment_signature)})

{:ok, signed_deployment_bytes} =
  deployment
  |> Deployment.to_value()
  |> put_member.("signatures", {:array, [deployment_entry]})
  |> Canonicalization.encode()

{:ok, signed_deployment} = AgentBlueprintProtocol.decode_deployment(signed_deployment_bytes)
{:ok, attributes} = Signature.verify(deployment_entry, [public_key_record])
true = attributes.purpose == :deployment
true = Digest.to_tagged(attributes.content_digest) == deployment_digest

alias AgentBlueprintProtocol.{BoundsAlgebra, Evidence, Reconcile}
{:ok, host_bounds} = BoundsAlgebra.from_deployment(signed_deployment)

inputs = %Reconcile.Inputs{
  host_bounds: host_bounds,
  support: %AgentBlueprintProtocol.Negotiation.Support{revisions: MapSet.new([1])},
  keys: [public_key_record],
  protected_clamp: :acknowledge,
  observations: %Deployment.Observations{}
}

{:ok, pair_evidence} =
  AgentBlueprintProtocol.reconcile(signed_blueprint, signed_deployment, inputs)

signature_subjects =
  Enum.map(["blueprint", "deployment"], fn artifact ->
    check =
      Enum.find(pair_evidence.checks, &(&1.surface == :signatures and &1.subject == [artifact]))

    %{verified: true, detail: %Evidence.Signatures{key_ids: ids}} = check
    {artifact, ids}
  end)

# Reconcile once with the unsigned Manifest to show subject-aware coverage.
{:ok, mixed_evidence} = AgentBlueprintProtocol.reconcile(signed_blueprint, deployment, inputs)

%{
  signed_subjects: signature_subjects,
  pair_signatures_unverified: :signatures in pair_evidence.not_verified,
  mixed_signatures_unverified: :signatures in mixed_evidence.not_verified
}
```

The summary preserves both subjects. With an unsigned Manifest, the Blueprint signature remains verified while the Manifest signature is unverified. A valid pair does not establish the host's tenancy, local policy, authority, effect ownership, execution, billing, or evaluation truth.

## 4. Save, reload, and check in CI

Choose a fresh output directory. This cell refuses to overwrite an existing one. Keys remain in memory; only canonical artifact bytes are written. Re-evaluating this stage requires choosing a new directory or removing your previous example output.

```elixir
output_dir = Path.join(File.cwd!(), "abp-artifacts")
:ok = File.mkdir(output_dir)
System.at_exit(fn _status -> File.rm_rf!(output_dir) end)
blueprint_output = Path.join(output_dir, "blueprint.json")
deployment_output = Path.join(output_dir, "deployment.json")
:ok = File.write(blueprint_output, signed_bytes)
:ok = File.write(deployment_output, signed_deployment_bytes)
{:ok, reloaded_blueprint} = AgentBlueprintProtocol.decode_blueprint(File.read!(blueprint_output))

{:ok, reloaded_deployment} =
  AgentBlueprintProtocol.decode_deployment(File.read!(deployment_output))

{:ok, ^signed_bytes} = AgentBlueprintProtocol.canonical_bytes(reloaded_blueprint)
{:ok, ^signed_deployment_bytes} = AgentBlueprintProtocol.canonical_bytes(reloaded_deployment)

{:ok, _reloaded_evidence} =
  AgentBlueprintProtocol.reconcile(reloaded_blueprint, reloaded_deployment, inputs)

%{files: ["abp-artifacts/blueprint.json", "abp-artifacts/deployment.json"], reloaded_pair: true}
```

From the directory containing `abp-artifacts`, with Node.js 24 or newer:

```sh
npx @agent-blueprint-protocol/verifier@1.0.1 --artifact abp-artifacts/blueprint.json
npx @agent-blueprint-protocol/verifier@1.0.1 --artifact abp-artifacts/deployment.json
```

Each command prints a valid report and exits `0`. Decoder-only artifact mode establishes no key verification or pair reconciliation. See [CI pair verification](verifying-in-ci.md) for a complete script with host inputs. Copy the files into your project before exiting IEx. The walkthrough owns `abp-artifacts` and removes it when its runtime exits; run the CLI in a second terminal while that runtime is open.

The walkthrough follows `Blueprint.from_value/2`, `Deployment.from_value/2`, their digest/encoder/decoder functions, `Signature.signing_input/1`, `Signature.verify/2`, and `Reconcile.reconcile/3`. These are the public contracts checked in the 1.0.1 source.

## Next steps

- [Supply independent host observations](host-integration.md)
- [Read both evidence subjects](reading-evidence.md)
- [Handle typed denials](handling-errors.md)
