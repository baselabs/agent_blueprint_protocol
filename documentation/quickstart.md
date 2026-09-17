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
    {:agent_blueprint_protocol, "~> 0.7.0"}
  ]
end
```

Fetch and start:

```bash
mix deps.get
iex -S mix
```

## 2. Verify a real artifact

Fetch the shipped example — a byte-exact conformance-corpus case — and
verify it. The package requires Elixir 1.19+ and nothing else; it is
built and tested across the supported OTP set (27/28/29).

```bash
mkdir -p examples
curl -fsSL -o examples/echo-blueprint.json \
  https://raw.githubusercontent.com/baselabs/agent_blueprint_protocol/main/examples/echo-blueprint.json
```

In `iex`:

```elixir
bytes = File.read!("examples/echo-blueprint.json")
{:ok, blueprint} = AgentBlueprintProtocol.decode_blueprint(bytes)
{:ok, same} = AgentBlueprintProtocol.canonical_bytes(blueprint)
same == bytes # => true
```

That green `true` is the full pipeline: canonical bytes verified, all 18
members validated against the registry, the portability scan passed, the
content digest matched — and the decode round-trips byte-exactly, because
the bytes ARE the artifact's identity. A typed fact — never authority.

## 3. See a typed denial

The closed world denies unknowns before any digest work — with a value
that is NOT a Blueprint at all:

```elixir
{:ok, bytes} = AgentBlueprintProtocol.Canonicalization.encode({:object, [{"a", {:integer, 1}}]})
AgentBlueprintProtocol.Json.decode(bytes) # => {:ok, {:object, [{"a", {:integer, 1}}]}}
AgentBlueprintProtocol.decode_blueprint(bytes) # => {:error, :unknown_member}
```

`a` is not a Blueprint member — the denial is typed, and there is never a
silent repair.

## 4. The corpus (what the package proves about itself)

The package you installed ships a 96-case conformance corpus, and its
release was gated on that corpus passing plus a mutation gate (the
corpus must catch seven named implementation breaks) and byte-agreement
with an independent TypeScript verifier. You consume an already
verified package; the corpus and the standalone verification kit (the
verifier + corpus tarball) are attached to every git release tag if
you want to re-run the evidence yourself.

That is the whole verification surface: canonical bytes, typed
denials, a digest-bound corpus — and no authority granted anywhere.
