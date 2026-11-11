# Quickstart

This guide is for Elixir developers who want to verify an [artifact](glossary.md#artifact). You will load the shipped Blueprint, inspect a typed denial, and run the shipped conformance corpus.

## Prerequisites

Install Elixir 1.19 or newer with OTP 27, 28, or 29.

## Install

Create a Mix project and add the dependency to its `mix.exs` file:

```sh
mix new verify_blueprint
cd verify_blueprint
```

Replace the generated `deps/0` body with this excerpt:

```elixir
defp deps do
  [{:agent_blueprint_protocol, "~> 1.0.0-rc.1"}]
end
```

Fetch the dependency and start IEx:

```sh
mix deps.get
iex -S mix
```

## Decode the shipped Blueprint

A [Blueprint](glossary.md#blueprint) is a JSON artifact that describes an agent's capabilities and bounds. The Hex package includes the example under `examples/`.

```elixir
dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
example_path = Path.join(dependency_root, "examples/echo-blueprint.json")
bytes = File.read!(example_path)
{:ok, blueprint} = AgentBlueprintProtocol.decode_blueprint(bytes)
AgentBlueprintProtocol.canonical_bytes(blueprint) == {:ok, bytes} # => true
```

The last expression returns:

```elixir
true
```

## Read a typed denial

Fallible calls return `%AgentBlueprintProtocol.Error{}` values. This input has an unknown top-level member:

```elixir
{:error, %AgentBlueprintProtocol.Error{} = error} = AgentBlueprintProtocol.decode_blueprint(~s({"unknown":true}))

error.code # => :unknown_member
```

## Run the shipped corpus

The package includes a [conformance corpus](glossary.md#conformance-corpus) under `priv/conformance/`. Load its files through the public corpus, runner, and report functions:

```elixir
root = Application.app_dir(:agent_blueprint_protocol, "priv/conformance")
files = Path.wildcard(Path.join(root, "**/*")) |> Enum.filter(&File.regular?/1)
files = Map.new(files, fn path -> {Path.relative_to(path, root), File.read!(path)} end)
{:ok, corpus} = AgentBlueprintProtocol.Conformance.Corpus.load(files)
results = AgentBlueprintProtocol.Conformance.Runner.run(corpus)
report = AgentBlueprintProtocol.Conformance.Report.build(corpus, results)
report.agreement # => true
```

## Next steps

- [TypeScript guide](typescript.md)
- [Conformance guide](conformance.md)
- [Livebook walkthrough](../docs/livebooks/abp-walkthrough.livemd)
- [Glossary](glossary.md)
- [Protocol specification](../spec/protocol.md)
