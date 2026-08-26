// The case executor — the mirror of AgentBlueprintProtocol.Conformance.Runner:
// dispatches each corpus case against the verifier's own surface twins and
// compares to the case's code-level, shape-agnostic expectation (invalid →
// projected error-code string; valid → per-surface projection members with
// the byte_fallback and Elixir-`==`-style numeric-tolerant comparison).

import * as b64 from "./b64url.ts";
import type { Bounds } from "./bounds.ts";
import { coerce } from "./bounds.ts";
import type { LoadedCorpus, CaseObj } from "./corpus.ts";
import { member, memberNumber, memberString } from "./corpus.ts";
import * as digest from "./digest.ts";
import type { Value } from "./value.ts";
import { float, int, nil, str } from "./value.ts";

// Surface twins (implemented in their own modules):
import * as blueprint from "./blueprint.ts";
import * as deployment from "./deployment.ts";
import * as negotiation from "./negotiation.ts";
import * as boundsAlgebra from "./bounds_algebra.ts";
import * as compatibility from "./compatibility.ts";
import * as federation from "./federation.ts";
import * as portability from "./portability.ts";
import * as schema from "./schema.ts";
import * as signature from "./signature.ts";

export interface CaseResult {
  caseId: string;
  agree: boolean;
}

export function run(corpus: LoadedCorpus): CaseResult[][] {
  return corpus.cases.map((file) =>
    file.cases.map((caseObj) => ({
      caseId: caseObj.id,
      agree: execute(caseObj, corpus.data, corpus.raws).agree,
    })),
  );
}

export function execute(
  caseObj: CaseObj,
  data: Map<string, Value>,
  raws: Map<string, Buffer>,
): { actual: SurfaceResult; agree: boolean } {
  const input = caseObj.input;
  const expected = caseObj.expected;
  const actual = dispatch(caseObj.surface, input, data, raws);
  return { actual, agree: agrees(expected, actual) };
}

export type SurfaceResult = { ok: true; v: Record<string, unknown> } | { ok: false; e: string };

// --- agreement -------------------------------------------------------------------

function agrees(expected: Value, actual: SurfaceResult): boolean {
  if (expected.t !== "obj") return false;
  const verdict = memberString(expected, "verdict");

  if (verdict === "invalid") {
    if (!actual.ok) return actual.e === memberString(expected, "code");
    return false;
  }

  if (verdict === "valid") {
    const projections = expected.v.filter(([k]) => k !== "verdict");
    if (projections.length === 0) return false; // vacuous-green refusal
    if (!actual.ok) return false;
    return projections.every(([key, want]) => {
      const got = (actual.v as Record<string, unknown>)[key];
      if (got === undefined) return false;
      return compare(want, got);
    });
  }

  return false;
}

function compare(want: Value, got: unknown): boolean {
  if (want.t === "str" && typeof got === "string") {
    if (want.v === got) return true;
    const decoded = b64.decodeLenient(want.v);
    return decoded.ok && decoded.v.equals(Buffer.from(got, "utf8"));
  }
  // Byte-bearing projections keep Buffers: the expected b64url spelling
  // decodes to the actual bytes (the twin's byte_fallback).
  if (want.t === "str" && Buffer.isBuffer(got)) {
    const decoded = b64.decodeLenient(want.v);
    return decoded.ok && decoded.v.equals(got);
  }
  // Numeric-tolerant deep comparison (Elixir == semantics: int 2 == float 2.0).
  return deepEqual(want, got);
}

function deepEqual(want: Value, got: unknown): boolean {
  if (want.t === "int" || want.t === "float") {
    return typeof got === "number" && want.v === got;
  }
  if (want.t === "bool") return typeof got === "boolean" && want.v === got;
  if (want.t === "null") return got === null;
  if (want.t === "str") return typeof got === "string" && want.v === got;
  if (want.t === "arr") {
    return (
      Array.isArray(got) && want.v.length === got.length && want.v.every((w, i) => deepEqual(w, got[i]))
    );
  }
  if (want.t === "obj") {
    if (got === null || typeof got !== "object" || Array.isArray(got)) return false;
    const gotRecord = got as Record<string, unknown>;
    if (Object.keys(gotRecord).length !== want.v.length) return false;
    return want.v.every(([k, w]) => k in gotRecord && deepEqual(w, gotRecord[k]));
  }
  return false;
}

