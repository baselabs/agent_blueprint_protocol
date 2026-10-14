# Errata — specification corrections

Corrections to the specification name the affected section of
`protocol.md`, the releases affected, and the re-certification: the
conformance corpus, the gates, and the mutation evidence must hold over
the corrected text (a correction that breaks the chain is a revision,
not an erratum). Errata are append-only.

| Date | Section | Releases | Correction |
|---|---|---|---|
| 2026-10-13 | `protocol.md` §6, signing input | every release before 0.8.1 that ships this specification | The text named the signature domain separator, a zero byte, and JCS(signed_attributes) as the signing input. Every release signs and verifies the RFC 7797 §3 input `BASE64URL(JCS(protected)) \|\| "." \|\| JCS(signed_attributes)`; the text now states that input, and the `protocol.md` §5 separator row is marked reserved. No verdict changes; the corpus's honest `signature.verify` cases certify the input in both verifiers. |
| 2026-10-13 | `protocol.md` §6 and `protocol.md` §12, unusable key | every release before 0.8.1 that ships this specification | The text required a small-order public key to deny `:signature_key_unsupported`. Every release denies a matched key that is not usable Ed25519 (small-order, non-canonical, or off the curve) with `:signature_algorithm_unsupported`, keeping `:signature_key_unsupported` for a `key_id` with no supplied key; the text now says so and states the order of the checks. No verdict changes; the corpus's eight small-order-key cases, the y = p and off-curve key cases, the zero-key all-zero-signature case, and the unmatched-key case certify it in both verifiers. |
