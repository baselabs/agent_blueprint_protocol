// The Deployment Manifest artifact — the mirror of AgentBlueprintProtocol.Deployment:
// canonical verify → the 19-member registry table (exact-only build-identity
// versions, lifecycle temporal rules, the as_of total rule) → the portability
// scan (eligibility expressions as the open region) → the content-digest
// comparison under the deployment_content domain; plus the six-stage
// verify_binding deny set with its pinned order.

import type { Bounds } from "./bounds.ts";
import { coerce as coerceBounds, maximum as maxBounds } from "./bounds.ts";
import * as blueprint from "./blueprint.ts";
import * as canonical from "./canonical.ts";
import * as digest from "./digest.ts";
import * as extension from "./extension.ts";
import { field, keyfind, validate, type Spec } from "./registry_engine.ts";
import * as portability from "./portability.ts";
import type { Value } from "./value.ts";

export interface Deployment {
  value: Value;
}

export interface Observations {
  now: string | null; // RFC 3339 (Z-form in practice); null skips staleness
  maxAttestationAgeMs: number | null;
  observed: Record<string, string>; // logical operation → tagged digest
}

type VResult = { ok: true } | { ok: false; e: string };

const CEILING_TOOL_BINDINGS = 128;
const CEILING_DATA_BINDINGS = 64;
const CEILING_BUILD_IDENTITIES = 128;
const CEILING_SIGNATURES = 16;
const CEILING_ATTESTATIONS = 16;
const IDENTIFIER_BYTES = 512;

const CLASSIFICATION = ["public", "internal", "confidential", "restricted"];
const AUTHORITY_TRAITS = ["none", "local_policy", "external_authority_required"];
const APPROVAL_TRAITS = ["none", "human_required", "separated_human_required"];
const IMPACT_CLASSES = ["ordinary", "money", "authority", "secret"];
const DISCLOSURE_STEPS = ["none", "summary", "detail", "full"];
const CUSTODY_MODES = ["host_managed", "external_kms", "holder_edge"];
const BUILD_KINDS = ["package", "build", "adapter", "extension"];
const LIFECYCLE_STATES = ["draft", "active", "retired"];
const AS_OF_MODES = ["required", "none"];

const NUMERIC_CEILINGS = [
  "max_attempts",
  "max_concurrency",
  "max_depth",
  "max_descendants",
  "max_elapsed_ms",
  "max_fan_out",
  "max_tokens",
];

// The 16 digest-covered members; the evidence trio is excluded by §8.2.
const COVERED_MEMBERS = [
  "authority_requirement",
  "blueprint_release",
  "build_identities",
  "data_bindings",
  "effect_owner",
  "eligibility",
  "evaluation_binding",
  "extensions",
  "host_bounds",
  "lifecycle",
  "model_policy",
  "protocol_revision",
  "required_core_fields",
  "scope_projection",
  "signer_custody",
  "tool_bindings",
];

const EVIDENCE_MEMBERS = ["deployment_digest", "signatures", "attestations"];

const SEGMENT = /^[a-z0-9][a-z0-9._-]*$/;
const Z_FORM = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const CURRENCY = /^[A-Z]{3}$/;
const EXACT_CHARSET = /^[A-Za-z0-9.+-]+$/;

const enumSet = (values: string[]) => new Set(values);

// ---- the 19-member table ------------------------------------------------------------

function identityString(name: string): Spec {
  return field(name, "string", { check: checkIdentityString });
}

function identityProfileMembers(): Spec[] {
  return [identityString("adapter_identity"), identityString("profile_identity")];
}

function releaseMembers(): Spec[] {
  return [
    field("blueprint_id", "string", { check: checkProducerQualified }),
    field("release_number", "integer", { check: checkPositive }),
    field("content_digest", "string", { check: checkTaggedDigest }),
  ];
}

function buildIdentityElement(): Spec {
  return {
    kind: {
      object: {
        members: [
          field("kind", { enum: enumSet(BUILD_KINDS) }),
          identityString("name"),
          field("version", "string", { check: checkExactVersion }),
          field("digest", "string", { check: checkTaggedDigest }),
        ],
      },
    },
  };
}

