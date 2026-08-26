# The extension-author guide

Extensions carry what the core does not: product-shaped capability
declarations riding a registered namespace with a declared
criticality.

## The registry is a closed world

Namespaces are reverse-DNS-plus-path (`com.example.commerce/graph`),
lowercase, one `/`, never parseable as an endpoint. The
governance-canonical source is `spec/registry/registry.json`; entries
carry owner, criticality, lifecycle state, and — for critical
namespaces — a schema digest pin.

## Critical vs optional

- **Critical** bodies validate against a host-supplied schema whose
  digest matches the registry pin; a missing schema denies
  `:extension_schema_unavailable`, a mismatched digest denies
  `:extension_schema_digest_mismatch`. An unregistered critical
  namespace denies outright.
- **Optional** bodies quarantine when unknown: retained byte-exactly,
  typed as unscanned, never executed — and they round-trip
  byte-exactly (decode → to_value → encode is a fixed point).

## Authoring a schema

Schemas live inside the bounded 2020-12 dialect: a closed 16-keyword
subset with a complexity ceiling and `$ref` acyclicity. Keep tiers
uniform-depth; the dialect denies cycles and over-complex documents
with typed errors, not silence.

## Registering

See the specification tree's registry operations process:
qualification, the mirrored-twins change, the corpus rebind. The
registry carries published facts, never authority.
