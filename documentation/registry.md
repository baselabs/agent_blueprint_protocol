# The registry guide

The compiled-in extension registry: six example-class namespaces, one
deprecated, one product-owned critical entry with an authored schema
pin. Registry content is a code release; there is no runtime registry
file — drift between shipped code and shipped registry is
unrepresentable.

## Governance

The governance-canonical SOURCE is `spec/registry/registry.json`,
bound to both compiled twins (the Elixir module and the TypeScript
verifier's registry) and the corpus index by the registry-equality
gate: all four carriers must carry the same canonical digest.

## Lifecycle

reserved → active → deprecated → retired. Promotion to critical
requires a protocol revision increment; demotion does not; a retired
namespace is never reused. Deprecated entries keep their artifacts
verifiable with a typed notice.

## Pinning

The registry's digest is bound into the corpus index but not into
artifact digests — an artifact stays verifiable against a registry
that legitimately gained entries after it was produced. Hosts wanting
pinning use `build_identities`.