function dataBindingElement(): Spec {
  return {
    kind: {
      object: {
        members: [
          field("logical_dataset", "string", { check: checkIdentityString }),
          field("classification_ceiling", { enum: enumSet(CLASSIFICATION) }),
          field("as_of", { object: { members: asOfMembers() } }, { check: checkAsOf }),
        ],
      },
    },
  };
}

function asOfMembers(): Spec[] {
  return [field("mode", { enum: enumSet(AS_OF_MODES) }), field("max_age_ms", "custom")];
}

function effectOwnerMembers(): Spec[] {
  return [
    identityString("adapter_identity"),
    field("idempotency", {
      object: {
        members: [
          field("key_derivation", { enum: enumSet(["host"]) }),
          field("recovery", { enum: enumSet(["authoritative", "none"]) }),
        ],
      },
    }),
  ];
}

function eligibilityMembers(): Spec[] {
  return [
    field("owner", "custom", { check: checkExpression }),
    field("beneficiary", "custom", { check: checkExpression }),
    field("runtime_principal", "custom", { check: checkExpression }),
  ];
}

function evaluationMembers(): Spec[] {
  return [
    identityString("adapter_identity"),
    field("corpus", {
      object: {
        members: [
          field("name", "string", { check: checkIdentityString }),
          field("digest", "string", { check: checkTaggedDigest }),
        ],
      },
    }),
  ];
}

// Name order, pinned for the mirror: the seven numerics, cost, and the five
// protected bounds, member-name-sorted (NOT spec-map shape order).
function hostBoundsMembers(): Spec[] {
  const numeric = NUMERIC_CEILINGS.map((name) => field(name, "integer", { check: checkPositive }));
  const cost = field("max_cost", {
    object: {
      members: [
        field("amount", "integer", { check: checkPositive }),
        field("currency", "string", { check: checkCurrency }),
      ],
    },
  });
  const protectedBounds = [
    field("classification_ceiling", { enum: enumSet(CLASSIFICATION) }),
    field("authority_trait", { enum: enumSet(AUTHORITY_TRAITS) }),
    field("approval_trait", { enum: enumSet(APPROVAL_TRAITS) }),
    field("effect_impact_ceiling", { enum: enumSet(IMPACT_CLASSES) }),
    field("disclosure_ceiling", { enum: enumSet(DISCLOSURE_STEPS) }),
  ];
  return [...numeric, cost, ...protectedBounds].sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
}

function lifecycleMembers(): Spec[] {
  return [
    field("state", { enum: enumSet(LIFECYCLE_STATES) }),
    field("activated_at", "string", { required: false, check: checkZForm }),
    field("retired_at", "string", { required: false, check: checkZForm }),
  ];
}

function modelPolicyMembers(): Spec[] {
  return [
    field("allowed_model_roles", { array: { kind: "string" } }, {
      uniqueBy: ":value",
      check: checkRoleStrings,
    }),
    field("max_tokens", "integer", { check: checkPositive }),
    field("max_cost", {
      object: {
        members: [
          field("amount", "integer", { check: checkPositive }),
          field("currency", "string", { check: checkCurrency }),
        ],
      },
    }),
  ];
}

function toolBindingElement(): Spec {
  return {
    kind: {
      object: {
        members: [
          field("logical_operation", "string", { check: checkIdentityString }),
          identityString("adapter_identity"),
          field("descriptor_digest", "string", { check: checkTaggedDigest }),
          field("schema_digest", "string", { check: checkTaggedDigest }),
          field("attested_at", "string", { check: checkZForm }),
        ],
      },
    },
  };
}

