# Examples

This guide is for readers who want to inspect valid protocol artifacts. You will see complete examples and a Federation excerpt and learn how to verify each one.

The examples are stored under `examples/`. Their files are the source for the JSON shown here.
Timestamp values shown in these examples are fixed artifact data, not readings from the current clock.

In a Mix project with the package installed, start `iex -S mix`. Run each Elixir block below in that session.

Formatted JSON is for reading, not wire-ready bytes. Download the exact canonical files from the linked release sources; added whitespace or a trailing newline changes the byte representation. See [canonical-byte construction](compose-and-sign.md).

## Echo Blueprint

[Download the exact canonical file](https://raw.githubusercontent.com/baselabs/agent_blueprint_protocol/v1.0.1/examples/echo-blueprint.json).

This Blueprint declares one read capability, one input port, one output port, and operational ceilings. Its cost amount is expressed in millionths of USD.

```json
{
  "blueprint_id": "example.demo/echo",
  "capability_requirements": [
    {
      "approval_trait": "none",
      "argument_schema": {
        "type": "object"
      },
      "authority_trait": "none",
      "classification_ceiling": "internal",
      "impact_class": "ordinary",
      "operation_family": "example.demo.read_shape",
      "operation_kind": "read",
      "result_schema": {
        "type": "object"
      }
    }
  ],
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
  },
  "classification_ceiling": "internal",
  "content_digest": "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8",
  "effect_intents": [
    {
      "impact_class": "ordinary",
      "logical_operation": "record_summary",
      "operation_kind": "mutation"
    }
  ],
  "evaluation_assertions": [
    {
      "kind": "output_schema",
      "port": "result",
      "schema": {
        "type": "object"
      }
    }
  ],
  "extensions": {
    "critical": {},
    "optional": {}
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
  "output_ports": [
    {
      "classification_ceiling": "internal",
      "name": "result",
      "required": true,
      "schema": {
        "type": "object"
      }
    }
  ],
  "producer": {
    "created_at": "2026-08-20T00:00:00Z",
    "identity": "example.demo",
    "toolchain": "example.demo.toolchain"
  },
  "protocol_revision": 1,
  "release_number": 1,
  "required_core_fields": [],
  "triggers": [
    "manual"
  ]
}
```

Decode the Blueprint and compare its canonical bytes with the file:

```elixir
dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
bytes = File.read!(Path.join(dependency_root, "examples/echo-blueprint.json"))
{:ok, blueprint} = AgentBlueprintProtocol.decode_blueprint(bytes)
{:ok, ^bytes} = AgentBlueprintProtocol.Blueprint.canonical_bytes(blueprint)
```

## Echo Deployment Manifest

[Download the exact canonical file](https://raw.githubusercontent.com/baselabs/agent_blueprint_protocol/v1.0.1/examples/echo-deployment.json).

This manifest records environment-specific bindings and bounds for the echo Blueprint.

```json
{
  "authority_requirement": {
    "adapter_identity": "example.adapters.authority",
    "profile_identity": "example.profiles.read-only"
  },
  "blueprint_release": {
    "blueprint_id": "example.demo/echo",
    "content_digest": "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8",
    "release_number": 1
  },
  "build_identities": [
    {
      "digest": "sha-256:5JPgXuHZCEXmNHvHfvBfM6jAp9JiMTvqf6y3n4YchnY",
      "kind": "package",
      "name": "agent_blueprint_protocol",
      "version": "0.1.0"
    }
  ],
  "data_bindings": [
    {
      "as_of": {
        "max_age_ms": 86400000,
        "mode": "required"
      },
      "classification_ceiling": "internal",
      "logical_dataset": "shape_orders"
    }
  ],
  "deployment_digest": "sha-256:tWFr0caS0AWFJd2UcB9gZv3kNjIUP8xZ08WWM_h8xgo",
  "effect_owner": {
    "adapter_identity": "example.adapters.effects",
    "idempotency": {
      "key_derivation": "host",
      "recovery": "authoritative"
    }
  },
  "eligibility": {
    "beneficiary": {
      "band": "operator",
      "kind": "beneficiary_band",
      "policy": "example.policies/principal-bands"
    },
    "owner": {
      "band": "operator",
      "kind": "owner_band",
      "policy": "example.policies/principal-bands"
    },
    "runtime_principal": {
      "band": "operator",
      "kind": "runtime_band",
      "policy": "example.policies/principal-bands"
    }
  },
  "evaluation_binding": {
    "adapter_identity": "example.adapters.evaluations",
    "corpus": {
      "digest": "sha-256:zenFB2mNSBmxJWG4DLIWcNyvFdf85m5Ic-BUmWOU02w",
      "name": "example.corpora/echo"
    }
  },
  "extensions": {
    "critical": {},
    "optional": {}
  },
  "host_bounds": {
    "approval_trait": "none",
    "authority_trait": "none",
    "classification_ceiling": "internal",
    "disclosure_ceiling": "summary",
    "effect_impact_ceiling": "ordinary",
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
  },
  "lifecycle": {
    "activated_at": "2026-08-20T00:00:00Z",
    "state": "active"
  },
  "model_policy": {
    "allowed_model_roles": [
      "reasoner"
    ],
    "max_cost": {
      "amount": 500,
      "currency": "USD"
    },
    "max_tokens": 50000
  },
  "protocol_revision": 1,
  "required_core_fields": [],
  "scope_projection": {
    "adapter_identity": "example.adapters.scope"
  },
  "signer_custody": "host_managed",
  "tool_bindings": [
    {
      "adapter_identity": "example.adapters.tools",
      "attested_at": "2026-08-20T00:00:00Z",
      "descriptor_digest": "sha-256:VpMcbixeDnkz4W6WwFyJVm3BG_n8s1jEZANpZLvZEKI",
      "logical_operation": "example.demo.read_shape",
      "schema_digest": "sha-256:4aRchkjuUMTF6Sm4-oCuZQkzYHP0CvJfGLFHhdjHvY0"
    },
    {
      "adapter_identity": "example.adapters.effects.tools",
      "attested_at": "2026-08-20T00:00:00Z",
      "descriptor_digest": "sha-256:VpMcbixeDnkz4W6WwFyJVm3BG_n8s1jEZANpZLvZEKI",
      "logical_operation": "record_summary",
      "schema_digest": "sha-256:4aRchkjuUMTF6Sm4-oCuZQkzYHP0CvJfGLFHhdjHvY0"
    }
  ]
}
```

Decode the Deployment Manifest and compare its canonical bytes with the file:

```elixir
dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
bytes = File.read!(Path.join(dependency_root, "examples/echo-deployment.json"))
{:ok, deployment} = AgentBlueprintProtocol.decode_deployment(bytes)
{:ok, ^bytes} = AgentBlueprintProtocol.Deployment.canonical_bytes(deployment)
```

## Signed Blueprint

[Download the exact canonical file](https://raw.githubusercontent.com/baselabs/agent_blueprint_protocol/v1.0.1/examples/signed-blueprint.json).

This example adds a signature entry to the echo Blueprint. Decoding checks the artifact structure and content digest. The signature verification operation also needs the public key supplied by the caller.

```json
{
  "blueprint_id": "example.demo/echo",
  "capability_requirements": [
    {
      "approval_trait": "none",
      "argument_schema": {
        "type": "object"
      },
      "authority_trait": "none",
      "classification_ceiling": "internal",
      "impact_class": "ordinary",
      "operation_family": "example.demo.read_shape",
      "operation_kind": "read",
      "result_schema": {
        "type": "object"
      }
    }
  ],
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
  },
  "classification_ceiling": "internal",
  "content_digest": "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8",
  "effect_intents": [
    {
      "impact_class": "ordinary",
      "logical_operation": "record_summary",
      "operation_kind": "mutation"
    }
  ],
  "evaluation_assertions": [
    {
      "kind": "output_schema",
      "port": "result",
      "schema": {
        "type": "object"
      }
    }
  ],
  "extensions": {
    "critical": {},
    "optional": {}
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
  "output_ports": [
    {
      "classification_ceiling": "internal",
      "name": "result",
      "required": true,
      "schema": {
        "type": "object"
      }
    }
  ],
  "producer": {
    "created_at": "2026-08-20T00:00:00Z",
    "identity": "example.demo",
    "toolchain": "example.demo.toolchain"
  },
  "protocol_revision": 1,
  "release_number": 1,
  "required_core_fields": [],
  "signatures": [
    {
      "protected": {
        "alg": "EdDSA",
        "b64": false,
        "crit": [
          "b64"
        ],
        "kid": "example-demo-signing-key"
      },
      "signature": "V3-RJiWxEcb6lKa66VHs8nFEzP91ikrkMM68aCrhuDBdUdHs1mfs5-m5vAyX0lFjfNALxjId292rwq1tiab7Cw",
      "signed_attributes": {
        "algorithm": "Ed25519",
        "content_digest": "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8",
        "created_at": "2026-08-20T00:00:00Z",
        "key_id": "example-demo-signing-key",
        "purpose": "blueprint"
      }
    }
  ],
  "triggers": [
    "manual"
  ]
}
```

Decode it and compare the canonical bytes:

```elixir
dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
bytes = File.read!(Path.join(dependency_root, "examples/signed-blueprint.json"))
{:ok, blueprint} = AgentBlueprintProtocol.decode_blueprint(bytes)
{:ok, ^bytes} = AgentBlueprintProtocol.Blueprint.canonical_bytes(blueprint)
```

This shipped signature uses the accepted `EdDSA` header spelling. The [compose guide](compose-and-sign.md) uses the preferred `Ed25519` header spelling.

## Extension Blueprint

[Download the exact canonical file](https://raw.githubusercontent.com/baselabs/agent_blueprint_protocol/v1.0.1/examples/extension-blueprint.json).

This example carries an optional classification-labels namespace in the extension member.

```json
{
  "blueprint_id": "example.demo/echo",
  "capability_requirements": [
    {
      "approval_trait": "none",
      "argument_schema": {
        "type": "object"
      },
      "authority_trait": "none",
      "classification_ceiling": "internal",
      "impact_class": "ordinary",
      "operation_family": "example.demo.read_shape",
      "operation_kind": "read",
      "result_schema": {
        "type": "object"
      }
    }
  ],
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
  },
  "classification_ceiling": "internal",
  "content_digest": "sha-256:xKEhhM60EgG3BcYN09DQDxP8ktzD7DLWVS_igana6D8",
  "effect_intents": [
    {
      "impact_class": "ordinary",
      "logical_operation": "record_summary",
      "operation_kind": "mutation"
    }
  ],
  "evaluation_assertions": [
    {
      "kind": "output_schema",
      "port": "result",
      "schema": {
        "type": "object"
      }
    }
  ],
  "extensions": {
    "critical": {},
    "optional": {
      "com.example.vendor/labels": {
        "labels": [
          "pci"
        ]
      }
    }
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
  "output_ports": [
    {
      "classification_ceiling": "internal",
      "name": "result",
      "required": true,
      "schema": {
        "type": "object"
      }
    }
  ],
  "producer": {
    "created_at": "2026-08-20T00:00:00Z",
    "identity": "example.demo",
    "toolchain": "example.demo.toolchain"
  },
  "protocol_revision": 1,
  "release_number": 1,
  "required_core_fields": [],
  "triggers": [
    "manual"
  ]
}
```

Decode it and compare the canonical bytes:

```elixir
dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
bytes = File.read!(Path.join(dependency_root, "examples/extension-blueprint.json"))
{:ok, blueprint} = AgentBlueprintProtocol.decode_blueprint(bytes)
{:ok, ^bytes} = AgentBlueprintProtocol.Blueprint.canonical_bytes(blueprint)
```

## Federation TaskEnvelope

[Download the exact canonical file](https://raw.githubusercontent.com/baselabs/agent_blueprint_protocol/v1.0.1/examples/federation-envelope.json).

This JSON excerpt comes from the shipped Federation TaskEnvelope. It is not a complete envelope. Its namespace and carrier fields are described in the [federation guide](federation.md).

```json
{
  "task_identity": "task-7f3a2c",
  "terminal_state": "completed",
  "evidence_receipt": {
    "terminal_commitment": "sha-256:BshcxIagBOfO1pAFNXbJY5qIFIHhl2lMyq6lIhH8Pfo"
  }
}
```

Decode it and compare the canonical bytes:

```elixir
dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
bytes = File.read!(Path.join(dependency_root, "examples/federation-envelope.json"))
{:ok, envelope} = AgentBlueprintProtocol.decode_federation_envelope(bytes)
{:ok, ^bytes} = AgentBlueprintProtocol.Federation.canonical_bytes(envelope)
```

The conformance corpus separately includes valid terminal commitment and conflict cases.

## Verify the corpus

From the repository root, run the conformance runner to check all shipped examples and fixtures:

```sh
mix conformance.verify
```

## Next steps

- [Read the concept guides](what-a-blueprint-is.md)
- [Verify in CI](verifying-in-ci.md)
- [Read the conformance guide](conformance.md)
