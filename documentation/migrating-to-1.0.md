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

Use the documented functions in the [Elixir reference](https://agent-blueprint-protocol.hexdocs.pm/1.0.1-rc.1/). For TypeScript, use the package-root exports in the [TypeScript guide](typescript.md).

## 6. Update package and release identity pins

Version 1.0 changes the registry digest and sets `verification_semantics_version` to `3`. The protocol revision remains `1`.

Before, pin the previous Hex release:

```elixir
  {:agent_blueprint_protocol, "~> 0.8.4"}
```

After, pin the 1.0 release:

```elixir
{:agent_blueprint_protocol, "~> 1.0.1-rc.1"}
```

For TypeScript, install the same version with `npm install @agent-blueprint-protocol/verifier@1.0.1-rc.1`. The Hex and npm packages carry the same version.

Before, install the previous npm release; after, install the 1.0 release:

```sh
npm install @agent-blueprint-protocol/verifier@0.8.4
npm install @agent-blueprint-protocol/verifier@1.0.1-rc.1
```

## 7. Use the preferred identifiers

Revision 1 accepts both `EdDSA` and `Ed25519` in the protected header. Producers should emit `Ed25519`:

```json
{"alg":"Ed25519"}
```

Use `io.github.baselabs/federation` for new federation artifacts. The previous `com.example/federation` namespace is deprecated and remains accepted throughout 1.x.

## 8. Supply host registrations and held schemas

Earlier integrations sometimes relied on example namespaces in the package registry. Version 1.0 ships only the active and deprecated federation registrations. Product and third-party namespaces belong in host support. Missing registration for a critical namespace denies with `extension_unknown_critical`; a missing held schema denies with `extension_schema_unavailable`.

Before (conceptual 0.8 excerpt), the host supplied revision support and relied on a compiled example entry:

```elixir
support = %AgentBlueprintProtocol.Negotiation.Support{revisions: MapSet.new([1])}
```

After, the host owns both registration and schema. This complete Elixir setup uses the same generic namespace and pin as the [worked negotiation example](extensions.md#register-a-namespace-with-the-host):

```elixir
alias AgentBlueprintProtocol.{Canonicalization, Digest, ExtensionRegistry, Json, Negotiation}
namespace = "com.example.vendor/record"
{:ok, schema} = Json.decode(~s({"additionalProperties":false,"properties":{"value":{"type":"string"}},"required":["value"],"type":"object"}))
{:ok, schema_bytes} = Canonicalization.encode(schema)
pin = Digest.to_tagged(Digest.hash(:extension_schema, schema_bytes))
support = %Negotiation.Support{
  revisions: MapSet.new([1]),
  registry: %{namespace => %ExtensionRegistry{
    namespace: namespace, owner: "ExampleVendor", state: :active,
    criticality: :critical, schema_digest: pin,
    a2a_uri: "https://example.com/extensions/record", promoted_at_revision: nil
  }},
  schemas: %{namespace => schema}
}
```

Before (TypeScript excerpt): `const support = {revisions: new Set([1]), coreFields: new Set(), registry: {}, schemas: {}};`.

After (TypeScript excerpt; supply this `Support` to `negotiate` or `reconcile`):

```ts
import type { Support } from "@agent-blueprint-protocol/verifier";
const namespace = "com.example.vendor/record";
const support: Support = {
  revisions: new Set([1]), coreFields: new Set(),
  registry: {[namespace]: {
    owner: "ExampleVendor", state: "active", criticality: "critical",
    schemaDigest: "sha-256:WkeuAuJF6Sw3MWlcvPoV7JLBSPoipNSCFMOk8jCHJYo",
    a2aUri: "https://example.com/extensions/record", promotedAtRevision: null
  }},
  schemas: {[namespace]: {additionalProperties: false,
    properties: {value: {type: "string"}}, required: ["value"], type: "object"}}
};
```

The [complete registration examples](extensions.md#register-a-namespace-with-the-host) construct a preview, show `critical_extensions`/`criticalExtensions`, and assert the missing-registration denial in both languages. A host cannot alter a compiled entry's criticality or schema pin.

## 9. Update carrier producers and rebuild edited artifacts

| Carrier | Accepted legacy input | Active output |
|---|---|---|
| A2A metadata URI | `https://example.com/extensions/federation` | `https://baselabs.github.io/agent_blueprint_protocol/extensions/federation` |
| MCP `_meta` key | `com.example/federation` | `io.github.baselabs/federation` |

Old input remains accepted throughout 1.x; new carrier output uses the active spelling. Intentionally changing an artifact's extension namespace changes content: rebuild its digest and recreate affected signatures. Changing a Blueprint also requires rebuilding any Manifest that references that release's digest. Do not relabel received bytes and treat the old signature as current.

## Migration checklist and one integration

- Replace deep imports and internal result fields with package-root imports and `value`/`error`.
- Match typed denials and member paths; use verified attributes returned by signature checks.
- Read signature checks for both artifact subjects and retain skipped binding checks and unknown detail branches.
- Supply host registrations, held schemas, all thirteen host bounds, trusted public keys, and independent observations.
- Emit active carrier keys; rebuild intentionally edited artifacts and their affected signatures.
- Update package pins and release identities together; protocol revision stays `1`, verification semantics becomes `3`.

Before (0.8 TypeScript integration excerpt):

```ts
import { decode } from "@agent-blueprint-protocol/verifier/dist/verifier/blueprint.js";
const oldResult = decode(blueprintBytes);
if (oldResult.ok) useBlueprint(oldResult.v);
else rejectCode(oldResult.e);
```

After, follow the [installed-package setup](typescript.md#install-and-decode) and save this complete replacement as `migrate.mts`. Use the [TypeScript check/run commands](typescript.md#run-the-typescript-examples), then run `node migrate.mts`. It decodes both downloaded files, supplies all host inputs, handles denials, and prints both signature subjects and the unverified surfaces. The sample pair is unsigned, so both signature flags are `false`:

```ts
import { readFileSync } from "node:fs";
import {
  decodeBlueprint,
  decodeDeployment,
  reconcile,
  type BoundSet,
  type Inputs,
  type Support,
} from "@agent-blueprint-protocol/verifier";

const blueprint = decodeBlueprint(readFileSync("examples/echo-blueprint.json"));
const deployment = decodeDeployment(readFileSync("examples/echo-deployment.json"));
if (!blueprint.ok) throw new Error(blueprint.error.code);
if (!deployment.ok) throw new Error(deployment.error.code);

const support: Support = {
  revisions: new Set([1]),
  coreFields: new Set(),
  registry: {},
  schemas: {},
};
const hostBounds: BoundSet = {
  max_attempts: 3,
  max_concurrency: 2,
  max_cost: { amount: 1000, currency: "USD" },
  max_depth: 8,
  max_descendants: 64,
  max_elapsed_ms: 60000,
  max_fan_out: 4,
  max_tokens: 100000,
  classification_ceiling: { ordinal: "internal", markers: [] },
  disclosure_ceiling: "summary",
  effect_impact_ceiling: "ordinary",
  authority_trait: "none",
  approval_trait: "none",
};
const inputs: Inputs = {
  hostBounds,
  support,
  keys: [],
  protectedClamp: "acknowledge",
  observations: { now: null, maxAttestationAgeMs: null, observed: {} },
};
const result = reconcile(blueprint.value, deployment.value, inputs);
if (!result.ok) throw new Error(result.error.code);
const signatures = ["blueprint", "deployment"].map(artifact => {
  const check = result.value.checks.find(c => c.surface === "signatures" &&
    c.subject.length === 1 && c.subject[0] === artifact);
  return {artifact, verified: check?.verified === true};
});
console.log(signatures, result.value.not_verified);
```

Replace these fixture bounds with configured host limits and supply trusted keys and independent observations before using this in an application. Add the registration from step 8 when your artifacts carry that critical namespace. Keep a default branch for unfamiliar JSON detail variants as the [evidence reader](typescript.md#read-json-evidence-details) shows, and check the actual producer files in [CI](verifying-in-ci.md).

## Next steps

- [Quickstart](quickstart.md)
- [TypeScript guide](typescript.md)
- [Stability policy](stability.md)
- [Upgrading and identity guidance](upgrading.md)