export function table(): Spec[] {
  return [
    field("authority_requirement", { object: { members: identityProfileMembers() } }),
    field("blueprint_release", { object: { members: releaseMembers() } }),
    field("build_identities", { array: buildIdentityElement() }, {
      minItems: 1,
      maxItems: CEILING_BUILD_IDENTITIES,
      uniqueBy: "name",
    }),
    field("data_bindings", { array: dataBindingElement() }, {
      maxItems: CEILING_DATA_BINDINGS,
      uniqueBy: "logical_dataset",
    }),
    field("effect_owner", { object: { members: effectOwnerMembers() } }),
    field("eligibility", { object: { members: eligibilityMembers() } }),
    field("evaluation_binding", { object: { members: evaluationMembers() } }),
    field("extensions", "custom", { check: (v) => extension.envelopeOk(v) }),
    field("host_bounds", { object: { members: hostBoundsMembers() } }),
    field("lifecycle", { object: { members: lifecycleMembers() } }, { check: checkLifecycle }),
    field("model_policy", { object: { members: modelPolicyMembers() } }),
    field("protocol_revision", "integer", { check: checkPositive }),
    field("required_core_fields", { array: { kind: "string" } }, {
      uniqueBy: ":value",
      check: checkRequiredCoreFields,
    }),
    field("scope_projection", {
      object: { members: [field("adapter_identity", "string", { check: checkIdentityString })] },
    }),
    field("signer_custody", { enum: enumSet(CUSTODY_MODES) }),
    field("tool_bindings", { array: toolBindingElement() }, {
      maxItems: CEILING_TOOL_BINDINGS,
      uniqueBy: "logical_operation",
    }),
    field("signatures", { array: { kind: "custom", check: checkSignatureEntry } }, {
      required: false,
      maxItems: CEILING_SIGNATURES,
    }),
    field("attestations", { array: { kind: "any" } }, {
      required: false,
      maxItems: CEILING_ATTESTATIONS,
      check: checkAttestations,
    }),
    field("deployment_digest", "string", { check: checkTaggedDigest }),
  ];
}

// ---- decode -------------------------------------------------------------------------

export function decode(
  bytes: Buffer | string,
  bounds?: Bounds | Record<string, unknown>,
): { ok: true; v: Deployment } | { ok: false; e: string } {
  if (typeof bytes !== "string" && !Buffer.isBuffer(bytes)) return { ok: false, e: "invalid_type" };
  const profile = normalizeBounds(bounds);
  if (!profile.ok) return profile;

  const verified = canonical.verify(bytes, profile.v);
  if (!verified.ok) return verified;
  const value = verified.v;

  const validated = validate(table(), value);
  if (!validated.ok) return validated;

  const scanned = scan(value, new Set());
  if (!scanned.ok) return scanned;

  const digestOk = verifyContentDigest({ value });
  if (!digestOk.ok) return digestOk;

  return { ok: true, v: { value } };
}

export function fromValue(value: Value, opts: { authoredExtensions?: string[] } = {}): { ok: true; v: Deployment } | { ok: false; e: string } {
  const validated = opts.authoredExtensions ?? [];
  if (validated.length > 0) {
    if (value.t !== "obj") return { ok: false, e: "invalid_type" };
    const critical = extension.criticalNamespaces(value.v);
    if (!validated.every((ns) => critical.has(ns))) return { ok: false, e: "invalid_type" };
  }
  const tabled = validate(table(), value);
  if (!tabled.ok) return tabled;
  const scanned = scan(value, new Set(validated));
  if (!scanned.ok) return scanned;
  return { ok: true, v: { value } };
}

export function toValue(deployment: Deployment): Value {
  return deployment.value;
}

// ---- digest surface --------------------------------------------------------------------

export function digestInput(deployment: Deployment): Value {
  if (deployment.value.t !== "obj") return deployment.value;
  return { t: "obj", v: deployment.value.v.filter(([name]) => !EVIDENCE_MEMBERS.includes(name)) };
}

export function canonicalBytes(deployment: Deployment): { ok: true; v: string } | { ok: false; e: string } {
  return canonical.encode(deployment.value);
}

export function contentDigest(deployment: Deployment): string {
  const jcs = canonical.encode(digestInput(deployment));
  if (!jcs.ok) throw new Error("deployment digest input must encode");
  return digest.toTagged(digest.hash("deployment_content", Buffer.from(jcs.v, "utf8")));
}

export function verifyContentDigest(deployment: Deployment): VResult {
  const members = deployment.value.t === "obj" ? deployment.value.v : [];
  const declared = keyfind(members, "deployment_digest");
  if (declared === null || declared.t !== "str") return { ok: false, e: "invalid_type" };
  const jcs = canonical.encode(digestInput(deployment));
  if (!jcs.ok) return jcs;
  return digest.verifyContent("deployment_content", Buffer.from(jcs.v, "utf8"), declared.v);
}

// ---- the binding surface ---------------------------------------------------------------

interface Release {
  blueprintId: string;
  releaseNumber: number;
  contentDigest: digest.Digest;
}

