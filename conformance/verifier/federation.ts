// The federation profile — the mirror of AgentBlueprintProtocol.Federation:
// the 23-member TaskEnvelope decoded through the registry engine (carrier-key
// placement laws, R1-R4 root hooks), the lossy-aware A2A/MCP state codecs
// (federation_state_unmappable, never a silent degrade), the bounded
// from_value reconstruction path, and verify_commitment's numbered steps
// (terminal members → JWS verify → binding → commitment recompute → context
// compare → prior-receipt conflict → signed freshness).

import type { Bounds } from "./bounds.ts";
import { MAXIMA as CEILINGS, coerce as coerceBounds, maximum as maxBounds } from "./bounds.ts";
import * as blueprint from "./blueprint.ts";
import * as canonical from "./canonical.ts";
import * as digest from "./digest.ts";
import { entry as compiledEntry } from "./registry.ts";
import { field, keyfind, validate, type Spec } from "./registry_engine.ts";
import * as portability from "./portability.ts";
import * as signature from "./signature.ts";
import type { Value } from "./value.ts";

export interface Envelope {
  value: Value;
}

export interface PriorReceipt {
  taskIdentity: string;
  terminalState: string;
  terminalCommitment: digest.Digest;
}

export interface Context {
  keys: signature.PublicKey[];
  // issuer/subject/audience ride as RAW tagged values: the twin compares the
  // envelope member against {:string, pin} exactly — a present non-string pin
  // DENIES the audience check, never silently skips it. null/undefined = no pin.
  issuer?: unknown;
  subject?: unknown;
  audience?: unknown;
  issuerKeySets: Record<string, signature.PublicKey[]> | null;
  createdAfter?: string;
  createdBefore?: string;
  priorReceipts: PriorReceipt[];
}

export type CodecResult = { ok: true; v: string | { decoded: true } } | { ok: false; e: string };

type VResult = { ok: true } | { ok: false; e: string };

const IDENTIFIER_BYTES = 512;
const SEGMENT = /^[a-z0-9][a-z0-9._-]*$/;
const Z_FORM = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;

const CLASSIFICATION = ["public", "internal", "confidential", "restricted"];
const REGULATED_MARKERS = ["pci", "phi"];
const CLAIM_KINDS = ["correlation", "binding", "authority"];
const CHECKPOINT_KINDS = ["input_required", "auth_required"];
const CHECKPOINT_STATUSES = ["submitted", "working", "input_required", "auth_required"];
const TERMINAL_STATES = ["completed", "failed", "canceled", "rejected"];
const TERMINAL_ATOMS = ["completed", "failed", "canceled", "rejected"];

const NATIVE_MEMBERS = ["task_identity", "recovery_handle", "checkpoint_status", "terminal_state"];

const A2A_TO_LOGICAL: Record<string, string> = {
  TASK_STATE_SUBMITTED: "submitted",
  TASK_STATE_WORKING: "working",
  TASK_STATE_COMPLETED: "completed",
  TASK_STATE_FAILED: "failed",
  TASK_STATE_CANCELED: "canceled",
  TASK_STATE_INPUT_REQUIRED: "input_required",
  TASK_STATE_REJECTED: "rejected",
  TASK_STATE_AUTH_REQUIRED: "auth_required",
};

const LOGICAL_TO_A2A: Record<string, string> = Object.fromEntries(
  Object.entries(A2A_TO_LOGICAL).map(([k, v]) => [v, k]),
);

const MCP_TO_LOGICAL: Record<string, string> = {
  working: "working",
  input_required: "input_required",
  completed: "completed",
  failed: "failed",
  cancelled: "canceled",
};

const LOGICAL_TO_MCP: Record<string, string> = {
  working: "working",
  input_required: "input_required",
  completed: "completed",
  failed: "failed",
  canceled: "cancelled",
};

// The runner's @logical_states gate: to_* codecs receive a wire spelling of
// one of the eight logical states.
const WIRE_LOGICAL_STATES = [
  "submitted",
  "working",
  "completed",
  "failed",
  "canceled",
  "rejected",
  "input_required",
  "auth_required",
];

const enumSet = (values: string[]) => new Set(values);

// ---- the field table (23 members, bijective with the mapping rows) ---------------

