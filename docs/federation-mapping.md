# Federation profile — the A2A / MCP Tasks field mapping

The Agent Blueprint Protocol's federation profile maps every logical task
and evidence field against the CURRENT A2A and MCP Tasks contracts before
inventing anything (the mapping-before-inventing law). The verdict, re-derived
against the live sources below: **3 fields map natively, 5 partially, and 15
have no safe native home** — so no protocol-native wire field and no native
transport are warranted. The profile is one registered extension
(`io.github.baselabs/federation`, critical) carried inside each transport's
untyped extension channel, with the same JCS-canonical object and the same
detached Ed25519 signature envelope on both.

## Pinned sources (re-derived 2026-11-10)

The transport baseline is released A2A v1.0.1, not a candidate. The MCP Tasks
extension has released tags, including v0.2.3; its dated 2026-07-28 contract
remains Beta. The following plain SHA-1 values identify exact source files.

| Source | Version / path | plain SHA-1 | Canonical URL |
|---|---|---|---|
| `a2a.proto` | A2A v1.0.1, `specification/a2a.proto` | `2e005333992e47f9a03392f938e252ede8eaf603` | [released proto](https://github.com/a2aproject/A2A/blob/v1.0.1/specification/a2a.proto) |
| A2A specification | A2A v1.0.1, `docs/specification.md` | `6bf47754e845c854cc771a7c30e04d3e10ce00e1` | [released specification](https://github.com/a2aproject/A2A/blob/v1.0.1/docs/specification.md) |
| `ext-tasks` spec | v0.2.3, `specification/2026-07-28/tasks.md` | `1eb549d56df0a67b1df6367d392fba85952dfa49` | [dated tasks specification](https://github.com/modelcontextprotocol/ext-tasks/blob/v0.2.3/specification/2026-07-28/tasks.md) |
| `ext-tasks` schema | v0.2.3, `schema/2026-07-28/schema.ts` | `49d3d7ffa0d0c6e3a7b02691f8e2cce4ce1e3892` | [dated schema](https://github.com/modelcontextprotocol/ext-tasks/blob/v0.2.3/schema/2026-07-28/schema.ts) |
| `ext-tasks` types | v0.2.3, `schema/2026-07-28/spec.types.ts` | `3e3af71bcb179ce58ddba58e441032194944e0cb` | [dated types](https://github.com/modelcontextprotocol/ext-tasks/blob/v0.2.3/schema/2026-07-28/spec.types.ts) |

The released proto preserves the mapped task, context, message, and part
locations; `AgentSkill.output_modes` is line 449. Tasks retains `taskId`,
`ttlMs`, status variants, and `CompletedTask.result` at the cited schema
locations. The dated contract confirms cooperative cancellation and that TTL
concerns task retention. A2A's AgentCard field-presence rules remain before
JCS in its signing procedure. The A2A v1.1.0-rc line is informative only.

## The mapping table

Verdicts: **native** = the transport field carries the semantic exactly;
**partial** = a native home exists but loses or misplaces the semantic;
**extension** = no native home; the field rides the extension body.

| # | Logical field | A2A location | MCP Tasks location | Verdict |
|---|---|---|---|---|
| 1 | task identity | `Task.id` (a2a.proto:170) | `Task.taskId` (mcp-schema.ts:47) | native |
| 2 | idempotency identity | none — `Message.message_id` (a2a.proto:262) is a message id, not an idempotency key | none | extension |
| 3 | parent execution reference | `Message.reference_task_ids` (a2a.proto:276), `Task.context_id` (a2a.proto:173) — a reference, not a parent execution | none | partial |
| 4 | initiating subject | none — `SecurityScheme`/`SecurityRequirement` (a2a.proto:495-517) are transport-level | none — transport auth | extension |
| 5 | exact Blueprint digest | none | none | extension |
| 6 | exact Deployment digest | none | none | extension |
| 7 | input commitment | `Message.parts[].data` (a2a.proto:233), `Part.metadata` (a2a.proto:236) — a payload home, not a digest commitment | request params | partial |
| 8 | result schema identity | `Part.media_type` (a2a.proto:241), `AgentSkill.output_modes` (a2a.proto:449) — a media type is not a schema identity | `CompletedTask.result {[key: string]: unknown}` (mcp-schema.ts:135) | extension |
| 9 | result classification ceiling | none | none | extension |
| 10 | bounded time policy | `SendMessageConfiguration` (a2a.proto:143-161) has no time bound | `Task.ttlMs` (mcp-schema.ts:82) | partial |
| 11 | bounded resource policy | none | none | extension |
| 12 | recovery handle | `Task.id` + `GetTask` (a2a.proto:45) | `taskId` + `tasks/get` | native |
| 13 | issuer | transport-level only (`SecurityScheme`) | transport auth | extension |
| 14 | subject | none | none | extension |
| 15 | audience | none | none | extension |
| 16 | local identity-mapping evidence | none | none | extension |
| 17 | typed checkpoint request | `TASK_STATE_INPUT_REQUIRED` (a2a.proto:201) + `TaskStatus.message` — free-form, not typed | `status input_required` + `inputRequests` (`InputRequest` union: elicitation/sampling/roots; mcp-schema.ts:111-119, mcp-spec.types.ts:545) | partial |
| 18 | checkpoint status | `TaskStatus.state` (a2a.proto:213) | `Task.status` (mcp-schema.ts:31-36) | native |
| 19 | checkpoint decision commitment | none | `tasks/update inputResponses` (mcp-schema.ts:232-246) carries responses, no commitment digest | extension |
| 20 | terminal state | `TASK_STATE_COMPLETED/FAILED/CANCELED/REJECTED` (a2a.proto:194-205) | `completed/failed/cancelled` (mcp-schema.ts:31-36) | partial |
| 21 | signed evidence receipt | `AgentCardSignature` (a2a.proto:455-467) signs the **AgentCard**, not a task result | none | extension |
| 22 | exact compatibility reference | `AgentCard.version` (a2a.proto:374-376) — a version string, not an exact build identity | none | extension |
| 23 | authority-proof references | transport-level only | transport auth | extension |

The same rows are shipped as data: `AgentBlueprintProtocol.federation_mapping/0`.

## Transport flags (binding on host adapters)

**A2A is the primary lane.** The MCP Tasks mapping ships **flagged
draft-tracking**: the extension lives outside MCP core, has released
tags, and remains Beta. The reopen trigger is when the MCP tasks extension
leaves Beta. The deferred native-wire work remains deferred.

**`ttlMs` is not an execution bound.** MCP's `Task.ttlMs` is a storage
TTL — "the server MAY discard the task after the TTL elapses", and the
value MAY change over a task's lifetime. It bounds record retention, not
work; the envelope's `time_policy` is the execution bound and rides the
extension body on both transports.

**`AUTH_REQUIRED` is not authorization.** A2A §7.6.4: agents MUST NOT
treat the `TASK_STATE_AUTH_REQUIRED` state transition, by itself, as
authorization for any operation. `:auth_required` crossing into MCP denies
(`:federation_state_unmappable` — MCP has no counterpart state); inside
A2A it is an interrupted state, never a terminal receipt.

**AgentCard signatures need protobuf pre-normalization.** A2A §8.4.1
specifies the canonicalization for AgentCard signing: BEFORE RFC 8785
JCS, the JSON must respect proto3 field presence — unset optional fields
omitted, explicitly-set optionals kept even at default values, REQUIRED
fields always present, default values omitted unless REQUIRED/optional,
and the `signatures` field excluded from the signed content. A host
adapter that JCS-canonicalizes the received card JSON directly computes a
different preimage and verification fails silently.

## Carrier keys and lossy-state rules

The envelope rides `Task.metadata[<a2a_uri>]` on A2A (keyed by the
registry entry's `https://baselabs.github.io/agent_blueprint_protocol/extensions/federation`, following
A2A's URI-keyed metadata convention) and `_meta["io.github.baselabs/federation"]`
on MCP (the reverse-DNS namespace; the MCP `_meta` key grammar forbids a
`://` URI key). The same JCS-canonical object under both.

State mapping is explicit and lossy-aware: A2A
`TASK_STATE_UNSPECIFIED` denies `:federation_state_unmappable` at intake;
crossing into MCP denies for `:rejected` (terminal, no MCP counterpart)
and `:submitted`/`:auth_required` (no counterpart) — never a silent
degrade. `cancelled` (MCP) folds to `:canceled` (A2A single-L).
Cancellation is a request, never a terminal receipt: no codec path
synthesizes terminal evidence from a cancel request or acknowledgment
(MCP cancellation is cooperative and eventually consistent — a cancelled
task "MAY ultimately reach a terminal status other than cancelled").

Correlation grants nothing. The envelope's identity fields
(`issuer`/`subject`/`audience` and the identity-mapping evidence) are
correlation only; an authority-shaped claim in the evidence block denies
`:nonportable_content`. Two terminal receipts for one task identity
diverging in ANY commitment component — not just state — deny
`:federation_terminal_conflict`.

## Receiver posture

**Purpose pinning.** `verify_commitment/2` accepts only signatures whose
signed `purpose` is `federation-envelope` — a signature minted for a
blueprint or deployment never verifies a federation receipt, whatever
digest it names.

**Key ids are labels, and the signature blob is opaque.** The receipt's
`kid`/`key_id` positions are portability-scanned in the strict mode: a PEM
block or hex secret riding a key id denies `:forbidden_portable_value`.
Use named, low-entropy key labels (the corpus shape), not embedded
fingerprints. The signature member itself is deliberately unscanned —
every honest signature is entropy-dense by nature; it never survives
verification without the matching key.

**Keys are not issuers — but attribution is expressible.** The flat
`Context.keys` pool matches by `key_id` only; nothing binds a key to the
receipt's self-declared `issuer` string. Receivers wanting per-issuer
attribution set `Context.issuer_key_sets` (issuer → keys): the receipt's
claimed `issuer` member — proven signed by the binding step — selects the
pool for the signature attempt, org-B's key never verifies a receipt
claiming org-A, and precedence is strictest-wins (sets non-nil ⇒ the flat
pool is ignored; an empty map trusts no issuer). Possession-of-key ==
signing authority remains the default model for single-issuer receivers.

**Replay is the receiver's policy — with a signed-staleness mechanism.**
A receipt re-verifies idempotently; divergence-replay is
`prior_receipts` state. Staleness is enforceable over signed bytes:
`Context.created_after`/`created_before` bound the signed `created_at`
(RFC 3339 Z-form, inclusive both ends; the receiver supplies the window,
the package never invents a clock), checked after conflict detection so
integrity and consistency outrank receiver policy.

**The codec lane is bounded like the decode lane.** Carrier
reconstruction (`from_a2a_carrier`/`from_mcp_carrier`) re-imposes the
decoder's member/item/node/string/depth ceilings and the UTF-8 gate on
hand-built carrier maps — a hostile carrier cannot buy unbounded
validation work or crash later digest encodes with non-UTF-8 bytes.

## One namespace, two bodies

`io.github.baselabs/federation` names two deliberately distinct objects: the
ARTIFACT-side critical-extension body a Blueprint declares (the
digest-pinned issuer/subject/audience trio in the compiled-in extension
registry, validated at negotiation) and the WIRE-side TaskEnvelope
extension body (the 23-member JCS object under the carrier key, validated
by the Federation field table, which never passes through negotiation).
The artifact-side schema is a frozen-digest contract for a different
surface; widening it to cover the envelope would re-pin a shipped digest
for no negotiation-time gain.
