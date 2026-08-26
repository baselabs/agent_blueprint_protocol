# Getting started

Verify your first artifact in minutes. The package is inert: no
application callback, no supervision tree, zero production
dependencies.

## Install

```elixir
def deps do
  [
    {:agent_blueprint_protocol, "~> 0.3.0"}
  ]
end
```

## Verify a blueprint

A Blueprint travels as canonical JSON bytes; decoding is fail-closed —
a typed fact or a typed denial, never a silent repair.

```elixir
{:ok, bytes} = AgentBlueprintProtocol.Canonicalization.encode({:object, [{"a", {:integer, 1}}]})

AgentBlueprintProtocol.Json.decode(bytes) # => {:ok, {:object, [{"a", {:integer, 1}}]}}
AgentBlueprintProtocol.decode_blueprint(bytes) # => {:error, :unknown_member}
```

## Run the shipped conformance corpus

The package ships a 94-case conformance corpus; run it to see the
protocol's whole behavior surface:

```bash
mix conformance.verify    # load, integrity-verify, execute: exit 0/1/2
```

## What to read next

- [What a blueprint is](what-a-blueprint-is.md) — the artifact's shape
- [The error guide](errors.md) — every code, what it means, what the
  host does
- [Host integration](host-integration.md) — reconcile into an import
  path

## What this package will never do

Grant authority. A fully green verification is structural evidence;
identity, tenancy, live policy, effect ownership, execution, billing,
and evaluation truth remain yours. See the specification's
non-authorizing boundary.