function classificationElement(): Spec["kind"] {
  return {
    object: {
      members: [
        field("level", { enum: enumSet(CLASSIFICATION) }),
        field("markers", { array: { kind: { enum: enumSet(REGULATED_MARKERS) } } }, {
          uniqueBy: ":value",
        }),
      ],
    },
  };
}

function identityEvidenceElement(): Spec["kind"] {
  return {
    object: {
      members: [
        field("claims", {
          array: {
            kind: {
              object: {
                members: [
                  field("kind", { enum: enumSet(CLAIM_KINDS) }),
                  field("value", "string", { check: checkNonempty }),
                ],
              },
            },
          },
        }, { minItems: 1, uniqueBy: "value" }),
      ],
    },
  };
}

function table(): Spec[] {
  return [
    field("task_identity", "string", { check: checkIdentifier }),
    field("idempotency_identity", "string", { check: checkIdentifier }),
    field("parent_execution_reference", "string", {
      required: false,
      check: checkIdentifier,
      rootHook: hookParent,
    }),
    field("initiating_subject", "string", { required: false, check: checkIdentifier }),
    field("blueprint_digest", "custom", { check: checkTaggedDigest }),
    field("deployment_digest", "custom", { check: checkTaggedDigest }),
    field("input_commitment", "custom", { check: checkTaggedDigest }),
    field("result_schema", "custom", { check: checkTaggedDigest }),
    field("result_classification_ceiling", classificationElement()),
    field("time_policy", {
      object: { members: [field("elapsed_ms", "integer", { check: checkPositive })] },
    }),
    field("resource_policy", {
      object: {
        members: [
          field("attempts", "integer", { check: checkPositive }),
          field("concurrency", "integer", { check: checkPositive }),
          field("tokens", "integer", { check: checkPositive }),
          field("cost", "integer", { check: checkPositive }),
        ],
      },
    }),
    field("recovery_handle", "string", { check: checkIdentifier }),
    field("issuer", "string", { check: checkIdentifier }),
    field("subject", "string", { check: checkIdentifier }),
    field("audience", "string", { check: checkIdentifier }),
    field("identity_mapping_evidence", identityEvidenceElement()),
    field("checkpoint_request", {
      object: {
        members: [
          field("kind", { enum: enumSet(CHECKPOINT_KINDS) }),
          field("request_digest", "custom", { check: checkTaggedDigest }),
        ],
      },
    }, { required: false }),
    field("checkpoint_status", { enum: enumSet(CHECKPOINT_STATUSES) }, {
      required: false,
      rootHook: hookCheckpoint,
    }),
    field("checkpoint_commitment", "custom", {
      required: false,
      check: checkTaggedDigest,
      rootHook: hookCheckpoint,
    }),
    field("terminal_state", { enum: enumSet(TERMINAL_STATES) }, {
      required: false,
      rootHook: hookTerminal,
    }),
    field("evidence_receipt", {
      object: {
        members: [
          field("result_digest", "custom", { check: checkTaggedDigest }),
          field("checkpoint_history_commitment", "custom", { check: checkTaggedDigest }),
          field("terminal_commitment", "custom", { check: checkTaggedDigest }),
          field("signature", "custom", { check: checkSignatureShape }),
        ],
      },
    }, { required: false, rootHook: hookTerminal }),
    field("compatibility_reference", {
      array: {
        kind: {
          object: {
            members: [
              field("name", "string", { check: checkIdentifier }),
              field("identity", "string", { check: checkNonempty }),
            ],
          },
        },
      },
    }, { minItems: 1, uniqueBy: "name" }),
    field("authority_proof_references", { array: { kind: "custom", check: checkTaggedDigest } }),
  ];
}

// ---- member checks -------------------------------------------------------------------

function checkIdentifier(value: Value): VResult {
  if (value.t !== "str") return { ok: false, e: "invalid_constraint" };
  return Buffer.byteLength(value.v, "utf8") <= IDENTIFIER_BYTES && SEGMENT.test(value.v)
    ? { ok: true }
    : { ok: false, e: "invalid_constraint" };
}

function checkNonempty(value: Value): VResult {
  if (value.t === "str" && value.v !== "") return { ok: true };
  return { ok: false, e: "invalid_constraint" };
}

