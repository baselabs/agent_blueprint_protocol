# What a Blueprint is

This guide is for people who publish agent descriptions. You will learn what a Blueprint contains and how its members fit together.

A Blueprint is a portable description of an agent's declared capabilities, inputs, outputs, effects, and limits. It does not execute an agent or grant access to a host.

## The 18 members

The core member set is closed for protocol revision 1. The table lists every member.

| Member | Meaning |
|---|---|
| `blueprint_id` | Producer-qualified identity for this Blueprint. |
| `protocol_revision` | Revision of the artifact grammar. |
| `producer` | Producer identity, creation metadata, and toolchain label. |
| `release_number` | Positive integer identifying this Blueprint release. |
| `capability_requirements` | Declared operations, schemas, impact, classification, and traits. |
| `input_ports` | Named inputs, their schemas, classification ceilings, and required flags. |
| `output_ports` | Named outputs, their schemas, classification ceilings, and required flags. |
| `output_contract` | The output port and its classification ceiling. |
| `triggers` | At least one declared trigger category. |
| `ceilings` | Operational maxima, including cost in millionths of a currency unit. |
| `classification_ceiling` | Highest classification declared by the Blueprint. |
| `effect_intents` | Declared operations that may have effects. |
| `evaluation_assertions` | Assertions describing expected evaluation properties. |
| `extensions` | Critical and optional namespaced extension values. |
| `required_core_fields` | Core members a consumer is asked to honor. |
| `content_digest` | Tagged digest of the Blueprint's digest-covered content. |
| `signatures` | Optional signature entries associated with the artifact. |
| `attestations` | Optional additional artifact data. |

Every core member except `signatures` and `attestations` is required. A member outside the table is rejected.

## Cost amounts

Every `max_cost.amount` is an integer count of millionths of the currency unit named by `currency`. The scale does not follow a currency's minor-unit exponent.

In the example, `amount: 1000` and `currency: "USD"` represent 0.001 USD. Values stay integers, so verifiers do not need floating-point arithmetic.

## Example

This is the complete shipped example from [examples/echo-blueprint.json](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.2/examples/echo-blueprint.json).

```json
{"blueprint_id":"example.demo/echo","capability_requirements":[{"approval_trait":"none","argument_schema":{"type":"object"},"authority_trait":"none","classification_ceiling":"internal","impact_class":"ordinary","operation_family":"example.demo.read_shape","operation_kind":"read","result_schema":{"type":"object"}}],"ceilings":{"max_attempts":3,"max_concurrency":2,"max_cost":{"amount":1000,"currency":"USD"},"max_depth":8,"max_descendants":64,"max_elapsed_ms":60000,"max_fan_out":4,"max_tokens":100000},"classification_ceiling":"internal","content_digest":"sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8","effect_intents":[{"impact_class":"ordinary","logical_operation":"record_summary","operation_kind":"mutation"}],"evaluation_assertions":[{"kind":"output_schema","port":"result","schema":{"type":"object"}}],"extensions":{"critical":{},"optional":{}},"input_ports":[{"classification_ceiling":"internal","name":"request","required":true,"schema":{"type":"object"}}],"output_contract":{"classification_ceiling":"internal","port":"result"},"output_ports":[{"classification_ceiling":"internal","name":"result","required":true,"schema":{"type":"object"}}],"producer":{"created_at":"2026-08-20T00:00:00Z","identity":"example.demo","toolchain":"example.demo.toolchain"},"protocol_revision":1,"release_number":1,"required_core_fields":[],"triggers":["manual"]}
```

## Next steps

- [Compose and sign a Blueprint](compose-and-sign.md)
- [Read the complete protocol](../spec/protocol.md#2-artifacts-and-the-closed-world)
- [Review the shipped examples](examples.md)
