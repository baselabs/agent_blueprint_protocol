# Producer guide

This guide is for developers who publish Blueprints and Deployment Manifests. You will find the steps for composing, signing, and checking a producer artifact.

Compose the tagged JSON value with a well-formed provisional digest. Construct a draft with the artifact's `from_value/2`, compute `content_digest/1`, convert it with `Digest.to_tagged/1`, and replace the value's `content_digest` or `deployment_digest` member. Canonically encode the updated value and decode those bytes to validate the completed artifact. Sign the completed digest and recreate any signatures affected by the edit. Keep producer data portable and use the exact member set for its protocol revision.

The [compose and sign guide](compose-and-sign.md) walks through a complete signed pair built with `Blueprint.from_value/2`. It computes and inserts both digests, signs with the producer's own Ed25519 key using `:crypto`, attaches the signature, checks the pair and round trips, and saves files for CI.

## Artifact identities in JSON

These excerpts show the identity members of the installed unsigned Blueprint and its matching Deployment Manifest. The Manifest names the Blueprint's exact identity, release number, and completed content digest. Each artifact has its own digest. These are reading excerpts, not complete artifacts or canonical wire bytes. The [gallery](examples.md) supplies the complete artifacts.

```json
{
  "echo-blueprint.json": {
    "blueprint_id": "example.demo/echo",
    "protocol_revision": 1,
    "release_number": 1,
    "content_digest": "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8"
  },
  "echo-deployment.json": {
    "blueprint_release": {
      "blueprint_id": "example.demo/echo",
      "content_digest": "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8",
      "release_number": 1
    },
    "deployment_digest": "sha-256:tWFr0caS0AWFJd2UcB9gZv3kNjIUP8xZ08WWM_h8xgo"
  }
}
```

Run this in a project with the [Hex dependency installed](quickstart.md). It decodes the complete installed artifacts, then checks every member shown above against those bytes.

```elixir
json = ~S"""
{
  "echo-blueprint.json": {
    "blueprint_id": "example.demo/echo",
    "protocol_revision": 1,
    "release_number": 1,
    "content_digest": "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8"
  },
  "echo-deployment.json": {
    "blueprint_release": {
      "blueprint_id": "example.demo/echo",
      "content_digest": "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8",
      "release_number": 1
    },
    "deployment_digest": "sha-256:tWFr0caS0AWFJd2UcB9gZv3kNjIUP8xZ08WWM_h8xgo"
  }
}
"""

decoders = %{
  "echo-blueprint.json" => &AgentBlueprintProtocol.decode_blueprint/1,
  "echo-deployment.json" => &AgentBlueprintProtocol.decode_deployment/1
}

for {name, excerpt} <- :json.decode(json) do
  directory = Application.app_dir(:agent_blueprint_protocol, "priv/examples")
  bytes = File.read!(Path.join(directory, name))
  {:ok, _artifact} = Map.fetch!(decoders, name).(bytes)
  true = Map.take(:json.decode(bytes), Map.keys(excerpt)) == excerpt
end
```

## Next steps

- [What a Blueprint is](what-a-blueprint-is.md)
- [Compose and sign artifacts](compose-and-sign.md)
- [Read the security model](security-model.md)