function checkPositive(value: Value): VResult {
  if (value.t === "int" && value.v >= 1) return { ok: true };
  return { ok: false, e: "invalid_constraint" };
}

function checkTaggedDigest(value: Value): VResult {
  if (value.t !== "str") return { ok: false, e: "invalid_type" };
  return digest.fromTagged(value.v).ok ? { ok: true } : { ok: false, e: "invalid_constraint" };
}

// The receipt's JWS entry must at least parse as the §8.3 envelope; its
// cryptographic facts are verify_commitment's to establish.
function checkSignatureShape(entry: Value): VResult {
  const input = signature.signingInput(entry);
  return input.ok ? { ok: true } : { ok: false, e: "invalid_constraint" };
}

// ---- root hooks (R1-R3 + terminal-supersedes) ---------------------------------------

function hookParent(members: Map<string, Value>): VResult {
  if (members.has("parent_execution_reference") && !members.has("initiating_subject")) {
    return { ok: false, e: "invalid_constraint" };
  }
  return { ok: true };
}

function hookCheckpoint(members: Map<string, Value>): VResult {
  const status = members.has("checkpoint_status");
  const commitment = members.has("checkpoint_commitment");
  if (status !== commitment) return { ok: false, e: "invalid_constraint" };
  if (status && members.has("terminal_state")) return { ok: false, e: "invalid_constraint" };
  return { ok: true };
}

function hookTerminal(members: Map<string, Value>): VResult {
  const terminal = members.has("terminal_state");
  const receipt = members.has("evidence_receipt");
  if (terminal !== receipt) return { ok: false, e: "invalid_constraint" };
  return { ok: true };
}

// ---- decode -------------------------------------------------------------------------

export function decode(
  bytes: Buffer | string,
  bounds?: Bounds | Record<string, unknown>,
): { ok: true; v: Envelope } | { ok: false; e: string } {
  if (typeof bytes !== "string" && !Buffer.isBuffer(bytes)) {
    return { ok: false, e: "invalid_type" };
  }
  const profile = normalizeBounds(bounds);
  if (!profile.ok) return profile;

  const verified = canonical.verify(bytes, profile.v);
  if (!verified.ok) return verified;
  const value = verified.v;

  const validated = validate(table(), value);
  if (!validated.ok) return validated;

  const scanned = scan(value);
  if (!scanned.ok) return scanned;

  return { ok: true, v: { value } };
}

// The codec-reconstruction path: registry walk + portability pass over an
// already-decoded value, with the decoder's ceilings re-imposed (a hostile
// carrier body cannot buy unbounded work the decode lane would have refused).
export function fromValue(value: Value): { ok: true; v: Envelope } | { ok: false; e: string } {
  if (value.t !== "obj") return { ok: false, e: "invalid_type" };
  const bounded = boundedShape(value);
  if (!bounded.ok) return bounded;
  const validated = validate(table(), value);
  if (!validated.ok) return validated;
  const scanned = scan(value);
  if (!scanned.ok) return scanned;
  return { ok: true, v: { value } };
}

function normalizeBounds(bounds?: Bounds | Record<string, unknown>): { ok: true; v: Bounds } | { ok: false; e: string } {
  if (bounds === undefined) return { ok: true, v: maxBounds() };
  return coerceBounds(bounds as Record<string, unknown>);
}

// ---- the bounded shape walk (from_value's decoder-parity gate) ----------------------

interface ShapeAcc {
  members: number;
  items: number;
  nodes: number;
  string: number;
  depth: number;
}

function boundedShape(value: Value): VResult {
  return shapeWalk(value, { members: 0, items: 0, nodes: 0, string: 0, depth: 0 });
}

function shapeWalk(value: Value, acc: ShapeAcc): VResult {
  const entry = ceiling(acc);
  if (!entry.ok) return entry;

  switch (value.t) {
    case "obj": {
      const bumped = bump(acc, { members: value.v.length, nodes: 1, depth: 1 });
      return walkShapeMembers(value.v, bumped);
    }
    case "arr": {
      const bumped = bump(acc, { items: value.v.length, nodes: 1, depth: 1 });
      return walkShapeItems(value.v, bumped);
    }
    case "str": {
      const bumped = bump(acc, { nodes: 1, string: Buffer.byteLength(value.v, "utf8"), depth: 1 });
      return ceiling(bumped);
    }
    default:
      return ceiling(bump(acc, { nodes: 1 }));
  }
}