// --- dispatch ----------------------------------------------------------------------

const BOUNDS_KEYS: Record<string, string> = {
  bytes: "bytes",
  depth: "depth",
  members: "members",
  items: "items",
  nodes: "nodes",
  string: "string",
  key: "key",
  number_lexeme: "number_lexeme",
};

const DIGEST_DOMAINS = [
  "blueprint_content",
  "deployment_content",
  "federation_envelope",
  "signature",
  "extension_schema",
  "extension_registry",
  "conformance_report",
  "corpus_index",
] as const;

const LOGICAL_STATES = [
  "submitted",
  "working",
  "completed",
  "failed",
  "canceled",
  "rejected",
  "input_required",
  "auth_required",
] as const;

const FEDERATION_CODEC_KEYS = [
  "from_a2a_state",
  "to_a2a_state",
  "from_mcp_state",
  "to_mcp_state",
  "from_a2a_carrier",
  "from_mcp_carrier",
];

const LATTICE = [
  "public",
  "internal",
  "confidential",
  "restricted",
  "none",
  "local_policy",
  "external_authority_required",
  "human_required",
  "separated_human_required",
  "ordinary",
  "money",
  "authority",
  "secret",
  "summary",
  "detail",
  "full",
  "pci",
  "phi",
];

function dispatch(
  surface: string,
  input: Value,
  data: Map<string, Value>,
  raws: Map<string, Buffer>,
): SurfaceResult {
  switch (surface) {
    case "json.decode": {
      const overrides = boundsOverrides(input);
      if (!overrides.ok) return overrides;
      const bytes = inputBytes(input, raws);
      if (!bytes.ok) return bytes;
      const { decode } = require_decode();
      const decoded = decode(bytes.v === NON_BINARY ? 123 : bytes.v, overrides.v);
      if (!decoded.ok) return decoded;
      return { ok: true, v: { value: toPlainValue(decoded.v) } };
    }
    case "canonicalization.encode": {
      const bytes = inputBytes(input, raws);
      if (!bytes.ok) return bytes;
      const { decode } = require_decode();
      const decoded = decode(bytes.v === NON_BINARY ? 123 : bytes.v);
      if (!decoded.ok) return decoded;
      const overrides = boundsOverrides(input);
      if (!overrides.ok) return overrides;
      const { encode } = require_encode();
      const encoded = encode(decoded.v, overrides.v);
      if (!encoded.ok) return encoded;
      return { ok: true, v: { encoded: encoded.v } };
    }
    case "base64url.decode": {
      const segment = memberString(input, "base64url");
      if (segment === null) return { ok: false, e: "invalid_type" };
      const decoded = b64.decodeStrict(segment);
      if (!decoded.ok) return decoded;
      // Keep the raw bytes: toString("utf8") is lossy for non-UTF8 decodes,
      // and agreement runs through the b64 byte-fallback (the twin's
      // %{"decoded" => binary} + byte_fallback semantics).
      return { ok: true, v: { decoded: decoded.v } };
    }
    case "digest.tagged": {
      const tagged = memberString(input, "tagged");
      if (tagged !== null) {
        const parsed = digest.fromTagged(tagged);
        if (!parsed.ok) return parsed;
        return { ok: true, v: { tagged: digest.toTagged(parsed.v) } };
      }
      const text = memberString(input, "text");
      const declared = memberString(input, "declared");
      if (text !== null && declared !== null) {
        const bytes = inputBytes(input, raws);
        if (!bytes.ok) return bytes;
        const domain = memberString(input, "domain");
        if (domain === null || !(DIGEST_DOMAINS as readonly string[]).includes(domain)) {
          return { ok: false, e: "invalid_type" };
        }
        const verified = digest.verifyContent(domain as digest.Domain, bytes.v, declared);
        if (!verified.ok) return verified;
        return { ok: true, v: { verified: true } };
      }
      return { ok: false, e: "invalid_type" };
    }
    case "blueprint.decode": {
      const overrides = boundsOverrides(input);
      if (!overrides.ok) return overrides;
      const bytes = inputBytes(input, raws);
      if (!bytes.ok) return bytes;
      const decoded = blueprint.decode(bytes.v, overrides.v);
      if (!decoded.ok) return decoded;
      return { ok: true, v: { digest: blueprint.contentDigest(decoded.v) } };
    }
    case "deployment.decode": {
      const overrides = boundsOverrides(input);
      if (!overrides.ok) return overrides;
      const bytes = inputBytes(input, raws);
      if (!bytes.ok) return bytes;
      const decoded = deployment.decode(bytes.v, overrides.v);
      if (!decoded.ok) return decoded;
      return projectDeployment(decoded.v, input);
    }
    case "signature.verify": {
      const entryText = memberString(input, "entry");
      if (entryText === null) return { ok: false, e: "invalid_type" };
      const { decode } = require_decode();
      const entry = decode(entryText);
      if (!entry.ok) return entry;
      const keys = buildKeys(input);
      if (!keys.ok) return keys;
      const verified = signature.verify(entry.v, keys.v);
      if (!verified.ok) return verified;
      return { ok: true, v: { verified: true } };
    }
    case "schema.validate_instance": {
      const schemaInput = schemaInputValue(input, data);
      if (!schemaInput.ok) return schemaInput;
      const instance = taggedField(input, "instance");
      if (!instance.ok) return instance;
      const dialect = memberString(input, "dialect") ?? schema.dialect();
      const validated = schema.validateInstance(schemaInput.v, instance.v, dialect);
      if ("ok" in validated && !validated.ok) return validated;
      return { ok: true, v: { valid: true } };
    }
    case "negotiation.negotiate":
    case "extension.resolve": {
      const artifact = taggedField(input, "artifact");
      if (!artifact.ok) return artifact;
      const support = buildSupport(input);
      if (!support.ok) return support;
      return projectNegotiation(negotiation.negotiate(artifact.v, support.v));
    }
    case "bounds.new": {
      const overrides = boundsOverrides(input);
      if (!overrides.ok) return overrides;
      const bounds = coerce(overrides.v);
      if (!bounds.ok) return bounds;
      return { ok: true, v: { bounds: bounds.v } };
    }
    case "bounds_algebra.intersect": {
      const blueprintSet = boundSet(input, "blueprint");
      if (!blueprintSet.ok) return blueprintSet;
      const deploymentSet = boundSet(input, "deployment");
      if (!deploymentSet.ok) return deploymentSet;
      const hostSet = boundSet(input, "host");
      if (!hostSet.ok) return hostSet;
      const result = boundsAlgebra.intersect(
        blueprintSet.v,
        deploymentSet.v,
        hostSet.v,
        memberString(input, "protected_clamp") === "acknowledge" ? "acknowledge" : "deny",
      );
      if (!result.ok) return result;
      const effective: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(result.v.effective)) effective[k] = v;
      return { ok: true, v: { effective, clamp_count: result.v.clamps.length } };
    }
    case "portability.scan": {
      const bytes = inputBytes(input, raws);
      if (!bytes.ok) return bytes;
      const { decode } = require_decode();
      const decoded = decode(bytes.v);
      if (!decoded.ok) return decoded;
      const scanned = portability.scan(decoded.v);
      if (!scanned.ok) return scanned;
      return { ok: true, v: { clean: true } };
    }
    case "compatibility.verify": {
      const bytes = inputBytes(input, raws);
      if (!bytes.ok) return bytes;
      const decoded = deployment.decode(bytes.v);
      if (!decoded.ok) return decoded;
      const observed = buildObserved(input);
      if (!observed.ok) return observed;
      const verified = compatibility.verify(decoded.v, observed.v);
      if (!verified.ok) return verified;
      return { ok: true, v: { verified: true } };
    }
    case "federation.decode": {
      const text = memberString(input, "text");
      const b64Input = memberString(input, "base64url");
      const nonBinary = member(input, "non_binary");
      if (text !== null || b64Input !== null || (nonBinary !== null && nonBinary.t === "bool" && nonBinary.v)) {
        const overrides = boundsOverrides(input);
        if (!overrides.ok) return overrides;
        const bytes = inputBytes(input, raws);
        if (!bytes.ok) return bytes;
        const decoded = federation.decode(bytes.v, overrides.v);
        if (!decoded.ok) return decoded;
        const canonical = federation.canonicalBytes(decoded.v);
        if (!canonical.ok) return canonical;
        return { ok: true, v: { canonical: canonical.v } };
      }
      if (FEDERATION_CODEC_KEYS.some((k) => member(input, k) !== null)) {
        return dispatchFederationCodec(input);
      }
      return { ok: false, e: "invalid_type" };
    }
    case "federation.verify_commitment": {
      const envelopeText = memberString(input, "envelope");
      if (envelopeText === null) return { ok: false, e: "invalid_type" };
      const decoded = federation.decode(envelopeText);
      if (!decoded.ok) return decoded;
      const context = buildContext(input);
      if (!context.ok) return context;
      const fact = federation.verifyCommitment(decoded.v, context.v);
      if (!fact.ok) return fact;
      return { ok: true, v: { task_identity: fact.v.taskIdentity } };
    }
    default:
      return { ok: false, e: "invalid_type" };
  }
}