// The one total reader every binding stage consumes: duplicate root members,
// a non-array member, a non-object entry, a non-string operand, or an
// unparsable descriptor digest is a malformed deployment, never empty.
function boundToolBindings(deployment: Deployment): { ok: true; v: Value[] } | { ok: false; e: string } {
  if (deployment.value.t !== "obj") return { ok: false, e: "invalid_type" };
  const members = deployment.value.v;
  const names = members.map(([name]) => name);
  if (new Set(names).size !== names.length) return { ok: false, e: "invalid_type" };

  const toolBindings = keyfind(members, "tool_bindings");
  if (toolBindings === null) return { ok: true, v: [] };
  if (toolBindings.t !== "arr") return { ok: false, e: "invalid_type" };

  for (const entry of toolBindings.v) {
    const judgment = entryJudgment(entry);
    if (!judgment.ok) return judgment;
  }
  return { ok: true, v: toolBindings.v.filter((entry) => entry.t === "obj") };
}

function entryJudgment(entry: Value): VResult {
  if (entry.t !== "obj") return { ok: false, e: "invalid_type" };
  const operation = keyfind(entry.v, "logical_operation");
  const attested = keyfind(entry.v, "attested_at");
  const descriptor = keyfind(entry.v, "descriptor_digest");
  if (operation === null || operation.t !== "str") return { ok: false, e: "invalid_type" };
  if (attested === null || attested.t !== "str") return { ok: false, e: "invalid_type" };
  if (descriptor === null || descriptor.t !== "str") return { ok: false, e: "invalid_type" };
  return digest.fromTagged(descriptor.v);
}

function boundRelease(deployment: Deployment): { ok: true; v: Release } | { ok: false; e: string } {
  const bindings = boundToolBindings(deployment);
  if (!bindings.ok) return bindings;

  if (deployment.value.t !== "obj") return { ok: false, e: "invalid_type" };
  const release = keyfind(deployment.value.v, "blueprint_release");
  if (release === null || release.t !== "obj") return { ok: false, e: "invalid_type" };

  const id = keyfind(release.v, "blueprint_id");
  const number = keyfind(release.v, "release_number");
  const tagged = keyfind(release.v, "content_digest");
  if (id === null || id.t !== "str") return { ok: false, e: "invalid_type" };
  if (number === null || number.t !== "int" || number.v < 1) return { ok: false, e: "invalid_type" };
  if (tagged === null || tagged.t !== "str") return { ok: false, e: "invalid_type" };
  const parsed = digest.fromTagged(tagged.v);
  if (!parsed.ok) return parsed;

  return { ok: true, v: { blueprintId: id.v, releaseNumber: number.v, contentDigest: parsed.v } };
}

// The bind-time deny set (order pinned): release digest → release identity →
// tool-binding completeness → mutation/recovery → attestation staleness →
// observed rug-pull. Stages 5-6 are observation-gated.
export function verifyBinding(
  deployment: Deployment,
  bound: blueprint.Blueprint,
  obs: Observations,
): VResult {
  const bindings = boundToolBindings(deployment);
  if (!bindings.ok) return bindings;

  const releaseDigest = stageReleaseDigest(deployment, bound);
  if (!releaseDigest.ok) return releaseDigest;

  const releaseIdentity = stageReleaseIdentity(deployment, bound);
  if (!releaseIdentity.ok) return releaseIdentity;

  const completeness = stageCompleteness(bindings.v, bound);
  if (!completeness.ok) return completeness;

  const recovery = stageRecovery(deployment, bindings.v, bound);
  if (!recovery.ok) return recovery;

  const staleness = stageStaleness(bindings.v, obs);
  if (!staleness.ok) return staleness;

  return stageRugPull(bindings.v, obs);
}

function stageReleaseDigest(deployment: Deployment, bound: blueprint.Blueprint): VResult {
  const release = boundRelease(deployment);
  if (!release.ok) return { ok: false, e: "invalid_type" };
  const expected = blueprintContentDigest(bound);
  if (expected === null) return { ok: false, e: "invalid_type" };
  return digest.equal(release.v.contentDigest, expected)
    ? { ok: true }
    : { ok: false, e: "deployment_digest_mismatch" };
}

