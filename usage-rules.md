# Usage rules for coding agents

Use these rules when generating or changing code that consumes Agent Blueprint Protocol. See the [glossary](documentation/glossary.md) for protocol terms.

| Rule | Do | Don't |
| --- | --- | --- |
| Decode before use. | `{:ok, bp} = AgentBlueprintProtocol.decode_blueprint(bytes)` | `AgentBlueprintProtocol.reconcile(bytes, deployment, inputs)` |
| Verification is never authorization. | `may_run = host_policy.allows?(evidence)` | `authorized = result.ok` |
| Match the typed Elixir denial. | `{:error, %AgentBlueprintProtocol.Error{code: code}} = result` | `{:error, code} = result` |
| Pass host keys explicitly. | `keys: host_public_keys` | `keys: []` for an artifact that has signatures |
| Use `reconcile/3` for imports and read `not_verified`. | `{:ok, evidence} = reconcile(bp, dep, inputs); evidence.not_verified` | `decode_blueprint(bytes)` as the whole import check |
| Prefer the `Ed25519` header identifier for new artifacts. | `%{"alg" => "Ed25519"}` | `%{"alg" => "EdDSA"}` for a new artifact |
| In TypeScript, import from the package root and handle every `ErrorCode`. | `import { decodeBlueprint } from "@agent-blueprint-protocol/verifier"` | `import { decode } from "@agent-blueprint-protocol/verifier/dist/verifier/blueprint.js"` |

For TypeScript denials, use an exhaustive `switch` over `ErrorCode` and include a `never` check in the default branch. The [TypeScript guide](documentation/typescript.md) has a complete example.
