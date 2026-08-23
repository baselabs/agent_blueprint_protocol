# ADR: the non-authorizing boundary

Status: accepted (2026-08-20, design approval; mechanically enforced since
the architecture lane landed).

## Context

Agent-run blueprints describe capabilities and bindings. The obvious
failure mode of such a protocol is scope creep into authorization: a
"verified" artifact being treated as permission to act. Hosts own
identity, tenancy, policy, and effect authority; several adjacent
internal systems already occupy that ground.

## Decision

The protocol validates structure, canonical bytes, bounds, compatibility,
and evidence — nothing else. Protocol validity never grants authority.
Concretely:

- `reconcile/3`'s result is an `%Evidence{}` record, never a decision;
  its `not_verified` list is non-empty BY CONSTRUCTION, always naming
  the seven host-owned surfaces (tenancy, live policy, authority,
  effect ownership, execution, billing, evaluation truth).
- No authorization-decision vocabulary exists in any shipped
  identifier — no `authorize`/`authorized`, no `:unauthorized` in
  either polarity (source-scan gate).
- Signatures and attestations are evidence; verification never
  authorizes execution.
- Every shipped module's moduledoc states the boundary (spec-coverage
  gate); usage rules repeat it.

## Consequences

Hosts cannot delegate their authority checks to this package — by
design. The boundary costs a little boilerplate (the stance sentence per
moduledoc) and buys a claim that survives adversarial review: the
package's public surface cannot express permission. Red proofs: the
vocabulary gate reds on a planted `authorize_import/1`; the stance gate
reds on a moduledoc without boundary phrasing.