function walkShapeMembers(members: [string, Value][], acc: ShapeAcc): VResult {
  for (const [, value] of members) {
    const result = shapeWalk(value, acc);
    if (!result.ok) return result;
  }
  return { ok: true };
}

function walkShapeItems(items: Value[], acc: ShapeAcc): VResult {
  for (const item of items) {
    const result = shapeWalk(item, acc);
    if (!result.ok) return result;
  }
  return { ok: true };
}

function bump(acc: ShapeAcc, adds: Partial<Record<keyof ShapeAcc, number>>): ShapeAcc {
  const out = { ...acc };
  for (const [key, add] of Object.entries(adds)) {
    out[key as keyof ShapeAcc] += add!;
  }
  return out;
}

function ceiling(acc: ShapeAcc): VResult {
  const checks: [keyof ShapeAcc, number, string][] = [
    ["members", CEILINGS.members, "members"],
    ["items", CEILINGS.items, "items"],
    ["nodes", CEILINGS.nodes, "nodes"],
    ["string", CEILINGS.string, "string"],
    ["depth", CEILINGS.depth, "depth"],
  ];
  for (const [key, max, name] of checks) {
    if (acc[key] > max) return { ok: false, e: `ceiling:${name}` };
  }
  return { ok: true };
}

// ---- canonical bytes ------------------------------------------------------------------

export function canonicalBytes(envelope: Envelope): { ok: true; v: string } | { ok: false; e: string } {
  return canonical.encode(envelope.value);
}

// ---- the federation portability pass (mode map + R4) ----------------------------------

const IDENTIFIER_SCANNED = [
  "task_identity",
  "idempotency_identity",
  "parent_execution_reference",
  "initiating_subject",
  "recovery_handle",
  "issuer",
  "subject",
  "audience",
];

function scan(value: Value): VResult {
  if (value.t !== "obj") return { ok: true };
  for (const [name, member] of value.v) {
    if (name === "identity_mapping_evidence" && member.t === "obj") {
      const claims = keyfind(member.v, "claims");
      if (claims !== null && claims.t === "arr") {
        for (const [index, claim] of claims.v.entries()) {
          const result = claimScan(claim, index);
          if (!result.ok) return result;
        }
      }
      continue;
    }
    if (name === "compatibility_reference" && member.t === "arr") {
      for (const entry of member.v) {
        if (entry.t !== "obj") continue;
        const identity = keyfind(entry.v, "identity");
        if (identity === null) continue;
        const result = portability.scanValue(identity);
        if (!result.ok) return result;
      }
      continue;
    }
    if (name === "evidence_receipt" && member.t === "obj") {
      const entry = keyfind(member.v, "signature");
      if (entry !== null && entry.t === "obj") {
        for (const [position, value] of keyIdPositions(entry.v)) {
          const result = portability.scanValue(value);
          if (!result.ok) return { ok: false, e: result.e };
        }
      }
      continue;
    }
    if (IDENTIFIER_SCANNED.includes(name)) {
      const result = portability.scanIdentifier(member);
      if (!result.ok) return result;
      continue;
    }
  }
  return { ok: true };
}

// R4: correlation grants nothing — an authority-shaped claim is nonportable
// content, denied with the claim's schema path.
function claimScan(claim: Value, index: number): VResult {
  if (claim.t !== "obj") return { ok: true };
  const kind = keyfind(claim.v, "kind");
  if (kind !== null && kind.t === "str" && kind.v === "authority") {
    return { ok: false, e: "nonportable_content" };
  }
  const value = keyfind(claim.v, "value");
  if (value === null) return { ok: true };
  const result = portability.scanValue(value);
  return result.ok ? { ok: true } : { ok: false, e: result.e };
}

// The receipt's signature entry carries key ids in two positions (protected
// kid and signed key_id — equal by the JWS shape check), both scanned STRICT.
function keyIdPositions(entry: [string, Value][]): [string, Value][] {
  const header = keyfind(entry, "protected");
  const attrs = keyfind(entry, "signed_attributes");
  if (header === null || header.t !== "obj" || attrs === null || attrs.t !== "obj") return [];
  const kid = keyfind(header.v, "kid");
  const keyId = keyfind(attrs.v, "key_id");
  if (kid === null || keyId === null) return [];
  return [
    ["kid", kid],
    ["key_id", keyId],
  ];
}