// decode/encode are imported lazily through these accessors to keep the
// module-init graph acyclic under node ESM (decode ↔ canonical already
// cycle by design; runner sits above both).
import { decode } from "./decode.ts";
import { encode } from "./canonical.ts";
function require_decode() {
  return { decode };
}
function require_encode() {
  return { encode };
}

// --- input builders ------------------------------------------------------------------

const NON_BINARY = Symbol("non-binary");

function inputBytes(input: Value, raws: Map<string, Buffer>): { ok: true; v: Buffer | typeof NON_BINARY } | { ok: false; e: string } {
  const nonBinary = member(input, "non_binary");
  if (nonBinary !== null && nonBinary.t === "bool" && nonBinary.v) return { ok: true, v: NON_BINARY };
  const text = memberString(input, "text");
  if (text !== null) return { ok: true, v: Buffer.from(text, "utf8") };
  const encoded = memberString(input, "base64url");
  if (encoded !== null) {
    const decoded = b64.decodeLenient(encoded);
    if (!decoded.ok) return { ok: false, e: "invalid_type" };
    return { ok: true, v: decoded.v };
  }
  const rawFile = memberString(input, "raw_file");
  if (rawFile !== null) {
    const bytes = raws.get(rawFile);
    if (bytes === undefined) return { ok: false, e: "invalid_type" };
    return { ok: true, v: bytes };
  }
  return { ok: false, e: "invalid_type" };
}

