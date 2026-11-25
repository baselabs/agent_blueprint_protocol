# 0022: Procedure identity as a critical extension

Status: Accepted

## Decision

Register `io.github.baselabs/procedure` as an active, critical Deployment
Manifest extension. Its closed body is covered by the Deployment digest.
Profiles define host-owned roles and constraints and are accepted by their
JCS SHA-256 digest. Hosts supply the profiles, roles and committed documents.

The binding stage pairs execution-scoped observations with the declaration
and binds the inventory to the Deployment digest and attempt commitment.
Reconcile requires the stage for a critical procedure declaration. Hosts can
also run it for before-send and returned-run imports. Composition uses
child-first digests and bounded acyclic traversal with support for shared children.
Procedure bodies always receive the strict portability scan.

## Consequences

Blueprint payloads in either extension region deny
`extension_payload_forbidden` before extension lifecycle or criticality
checks. The subject is `["extensions"]`, prefixed by `"blueprint"` in reconcile.
Evidence covers the declaration and the supplied observations. The host owns
the validity, freshness and authenticity judgments and the execution decision.

## Error and revision stability

Pairing failures use `binding_incomplete`. Invalid declarations and committed
documents use `invalid_constraint` where a more specific structural code
does not apply. A child Deployment with a wrong digest uses `digest_mismatch`.
The `compatibility_*` results from this stage retain their revision 1 triggers
and subjects for comparing observed builds with `build_identities`.
The new conformance cases extend the census under core revision 1 and retain
the closed error vocabulary and prior certified verdicts.
