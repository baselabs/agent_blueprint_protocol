# What a deployment is

A Deployment Manifest binds ONE Blueprint release digest to ONE
execution environment: tools, principals, data, authority, effects,
evaluation, and exact builds.

## The 19-member closed world

- `blueprint_release` — the exact binding: blueprint id, release
  number, and content digest. Digest equality only; no fuzzy match.
- `tool_bindings` — each logical operation bound to an adapter with
  descriptor and schema digests (the rug-pull guards).
- `build_identities` — exact version + digest per named build input;
  ranges deny (`:compatibility_identity_inexact`).
- `host_bounds` — the deployment's own bound declarations that meet
  the blueprint's ceilings at the narrowest point.
- `lifecycle` — draft / active / retired with Z-form timestamps.

## The binding check is deny-ordered

`Deployment.verify_binding/3` runs a pinned order: identity, staleness
(attestation freshness), descriptor-digest equality. Any divergence is
a typed denial — the host never receives a repaired manifest.