// ---- state codecs: lossy-aware by construction -----------------------------------------

export function fromA2aState(spelling: string): CodecResult {
  if (typeof spelling !== "string") return { ok: false, e: "invalid_type" };
  if (spelling in A2A_TO_LOGICAL) return { ok: true, v: A2A_TO_LOGICAL[spelling]! };
  if (spelling === "TASK_STATE_UNSPECIFIED") {
    return { ok: false, e: "federation_state_unmappable" };
  }
  return { ok: false, e: "invalid_constraint" };
}

export function toA2aState(spelling: string): CodecResult {
  // The runner's to_logical_state gate: only the eight wire spellings of the
  // logical states reach the codec; anything else denies invalid_type.
  if (!WIRE_LOGICAL_STATES.includes(spelling)) return { ok: false, e: "invalid_type" };
  return { ok: true, v: LOGICAL_TO_A2A[spelling]! };
}

export function fromMcpState(spelling: string): CodecResult {
  if (typeof spelling !== "string") return { ok: false, e: "invalid_type" };
  if (spelling in MCP_TO_LOGICAL) return { ok: true, v: MCP_TO_LOGICAL[spelling]! };
  return { ok: false, e: "invalid_constraint" };
}

export function toMcpState(spelling: string): CodecResult {
  if (!WIRE_LOGICAL_STATES.includes(spelling)) return { ok: false, e: "invalid_type" };
  const mapped = LOGICAL_TO_MCP[spelling];
  if (mapped === undefined) return { ok: false, e: "federation_state_unmappable" };
  return { ok: true, v: mapped };
}

// ---- carriers: the placement laws, per transport ----------------------------------------

// The A2A-side carrier key: the registry entry's a2a_uri.
export function a2aCarrierKey(): string {
  return compiledEntry("com.example/federation")!.a2a_uri;
}

// The MCP-side carrier key: the registry namespace.
export function mcpCarrierKey(): string {
  return "com.example/federation";
}

export function fromA2aCarrier(carrier: Value): CodecResult {
  if (carrier.t !== "obj") return { ok: false, e: "invalid_type" };
  const id = carrierString(carrier.v, "id");
  if (!id.ok) return id;
  const stateRaw = carrierState(carrier.v);
  if (!stateRaw.ok) return stateRaw;
  const logical = fromA2aState(stateRaw.v);
  if (!logical.ok) return logical;
  const body = carrierBody(carrier.v, "metadata", a2aCarrierKey());
  if (!body.ok) return body;
  const placed = noDoublePlacement(body.v);
  if (!placed.ok) return placed;
  const rebuilt = rebuild(id.v, logical.v as string, body.v);
  return rebuilt.ok ? { ok: true, v: { decoded: true } } : rebuilt;
}

export function fromMcpCarrier(carrier: Value): CodecResult {
  if (carrier.t !== "obj") return { ok: false, e: "invalid_type" };
  const id = carrierString(carrier.v, "taskId");
  if (!id.ok) return id;
  const stateRaw = carrierString(carrier.v, "status");
  if (!stateRaw.ok) return stateRaw;
  const logical = fromMcpState(stateRaw.v);
  if (!logical.ok) return logical;
  const body = carrierBody(carrier.v, "_meta", mcpCarrierKey());
  if (!body.ok) return body;
  const placed = noDoublePlacement(body.v);
  if (!placed.ok) return placed;
  const rebuilt = rebuild(id.v, logical.v as string, body.v);
  return rebuilt.ok ? { ok: true, v: { decoded: true } } : rebuilt;
}

function carrierString(members: [string, Value][], name: string): { ok: true; v: string } | { ok: false; e: string } {
  const found = keyfind(members, name);
  if (found === null) return { ok: false, e: "missing_required_field" };
  if (found.t !== "str") return { ok: false, e: "invalid_type" };
  return { ok: true, v: found.v };
}