function stageReleaseIdentity(deployment: Deployment, bound: blueprint.Blueprint): VResult {
  const release = boundRelease(deployment);
  if (!release.ok) return { ok: false, e: "invalid_type" };
  if (bound.value.t !== "obj") return { ok: false, e: "invalid_type" };
  const id = keyfind(bound.value.v, "blueprint_id");
  const number = keyfind(bound.value.v, "release_number");
  if (id === null || id.t !== "str") return { ok: false, e: "invalid_type" };
  if (number === null || number.t !== "int") return { ok: false, e: "invalid_type" };
  return release.v.blueprintId === id.v && release.v.releaseNumber === number.v
    ? { ok: true }
    : { ok: false, e: "binding_incomplete" };
}

function stageCompleteness(bindings: Value[], bound: blueprint.Blueprint): VResult {
  const known = new Set<string>([...blueprintFamilies(bound), ...blueprintEffects(bound)]);
  for (const entry of bindings) {
    const operation = memberString(entry, "logical_operation");
    if (!known.has(operation)) return { ok: false, e: "binding_incomplete" };
  }
  return { ok: true };
}

function stageRecovery(deployment: Deployment, bindings: Value[], bound: blueprint.Blueprint): VResult {
  const mode = recoveryMode(deployment);
  if (!mode.ok) return mode;
  if (mode.v === "authoritative") return { ok: true };

  const families = blueprintFamilyKinds(bound);
  const effects = blueprintEffectKinds(bound);
  for (const entry of bindings) {
    const operation = memberString(entry, "logical_operation");
    const familyKind = families[operation];
    const effectKind = effects[operation];
    if (familyKind === "mutation" || effectKind === "mutation") {
      return { ok: false, e: "no_authoritative_recovery" };
    }
  }
  return { ok: true };
}

// now: null skips every staleness judgment (the host's governance choice).
function stageStaleness(bindings: Value[], obs: Observations): VResult {
  if (obs.now === null) return { ok: true };
  const now = parseTimestamp(obs.now);
  if (now === null) return { ok: true }; // parse_time parity: undecodable now skips

  if (obs.maxAttestationAgeMs !== null && !Number.isInteger(obs.maxAttestationAgeMs)) {
    return { ok: false, e: "invalid_type" };
  }

  for (const entry of bindings) {
    const attested = memberString(entry, "attested_at");
    const at = parseTimestamp(attested);
    if (at === null) return { ok: false, e: "invalid_type" };

    if (at > now) return { ok: false, e: "binding_attestation_stale" };
    if (
      obs.maxAttestationAgeMs !== null &&
      now - at > obs.maxAttestationAgeMs
    ) {
      return { ok: false, e: "binding_attestation_stale" };
    }
  }
  return { ok: true };
}

function stageRugPull(bindings: Value[], obs: Observations): VResult {
  const observedEntries = Object.entries(obs.observed);
  if (observedEntries.length === 0) return { ok: true };

  const attested = new Map<string, digest.Digest>();
  for (const entry of bindings) {
    const operation = memberString(entry, "logical_operation");
    const tagged = memberString(entry, "descriptor_digest");
    const parsed = digest.fromTagged(tagged);
    if (parsed.ok) attested.set(operation, parsed.v);
  }

  for (const [operation, observedTagged] of observedEntries) {
    const declared = attested.get(operation);
    if (declared === undefined) continue;
    const observed = digest.fromTagged(observedTagged);
    if (!observed.ok) return observed;
    if (!digest.equal(observed.v, declared)) {
      return { ok: false, e: "binding_descriptor_mismatch" };
    }
  }
  return { ok: true };
}

function recoveryMode(deployment: Deployment): { ok: true; v: string } | { ok: false; e: string } {
  if (deployment.value.t !== "obj") return { ok: false, e: "invalid_type" };
  const owner = keyfind(deployment.value.v, "effect_owner");
  if (owner === null || owner.t !== "obj") return { ok: false, e: "invalid_type" };
  const idempotency = keyfind(owner.v, "idempotency");
  if (idempotency === null || idempotency.t !== "obj") return { ok: false, e: "invalid_type" };
  const recovery = keyfind(idempotency.v, "recovery");
  if (recovery === null || recovery.t !== "str") return { ok: false, e: "invalid_type" };
  if (recovery.v !== "authoritative" && recovery.v !== "none") return { ok: false, e: "invalid_type" };
  return { ok: true, v: recovery.v };
}

