# ARD mapping — the Agentic Resource Discovery field mapping

The Agent Blueprint Protocol maps its artifact surface against the
CURRENT ARD specification before claiming any carriage (the
mapping-before-inventing law, the same method as the A2A/MCP federation
mapping). The verdict, re-derived against the live sources below:
**the trust-manifest layer shares this protocol's cryptographic DNA
(detached JWS over JCS, EdDSA in the allowlist) and can carry a
blueprint's identity and integrity natively — but the capability
contract itself (typed ports, bounds, ceilings, effect intents,
evaluation assertions, evidence commitments) has NO home in either ARD
data model, and ARD's `capabilities` field is an unsigned freeform
token list.** The layer this protocol owns is unclaimed inside the
best-backed discovery specification of 2026; ARD's JSON-LD extension
seam is the designed place it plugs in.

## Pinned sources (bytes re-verified 2026-09-13)

ARD publishes two data models (the closed-vocabulary LF AI Catalog
form and the open JSON-LD ARD entry), and v0.91 moved the well-known
path: `/.well-known/ard.json` is normative; `/.well-known/ai-catalog.json`
is the explicitly deprecated predecessor. Each row pins the exact bytes
by plain SHA-1 of the file at the named commit.

| Source | Path @ commit | plain SHA-1 |
|---|---|---|
| ARD spec v0.91 (2026-08-26, Proposal) | `spec/ard.md` @ [ards-project/ard-spec `b76f235a`](https://github.com/ards-project/ard-spec/blob/b76f235a8f461876ad4f1e77abd0eb0eb302b48d/spec/ard.md) | `cac2295db7c75743a4acf86fedda6b18a35a00bb` |
| LF catalog schema | `spec/schemas/ai-catalog.schema.json` @ `b76f235a` | `a0d82fc810b5920a8924dffda7e9cba52c0c5848` |
| ARD entry schema | `spec/schemas/ard-entry.schema.json` @ `b76f235a` | `479eff4c65992e646c92718bca1fa06c6ef3f544` |
| LF AI Catalog data model + normative Trust Manifest chapter | `specification/ai-catalog.md` @ [Agent-Card/ai-catalog `04a99cd1`](https://github.com/Agent-Card/ai-catalog/blob/04a99cd1ac9a20dd6586c6196e87f5e4570303b1/specification/ai-catalog.md) | `c9a10cb992ad88f3523d326c94e03c492181343d` |

The normative crypto lives in the LF Catalog layer; ARD defers signing,
canonicalization, and key resolution to whatever framework a manifest's
`trustSchema` declares ("a future ARD profile MAY pin a concrete
default scheme, but this specification does not").

## The mapping table

Verdicts: **native** = the ARD field carries the semantic exactly;
**partial** = a home exists but loses or widens the semantics;
**extension** = no home; the field rides the JSON-LD extension seam or
the referenced artifact.

| # | Blueprint surface | ARD / LF Catalog location | Verdict |
|---|---|---|---|
| 1 | content digest (domain-separated, tagged) | `trustManifest.subject.digest` — signed, SHA-256+ mandatory, over exact or JCS bytes | partial — the digest commitment is signed, but ARD has one digest domain; this protocol's blueprint/deployment domain separation has no counterpart |
| 2 | detached signature envelope | `trustManifest.signature` — detached JWS (RFC 7515) over the JCS-canonicalized manifest; ES/PS/RSA/**EdDSA** allowlisted; `none` MUST be rejected | native family — same JWS-over-JCS DNA; this protocol pins Ed25519, the RFC 7797 unencoded payload, and `kid`-to-`key_id` binding for determinism where ARD stays algorithm-agile |
| 3 | purpose binding (signed purpose + digest inside the payload) | `subject {url?, type, digest}` | partial — `type` is an artifact media type, not a purpose vocabulary; a signature still cannot be lifted onto other content |
| 4 | producer identity | entry `publisher {identifier, identityType}` / `host` — DID/SPIFFE/HTTPS, domain-bound to the URN publisher segment | partial — identity yes; no producer-qualified capability naming |
| 5 | release version | entry `version` — informational string | partial — this protocol's release line is digest-covered |
| 6 | typed input/output ports | none | extension |
| 7 | capability requirements (typed, signed) | entry `capabilities` — MAY, freeform string tokens, filterable — **outside the trust manifest and any signature** | extension — a native field exists but is unsigned freeform; the signed typed surface has no home |
| 8–15 | operational bounds (attempts, concurrency, cost, depth, descendants, elapsed, fan-out, tokens) | none | extension |
| 16 | classification / disclosure ceilings (protected lattice) | none | extension |
| 17 | effect intents | none | extension |
| 18 | evaluation assertions | none | extension |
| 19 | evidence commitments (the reconcile Evidence record, `not_verified` honesty) | `attestations[] {type, uri, digest}` — integrity of the evidence DOCUMENT only; "treat attestations as evidence, not guarantees" | extension — document digests are not claim commitments |
| 20 | extension registry governance (criticality, unknown-critical denies) | JSON-LD `@context` namespaced terms become filter dimensions; no criticality semantics | partial seam — the designed plug point (the ARD specification's extension and vocabulary sections, and the LF catalog's loose-coupling ADR, which keeps the catalog a "thin pointer") |
| 21 | negotiation / evolution gate | none | extension |
| 22 | Deployment Manifest build identities | none | extension |
| 23 | portability guarantees | none | extension |

Instrument-verified absence: a scan of all four pinned normative files
for `bound`, `ceiling`, `effect`, `evaluat`, `assertion`, `evidence`,
`ed25519`, `eddsa` returns only prose and the EdDSA allowlist entry —
no field of either data model names any concept in rows 6–23.

## Receiver posture

An ARD entry is a thin pointer: `identifier` (URN), `displayName`,
`type` (IANA media type), and exactly one of `url` XOR `data`. The
natural carriage for this protocol is therefore the entry's `url`
pointing AT a Blueprint artifact, with the trust manifest's
`subject.digest` equal to the blueprint's `content_digest` — one line
of integration that makes discovery-level verification and
protocol-level verification agree on identity before any semantic
read. A registry operator gains: signed identity + integrity from ARD's
own machinery, and typed, signed, fail-closed capability semantics from
the artifact the entry points at — with the protocol's non-authorizing
boundary intact (a verified entry and a verified blueprint are both
evidence; neither admits an agent to anything).

## Momentum and health (informative)

Spec v0.91, status Proposal; the well-known path moved 2026-08-26 and
operators are transitional (Hugging Face's live registry still serves
the deprecated `ai-catalog.json` path). Governance: maintainer majority
(Google, Hugging Face, Microsoft, Amazon, Cisco oversight board); no
standards-body home — the governance page defers neutral hosting as
"roughly twelve months out." The LF Agent Card Working Group (Google,
Microsoft, Anthropic, PulseMCP) owns the catalog data model ARD builds
on. This document re-derives against the pinned bytes above; when ARD
tags a release or moves the path again, the pin rows are the reopen
trigger.
