# Quickstart

This guide is for Elixir developers who want to verify an [artifact](glossary.md#artifact). You will load the shipped Blueprint, inspect a typed denial, and run the shipped conformance corpus.

## Prerequisites

Install Elixir 1.19 or newer on Erlang/OTP 27, 28, or 29.

## Install

Create a Mix project and add the dependency to its `mix.exs` file:

```sh
mix new verify_blueprint
cd verify_blueprint
```

Replace the generated `deps/0` function with:

<!-- fragment -->
```elixir
defp deps do
  [{:agent_blueprint_protocol, "~> 1.1.0-rc.5"}]
end
```

Fetch the dependency and start IEx:

```sh
mix deps.get
iex -S mix
```

## Decode the shipped Blueprint

A [Blueprint](glossary.md#blueprint) is a JSON artifact that describes an agent's capabilities and bounds. The Hex package includes the example under `priv/examples/`.

```elixir
example_path = Application.app_dir(:agent_blueprint_protocol, "priv/examples/echo-blueprint.json")
bytes = File.read!(example_path)
{:ok, blueprint} = AgentBlueprintProtocol.decode_blueprint(bytes)
AgentBlueprintProtocol.canonical_bytes(blueprint) == {:ok, bytes} # => true
```

The last expression returns:

```text
true
```

Decoding checks canonical encoding, structure, portability, and the declared digest. This example is unsigned, so it establishes no cryptographic signature verification.

## Read a typed denial

Fallible calls return `%AgentBlueprintProtocol.Error{}` values. This input has an unknown top-level member:

```elixir
{:error, %AgentBlueprintProtocol.Error{} = error} = AgentBlueprintProtocol.decode_blueprint(~s({"unknown":true}))

error.code # => :unknown_member
```

## Next steps

- [Create and sign your own artifact](compose-and-sign.md)
- [Verify a Blueprint/Deployment pair and read its evidence](host-integration.md)
- [Check your artifacts in CI](verifying-in-ci.md)

## Implementing a verifier?

### Optional: run the shipped corpus

The package includes a [conformance corpus](glossary.md#conformance-corpus) under `priv/conformance/`. Load its files through the public corpus, runner, and report functions:

```elixir
corpus_root = Application.app_dir(:agent_blueprint_protocol, "priv/conformance")
files =
  for relative <- :filelib.wildcard(~c"**/*", String.to_charlist(corpus_root)),
      path = Path.join(corpus_root, relative),
      File.regular?(path),
      into: %{},
      do: {List.to_string(relative), File.read!(path)}
{:ok, corpus} = AgentBlueprintProtocol.Conformance.Corpus.load(files)
results = AgentBlueprintProtocol.Conformance.Runner.run(corpus)
report = AgentBlueprintProtocol.Conformance.Report.build(corpus, results)
report.agreement # => true
```

- [Run the conformance corpus](conformance.md)
- [TypeScript guide](typescript.md)
- [Livebook walkthroughs](../docs/livebooks/abp-walkthrough.livemd): [producing artifacts](../docs/livebooks/producing-artifacts.livemd), [host import](../docs/livebooks/host-import.livemd), [extensions and federation](../docs/livebooks/extensions-and-federation.livemd), and [conformance and attacks](../docs/livebooks/conformance-and-attacks.livemd).
- [Glossary](glossary.md)
- [Protocol specification](../spec/protocol.md)
