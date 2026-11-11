# What a Deployment Manifest is

This guide is for people who connect a Blueprint to an environment. You will learn what a Deployment Manifest records and how its 19 members fit together.

A Deployment Manifest describes environment-specific bindings and bounds for one Blueprint release. The protocol checks its structure and consistency. It does not make the host's decisions.

## The 19 members

The member set is closed for protocol revision 1. The table lists every member.

| Member | Meaning |
|---|---|
| `protocol_revision` | Revision of the artifact grammar. |
| `blueprint_release` | Blueprint identity, release number, and content digest. |
| `scope_projection` | Identity of the adapter that supplies scope information. |
| `tool_bindings` | Declared operations and their adapter, descriptor, schema, and observation labels. |
| `data_bindings` | Dataset names, classification ceilings, and related constraints. |
| `authority_requirement` | Adapter and profile identities associated with authority data. |
| `effect_owner` | Adapter identity and idempotency and recovery categories for effects. |
| `signer_custody` | Declared category for signature-key custody. |
| `eligibility` | Owner, beneficiary, and runtime-principal categories with policy references. |
| `model_policy` | Allowed model roles and maximum tokens and cost. |
| `host_bounds` | Environment bounds, including cost in millionths of a currency unit. |
| `lifecycle` | Manifest state and optional lifecycle timestamps. |
| `build_identities` | Exact named build identities and their digest values. |
| `evaluation_binding` | Adapter identity and named corpus digest. |
| `extensions` | Critical and optional namespaced extension values. |
| `required_core_fields` | Core members a consumer is asked to honor. |
| `deployment_digest` | Tagged digest of the manifest's digest-covered content. |
| `signatures` | Optional signature entries associated with the artifact. |
| `attestations` | Optional additional artifact data. |

Every member except `signatures` and `attestations` is required. A member outside the table is rejected.

## Cost amounts

Every `max_cost.amount` is an integer count of millionths of the currency unit named by `currency`. This applies in `host_bounds` and `model_policy`.

In the example, `amount: 1000` with `currency: "USD"` means 0.001 USD. The scale does not use the currency's minor-unit exponent.

## Example

This is the complete shipped example from [examples/echo-deployment.json](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.3/examples/echo-deployment.json).

```json
{"authority_requirement":{"adapter_identity":"example.adapters.authority","profile_identity":"example.profiles.read-only"},"blueprint_release":{"blueprint_id":"example.demo/echo","content_digest":"sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8","release_number":1},"build_identities":[{"digest":"sha-256:5JPgXuHZCEXmNHvHfvBfM6jAp9JiMTvqf6y3n4YchnY","kind":"package","name":"agent_blueprint_protocol","version":"0.1.0"}],"data_bindings":[{"as_of":{"max_age_ms":86400000,"mode":"required"},"classification_ceiling":"internal","logical_dataset":"shape_orders"}],"deployment_digest":"sha-256:tWFr0caS0AWFJd2UcB9gZv3kNjIUP8xZ08WWM_h8xgo","effect_owner":{"adapter_identity":"example.adapters.effects","idempotency":{"key_derivation":"host","recovery":"authoritative"}},"eligibility":{"beneficiary":{"band":"operator","kind":"beneficiary_band","policy":"example.policies/principal-bands"},"owner":{"band":"operator","kind":"owner_band","policy":"example.policies/principal-bands"},"runtime_principal":{"band":"operator","kind":"runtime_band","policy":"example.policies/principal-bands"}},"evaluation_binding":{"adapter_identity":"example.adapters.evaluations","corpus":{"digest":"sha-256:zenFB2mNSBmxJWG4DLIWcNyvFdf85m5Ic-BUmWOU02w","name":"example.corpora/echo"}},"extensions":{"critical":{},"optional":{}},"host_bounds":{"approval_trait":"none","authority_trait":"none","classification_ceiling":"internal","disclosure_ceiling":"summary","effect_impact_ceiling":"ordinary","max_attempts":3,"max_concurrency":2,"max_cost":{"amount":1000,"currency":"USD"},"max_depth":8,"max_descendants":64,"max_elapsed_ms":60000,"max_fan_out":4,"max_tokens":100000},"lifecycle":{"activated_at":"2026-08-20T00:00:00Z","state":"active"},"model_policy":{"allowed_model_roles":["reasoner"],"max_cost":{"amount":500,"currency":"USD"},"max_tokens":50000},"protocol_revision":1,"required_core_fields":[],"scope_projection":{"adapter_identity":"example.adapters.scope"},"signer_custody":"host_managed","tool_bindings":[{"adapter_identity":"example.adapters.tools","attested_at":"2026-08-20T00:00:00Z","descriptor_digest":"sha-256:VpMcbixeDnkz4W6WwFyJVm3BG_n8s1jEZANpZLvZEKI","logical_operation":"example.demo.read_shape","schema_digest":"sha-256:4aRchkjuUMTF6Sm4-oCuZQkzYHP0CvJfGLFHhdjHvY0"},{"adapter_identity":"example.adapters.effects.tools","attested_at":"2026-08-20T00:00:00Z","descriptor_digest":"sha-256:VpMcbixeDnkz4W6WwFyJVm3BG_n8s1jEZANpZLvZEKI","logical_operation":"record_summary","schema_digest":"sha-256:4aRchkjuUMTF6Sm4-oCuZQkzYHP0CvJfGLFHhdjHvY0"}]}
```

## Next steps

- [Compose and sign a Blueprint](compose-and-sign.md)
- [Integrate verification into a host](host-integration.md)
- [Read the complete protocol](../spec/protocol.md#2-artifacts-and-the-closed-world)
