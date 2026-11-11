# Migrating to 1.0

This guide is for Elixir and TypeScript consumers moving from 0.8.x to 1.0. You will update imports, denial handling, evidence reads, and package pins.

The [glossary](glossary.md) defines the artifact and verification terms used here. The [stability policy](stability.md) describes the supported 1.x contract.

## 1. Import TypeScript functions from the package root

Deep imports no longer resolve. Replace internal imports and names with the package-root exports:

| Previous import and symbol | Package-root export |
| --- | --- |
| `dist/verifier/blueprint.js`: `decode` | `decodeBlueprint` |
| `dist/verifier/deployment.js`: `decode` | `decodeDeployment` |
| `dist/verifier/federation.js`: `decode` | `decodeFederationEnvelope` |
| Artifact modules: `canonicalBytes` | `canonicalBytes` |
| `dist/verifier/negotiation.js`: `negotiate` | `negotiate` |
| `dist/verifier/bounds_algebra.js`: `intersect` | `intersect` with a `Sources` object |
| `dist/verifier/compatibility.js`: `verify` | `verifyCompatibility` |
| `dist/verifier/signature.js`: `verify` | `verifySignature` |
| `dist/verifier/corpus.js`: `load` | `loadCorpus` |
| `dist/verifier/runner.js`: `run` | `runCorpus` |
| `dist/verifier/report.js`: `build`, `toBytes` | `buildReport`, `buildResultsDocument` |

The TypeScript blocks below are excerpts. Elixir's public decode call is unchanged.

Before, TypeScript imported an internal module and read `v`:

```ts
import { decode } from "@agent-blueprint-protocol/verifier/dist/verifier/blueprint.js";
const result = decode(bytes);
if (result.ok) result.v;
```

After, import from the package root and read `value`:

```ts
import { decodeBlueprint } from "@agent-blueprint-protocol/verifier";
const result = decodeBlueprint(bytes);
if (result.ok) result.value;
```

The root library returns `{ok, value, error}` results. Import only from `@agent-blueprint-protocol/verifier`.

## 2. Match typed Elixir errors

Every fallible public Elixir operation returns `{:error, %AgentBlueprintProtocol.Error{}}`.

The following code blocks are excerpts.

Before, Elixir callers matched the error atom directly:

```elixir
{:error, :unknown_member} = AgentBlueprintProtocol.decode_blueprint(bytes)
```

After, match the typed error struct:

```elixir
{:error, %AgentBlueprintProtocol.Error{code: :unknown_member}} =
  AgentBlueprintProtocol.decode_blueprint(bytes)
```

The package-root TypeScript result uses the `error` object:

```ts
const result = decodeBlueprint(bytes);
if (!result.ok) {
  result.error.code;
  result.error.subject;
}
```

Before, the internal TypeScript result used `e` for an error:

```ts
const result = decode(bytes);
if (!result.ok) result.e;
```

Decoder ceiling codes use `{:ceiling, key}` in Elixir and `ceiling:<key>` in TypeScript:

Before (Elixir excerpt):

```elixir
{:error, {:ceiling, :depth}} = AgentBlueprintProtocol.Bounds.new(%{depth: 0})
```

After (Elixir excerpt):

```elixir
{:error, %AgentBlueprintProtocol.Error{code: {:ceiling, :depth}}} =
  AgentBlueprintProtocol.Bounds.new(%{depth: 0})
```

Before, the internal TypeScript result used `e`:

```ts
const result = decode(bytes);
if (!result.ok) result.e;
```

After, its public result uses a typed string code:

```ts
import type { ErrorCode } from "@agent-blueprint-protocol/verifier";
const code: ErrorCode = "ceiling:depth";
```

TypeScript represents the same ceiling as a string code. These TypeScript blocks are excerpts.

Denial details are `nil`; the schema-derived path is in `subject`. These Elixir excerpts show a protected-bound denial.

Before, callers read the denial detail:

```elixir
{:error, %AgentBlueprintProtocol.Error{code: :protected_bound_clamp_denied, detail: detail}} =
  AgentBlueprintProtocol.reconcile(blueprint, deployment, inputs)
```

After, `detail` is `nil` and the member path is in `subject`:

```elixir
{:error, %AgentBlueprintProtocol.Error{code: :protected_bound_clamp_denied, detail: nil, subject: subject}} =
  AgentBlueprintProtocol.reconcile(blueprint, deployment, inputs)
```

Value-returning helpers keep their success values. Check their documented error branch instead of matching a bare reason.

## 3. Read typed evidence details

Unsigned artifacts and skipped observations are represented as unverified. Signature details list distinct key identifiers. Binding details list performed and skipped checks, and every unverified surface appears in `not_verified`.

The following code blocks are excerpts.

Before, Elixir callers read a summary string:

```elixir
%{surface: :signatures, detail: "1 signature(s) verified"} = check
```

After, signature details have a typed structure and skipped surfaces are explicit:

```elixir
%{surface: :signatures, detail: %AgentBlueprintProtocol.Evidence.Signatures{key_ids: key_ids}} = check
evidence.not_verified
```

Before, the internal TypeScript result used `v` for its checks:

```ts
if (result.ok) result.v.checks;
```

After, inspect `value` and read `not_verified`:

```ts
if (result.ok) {
  result.value.checks;
  result.value.not_verified;
}
```

Denial `detail` values are `nil`, including protected-bound denials. Read the member path from `subject`. An acknowledged narrowing appears as typed clamp evidence in a successful result.

## 4. Update signature verification handling

`Signature.verify/2` returns the verified attributes. The TypeScript root function is `verifySignature` and returns the same attributes through `value`. The following code blocks are excerpts.

Before, Elixir returned a status atom:

```elixir
{:ok, :verified} = AgentBlueprintProtocol.Signature.verify(entry, keys)
```

After:

```elixir
{:ok, %AgentBlueprintProtocol.Signature.Attributes{} = attributes} =
  AgentBlueprintProtocol.Signature.verify(entry, keys)
attributes.content_digest
```

Before, TypeScript imported `verify` from an internal module:

```ts
import { verify } from "@agent-blueprint-protocol/verifier/dist/verifier/signature.js";
const checked = verify(entry, keys);
```

After, import `verifySignature` from the package root and read its attributes:

```ts
const checked = verifySignature(entry, keys);
if (checked.ok) checked.value.contentDigest;
```

Repeated key identifiers in one artifact now deny with `invalid_constraint` during structure validation. The following excerpt assumes `bytes` contains an artifact with repeated identifiers:

```elixir
{:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
  AgentBlueprintProtocol.decode_blueprint(bytes)
```

TypeScript reports the matching code through its typed error. This block is an excerpt:

```ts
const result = decodeBlueprint(bytes);
if (!result.ok) result.error.code; // "invalid_constraint"
```

## 5. Use the documented public API

Implementation modules and helpers are not part of the supported public API.

In Elixir, these 0.8 modules and helpers are no longer documented: `AgentBlueprintProtocol.Extension`, `AgentBlueprintProtocol.Registry`, <code>AgentBlueprintProtocol.Conformance.Cli</code>, and helpers including `Blueprint.table/0`, `Deployment.table/0`, and `ExtensionRegistry.entry/1`. To look up a namespace, search `ExtensionRegistry.registered_extensions/0` as the [extensions guide](extensions.md#read-the-registry) shows. `Blueprint.decode/2` and the other functions in the Elixir reference remain public.

Before (TypeScript excerpt), use a deep import:

```ts
import { decode } from "@agent-blueprint-protocol/verifier/dist/verifier/blueprint.js";
const oldResult = decode(bytes);
```

After (TypeScript excerpt), use the package root:

```ts
import { decodeBlueprint } from "@agent-blueprint-protocol/verifier";
const newResult = decodeBlueprint(bytes);
```

Use the documented functions in the [Elixir reference](https://agent-blueprint-protocol.hexdocs.pm/1.0.0-rc.3/). For TypeScript, use the package-root exports in the [TypeScript guide](typescript.md).

## 6. Update package and release identity pins

Version 1.0 changes the registry digest and sets `verification_semantics_version` to `3`. The protocol revision remains `1`.

Before, pin the previous Hex release:

```elixir
  {:agent_blueprint_protocol, "~> 0.8.4"}
```

After, pin the 1.0 release:

```elixir
{:agent_blueprint_protocol, "~> 1.0.0-rc.3"}
```

For TypeScript, install the same version with `npm install @agent-blueprint-protocol/verifier@1.0.0-rc.3`. The Hex and npm packages carry the same version.

Before, install the previous npm release; after, install the 1.0 release:

```sh
npm install @agent-blueprint-protocol/verifier@0.8.4
npm install @agent-blueprint-protocol/verifier@1.0.0-rc.3
```

## 7. Use the preferred identifiers

Revision 1 accepts both `EdDSA` and `Ed25519` in the protected header. Producers should emit `Ed25519`:

```json
{"alg":"Ed25519"}
```

Use `io.github.baselabs/federation` for new federation artifacts. The previous `com.example/federation` namespace is deprecated and remains accepted throughout 1.x.

## Next steps

- [Quickstart](quickstart.md)
- [TypeScript guide](typescript.md)
- [Stability policy](stability.md)
- [Upgrading and identity guidance](upgrading.md)

The shipped registry contains only the two federation registrations. Hosts that
used earlier example namespaces supply their registrations and held schemas
through negotiation support, as shown in the [extensions guide](extensions.md).
