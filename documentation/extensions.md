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

## Register a namespace

Registration requires a namespace, an owner, and criticality. A critical entry also supplies a schema document whose canonical digest is pinned. The process updates the registry and both implementations, then checks the registry and corpus. See the [registry operations process](https://github.com/baselabs/agent_blueprint_protocol/blob/main/spec/registry/OPERATIONS.md) for the complete requirements.

## Next steps

- [Read the extension registry rules](../spec/protocol.md#8-extension-registry)
- [Read the error reference](errors.md)
- [Explore the extension example](examples.md#extension-blueprint)
