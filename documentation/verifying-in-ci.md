# Verify in CI

This guide has two paths: producers check their own files; implementers check corpus agreement. A corpus pass does not inspect your project's artifacts.

## Check artifacts produced by your project

Use Node.js 24 or newer. These commands read the named files and print canonical JSON reports on stdout (without a trailing newline):

```sh
npx @agent-blueprint-protocol/verifier@1.0.1 --artifact abp-artifacts/blueprint.json
npx @agent-blueprint-protocol/verifier@1.0.1 --artifact abp-artifacts/deployment.json
```

Use the filenames saved by the [producer walkthrough](compose-and-sign.md#4-save-reload-and-check-in-ci), or substitute your build outputs. A valid report has `format: "agent-blueprint-protocol-artifact-report"`, `verdict: "valid"`, and `kind: "blueprint"` or `"deployment"`. Invalid reports have `verdict: "invalid"` and each decoder's denial code. Exit `0` means a valid artifact, `1` invalid, `2` unreadable input/usage error, and `3` internal error. Treat every nonzero status as failure.

Artifact mode performs canonical-byte, structure, portability, and (for Blueprint/Manifest) digest checks. It does not supply trusted keys, verify signatures cryptographically, compare a pair, discover descriptors, or intersect host bounds.

A minimal GitHub Actions workflow, for a project that commits the two canonical files, is:

```yaml
name: Check protocol artifacts
on: [push, pull_request]
jobs:
  artifacts:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '24'
      - run: npx --yes @agent-blueprint-protocol/verifier@1.0.1 --artifact abp-artifacts/blueprint.json
      - run: npx --yes @agent-blueprint-protocol/verifier@1.0.1 --artifact abp-artifacts/deployment.json
```

If your project generates artifacts, run its producer build before these checks. An artifact check needs the actual output files.

### Check a pair with host inputs

Install `@agent-blueprint-protocol/verifier@1.0.1`. Save this complete script as `verify-pair.mjs`. The third argument is a host-owned JSON configuration file. Public keys and observations must come from the host's trusted inventory; copying the artifact's declarations would only demonstrate equality. Do not put private keys in this file.

```js
import { readFileSync } from "node:fs";
import { decodeBlueprint, decodeDeployment, reconcile } from "@agent-blueprint-protocol/verifier";

const [blueprintPath, deploymentPath, configPath] = process.argv.slice(2);
if (!blueprintPath || !deploymentPath || !configPath) {
  throw new Error("Usage: node verify-pair.mjs <blueprint.json> <deployment.json> <host-inputs.json>");
}
const config = JSON.parse(readFileSync(configPath, "utf8"));
const blueprint = decodeBlueprint(readFileSync(blueprintPath));
const deployment = decodeDeployment(readFileSync(deploymentPath));
if (!blueprint.ok) throw new Error(blueprint.error.code);
if (!deployment.ok) throw new Error(deployment.error.code);
const result = reconcile(blueprint.value, deployment.value, {
  hostBounds: config.hostBounds,
  support: {
    revisions: new Set(config.revisions), coreFields: new Set(config.coreFields),
    registry: config.registry, schemas: config.schemas,
  },
  keys: config.keys.map(key => ({
    keyId: key.keyId, algorithm: "ed25519", key: Buffer.from(key.keyBase64url, "base64url"),
  })),
  protectedClamp: config.protectedClamp,
  observations: config.observations,
});
if (!result.ok) throw new Error(result.error.code);
const evidence = result.value;
for (const artifact of ["blueprint", "deployment"]) {
  const signature = evidence.checks.find(c => c.surface === "signatures" &&
    c.subject.length === 1 && c.subject[0] === artifact);
  if (config.requireSignatures && signature?.verified !== true) {
    throw new Error("Required artifact signature remains unverified");
  }
}
const binding = evidence.checks.find(c => c.surface === "bind" &&
  c.subject.length === 1 && c.subject[0] === "deployment");
const detail = binding?.detail;
for (const kind of config.requiredBindingChecks) {
  if (detail === null || typeof detail !== "object" || Array.isArray(detail) ||
      !Array.isArray(detail.checked) || !detail.checked.includes(kind)) {
    throw new Error("Required binding check remains unverified");
  }
}
console.log(JSON.stringify({
  effective_bounds: evidence.effective_bounds, clamps: evidence.clamps,
  not_verified: evidence.not_verified,
}));
```

This example `host-inputs.json` is runnable with the unsigned samples downloaded by the [TypeScript quickstart](typescript.md#install-and-decode). It deliberately requires no signatures or optional binding observations:

```json
{
  "revisions": [1], "coreFields": [], "registry": {}, "schemas": {}, "keys": [],
  "hostBounds": {
    "max_attempts": 2, "max_concurrency": 2,
    "max_cost": {"amount": 1000, "currency": "USD"},
    "max_depth": 8, "max_descendants": 64, "max_elapsed_ms": 60000,
    "max_fan_out": 4, "max_tokens": 100000,
    "classification_ceiling": {"ordinal": "internal", "markers": []},
    "disclosure_ceiling": "none", "effect_impact_ceiling": "ordinary",
    "authority_trait": "none", "approval_trait": "none"
  },
  "protectedClamp": "acknowledge",
  "observations": {"now": null, "maxAttestationAgeMs": null, "observed": {}},
  "requireSignatures": false,
  "requiredBindingChecks": []
}
```

```sh
node verify-pair.mjs examples/echo-blueprint.json examples/echo-deployment.json host-inputs.json
```

For signed producer output, populate `keys` with trusted `{keyId, keyBase64url}` public-key records and set `requireSignatures` to `true`. Supply independent descriptor digests, a clock, and maximum age as described in [host integration](host-integration.md); require `binding_descriptors` and `binding_staleness` through `requiredBindingChecks` when your CI policy needs both. Run `node verify-pair.mjs abp-artifacts/blueprint.json abp-artifacts/deployment.json host-inputs.json` as an additional CI step. The script exits nonzero on decode/reconciliation denial or a required check left unverified. Its summary is ordinary JSON, not a canonical conformance results document, and still leaves host-owned decisions with your application.

## Check a verifier implementation

The corpus contains shared inputs and expected results. A passing run establishes agreement on those cases.

### Elixir

From the repository root, run the Mix alias to build and execute the Elixir conformance runner:

```sh
mix conformance.verify
```

To save the per-case results document, build the escript and run it with the results option:

```sh
mix escript.build
./agent_blueprint_protocol_conformance --results --corpus priv/conformance > results.json
```

The command writes the canonical results document to standard output and a corpus identity line to standard error.

### npm

From the repository root, run the npm CLI against the repository corpus:

```sh
npx @agent-blueprint-protocol/verifier@1.0.1 --results --corpus ./priv/conformance > results.json
```

The results document has the format name, corpus and registry digests, and one result row per case. It contains no implementation identity.

## Exit codes

| Command | Exit | Meaning |
|---|---:|---|
| Elixir corpus runner | 0 | All cases agree. |
| Elixir corpus runner | 1 | At least one case disagrees. |
| Elixir corpus runner | 2 | Usage, read, or corpus-integrity failure. |
| npm corpus runner | 0 | Agreement, a valid artifact, help, or version output. |
| npm corpus runner | 1 | Disagreement or invalid artifact. |
| npm corpus runner | 2 | Usage, read, or corpus-integrity failure. |
| npm corpus runner | 3 | Internal invariant failure. |
| External harness | 0 | All results agree. |
| External harness | 2 | Usage, corpus-integrity, or claim-input failure. |
| External harness | 3 | Internal error. |
| External harness | 10 | Handshake mismatch. |
| External harness | 11 | Duplicate response identifier. |
| External harness | 12 | A successful adapter exit omitted a response. |
| External harness | 13 | Extra response. |
| External harness | 14 | Response out of order or an unexpected identifier. |
| External harness | 15 | Malformed response line or response shape. |
| External harness | 16 | Response line exceeded its size limit. |
| External harness | 17 | Response missed its deadline. |
| External harness | 18 | Adapter could not start, exited early, or returned a nonzero status. |
| External harness | 19 | Result disagreed with the expected projection. |

The [runner contract](../spec/conformance/runner.md) defines result projections and runner statuses. The [execution protocol](../spec/conformance/execution.md) defines harness responses and exit codes.

### Check another implementation

Copy the corpus to `./conformance` from `node_modules/@agent-blueprint-protocol/verifier/dist/corpus/` or the release asset's `conformance/` directory. Then run the npm harness with the adapter executable after `--`, replacing `./example-adapter` with the implementation's adapter.

```sh
npx @agent-blueprint-protocol/verifier@1.0.1 conformance run --corpus ./conformance --results results.json -- ./example-adapter
```

The harness compares the adapter's complete result projections. It writes a results document after a clean run.

For a complete installed-package run against the shipped adapter, including corpus acquisition and every unsigned-claim flag, follow the [terminal exchange walkthrough](conformance.md#run-the-external-exchange-in-a-terminal).

## Next steps

- [Conformance guide](conformance.md)
- [Architecture](architecture.md)
- [External execution protocol](../spec/conformance/execution.md)
