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

`Deployment.verify_binding/3` runs six checks in a pinned order, and
the first failure is the denial:

1. the bound release digest equals the Blueprint's recomputed content
   digest (`:deployment_digest_mismatch`);
2. the bound `blueprint_id` and `release_number` are the Blueprint's
   (`:binding_incomplete`);
3. every tool binding names an operation family or effect intent the
   Blueprint declares (`:binding_incomplete`);
4. a mutation is never bound under `recovery: "none"`
   (`:no_authoritative_recovery`);
5. no attestation is older than the host's maximum age or dated in the
   future (`:binding_attestation_stale`; runs only when the host
   supplies `now`);
6. each observed descriptor digest equals the attested one
   (`:binding_descriptor_mismatch`; runs only on the host's
   observations).

The host never receives a repaired manifest.