function blueprintContentDigest(bound: blueprint.Blueprint): digest.Digest | null {
  try {
    const tagged = blueprint.contentDigest(bound);
    const parsed = digest.fromTagged(tagged);
    return parsed.ok ? parsed.v : null;
  } catch {
    return null;
  }
}

function blueprintFamilies(bound: blueprint.Blueprint): string[] {
  const out: string[] = [];
  for (const entry of memberArrayOf(bound, "capability_requirements")) {
    if (entry.t !== "obj") continue;
    const family = keyfind(entry.v, "operation_family");
    if (family !== null && family.t === "str") out.push(family.v);
  }
  return out;
}

function blueprintEffects(bound: blueprint.Blueprint): string[] {
  const out: string[] = [];
  for (const entry of memberArrayOf(bound, "effect_intents")) {
    if (entry.t !== "obj") continue;
    const operation = keyfind(entry.v, "logical_operation");
    if (operation !== null && operation.t === "str") out.push(operation.v);
  }
  return out;
}

function blueprintFamilyKinds(bound: blueprint.Blueprint): Record<string, string> {
  const out: Record<string, string> = {};
  for (const entry of memberArrayOf(bound, "capability_requirements")) {
    if (entry.t !== "obj") continue;
    const family = keyfind(entry.v, "operation_family");
    const kind = keyfind(entry.v, "operation_kind");
    if (family !== null && family.t === "str" && kind !== null && kind.t === "str") {
      out[family.v] = kind.v;
    }
  }
  return out;
}

function blueprintEffectKinds(bound: blueprint.Blueprint): Record<string, string> {
  const out: Record<string, string> = {};
  for (const entry of memberArrayOf(bound, "effect_intents")) {
    if (entry.t !== "obj") continue;
    const operation = keyfind(entry.v, "logical_operation");
    const kind = keyfind(entry.v, "operation_kind");
    if (operation !== null && operation.t === "str" && kind !== null && kind.t === "str") {
      out[operation.v] = kind.v;
    }
  }
  return out;
}

function memberArrayOf(artifact: { value: Value }, name: string): Value[] {
  if (artifact.value.t !== "obj") return [];
  const found = keyfind(artifact.value.v, name);
  return found !== null && found.t === "arr" ? found.v : [];
}

// Pre-validated by stage 0: the named operand is a string on every entry.
function memberString(entry: Value, name: string): string {
  if (entry.t !== "obj") return "";
  const found = keyfind(entry.v, name);
  return found !== null && found.t === "str" ? found.v : "";
}

// ---- field checks (carried in the table as data) ----------------------------------------

function checkPositive(value: Value): VResult {
  if (value.t === "int" && value.v >= 1) return { ok: true };
  return { ok: false, e: "invalid_constraint" };
}

function checkCurrency(value: Value): VResult {
  if (value.t !== "str") return { ok: false, e: "invalid_constraint" };
  return CURRENCY.test(value.v) ? { ok: true } : { ok: false, e: "invalid_constraint" };
}

function checkProducerQualified(value: Value): VResult {
  if (value.t !== "str") return { ok: false, e: "invalid_constraint" };
  const segments = value.v.split("/");
  return (
    Buffer.byteLength(value.v, "utf8") <= IDENTIFIER_BYTES &&
    segments.length === 2 &&
    segments.every((s) => s !== "" && SEGMENT.test(s))
  )
    ? { ok: true }
    : { ok: false, e: "invalid_constraint" };
}

function checkIdentityString(value: Value): VResult {
  if (value.t !== "str") return { ok: false, e: "invalid_constraint" };
  return value.v !== "" && Buffer.byteLength(value.v, "utf8") <= IDENTIFIER_BYTES
    ? { ok: true }
    : { ok: false, e: "invalid_constraint" };
}

function checkZForm(value: Value): VResult {
  if (value.t !== "str") return { ok: false, e: "invalid_constraint" };
  return Z_FORM.test(value.v) && blueprint.validZFormDate(value.v)
    ? { ok: true }
    : { ok: false, e: "invalid_constraint" };
}

function checkTaggedDigest(value: Value): VResult {
  if (value.t !== "str") return { ok: false, e: "invalid_constraint" };
  return digest.fromTagged(value.v);
}