function carrierState(members: [string, Value][]): { ok: true; v: string } | { ok: false; e: string } {
  const found = keyfind(members, "status");
  if (found === null) return { ok: false, e: "missing_required_field" };
  if (found.t !== "obj") return { ok: false, e: "invalid_type" };
  return carrierString(found.v, "state");
}

function carrierBody(
  members: [string, Value][],
  envelopeMember: string,
  key: string,
): { ok: true; v: [string, Value][] } | { ok: false; e: string } {
  const found = keyfind(members, envelopeMember);
  if (found === null) return { ok: false, e: "missing_required_field" };
  if (found.t !== "obj") return { ok: false, e: "invalid_type" };
  const inner = keyfind(found.v, key);
  if (inner === null) return { ok: false, e: "missing_required_field" };
  if (inner.t !== "obj") return { ok: false, e: "invalid_type" };
  return { ok: true, v: inner.v };
}

// A native member appearing in the body is a double placement.
function noDoublePlacement(body: [string, Value][]): VResult {
  for (const [name] of body) {
    if (NATIVE_MEMBERS.includes(name)) return { ok: false, e: "federation_mapping_conflict" };
  }
  return { ok: true };
}

function rebuild(id: string, logical: string, body: [string, Value][]): { ok: true } | { ok: false; e: string } {
  const stateMember = TERMINAL_ATOMS.includes(logical) ? "terminal_state" : "checkpoint_status";
  const members: [string, Value][] = [
    ["task_identity", { t: "str", v: id }],
    ["recovery_handle", { t: "str", v: id }],
    [stateMember, { t: "str", v: logical }],
    ...body,
  ];
  return fromValue({ t: "obj", v: members });
}

// ---- terminal commitment + verify_commitment ---------------------------------------------

// The Terminal Commitment: the domain-separated digest over exactly the
// seven named components.
export function terminalCommitment(envelope: Envelope): { ok: true; v: digest.Digest } | { ok: false; e: string } {
  if (envelope.value.t !== "obj") return { ok: false, e: "invalid_type" };
  const members = new Map(envelope.value.v);

  const taskOk = stringMember(members, "task_identity");
  if (!taskOk.ok) return taskOk;
  const terminalOk = stringMember(members, "terminal_state");
  if (!terminalOk.ok) return terminalOk;

  const receipt = receiptOf(members);
  if (!receipt.ok) return receipt;
  const resultDigest = receiptFetch(receipt.v, "result_digest");
  if (!resultDigest.ok) return resultDigest;
  const history = receiptFetch(receipt.v, "checkpoint_history_commitment");
  if (!history.ok) return history;

  const ordered: [string, Value][] = [
    ["task_identity", members.get("task_identity")!],
    ["terminal_state", members.get("terminal_state")!],
    ["result_digest", resultDigest.v],
    ["result_classification_ceiling", members.get("result_classification_ceiling")!],
    ["compatibility_reference", members.get("compatibility_reference")!],
    ["authority_proof_references", members.get("authority_proof_references")!],
    ["checkpoint_history_commitment", history.v],
  ];

  const jcs = canonical.encode({ t: "obj", v: ordered });
  if (!jcs.ok) return jcs;
  return { ok: true, v: digest.hash("federation_envelope", Buffer.from(jcs.v, "utf8")) };
}

export function verifyCommitment(
  envelope: Envelope,
  context: Context,
): { ok: true; v: { taskIdentity: string } } | { ok: false; e: string } {
  if (envelope.value.t !== "obj") return { ok: false, e: "invalid_type" };
  const members = new Map(envelope.value.v);

  const taskOk = stringMember(members, "task_identity");
  if (!taskOk.ok) return taskOk;
  const terminalOk = stringMember(members, "terminal_state");
  if (!terminalOk.ok) return terminalOk;

  const receipt = receiptOf(members);
  if (!receipt.ok) return receipt;
  const signatureEntry = receiptFetch(receipt.v, "signature");
  if (!signatureEntry.ok) return signatureEntry;

  const pool = resolvePool(members, context);
  if (!pool.ok) return pool;

  const sigOk = signatureCheck(signatureEntry.v, pool.v.pool, pool.v.attributed);
  if (!sigOk.ok) return sigOk;

  const binding = bindingCheck(envelope.value, signatureEntry.v);
  if (!binding.ok) return binding;

  const commitment = terminalCommitment(envelope);
  if (!commitment.ok) return commitment;

  const commitmentOk = commitmentCheck(receipt.v, commitment.v);
  if (!commitmentOk.ok) return commitmentOk;

  const contextOk = contextCompare(members, context);
  if (!contextOk.ok) return contextOk;

  const conflictOk = conflictCheck(members, commitment.v, context);
  if (!conflictOk.ok) return conflictOk;

  const fresh = freshnessCheck(signatureEntry.v, context);
  if (!fresh.ok) return fresh;

  const taskIdentity = members.get("task_identity");
  return { ok: true, v: { taskIdentity: (taskIdentity as { t: "str"; v: string }).v } };
}

