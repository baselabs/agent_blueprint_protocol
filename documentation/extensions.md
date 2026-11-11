# Extensions

This guide is for producers and consumers that exchange namespaced extension data. You will learn how negotiation handles registry states and how to look up or register a namespace.

An extension is a namespaced value in an artifact's `extensions` member. A registry entry records its criticality and lifecycle state.

## Negotiation outcomes

| Registry state | Declared critical | Declared optional |
|---|---|---|
| Active, criticality matches | Supported. | Retained and available to a consumer that supports it. |
| Active, criticality differs | Denied with `extension_criticality_conflict`. | Denied with `extension_criticality_conflict`. |
| Deprecated | Supported with an `extension_deprecated` notice. | Supported with an `extension_deprecated` notice. |
| Retired | Denied with `extension_retired`. | Retained with a typed notice. |
| Reserved or unknown | Denied with `extension_unknown_critical`. | Retained without interpretation. Reserved entries may include a typed notice. |

For example, `io.github.baselabs/federation` is active and critical. The legacy `com.example/federation` namespace is deprecated and remains recognized. An unregistered optional value is retained but is not evidence that its meaning is known.

## Read the registry

Use `registered_extensions/0` to inspect registry entries. Match a namespace and use the returned fields you need:

From an IEx session launched with `iex -S mix` at the repository root, run:

```elixir
entry = Enum.find(AgentBlueprintProtocol.ExtensionRegistry.registered_extensions(), &(&1.namespace == "io.github.baselabs/federation"))
state = case entry && {entry.criticality, entry.state} do {:critical, :active} -> :supported; {:critical, :deprecated} -> :deprecated; _unknown -> :unknown end
state # => :supported
```

Registry entries may gain fields or lifecycle names. When reading a state value, match known names and keep a catch-all branch.

## MCP `_meta` keys

An extension carried in MCP `_meta` uses its namespace as the metadata key. For registry registration, the namespace must have at least two lowercase prefix labels before the slash. Each label starts with a lowercase letter, ends with a lowercase letter or digit, and contains only lowercase letters, digits, or hyphens.

The name after the slash is nonempty. It starts and ends with a lowercase letter or digit. Its interior may also contain lowercase letters, digits, hyphens, underscores, and dots. These lowercase and two-label rules are stricter than the MCP key grammar. Prefixes whose second label is `mcp` or `modelcontextprotocol` are reserved.

## Register a namespace with the host

The packages ship only `io.github.baselabs/federation` (active) and
`com.example/federation` (deprecated). Both are critical and pin the protocol's
federation schema. The deprecated spelling remains supported throughout 1.x.

Supply product and third-party entries in the host support registry. No package
change is required. A critical entry declares its schema digest, and the host
supplies the matching schema document. For compiled entries, an override can
select lifecycle state but cannot change criticality or the schema pin.

In Elixir, compute the pin from canonical schema bytes under the
`extension_schema` digest domain:

```elixir
alias AgentBlueprintProtocol.{Canonicalization, Digest, ExtensionRegistry, Json, Negotiation}

namespace = "com.example.vendor/record"
{:ok, schema} = Json.decode(~s({"additionalProperties":false,"properties":{"value":{"type":"string"}},"required":["value"],"type":"object"}))
{:ok, bytes} = Canonicalization.encode(schema)
pin = Digest.to_tagged(Digest.hash(:extension_schema, bytes))

support = %Negotiation.Support{
  revisions: MapSet.new([1]),
  registry: %{namespace => %ExtensionRegistry{
    namespace: namespace, owner: "ExampleVendor", criticality: :critical,
    state: :active, schema_digest: pin,
    a2a_uri: "https://example.com/extensions/record", promoted_at_revision: nil
  }},
  schemas: %{namespace => schema}
}
```

The TypeScript package-root `Support` type exposes the same fields. This pin
is the domain-separated SHA-256 digest of the same canonical schema:

```ts
import type { Support } from "@agent-blueprint-protocol/verifier";

const namespace = "com.example.vendor/record";
const support: Support = {
  revisions: new Set([1]), coreFields: new Set(),
  registry: {[namespace]: {
    owner: "ExampleVendor", criticality: "critical", state: "active",
    schemaDigest: "sha-256:WkeuAuJF6Sw3MWlcvPoV7JLBSPoipNSCFMOk8jCHJYo",
    a2aUri: "https://example.com/extensions/record", promotedAtRevision: null
  }},
  schemas: {[namespace]: {
    additionalProperties: false, properties: {value: {type: "string"}},
    required: ["value"], type: "object"
  }}
};
```

Use the resulting support input with `negotiate` or `reconcile`. Hosts manage
their entries' reserved, active, deprecated, and retired states. The
[registry operations process](../spec/registry/OPERATIONS.md) describes
registration syntax and the process for the protocol's shipped entries.

## Next steps

- [Read the extension registry rules](../spec/protocol.md#8-extension-registry)
- [Read the error reference](errors.md)
- [Explore the extension example](examples.md#extension-blueprint)