function checkRoleStrings(value: Value): VResult {
  if (value.t !== "arr") return { ok: false, e: "invalid_constraint" };
  const ok = value.v.every((item) => item.t === "str" && item.v !== "");
  return ok ? { ok: true } : { ok: false, e: "invalid_constraint" };
}

// The attestation kind registry is empty BY DESIGN, identical to Blueprint.
function checkAttestations(value: Value): VResult {
  if (value.t === "arr" && value.v.length === 0) return { ok: true };
  return { ok: false, e: "attestation_malformed" };
}

function checkRequiredCoreFields(value: Value): VResult {
  if (value.t !== "arr") return { ok: false, e: "invalid_constraint" };
  const ok = value.v.every((item) => item.t === "str" && COVERED_MEMBERS.includes(item.v));
  return ok ? { ok: true } : { ok: false, e: "invalid_constraint" };
}

// The purpose is this artifact's fact: the envelope parses AND must be
// "deployment" here.
function checkSignatureEntry(entry: Value): VResult {
  const attrs = blueprint.signatureAttributes(entry);
  if (!attrs.ok) return { ok: false, e: attrs.e };
  return attrs.v.purpose === "deployment" ? { ok: true } : { ok: false, e: "invalid_constraint" };
}

// An eligibility expression: any non-empty JSON object — the host's policy
// DSL, held verbatim and name-denylist-scanned.
function checkExpression(value: Value): VResult {
  if (value.t === "obj" && value.v.length > 0) return { ok: true };
  return { ok: false, e: "invalid_constraint" };
}

// The as_of total rule: exactly (required + positive age) or (none + null).
// A MISSING max_age_ms defers to the member recursion; a bad mode defers to
// its enum — one reason per defect, no collisions.
function checkAsOf(value: Value): VResult {
  if (value.t !== "obj") return { ok: true };
  const members = value.v;
  const mode = keyfind(members, "mode");
  const age = keyfind(members, "max_age_ms");
  if (mode !== null && mode.t === "str") {
    if (mode.v === "required") return requiredAge(age);
    if (mode.v === "none") return noneAge(age);
  }
  return { ok: true };
}

function requiredAge(age: Value | null): VResult {
  if (age === null) return { ok: true };
  if (age.t === "null") return { ok: false, e: "invalid_constraint" };
  if (age.t === "int") return age.v >= 1 ? { ok: true } : { ok: false, e: "invalid_constraint" };
  return { ok: false, e: "invalid_type" };
}

function noneAge(age: Value | null): VResult {
  if (age === null || age.t === "null") return { ok: true };
  if (age.t === "int") return { ok: false, e: "invalid_constraint" };
  return { ok: false, e: "invalid_type" };
}

// The lifecycle temporal rules (the closed state enum itself denies at the
// member recursion; this check owns the state/timestamp coupling).
function checkLifecycle(value: Value): VResult {
  if (value.t !== "obj") return { ok: true };
  const members = value.v;
  const state = keyfind(members, "state");
  const activated = keyfind(members, "activated_at");
  const retired = keyfind(members, "retired_at");

  if (state !== null && state.t === "str") {
    if (state.v === "draft") {
      return activated === null && retired === null ? { ok: true } : { ok: false, e: "lifecycle_state_invalid" };
    }
    if (state.v === "active") {
      return activated !== null && retired === null ? { ok: true } : { ok: false, e: "lifecycle_state_invalid" };
    }
    if (state.v === "retired") {
      if (
        activated !== null &&
        activated.t === "str" &&
        retired !== null &&
        retired.t === "str"
      ) {
        // Z-form whole-second strings sort lexicographically = chronologically.
        return activated.v <= retired.v ? { ok: true } : { ok: false, e: "lifecycle_state_invalid" };
      }
      return { ok: false, e: "lifecycle_state_invalid" };
    }
  }
  return { ok: true };
}

