# Extensions

This guide is for producers and consumers that exchange namespaced extension data. You will learn how negotiation handles registry states and how to look up or register a namespace.

An extension is a namespaced value in an artifact's `extensions` member. A registry entry records its criticality and lifecycle state.

## Negotiation outcomes

| Registry state | Declared critical | Declared optional |
|---|---|---|
| Active, criticality matches | Added to `critical_extensions` after schema validation. | Added to `optional_retained`. |
| Active, criticality differs | `extension_criticality_conflict`. | `extension_criticality_conflict`. |
| Deprecated, criticality matches | Added to `critical_extensions`, notice `extension_deprecated`. | Added to `optional_retained`, notice `extension_deprecated`. |
| Deprecated, criticality differs | `extension_criticality_conflict`. | `extension_criticality_conflict`. |
| Retired (either registered criticality) | `extension_retired`. | Added to `optional_retained`, notice `extension_retired`. |
| Reserved (either registered criticality) | `extension_unknown_critical`. | Added to `optional_retained`, notice `extension_unknown_optional_retained`. |
| Unknown namespace | `extension_unknown_critical`. | Added to `quarantined_extensions`, notice `extension_unknown_optional_retained`. |

For active or deprecated critical entries, success also requires the held schema, a matching schema digest, and a schema-valid body. The common payload checks still apply in every state. The table describes Elixir outcome field names; npm uses `criticalExtensions`, `optionalRetained`, and `quarantinedExtensions`.

For example, `io.github.baselabs/federation` is active and critical. The legacy `com.example/federation` namespace is deprecated and remains recognized. An unregistered optional value is retained but is not evidence that its meaning is known.

## Read the registry

Use `registered_extensions/0` to inspect registry entries. Match a namespace and use the returned fields you need:

From `iex -S mix` in any project with the dependency installed, run:

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

{:ok, schema} =
  Json.decode(
    ~s({"additionalProperties":false,"properties":{"value":{"type":"string"}},"required":["value"],"type":"object"})
  )

{:ok, bytes} = Canonicalization.encode(schema)
pin = Digest.to_tagged(Digest.hash(:extension_schema, bytes))

support = %Negotiation.Support{
  revisions: MapSet.new([1]),
  registry: %{
    namespace => %ExtensionRegistry{
      namespace: namespace,
      owner: "ExampleVendor",
      criticality: :critical,
      state: :active,
      schema_digest: pin,
      a2a_uri: "https://example.com/extensions/record",
      promoted_at_revision: nil
    }
  },
  schemas: %{namespace => schema}
}
```

Now negotiate a preview value carrying this critical body. Continue in the same session. The example comes from the installed Hex package:

```elixir
dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()

{:ok, {:object, members}} =
  File.read!(Path.join(dependency_root, "examples/echo-blueprint.json")) |> Json.decode()

regions =
  {:object,
   [
     {"critical", {:object, [{namespace, {:object, [{"value", {:string, "one"}}]}}]}},
     {"optional", {:object, []}}
   ]}

value = {:object, List.keystore(members, "extensions", 0, {"extensions", regions})}
{:ok, outcome} = AgentBlueprintProtocol.negotiate(value, support)

{outcome.critical_extensions, outcome.optional_retained, outcome.quarantined_extensions,
 outcome.notices}

{:error, %AgentBlueprintProtocol.Error{code: :extension_unknown_critical}} =
  AgentBlueprintProtocol.negotiate(value, %{support | registry: %{}})

{:ok, _draft} =
  AgentBlueprintProtocol.Blueprint.from_value(value, %{
    authored_extensions: outcome.critical_extensions
  })
```

The outcome tuple is `{["com.example.vendor/record"], [], [], []}`.

Negotiation checks declared semantics, not the content digest. This edited preview still needs its digest recomputed and affected signatures recreated before encoding a finished artifact; follow [compose and sign](compose-and-sign.md).

The TypeScript package-root `Support` type exposes the same fields. This pin
is the domain-separated SHA-256 digest of the same canonical schema:

```ts
import { readFileSync } from "node:fs";
import { decodeBlueprint, negotiate, type Support } from "@agent-blueprint-protocol/verifier";

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

Save the preceding TypeScript block as `registration.mts` and append this block. Use the [sample download and TypeScript run instructions](typescript.md#run-the-typescript-examples), then run `node registration.mts`. It prints the critical namespace followed by `extension_unknown_critical`:

```ts
const decoded = decodeBlueprint(readFileSync("examples/echo-blueprint.json"));
if (!decoded.ok) throw new Error(decoded.error.code);
const preview = {...decoded.value, value: {...decoded.value.value,
  extensions: {critical: {[namespace]: {value: "one"}}, optional: {}}
}};
const outcome = negotiate(preview, support);
if (!outcome.ok) throw new Error(outcome.error.code);
console.log(outcome.value.criticalExtensions);
const absent = negotiate(preview, {...support, registry: {}});
if (absent.ok) throw new Error("Expected a missing-registration denial");
console.log(absent.error.code);
```

Use the resulting support input with `negotiate` or `reconcile`. Hosts manage
their entries' reserved, active, deprecated, and retired states. The
[registry operations process](../spec/registry/OPERATIONS.md) describes
registration syntax and the process for the protocol's shipped entries.

## Next steps

- [Read the extension registry rules](../spec/protocol.md#8-extension-registry)
- [Read the error reference](errors.md)
- [Explore the extension example](examples.md#extension-blueprint)
