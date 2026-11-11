# Security model

This guide is for verifier implementers and host developers. You will learn which input threats the verifier checks and which decisions remain outside the protocol.

The verifier treats artifact bytes and caller-supplied data as untrusted input. It applies bounded decoding, canonical byte checks, closed member validation, digest checks, negotiation, portability checks, and signature verification.

## Threats the verifier checks

| Threat | Verifier response |
|---|---|
| Malformed or ambiguous JSON | Reject invalid syntax, duplicate members, and noncanonical bytes. |
| Oversized or deeply nested input | Enforce the decoder's configured ceilings. |
| Artifact tampering | Recompute digest values and reject mismatches. |
| Unknown core members or unsupported revisions | Reject values outside the declared artifact vocabulary. |
| Unsupported critical extensions | Apply registry negotiation and return a typed denial. |
| Invalid extension schemas | Check schema shape and the registered schema identity. |
| Invalid signatures | Verify the entry against caller-supplied Ed25519 public keys. |
| Private or environment-specific values | Apply structural portability checks. |
| Federation commitment verification | Return a typed conflict for an inconsistent terminal commitment. |

The conformance corpus includes cases for these checks. See the security and privacy considerations in [protocol sections 17 and 18](../spec/protocol.md#17-security-considerations-normative).

## What verification never decides

A successful result does not establish tenancy, live policy, authority, effect ownership, execution, billing, or evaluation truth. It does not run an agent or grant permission. The consuming host makes its own decisions.

The library uses only keys supplied by the caller. It verifies bytes against those keys, but it does not discover keys or establish who controls them.

## Ed25519 profile

The signature profile uses Ed25519. A public key is 32 bytes, and a signature is 64 bytes. The protected header may use `Ed25519` or its `EdDSA` alias. The signed `algorithm` attribute is `Ed25519`.

Producers should write `alg` as `Ed25519`. The verifier checks the signature against the supplied public key and the protocol-defined signed input. It rejects malformed encodings and signatures that fail verification.

The package does not decide whether a key is trusted for a real-world identity. That relationship comes from outside the protocol.

## Next steps

- [Compose and sign a Blueprint](compose-and-sign.md)
- [Read the evidence guide](reading-evidence.md)
- [Read the complete protocol](../spec/protocol.md#6-signature-envelope)