function boundsOverrides(input: Value): { ok: true; v: Record<string, unknown> } | { ok: false; e: string } {
  const overrides = member(input, "bounds");
  if (overrides === null) return { ok: true, v: {} };
  if (overrides.t !== "obj") return { ok: false, e: "invalid_type" };
  // Null prototype: a corpus-carried "__proto__" key stays a plain member
  // (Elixir denies it as unknown_bound; a plain object would silently drop it).
  const out: Record<string, unknown> = Object.create(null);
  for (const [key, value] of overrides.v) {
    // Unknown keys pass through so coerce() denies them (unknown_bound).
    const mapped = BOUNDS_KEYS[key] ?? key;
    out[mapped] = value.t === "int" || value.t === "float" ? value.v : plainOf(value);
  }
  return { ok: true, v: out };
}

function plainOf(value: Value): unknown {
  switch (value.t) {
    case "null":
      return null;
    case "bool":
    case "int":
    case "float":
    case "str":
      return value.v;
    case "arr":
      return value.v.map(plainOf);
    case "obj":
      return Object.fromEntries(value.v.map(([k, v]) => [k, plainOf(v)]));
  }
}

function taggedField(input: Value, key: string): { ok: true; v: Value } | { ok: false; e: string } {
  const found = member(input, key);
  if (found === null) return { ok: false, e: "invalid_type" };
  return { ok: true, v: found };
}

function schemaInputValue(
  input: Value,
  data: Map<string, Value>,
): { ok: true; v: Value } | { ok: false; e: string } {
  const schemaFile = memberString(input, "schema_file");
  if (schemaFile !== null) {
    const found = data.get(schemaFile);
    if (found === undefined) return { ok: false, e: "invalid_type" };
    // A loaded non-map value passes through raw (the twin's schema_input);
    // parse/validate owns its judgment.
    return { ok: true, v: found };
  }
  const inline = member(input, "schema");
  // The twin's schema_input accepts only inline MAP schemas; anything else
  // denies invalid_type at the input boundary.
  if (inline !== null && inline.t === "obj") return { ok: true, v: inline };
  return { ok: false, e: "invalid_type" };
}