function stringMember(members: Map<string, Value>, name: string): VResult {
  const found = members.get(name);
  if (found === undefined) return { ok: false, e: "missing_required_field" };
  if (found.t !== "str") return { ok: false, e: "invalid_type" };
  return { ok: true };
}

function receiptOf(members: Map<string, Value>): { ok: true; v: [string, Value][] } | { ok: false; e: string } {
  const found = members.get("evidence_receipt");
  if (found === undefined) return { ok: false, e: "missing_required_field" };
  if (found.t !== "obj") return { ok: false, e: "invalid_type" };
  return { ok: true, v: found.v };
}

function receiptFetch(receipt: [string, Value][], name: string): { ok: true; v: Value } | { ok: false; e: string } {
  const found = keyfind(receipt, name);
  if (found === null) return { ok: false, e: "missing_required_field" };
  return { ok: true, v: found };
}

function signatureCheck(
  entry: Value,
  pool: signature.PublicKey[],
  attributed: boolean,
): VResult {
  const verified = signature.verify(entry, pool);
  if (verified.ok) return { ok: true };
  // The key-miss class under attribution names the issuer; envelope and
  // algorithm failures keep the signature subject.
  return { ok: false, e: verified.e };
}

// Pool resolution: the flat pool is used only when issuer_key_sets is
// nil; the claimed issuer member selects the pool from validated sets, a
// forged absent/non-string issuer selecting the literal empty pool.
function resolvePool(
  members: Map<string, Value>,
  context: Context,
): { ok: true; v: { pool: signature.PublicKey[]; attributed: boolean } } | { ok: false; e: string } {
  if (context.issuerKeySets === null || context.issuerKeySets === undefined) {
    if (!Array.isArray(context.keys)) return { ok: false, e: "invalid_type" };
    return { ok: true, v: { pool: context.keys, attributed: false } };
  }
  const sets = context.issuerKeySets;
  for (const [issuer, pool] of Object.entries(sets)) {
    if (typeof issuer !== "string" || !Array.isArray(pool)) {
      return { ok: false, e: "invalid_type" };
    }
  }
  const claimed = members.get("issuer");
  if (claimed !== undefined && claimed.t === "str") {
    // Own-property lookup only: a prototype-chain key ("constructor") can
    // never surface a non-pool value from a caller-supplied plain object.
    const pool = Object.prototype.hasOwnProperty.call(sets, claimed.v)
      ? sets[claimed.v]!
      : [];
    return { ok: true, v: { pool, attributed: true } };
  }
  return { ok: true, v: { pool: [], attributed: true } };
}

// The F1 binding: the JWS is verified over its own input only; THIS step
// pins it to the envelope. The purpose member prevents cross-surface
// signature lifting; the covered bytes are the envelope minus the signature
// entry itself.
function bindingCheck(value: Value, signatureEntry: Value): VResult {
  const attrs = blueprint.signatureAttributes(signatureEntry);
  if (!attrs.ok) return attrs;

  if (attrs.v.purpose !== "federation-envelope") {
    return { ok: false, e: "invalid_constraint" };
  }

  const jcs = canonical.encode(coveredBody(value));
  if (!jcs.ok) return jcs;
  const expected = digest.hash("federation_envelope", Buffer.from(jcs.v, "utf8"));

  return digest.equal(attrs.v.contentDigest, expected)
    ? { ok: true }
    : { ok: false, e: "digest_mismatch" };
}

