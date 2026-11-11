# Portability

This guide is for producers and consumers of portable artifacts. You will learn which data the verifier denies and how to read a portability result.

Portability checks look for values and member names that bind an artifact to private or environment-specific data. The check is structural. It does not prove that every accepted value is safe for every use.

## What the verifier denies

The verifier rejects values that match the portability rules, including secrets, private keys, live grants, tenant identifiers, raw endpoints, database primary keys, and backend engine identifiers. These values can expose private state or make an artifact depend on one environment.

The scan applies to open regions at any depth. Names are compared after spelling normalization. Opaque extension values that the verifier does not inspect are not treated as verified evidence.

## A corpus denial

The shipped case [portability-forbidden](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.3/priv/conformance/cases/portability-scan.json) passes a key-shaped value to the portability scanner:

```json
{"api_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}
```

The conformance result is:

```json
{"code":"forbidden_portable_value","verdict":"invalid"}
```

The result names a typed code. It does not return the input value.

## Next steps

- [Read the security model](security-model.md)
- [Review all conformance cases](conformance.md)
- [Read the portability section of the protocol](../spec/protocol.md#14-portability)