function buildKeys(input: Value): { ok: true; v: signature.PublicKey[] } | { ok: false; e: string } {
  const keys = member(input, "keys");
  if (keys === null || keys.t !== "arr") return { ok: false, e: "invalid_type" };
  const out: signature.PublicKey[] = [];
  for (const entry of keys.v) {
    if (entry.t !== "obj") return { ok: false, e: "invalid_type" };
    const keyId = memberString(entry, "key_id");
    const encoded = memberString(entry, "key");
    if (keyId === null || encoded === null) return { ok: false, e: "invalid_type" };
    const decoded = b64.decodeLenient(encoded);
    if (!decoded.ok || decoded.v.length !== 32) return { ok: false, e: "invalid_type" };
    out.push({ keyId, key: decoded.v });
  }
  return { ok: true, v: out };
}

function buildSupport(input: Value): { ok: true; v: negotiation.Support } | { ok: false; e: string } {
  const support = member(input, "support");
  const supportInput = support === null ? null : support.t === "obj" ? support : null;
  if (support !== null && support.t !== "obj") return { ok: false, e: "invalid_type" };
  const source = supportInput ?? ({ t: "obj", v: [] } as Value);

  const revisionsRaw = member(source, "revisions");
  const revisions =
    revisionsRaw !== null && revisionsRaw.t === "arr"
      ? revisionsRaw.v.map((r) => (r.t === "int" ? r.v : plainOf(r) as number))
      : [1];
  const coreFieldsRaw = member(source, "core_fields");
  const coreFields =
    coreFieldsRaw !== null && coreFieldsRaw.t === "arr"
      ? coreFieldsRaw.v.map((r) => (r.t === "str" ? r.v : String(plainOf(r))))
      : [];

  const registryRaw = member(source, "registry");
  const registry: Record<string, negotiation.RegistryEntryInput> = Object.create(null);
  if (registryRaw !== null && registryRaw.t === "obj") {
    for (const [ns, entryValue] of registryRaw.v) {
      if (entryValue.t !== "obj") continue;
      const criticality = memberString(entryValue, "criticality") ?? "optional";
      const state = memberString(entryValue, "state") ?? "active";
      registry[ns] = {
        owner: memberString(entryValue, "owner") ?? "corpus",
        criticality: criticality === "critical" ? "critical" : "optional",
        state: (["reserved", "deprecated", "retired"].includes(state) ? state : "active") as
          | "reserved"
          | "deprecated"
          | "retired"
          | "active",
        schemaDigest: memberString(entryValue, "schema_digest") ?? null,
        a2aUri:
          memberString(entryValue, "a2a_uri") ?? `https://example.com/extensions/${ns}`,
        promotedAtRevision: memberNumber(entryValue, "promoted_at_revision") ?? null,
      };
    }
  }

  const schemasRaw = member(source, "schemas");
  const schemas: Record<string, Value> = {};
  if (schemasRaw !== null && schemasRaw.t === "obj") {
    for (const [ns, schemaValue] of schemasRaw.v) schemas[ns] = schemaValue;
  }

  return {
    ok: true,
    v: {
      revisions: new Set(revisions as number[]),
      coreFields: new Set(coreFields),
      registry,
      schemas,
    },
  };
}

function boundSet(
  input: Value,
  key: string,
): { ok: true; v: Record<string, unknown> } | { ok: false; e: string } {
  const found = member(input, key);
  if (found === null || found.t !== "obj") return { ok: false, e: "invalid_type" };
  const out: Record<string, unknown> = Object.create(null);
  for (const [name, value] of found.v) {
    if (!LATTICE.includes(name) && !isBoundName(name)) {
      // Off-lattice names pass through so the algebra denies them.
      out[name] = plainOf(value);
      continue;
    }
    out[name] = descopeValue(value);
  }
  return { ok: true, v: out };
}

// The 13-bound vocabulary (BoundsAlgebra.names()): every protected bound
// routes through descopeValue exactly as the twin's add_bound_entry does.
const BOUND_NAMES = [
  "approval_trait",
  "authority_trait",
  "classification_ceiling",
  "disclosure_ceiling",
  "effect_impact_ceiling",
  "max_attempts",
  "max_concurrency",
  "max_cost",
  "max_depth",
  "max_descendants",
  "max_elapsed_ms",
  "max_fan_out",
  "max_tokens",
];

