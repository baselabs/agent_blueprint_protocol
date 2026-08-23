# ADR: detached JWS signature envelope

Status: accepted (2026-08-20; hardening follow-ups landed with the
second-language verifier).

## Context

Artifacts need producer authentication that standard tooling can verify,
without embedding payloads redundantly (the artifact IS the payload) and
without the package ever holding key material. An earlier design sketch
used a bespoke preimage form.

## Decision

Real detached JWS: RFC 7515 compact serialization + RFC 7797 `b64=false`
unencoded detached payload. Payload = JCS(signed_attributes) carrying
`algorithm`, `content_digest`, `created_at`, `key_id`, `purpose`;
protected header `{alg: EdDSA, kid, crit: ["b64"], b64: false}` —
A2A §8.4-aligned, verifiable by stock JOSE libraries.

Ed25519 only. Algorithm succession is a data change plus a revision
increment, not a crypto-agility subsystem. The package verifies only:
never signs, never accepts a private key on any public function
(three-way architecture gate: banned parameter names, banned
`:crypto.sign` call sites, plus a beam census that resolves every remote
call with aliases expanded — no spelling hides). No key discovery, no
fetch, no trust selection: hosts supply trusted keys.

## Consequences

Because `content_digest` is inside the signed attributes and the digest
covers revision, identity, extensions, and required fields, signatures
cannot be lifted across artifacts, revisions, or purposes; `key_id`
blocks key substitution. Small-order Ed25519 keys reject. The sign-path
ban makes the package structurally unusable as a signing oracle. Red
proofs: the verify-only gate reds on each banned form (parameter,
source call, beam census).
