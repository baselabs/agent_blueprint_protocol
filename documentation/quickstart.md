# Quickstart — verify your first artifact

From nothing to a green verification in minutes. No heavyweight gates —
one dependency and `iex`.

## 1. Install

```bash
mix new my_verification && cd my_verification
```

Add the dependency:

```elixir
defp deps do
  [
    {:agent_blueprint_protocol, "~> 0.4.0"}
  ]
end
```

Fetch and start:

```bash
mix deps.get
iex -S mix
```

## 2. Verify

In `iex`, verify the canonical bytes of a value round-trip:

```elixir
{:ok, bytes} = AgentBlueprintProtocol.Canonicalization.encode({:object, [{"a", {:integer, 1}}]})
AgentBlueprintProtocol.Json.decode(bytes) # => {:ok, {:object, [{"a", {:integer, 1}}]}}
AgentBlueprintProtocol.decode_blueprint(bytes) # => {:error, :unknown_member}
```

## 3. See a typed denial

The last line above: `a` is not a Blueprint member — the closed world
denies `:unknown_member` before any digest work. Typed errors, never
repairs.

## 4. The corpus (what the package proves about itself)

The package you installed ships a 94-case conformance corpus, and its
release was gated on that corpus passing plus a mutation gate (the
corpus must catch seven named implementation breaks) and byte-agreement
with an independent TypeScript verifier. You consume an already
verified package; the corpus and the standalone verification kit (the
verifier + corpus tarball) are attached to every git release tag if
you want to re-run the evidence yourself.

That is the whole verification surface: canonical bytes, typed
denials, a digest-bound corpus — and no authority granted anywhere.