function isBoundName(name: string): boolean {
  return BOUND_NAMES.includes(name);
}

// Scope values arrive as {ordinal, markers[]}; costs as {amount, currency};
// bare strings as lattice atoms.
function descopeValue(value: Value): unknown {
  if (value.t === "obj") {
    const ordinal = memberString(value, "ordinal");
    if (ordinal !== null) {
      const markersRaw = member(value, "markers");
      return {
        ordinal,
        markers:
          markersRaw !== null && markersRaw.t === "arr"
            ? markersRaw.v.map((m) => (m.t === "str" ? m.v : String(plainOf(m))))
            : [],
      };
    }
    const amount = memberNumber(value, "amount");
    const currency = memberString(value, "currency");
    if (amount !== null && currency !== null) {
      return { amount, currency };
    }
    return plainOf(value);
  }
  if (value.t === "str") return value.v;
  return plainOf(value);
}

function buildObserved(input: Value): { ok: true; v: compatibility.Observed } | { ok: false; e: string } {
  const observed = member(input, "observed");
  if (observed === null || observed.t !== "obj") return { ok: false, e: "invalid_type" };
  const identities = member(observed, "identities");
  if (identities === null || identities.t !== "arr") return { ok: false, e: "invalid_type" };
  const out: { kind: unknown; name: unknown; version: unknown; digest: unknown }[] = [];
  // A malformed identity element denies typed at the RUNNER (the twin's
  // prior_receipts pattern) — never reaches Compatibility, never crashes.
  for (const entry of identities.v) {
    if (entry.t !== "obj") return { ok: false, e: "invalid_type" };
    const kind = entry.v.find(([k]) => k === "kind");
    const name = entry.v.find(([k]) => k === "name");
    const version = entry.v.find(([k]) => k === "version");
    const digestEntry = entry.v.find(([k]) => k === "digest");
    if (!kind || !name || !version || !digestEntry) return { ok: false, e: "invalid_type" };
    out.push({
      kind: kind[1].t === "str" ? kind[1].v : kind[1],
      name: name[1].t === "str" ? name[1].v : name[1],
      version: version[1].t === "str" ? version[1].v : version[1],
      digest: digestEntry[1].t === "str" ? digestEntry[1].v : digestEntry[1],
    });
  }
  return { ok: true, v: { identities: out } };
}

function buildContext(input: Value): { ok: true; v: federation.Context } | { ok: false; e: string } {
  const ctxValue = member(input, "context");
  if (ctxValue === null) {
    return { ok: true, v: { keys: [], issuerKeySets: null, priorReceipts: [] } };
  }
  if (ctxValue.t !== "obj") return { ok: false, e: "invalid_type" };
  const ctx = ctxValue;

  const keysRaw = member(ctx, "keys") ?? ({ t: "arr", v: [] } as Value);
  const keys = buildKeys({ t: "obj", v: [["keys", keysRaw]] } as Value);
  if (!keys.ok) return keys;

  const issuerKeySetsRaw = member(ctx, "issuer_key_sets");
  let issuerKeySets: Record<string, signature.PublicKey[]> | null = null;
  if (issuerKeySetsRaw !== null && issuerKeySetsRaw.t === "obj") {
    issuerKeySets = Object.create(null);
    for (const [issuer, keyList] of issuerKeySetsRaw.v) {
      if (keyList.t !== "arr") return { ok: false, e: "invalid_type" };
      const built = buildKeys({ t: "obj", v: [["keys", keyList]] } as Value);
      if (!built.ok) return built;
      issuerKeySets[issuer] = built.v;
    }
  }

  const receiptsRaw = member(ctx, "prior_receipts") ?? ({ t: "arr", v: [] } as Value);
  if (receiptsRaw.t !== "arr") return { ok: false, e: "invalid_type" };
  const priorReceipts: federation.PriorReceipt[] = [];
  {
    for (const receipt of receiptsRaw.v) {
      if (receipt.t !== "obj") return { ok: false, e: "invalid_type" };
      const taskIdentity = memberString(receipt, "task_identity");
      const terminalState = memberString(receipt, "terminal_state");
      const tagged = memberString(receipt, "commitment");
      if (taskIdentity === null || terminalState === null || tagged === null) {
        return { ok: false, e: "invalid_type" };
      }
      const parsed = digest.fromTagged(tagged);
      if (!parsed.ok) return { ok: false, e: "invalid_type" };
      priorReceipts.push({ taskIdentity, terminalState, terminalCommitment: parsed.v });
    }
  }

  return {
    ok: true,
    v: {
      keys: keys.v,
      // Pins ride as RAW tagged values: the twin compares members[m] against
      // {:string, pin} exactly, so a present non-string pin DENIES (the
      // audience constraint is enforced, never silently dropped).
      issuer: member(ctx, "issuer"),
      subject: member(ctx, "subject"),
      audience: member(ctx, "audience"),
      issuerKeySets,
      createdAfter: memberString(ctx, "created_after") ?? undefined,
      createdBefore: memberString(ctx, "created_before") ?? undefined,
      priorReceipts,
    },
  };
}

