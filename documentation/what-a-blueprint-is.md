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

This reading excerpt groups related members. The [gallery](examples.md) contains the full formatted artifact; [download the exact canonical file](https://raw.githubusercontent.com/baselabs/agent_blueprint_protocol/v1.0.0/examples/echo-blueprint.json). Formatted JSON is not wire-ready bytes, and this excerpt omits required members.

```json
{
  "blueprint_id": "example.demo/echo",
  "protocol_revision": 1,
  "release_number": 1,
  "producer": {
    "created_at": "2026-08-20T00:00:00Z",
    "identity": "example.demo",
    "toolchain": "example.demo.toolchain"
  },
  "input_ports": [
    {
      "classification_ceiling": "internal",
      "name": "request",
      "required": true,
      "schema": {
        "type": "object"
      }
    }
  ],
  "output_contract": {
    "classification_ceiling": "internal",
    "port": "result"
  },
  "ceilings": {
    "max_attempts": 3,
    "max_concurrency": 2,
    "max_cost": {
      "amount": 1000,
      "currency": "USD"
    },
    "max_depth": 8,
    "max_descendants": 64,
    "max_elapsed_ms": 60000,
    "max_fan_out": 4,
    "max_tokens": 100000
  }
}
```

Identity and producer metadata describe the release. Ports describe its data contract; `ceilings` limits resource use. Capabilities, effects, assertions, extensions, and the content digest appear in the full gallery example.

## Next steps

- [Compose and sign artifacts](compose-and-sign.md)
- [Read the complete protocol](../spec/protocol.md#2-artifacts-and-the-closed-world)
- [Review the shipped examples](examples.md)
