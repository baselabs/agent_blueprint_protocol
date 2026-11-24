# ARD and AI Catalog positioning

Agentic Resource Discovery (ARD) v0.91 is a Proposal for discovery and
search. AI Catalog defines a typed container and independently contributed
Trust Manifests. ABP supplies a portable capability and deployment contract;
a discovery entry can reference that artifact without adopting its semantics.

## Source pins

Plain SHA-1 values identify these exact upstream bytes:

| Source | Commit and path | plain SHA-1 |
|---|---|---|
| ARD v0.91 Proposal | [ard-spec f073b1ea](https://github.com/ards-project/ard-spec/blob/f073b1ea9b01a5f068d0b0986426f2ea49fa30b2/spec/ard.md) | `c178a417b41927dba4f4f4485f567349256d2e6e` |
| LF catalog schema | [catalog schema at f073b1ea](https://github.com/ards-project/ard-spec/blob/f073b1ea9b01a5f068d0b0986426f2ea49fa30b2/spec/schemas/ai-catalog.schema.json) | `a0d82fc810b5920a8924dffda7e9cba52c0c5848` |
| ARD entry schema | [entry schema at f073b1ea](https://github.com/ards-project/ard-spec/blob/f073b1ea9b01a5f068d0b0986426f2ea49fa30b2/spec/schemas/ard-entry.schema.json) | `43066da1c450ec54c0dc0f7e980030b9e28d9784` |
| AI Catalog v0.9 (v1.0 release candidate) | [ai-catalog v0.9.0 at 19208af2](https://github.com/Agent-Card/ai-catalog/blob/19208af2f8adbc0a6457e3ff36ce691a304fbd97/specification/ai-catalog.md) | `32eecc1c87f18f38d58f28730d0bce0ea3e529b5` |

Since the preceding pins, ARD clarified open media types, optional multi-part
URN namespaces, referral endpoint handling, and optional tracing. Its catalog
schema bytes are unchanged; its entry schema changed an evidence-description
string. AI Catalog substantially clarified contributor signatures, their
payload and subject coverage, and the distinction between a manifest signature
and a catalog snapshot signature. These changes invalidate a claim that its
signature envelope is interchangeable with ABP's.

AI Catalog v0.9.0 is the release candidate for v1.0. Its top-level object,
Catalog Entry, Host Info and Publisher objects are open to members the
specification does not define. A signed payload retains those members, and a
catalog signature covers them, but the signature authenticates only that the
signer published those bytes, not what they mean. Its Trust Manifest signature
is still a detached compact JWS over JCS bytes with a required protected `typ`
and no `b64` header.

## Boundaries

| ABP surface | Discovery-side fact | Relationship |
|---|---|---|
| Artifact identity | Catalog entries have a content digest; URL artifacts hash retrieved bytes and inline data hashes JCS bytes | ABP content digests use a different, domain-separated preimage |
| Signatures | Catalog uses detached compact JWS over a JCS payload, requires the protected `typ` marker, and forbids the protected `b64` header | ABP uses RFC 7797 `b64=false`; signatures are not interchangeable |
| Subject binding | A signed catalog manifest binds its contributor and subject; release coverage compares identifier, type, digest and optional version | These discovery checks do not establish ABP structure, bounds or deployment binding |
| Capability discovery | ARD has capability tokens and JSON-LD extension terms | Tokens do not provide ABP's typed port, bound, effect or evaluation contracts |
| Artifact location | Catalog entries reference `url` or embed `data` | An entry can point at canonical ABP bytes; retrieval does not imply verification |

ARD's normative path is `/.well-known/ard.json`; its predecessor path is an
optional compatibility source. ARD defers cryptography to a declared trust
framework. Neither that framework nor a catalog signature substitutes for
ABP verification, and an ABP pass grants no discovery or execution authority.