function projectDeployment(deploymentValue: deployment.Deployment, input: Value): SurfaceResult {
  const binding = member(input, "binding");
  if (binding !== null && binding.t === "obj") {
    const blueprintBytes = memberString(binding, "blueprint");
    if (blueprintBytes === null) return { ok: false, e: "invalid_type" };
    const decoded = blueprint.decode(Buffer.from(blueprintBytes, "utf8"));
    if (!decoded.ok) return decoded;
    const now = memberString(binding, "now");
    const observations: deployment.Observations = {
      now: now !== null ? now : null,
      maxAttestationAgeMs: memberNumber(binding, "max_attestation_age_ms"),
      observed: {},
    };
    const verified = deployment.verifyBinding(deploymentValue, decoded.v, observations);
    if (!verified.ok) return verified;
  }
  return { ok: true, v: { digest: deployment.contentDigest(deploymentValue) } };
}

function projectNegotiation(
  outcome: { ok: true; v: negotiation.Outcome } | { ok: false; e: string },
): SurfaceResult {
  if (!outcome.ok) return outcome;
  return {
    ok: true,
    v: {
      revision: outcome.v.protocolRevision,
      critical: [...outcome.v.criticalExtensions].sort(),
      quarantined: [...outcome.v.quarantinedExtensions].sort(),
      notices: [...outcome.v.notices].sort(),
    },
  };
}

function dispatchFederationCodec(input: Value): SurfaceResult {
  const fromA2aState = memberString(input, "from_a2a_state");
  if (fromA2aState !== null) {
    const result = federation.fromA2aState(fromA2aState);
    return projectCodec(result);
  }
  const toA2aState = memberString(input, "to_a2a_state");
  if (toA2aState !== null) {
    return projectCodec(federation.toA2aState(toA2aState));
  }
  const fromMcpState = memberString(input, "from_mcp_state");
  if (fromMcpState !== null) {
    const result = federation.fromMcpState(fromMcpState);
    return projectCodec(result);
  }
  const toMcpState = memberString(input, "to_mcp_state");
  if (toMcpState !== null) {
    return projectCodec(federation.toMcpState(toMcpState));
  }
  const fromA2aCarrier = member(input, "from_a2a_carrier");
  if (fromA2aCarrier !== null && fromA2aCarrier.t === "obj") {
    return projectCodec(federation.fromA2aCarrier(fromA2aCarrier));
  }
  const fromMcpCarrier = member(input, "from_mcp_carrier");
  if (fromMcpCarrier !== null && fromMcpCarrier.t === "obj") {
    return projectCodec(federation.fromMcpCarrier(fromMcpCarrier));
  }
  return { ok: false, e: "invalid_type" };
}

type CodecResult = { ok: true; v: string | { decoded: true } } | { ok: false; e: string };

function projectCodec(result: CodecResult): SurfaceResult {
  if (!result.ok) return result;
  if (typeof result.v === "string") return { ok: true, v: { value: result.v } };
  return { ok: true, v: result.v };
}

function toPlainValue(value: Value): unknown {
  switch (value.t) {
    case "null":
      return null;
    case "bool":
    case "int":
    case "float":
    case "str":
      return value.v;
    case "arr":
      return value.v.map(toPlainValue);
    case "obj":
      return Object.fromEntries(value.v.map(([k, v]) => [k, toPlainValue(v)]));
  }
}

export { str, int, float, nil };