function coveredBody(value: Value): Value {
  if (value.t !== "obj") return value;
  return {
    t: "obj",
    v: value.v.map(([name, member]) => {
      if (name === "evidence_receipt" && member.t === "obj") {
        return [name, { t: "obj", v: member.v.filter(([n]) => n !== "signature") }];
      }
      return [name, member];
    }),
  };
}

function commitmentCheck(receipt: [string, Value][], recomputed: digest.Digest): VResult {
  const taggedEntry = keyfind(receipt, "terminal_commitment");
  if (taggedEntry === null) return { ok: false, e: "missing_required_field" };
  if (taggedEntry.t !== "str") return { ok: false, e: "invalid_type" };
  const declared = digest.fromTagged(taggedEntry.v);
  if (!declared.ok) return declared;
  return digest.equal(declared.v, recomputed)
    ? { ok: true }
    : { ok: false, e: "digest_mismatch" };
}

// One code for the issuer/subject/audience triple; a nil pin skips that
// member entirely.
function contextCompare(members: Map<string, Value>, context: Context): VResult {
  const pins: [string, unknown][] = [
    ["issuer", context.issuer],
    ["subject", context.subject],
    ["audience", context.audience],
  ];
  for (const [member, pin] of pins) {
    if (pin === undefined || pin === null) continue;
    // The twin's exact match: members[m] must equal {:string, pin}. A pin
    // that is present but not a string can NEVER equal a string member, so
    // it denies — the receiver's constraint is enforced, never dropped.
    const found = members.get(member);
    const pinValue = pin as Value;
    const matches =
      pinValue !== null &&
      typeof pinValue === "object" &&
      (pinValue as Value).t === "str" &&
      found !== undefined &&
      found.t === "str" &&
      found.v === (pinValue as { v: string }).v;
    if (!matches) return { ok: false, e: "audience_mismatch" };
  }
  return { ok: true };
}

function conflictCheck(members: Map<string, Value>, commitment: digest.Digest, context: Context): VResult {
  const taskIdentity = members.get("task_identity");
  const terminalState = members.get("terminal_state");
  if (taskIdentity === undefined || taskIdentity.t !== "str") return { ok: false, e: "invalid_type" };
  if (terminalState === undefined || terminalState.t !== "str") return { ok: false, e: "invalid_type" };

  for (const prior of context.priorReceipts) {
    const divergent =
      prior.taskIdentity === taskIdentity.v &&
      (prior.terminalState !== terminalState.v ||
        !digest.equal(prior.terminalCommitment, commitment));
    if (divergent) return { ok: false, e: "federation_terminal_conflict" };
  }
  return { ok: true };
}

// Freshness: both bounds receiver-supplied Z-form, INCLUSIVE, over the
// SIGNED created_at; malformed pins deny typed. Runs after conflict
// detection so a stale AND equivocating receipt still reports the conflict.
function freshnessCheck(signatureEntry: Value, context: Context): VResult {
  const after = pin(context.createdAfter);
  if (!after.ok) return after;
  const before = pin(context.createdBefore);
  if (!before.ok) return before;

  const attrs = blueprint.signatureAttributes(signatureEntry);
  if (!attrs.ok) return attrs;

  const stamped = parseTimestampMs(attrs.v.createdAt);
  if (stamped === null) return { ok: false, e: "invalid_type" };

  const inWindow =
    (after.v === null || stamped >= after.v) && (before.v === null || stamped <= before.v);
  return inWindow ? { ok: true } : { ok: false, e: "invalid_constraint" };
}

// The SAME double gate as the signed member: the Z-form regex rejects
// offsets and fractions that a lenient parser alone accepts.
function pin(value: string | undefined): { ok: true; v: number | null } | { ok: false; e: string } {
  if (value === undefined || value === null) return { ok: true, v: null };
  if (typeof value !== "string" || !Z_FORM.test(value) || parseTimestampMs(value) === null) {
    return { ok: false, e: "invalid_type" };
  }
  return { ok: true, v: parseTimestampMs(value) };
}

function parseTimestampMs(stamped: string): number | null {
  const matched = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/.exec(stamped);
  if (matched === null) return null;
  const [, y, mo, d, h, mi, s] = matched;
  if (!blueprint.validZFormDate(stamped)) return null;
  return Date.UTC(Number(y), Number(mo) - 1, Number(d), Number(h), Number(mi), Number(s));
}
