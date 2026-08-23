# ADR: deny-default protected-bound clamps

Status: accepted (2026-08-20, approved default).

## Context

The bounds algebra meets three sources (Blueprint declared, Deployment
host-side, host live policy). Operational bounds narrow freely with
evidence. Protected bounds — classification and disclosure ceilings,
authority/approval/effect-impact traits — encode obligations. An
"acknowledge and narrow" default would let a portable artifact or a
deployment silently under-state an obligation; the privilege-escalation
direction is exactly the quiet failure.

## Decision

Narrowing a protected bound DENIES by default (`:protected_bound_clamp_denied`).
A host may explicitly opt into an `:acknowledge` posture, which always
records clamp evidence. Operational bounds always emit clamp evidence
iff effective ≠ requested. Obligation families meet at the strictest
value; classification markers are retained regulatory obligations whose
effective set is the union of sources — dropping one is a widening.

## Consequences

Portable input can never widen a host bound (property law,
mutation-gated: flipping the meet to loosest reds the corpus). The deny
default makes every protected narrowing a loud host decision rather
than a silent drift. Hosts that need narrowing flows opt in explicitly
and get evidence trails. The corpus pins the widening direction in both
families with red cases.
