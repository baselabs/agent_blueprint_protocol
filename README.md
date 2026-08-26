# Agent Blueprint Protocol

Agent Blueprint Protocol is a portable, non-authorizing contract for describing
an agent capability and binding one immutable release to an execution
environment.

The public package is the reference implementation for two
language-neutral artifacts:

- **Blueprint Core** — stable identity, typed ports, logical capability
  requirements, bounds, evidence commitments, and registered extensions.
- **Deployment Manifest** — environment-local tool, principal, data,
  authority, effect, evaluation, and exact-build bindings for one Blueprint
  release digest.

Protocol validity never grants authority. A consuming host remains responsible
for identity, tenancy, policy, live authorization, effect ownership, execution,
and evidence retention.

## Installation

```elixir
def deps do
  [
    {:agent_blueprint_protocol, "~> 0.1.0"}
  ]
end
```

The package has **zero production dependencies**, no application callback, and
no supervision tree.

## What it provides

Decoding and validation (every result is a typed fact or a typed denial —
never an authorization decision):

- `decode_blueprint/2` — bounded, fail-closed decode of a Blueprint: canonical
  byte verification, registry validation, portability scan, digest comparison.
- `decode_deployment/2` — the same pipeline for a Deployment Manifest bound to
  one Blueprint release digest.
- `decode_federation_envelope/2` — the 23-member federation task envelope
  through the shared registry engine; `federation_mapping/0` returns the
  A2A/MCP Tasks field mapping as data.
- `canonical_bytes/1` — the exact canonical (JCS) wire bytes of a decoded
  artifact.

Semantics:

- `negotiate/2` — the evolution gate: revision sets, required core fields,
  and the positional extension state machine (unknown critical denies,
  unknown optional quarantines byte-exactly).
- `intersect/1` — the bounds algebra: the pointwise narrowest intersection of
  Blueprint bounds, Deployment `host_bounds`, and host policy; protected
  narrowings deny or clamp-with-evidence, never silently.
- `verify_compatibility/2` — identity-exact matching of manifest build
  identities against host-observed identities.
- `reconcile/3` — the one call per import: the pinned eight-stage pass
  (canonical, digest, negotiation, structure, portability, signatures, bind,
  bounds), reject-or-annotate, never repair, under host-supplied inputs.

Tooling: `mix conformance.verify` executes the shipped 94-case corpus;
`mix conformance.mutations` re-proves the corpus catches named implementation
breaks; `mix verifier.agreement` byte-agrees the Elixir runner with the
independent TypeScript verifier.

## Status

The protocol API, schemas, canonicalization profile, extension registry,
and conformance corpus are implemented and gated locally: 899 tests
(59 properties) at 100% coverage, zero Dialyzer errors, `--strict`
Credo clean, a 94-case conformance corpus with a mutation gate, and a
byte-agreement gate against an independent second-language verifier.
The normative protocol document, [`docs/protocol.md`](docs/protocol.md),
ships in the Hex archive. Every build gate's recorded red proof is the
requirement
map ([`docs/design/requirement-map.md`](https://github.com/baselabs/agent_blueprint_protocol/blob/main/docs/design/requirement-map.md))
— public in this repository, deliberately not in the archive (its verbatim
red receipts quote the very internal tokens the publish guard bans from
the archive), and `mix release.candidate` re-derives its completeness
from the live project on every run.

The 0.x series is the public pre-1.0 line: shipped contracts may
change within 0.x under pre-1.0 conventions, and every contract change
lands with a red-capable test.

## Intended properties

- Language-neutral canonical artifacts with bounded parsing.
- Fail-closed protocol revision and required-field handling.
- Bounds that can narrow host policy but can never widen it.
- Critical extensions that deny when unsupported; optional extensions that
  round-trip without execution.
- Exact compatibility manifests and red-capable tamper/downgrade corpora.
- Zero third-party/Hex production dependencies and no supervision tree.
- No product-specific tenant, key, grant, endpoint, database, provider, or
  engine identifiers in portable artifacts.

## Development

Built and tested against Elixir 1.20.x on OTP 29.x — the single Elixir/OTP
target exercised in CI. Broader target support is not claimed until its own
CI receipts exist.

```bash
mix deps.get
mix quality
```

`mix quality` runs dependency audits, formatting, warnings-as-errors
compilation, Credo, tests with the 100% coverage threshold, the
conformance corpus and its mutation gate, the second-language verifier
agreement gate, Dialyzer, documentation with warnings-as-errors, and the
release-candidate check (requirement-map completeness plus protocol-doc
coupling). Every gate carries a recorded red proof — see the requirement map at
`docs/design/requirement-map.md` in this repository.

### Conformance corpus

The package ships a portable conformance corpus (`priv/conformance/`) — 94
cases covering every required cell of the 16-surface × 31-class applicability
floor, full-registry golden artifacts, RFC 8785 number vectors, and
deterministic Ed25519 fixtures. Run it:

```bash
mix conformance.verify    # loads, integrity-verifies, and executes the corpus
mix conformance.mutations # breaks the implementation at named points; the corpus must go red
```

The loader is pure over `%{path => binary}` and refuses corrupted, incomplete,
or empty corpora with typed errors; the report refuses a vacuous green. The
corpus is regenerated by `MIX_ENV=test mix run --no-start
scripts/generate_conformance_corpus.exs`, which refuses to write a corpus that
does not verify.

### Second-language verifier

`conformance/verifier/` is a repo-side TypeScript implementation (Node ≥ 24,
`node:` builtins only, zero npm runtime deps — never shipped in the Hex
archive) that independently recomputes every corpus verdict and integrity
check: its own bounded JSON scanner with duplicate rejection and the
integer-window rule, its own JCS canonicalizer (number digits anchored to the
native ECMAScript serializer, member sort by UTF-16 code units), domain-
separated digests, detached-JWS Ed25519 verification through `node:crypto`
with small-order key rejection, and the negotiation, bounds-algebra,
compatibility, and federation semantics. Run it:

```bash
node conformance/verifier/cli.ts --corpus priv/conformance  # exit 0/1/2, report bytes on stdout
node conformance/verifier/self_checks.ts                    # RFC 8785 Appendix B, window matrix,
                                                            # Ed25519 keys, stored JOSE vectors
mix verifier.agreement                                     # byte-agrees the TS report with the
                                                            # escript's (repo AND built archive),
                                                            # runs the self-checks, and proves three
                                                            # seeded reds fire
```

The agreement gate is part of `mix quality`: the two implementations must
produce byte-identical JCS reports over the same corpus, and node ≥ 24 is a
hard prerequisite of the gate.

## Security

See [`SECURITY.md`](SECURITY.md). A successful verifier result is
structural evidence only, never an authorization decision.

## License

Apache License 2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