// The exact-only version pin: the protocol rejects the RANGE VOCABULARY, not
// semver semantics. The charset rule is total (every range operator sits
// outside [A-Za-z0-9.+-]); a dot-separated release segment that is exactly
// x/X/* is a wildcard.
function checkExactVersion(value: Value): VResult {
  if (value.t !== "str") return { ok: false, e: "compatibility_identity_inexact" };
  const version = value.v;
  const release = version.split("-")[0]!.split("+")[0]!;
  const segments = release.split(".");

  if (version === "") return { ok: false, e: "compatibility_identity_inexact" };
  if (!EXACT_CHARSET.test(version)) return { ok: false, e: "compatibility_identity_inexact" };
  if (["*", "latest"].includes(version.toLowerCase())) {
    return { ok: false, e: "compatibility_identity_inexact" };
  }
  if (segments.some((s) => ["x", "X", "*"].includes(s))) {
    return { ok: false, e: "compatibility_identity_inexact" };
  }
  return { ok: true };
}

// ---- the portability scan ---------------------------------------------------------------

function scan(value: Value, authoredNs: Set<string>): VResult {
  if (value.t !== "obj") return { ok: false, e: "invalid_type" };
  const members = value.v;

  const openRegions = scanOpenRegions(members, authoredNs);
  if (!openRegions.ok) return openRegions;

  const coreStrings = scanCoreStrings(members);
  if (!coreStrings.ok) return coreStrings;

  return scanEvidenceKeyIds(members);
}

// Open regions: extension bodies (strict) and eligibility expressions (names
// strict, values under the authored exemption).
function scanOpenRegions(members: [string, Value][], validatedNs: Set<string>): VResult {
  const strictBodies = extension.bodies(members).filter(([ns]) => !validatedNs.has(ns));
  const eligibility = members.find(([name]) => name === "eligibility");
  const eligibilityValues: Value[] = [];
  if (eligibility !== undefined && eligibility[1].t === "obj") {
    for (const [, expression] of eligibility[1].v) {
      if (expression.t === "obj") eligibilityValues.push(expression);
    }
  }

  const scans: VResult[] = [
    ...strictBodies.map(([, body]) => portability.scan(body)),
    ...eligibilityValues.map((expression) => portability.scanAuthored(expression)),
  ];
  for (const result of scans) {
    if (!result.ok) return result;
  }
  return { ok: true };
}

// Value shapes over every other core string, recursively — no member of this
// artifact is exempt.
function scanCoreStrings(members: [string, Value][]): VResult {
  for (const [name, value] of members) {
    if (EVIDENCE_MEMBERS.includes(name) || name === "extensions") continue;
    if (name === "eligibility") continue; // open region, scanned above
    const result = portability.scanValue(value);
    if (!result.ok) return result;
  }
  return { ok: true };
}

// The one free string inside an evidence entry: evidence members are
// digest-UNCOVERED — a secret-shaped key there must still red.
function scanEvidenceKeyIds(members: [string, Value][]): VResult {
  const signatures = keyfind(members, "signatures");
  if (signatures === null || signatures.t !== "arr") return { ok: true };
  for (const entry of signatures.v) {
    const attrs = blueprint.signatureAttributes(entry);
    if (!attrs.ok) continue; // unparseable entries already denied at the table
    const scanned = portability.scanValue({ t: "str", v: attrs.v.keyId });
    if (!scanned.ok) return scanned;
  }
  return { ok: true };
}

// ---- helpers --------------------------------------------------------------------------------

function normalizeBounds(bounds?: Bounds | Record<string, unknown>): { ok: true; v: Bounds } | { ok: false; e: string } {
  if (bounds === undefined) return { ok: true, v: maxBounds() };
  return coerceBounds(bounds as Record<string, unknown>);
}

// Z-form whole-second timestamps → epoch milliseconds; null when undecodable
// (DateTime.from_iso8601 parity, restricted to the calendar-valid Z form the
// tables already enforce).
export function parseTimestamp(stamped: string): number | null {
  const matched = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(Z|[+-]\d{2}:\d{2})$/.exec(stamped);
  if (matched === null) return null;
  const [, y, mo, d, h, mi, s, zone] = matched;
  if (!blueprint.validZFormDate(`${y}-${mo}-${d}T${h}:${mi}:${s}Z`)) return null;
  let ms = Date.UTC(Number(y), Number(mo) - 1, Number(d), Number(h), Number(mi), Number(s));
  if (zone !== "Z") {
    const sign = zone[0] === "-" ? -1 : 1;
    const offset = Number(zone.slice(1, 3)) * 60 + Number(zone.slice(4, 6));
    ms -= sign * offset * 60_000;
  }
  return ms;
}
