// The Blueprint artifact — the mirror of AgentBlueprintProtocol.Blueprint:
// canonical verify → the 18-member registry table → the portability scan →
// the content-digest comparison, over the digest-covered members minus the
// evidence trio. Also hosts the Signature.attributes twin (the TS signature
// twin keeps its parts parser private; the artifact tables need the
// attributes projection for the purpose checks).

import * as b64 from "./b64url.ts";
import type { Bounds } from "./bounds.ts";
import { coerce as coerceBounds, maximum as maxBounds } from "./bounds.ts";
import * as canonical from "./canonical.ts";
import * as digest from "./digest.ts";
import * as extension from "./extension.ts";
import { field, keyfind, validate, type Spec } from "./registry_engine.ts";
import * as portability from "./portability.ts";
import * as predicate from "./predicate.ts";
import * as schema from "./schema.ts";
import type { Value } from "./value.ts";

export interface Blueprint {
  value: Value;
}

type VResult = { ok: true } | { ok: false; e: string };

const CEILING_PORTS = 64;
const CEILING_CAPABILITIES = 64;
const CEILING_EFFECTS = 64;
const CEILING_ASSERTIONS = 128;
const CEILING_SIGNATURES = 16;
const CEILING_ATTESTATIONS = 16;
const IDENTIFIER_BYTES = 512;

const CLASSIFICATION = ["public", "internal", "confidential", "restricted"];
const OPERATION_KINDS = ["read", "computation", "mutation"];
const IMPACT_CLASSES = ["ordinary", "money", "authority", "secret"];
const APPROVAL_TRAITS = ["none", "human_required", "separated_human_required"];
const AUTHORITY_TRAITS = ["none", "local_policy", "external_authority_required"];
const TRIGGER_KINDS = ["manual", "schedule", "condition", "evaluation", "delegated"];

const ASSERTION_KINDS = [
  "output_schema",
  "deterministic_predicate",
  "required_capability_use",
  "forbidden_capability_use",
  "grounding_presence",
  "policy_denial_expected",
  "approval_expected",
  "parameter_bound",
  "provenance_tie_out",
  "ceiling",
];

const NUMERIC_CEILINGS = [
  "max_attempts",
  "max_concurrency",
  "max_depth",
  "max_descendants",
  "max_elapsed_ms",
  "max_fan_out",
  "max_tokens",
];

// The 15 digest-covered members; the evidence trio is excluded by §8.2.
const COVERED_MEMBERS = [
  "blueprint_id",
  "capability_requirements",
  "ceilings",
  "classification_ceiling",
  "effect_intents",
  "evaluation_assertions",
  "extensions",
  "input_ports",
  "output_contract",
  "output_ports",
  "producer",
  "protocol_revision",
  "release_number",
  "required_core_fields",
  "triggers",
];

const EVIDENCE_MEMBERS = ["content_digest", "signatures", "attestations"];

const SEGMENT = /^[a-z0-9][a-z0-9._-]*$/;
const Z_FORM = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const CURRENCY = /^[A-Z]{3}$/;

const enumSet = (values: string[]) => new Set(values);

// ---- the 18-member table (base §6): data for the generic engine ---------------

function portElement(): Spec {
  return {
    kind: {
      object: {
        members: [
          field("name", "string"),
          field("schema", "custom", { check: checkSchemaDocument }),
          field("classification_ceiling", { enum: enumSet(CLASSIFICATION) }),
          field("required", "boolean"),
        ],
      },
    },
  };
}

function capabilityElement(): Spec {
  return {
    kind: {
      object: {
        members: [
          field("operation_family", "string"),
          field("argument_schema", "custom", { check: checkSchemaDocument }),
          field("result_schema", "custom", { check: checkSchemaDocument }),
          field("operation_kind", { enum: enumSet(OPERATION_KINDS) }),
          field("impact_class", { enum: enumSet(IMPACT_CLASSES) }),
          field("classification_ceiling", { enum: enumSet(CLASSIFICATION) }),
          field("approval_trait", { enum: enumSet(APPROVAL_TRAITS) }),
          field("authority_trait", { enum: enumSet(AUTHORITY_TRAITS) }),
        ],
      },
    },
  };
}

function effectElement(): Spec {
  return {
    kind: {
      object: {
        members: [
          field("logical_operation", "string"),
          field("operation_kind", { enum: enumSet(OPERATION_KINDS) }),
          field("impact_class", { enum: enumSet(IMPACT_CLASSES) }),
        ],
      },
    },
  };
}

function ceilingsMembers(): Spec[] {
  const numeric = NUMERIC_CEILINGS.map((name) => field(name, "integer", { check: checkPositive }));
  const cost = field("max_cost", {
    object: {
      members: [
        field("amount", "integer", { check: checkPositive }),
        field("currency", "string", { check: checkCurrency }),
      ],
    },
  });
  return [...numeric, cost];
}

function producerMembers(): Spec[] {
  return [
    field("identity", "string", { check: checkProducerName }),
    field("created_at", "string", { check: checkZForm }),
    field("toolchain", "string"),
  ];
}

function outputContractMembers(): Spec[] {
  return [
    field("port", "string"),
    field("classification_ceiling", { enum: enumSet(CLASSIFICATION) }),
  ];
}

// The assertion element carries the closed per-kind operand check; the
// predicate and the cross-field references validate in the root hook.
function assertionElement(): Spec {
  return { kind: "custom" as const, check: checkAssertion };
}

export function table(): Spec[] {
  return [
    field("blueprint_id", "string", { check: checkProducerQualified }),
    field("capability_requirements", { array: capabilityElement() }, {
      maxItems: CEILING_CAPABILITIES,
      uniqueBy: "operation_family",
    }),
    field("ceilings", { object: { members: ceilingsMembers() } }),
    field("classification_ceiling", { enum: enumSet(CLASSIFICATION) }),
    field("effect_intents", { array: effectElement() }, {
      maxItems: CEILING_EFFECTS,
      uniqueBy: "logical_operation",
    }),
    field("evaluation_assertions", { array: assertionElement() }, {
      maxItems: CEILING_ASSERTIONS,
      rootHook: hookAssertions,
    }),
    field("extensions", "custom", { check: (v) => extension.envelopeOk(v) }),
    field("input_ports", { array: portElement() }, { maxItems: CEILING_PORTS, uniqueBy: "name" }),
    field("output_contract", { object: { members: outputContractMembers() } }, {
      rootHook: hookOutputContract,
    }),
    field("output_ports", { array: portElement() }, { maxItems: CEILING_PORTS, uniqueBy: "name" }),
    field("producer", { object: { members: producerMembers() } }),
    field("protocol_revision", "integer", { check: checkPositive }),
    field("release_number", "integer", { check: checkPositive }),
    field("required_core_fields", { array: { kind: "string" } }, {
      uniqueBy: ":value",
      check: checkRequiredCoreFields,
    }),
    field("triggers", { array: { kind: { enum: enumSet(TRIGGER_KINDS) } } }, {
      minItems: 1,
      uniqueBy: ":value",
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
    field("content_digest", "string", { check: checkTaggedDigest }),
  ];
}

// ---- decode ---------------------------------------------------------------------

export function decode(
  bytes: Buffer | string,
  bounds?: Bounds | Record<string, unknown>,
): { ok: true; v: Blueprint } | { ok: false; e: string } {
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

export function fromValue(value: Value, opts: { authoredExtensions?: string[] } = {}): { ok: true; v: Blueprint } | { ok: false; e: string } {
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

export function toValue(blueprint: Blueprint): Value {
  return blueprint.value;
}

// ---- digest surface ----------------------------------------------------------------

export function digestInput(blueprint: Blueprint): Value {
  if (blueprint.value.t !== "obj") return blueprint.value;
  return { t: "obj", v: blueprint.value.v.filter(([name]) => !EVIDENCE_MEMBERS.includes(name)) };
}

export function canonicalBytes(blueprint: Blueprint): { ok: true; v: string } | { ok: false; e: string } {
  return canonical.encode(blueprint.value);
}

// The honest content digest over the covered members' canonical bytes.
export function contentDigest(blueprint: Blueprint): string {
  const jcs = canonical.encode(digestInput(blueprint));
  if (!jcs.ok) throw new Error("blueprint digest input must encode");
  return digest.toTagged(digest.hash("blueprint_content", Buffer.from(jcs.v, "utf8")));
}

export function verifyContentDigest(blueprint: Blueprint): VResult {
  const members = blueprint.value.t === "obj" ? blueprint.value.v : [];
  const declared = keyfind(members, "content_digest");
  if (declared === null || declared.t !== "str") return { ok: false, e: "invalid_type" };
  const jcs = canonical.encode(digestInput(blueprint));
  if (!jcs.ok) return jcs;
  return digest.verifyContent("blueprint_content", Buffer.from(jcs.v, "utf8"), declared.v);
}

// ---- bounds normalization (the twin's Bounds.coerce over override maps) -------------

function normalizeBounds(bounds?: Bounds | Record<string, unknown>): { ok: true; v: Bounds } | { ok: false; e: string } {
  if (bounds === undefined) return { ok: true, v: maxBounds() };
  return coerceBounds(bounds as Record<string, unknown>);
}

// ---- field checks (carried in the table as data) ------------------------------------

function checkPositive(value: Value): VResult {
  if (value.t === "int" && value.v >= 1) return { ok: true };
  return { ok: false, e: "invalid_constraint" };
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

function checkProducerName(value: Value): VResult {
  if (value.t !== "str") return { ok: false, e: "invalid_constraint" };
  return Buffer.byteLength(value.v, "utf8") <= IDENTIFIER_BYTES && SEGMENT.test(value.v)
    ? { ok: true }
    : { ok: false, e: "invalid_constraint" };
}

function checkZForm(value: Value): VResult {
  if (value.t !== "str") return { ok: false, e: "invalid_constraint" };
  return Z_FORM.test(value.v) && validZFormDate(value.v)
    ? { ok: true }
    : { ok: false, e: "invalid_constraint" };
}

function checkCurrency(value: Value): VResult {
  if (value.t !== "str") return { ok: false, e: "invalid_constraint" };
  return CURRENCY.test(value.v) ? { ok: true } : { ok: false, e: "invalid_constraint" };
}

function checkTaggedDigest(value: Value): VResult {
  if (value.t !== "str") return { ok: false, e: "invalid_constraint" };
  return digest.fromTagged(value.v);
}

function checkSchemaDocument(value: Value): VResult {
  const parsed = schema.parse(value, schema.dialect());
  if (parsed.ok) return { ok: true };
  return { ok: false, e: parsed.e };
}

// The purpose is the artifact's fact: the envelope parses AND must be
// "blueprint" here — a deployment-purpose signature riding a Blueprint is a
// wrong-position entry, denied as a table constraint.
function checkSignatureEntry(entry: Value): VResult {
  const attrs = signatureAttributes(entry);
  if (!attrs.ok) return { ok: false, e: attrs.e };
  return attrs.v.purpose === "blueprint" ? { ok: true } : { ok: false, e: "invalid_constraint" };
}

// The attestation kind registry is empty BY DESIGN; a non-empty array denies.
function checkAttestations(value: Value): VResult {
  if (value.t === "arr" && value.v.length === 0) return { ok: true };
  return { ok: false, e: "attestation_malformed" };
}

function checkRequiredCoreFields(value: Value): VResult {
  if (value.t !== "arr") return { ok: false, e: "invalid_constraint" };
  const ok = value.v.every((item) => item.t === "str" && COVERED_MEMBERS.includes(item.v));
  return ok ? { ok: true } : { ok: false, e: "invalid_constraint" };
}

// ---- assertion element check ----------------------------------------------------------

type OperandKind =
  | "string"
  | "nonempty_string"
  | "any"
  | "schema_document"
  | "optional_number"
  | "positive_number"
  | { enum: Set<string> };

const OPERAND_SPECS: Record<string, Record<string, [OperandKind, boolean]>> = {
  output_schema: { port: ["string", true], schema: ["schema_document", true] },
  deterministic_predicate: { predicate: ["any", true] },
  required_capability_use: { operation_family: ["string", true] },
  forbidden_capability_use: { operation_family: ["string", true] },
  grounding_presence: { dataset: ["nonempty_string", true] },
  policy_denial_expected: { operation_family: ["string", true] },
  approval_expected: {
    operation_family: ["string", true],
    approval_trait: [{ enum: enumSet(APPROVAL_TRAITS) }, true],
  },
  parameter_bound: {
    parameter: ["nonempty_string", true],
    minimum: ["optional_number", false],
    maximum: ["optional_number", false],
  },
  provenance_tie_out: { member: ["string", true] },
  ceiling: {
    ceiling: [{ enum: enumSet(NUMERIC_CEILINGS) }, true],
    at_most: ["positive_number", true],
  },
};

function checkAssertion(value: Value): VResult {
  if (value.t !== "obj") return { ok: false, e: "invalid_type" };
  const members = value.v;

  const kindFound = keyfind(members, "kind");
  if (kindFound === null) return { ok: false, e: "missing_required_field" };
  if (kindFound.t !== "str") return { ok: false, e: "invalid_type" };
  if (!ASSERTION_KINDS.includes(kindFound.v)) return { ok: false, e: "invalid_constraint" };
  const kind = kindFound.v;

  const operands = OPERAND_SPECS[kind]!;
  const allowed = new Set(["kind", ...Object.keys(operands)]);
  for (const [name] of members) {
    if (!allowed.has(name)) return { ok: false, e: "unknown_member" };
  }

  for (const [name, [, required]] of Object.entries(operands)) {
    if (required && keyfind(members, name) === null) return { ok: false, e: "missing_required_field" };
  }

  // Operand judgments run in the operands map's (alphabetical) key order.
  for (const name of Object.keys(operands).sort()) {
    const found = keyfind(members, name);
    if (found === null) continue;
    const judged = operandResult(operands[name]![0], found);
    if (!judged.ok) return judged;
  }

  // parameter_bound: at least one of minimum/maximum must be present.
  if (kind === "parameter_bound") {
    const has = keyfind(members, "minimum") !== null || keyfind(members, "maximum") !== null;
    return has ? { ok: true } : { ok: false, e: "invalid_constraint" };
  }

  return { ok: true };
}

function operandResult(operandKind: OperandKind, value: Value): VResult {
  switch (operandKind) {
    case "string":
      return value.t === "str" ? { ok: true } : { ok: false, e: "invalid_type" };
    case "nonempty_string":
      return value.t === "str" && value.v !== "" ? { ok: true } : { ok: false, e: "invalid_type" };
    case "any":
      return wellFormed(value) ? { ok: true } : { ok: false, e: "invalid_type" };
    case "schema_document":
      return checkSchemaDocument(value);
    case "optional_number":
      return value.t === "int" || value.t === "float" ? { ok: true } : { ok: false, e: "invalid_type" };
    case "positive_number":
      if (value.t === "int" && value.v >= 1) return { ok: true };
      if (value.t === "float" && value.v >= 1) return { ok: true };
      return { ok: false, e: "invalid_type" };
    default:
      if (value.t !== "str") return { ok: false, e: "invalid_type" };
      return operandKind.enum.has(value.v) ? { ok: true } : { ok: false, e: "invalid_constraint" };
  }
}

function wellFormed(value: Value): boolean {
  switch (value.t) {
    case "null":
    case "bool":
    case "int":
    case "float":
    case "str":
      return true;
    case "arr":
      return value.v.every(wellFormed);
    case "obj":
      return value.v.every(([name, member]) => typeof name === "string" && wellFormed(member));
  }
}

// ---- root hooks -----------------------------------------------------------------------

function hookAssertions(members: Map<string, Value>): VResult {
  const inputNames = portNames(members, "input_ports");
  const outputNames = portNames(members, "output_ports");
  const allPortNames = new Set([...inputNames, ...outputNames]);
  const families = new Set(capabilityFamilies(members));

  // One flat port namespace: an input/output name collision makes every
  // predicate root ambiguous.
  if (inputNames.some((name) => outputNames.includes(name))) {
    return { ok: false, e: "invalid_cardinality" };
  }

  const assertions = memberArray(members, "evaluation_assertions");
  for (const assertion of assertions) {
    if (assertion.t !== "obj") continue;
    const result = assertionHookCheck(assertion, allPortNames, families);
    if (!result.ok) return result;
  }
  return { ok: true };
}

function assertionHookCheck(
  assertion: Value & { t: "obj" },
  portNames: Set<string>,
  families: Set<string>,
): VResult {
  const kind = keyfind(assertion.v, "kind");
  if (kind === null || kind.t !== "str") return { ok: true };

  switch (kind.v) {
    case "deterministic_predicate": {
      const predicateValue = keyfind(assertion.v, "predicate");
      if (predicateValue === null) return { ok: true };
      return predicate.validate(predicateValue, [...portNames]);
    }
    case "output_schema": {
      const port = keyfind(assertion.v, "port");
      if (port === null || port.t !== "str") return { ok: true };
      return portNames.has(port.v) ? { ok: true } : { ok: false, e: "invalid_constraint" };
    }
    case "required_capability_use":
    case "approval_expected": {
      const family = keyfind(assertion.v, "operation_family");
      if (family === null || family.t !== "str") return { ok: true };
      return families.has(family.v) ? { ok: true } : { ok: false, e: "invalid_constraint" };
    }
    case "provenance_tie_out": {
      const member = keyfind(assertion.v, "member");
      if (member === null || member.t !== "str") return { ok: true };
      return COVERED_MEMBERS.includes(member.v) ? { ok: true } : { ok: false, e: "invalid_constraint" };
    }
    default:
      return { ok: true };
  }
}

function hookOutputContract(members: Map<string, Value>): VResult {
  const outputNames = new Set(portNames(members, "output_ports"));
  const contract = members.get("output_contract");
  if (contract === undefined || contract.t !== "obj") return { ok: true };
  const port = keyfind(contract.v, "port");
  if (port === null || port.t !== "str") return { ok: true };
  return outputNames.has(port.v) ? { ok: true } : { ok: false, e: "invalid_constraint" };
}

function portNames(members: Map<string, Value>, memberName: string): string[] {
  const out: string[] = [];
  for (const entry of memberArray(members, memberName)) {
    if (entry.t !== "obj") continue;
    const name = keyfind(entry.v, "name");
    if (name !== null && name.t === "str") out.push(name.v);
  }
  return out;
}

function capabilityFamilies(members: Map<string, Value>): string[] {
  const out: string[] = [];
  for (const entry of memberArray(members, "capability_requirements")) {
    if (entry.t !== "obj") continue;
    const family = keyfind(entry.v, "operation_family");
    if (family !== null && family.t === "str") out.push(family.v);
  }
  return out;
}

function memberArray(members: Map<string, Value>, name: string): Value[] {
  const found = members.get(name);
  return found !== undefined && found.t === "arr" ? found.v : [];
}

// ---- the portability scan -----------------------------------------------------------

function scan(value: Value, authoredNs: Set<string>): VResult {
  if (value.t !== "obj") return { ok: false, e: "invalid_type" };
  const members = value.v;

  const openRegions = scanOpenRegions(members, authoredNs);
  if (!openRegions.ok) return openRegions;

  const coreStrings = scanCoreStrings(members);
  if (!coreStrings.ok) return coreStrings;

  return scanEvidenceKeyIds(members);
}

// Extension bodies: names + strict values — EXCEPT negotiation-validated
// critical namespaces. Schema documents and predicate operands: names +
// exempting values.
function scanOpenRegions(members: [string, Value][], validatedNs: Set<string>): VResult {
  const strictBodies = extension.bodies(members).filter(([ns]) => !validatedNs.has(ns));

  const scans: VResult[] = [
    ...strictBodies.map(([, body]) => portability.scan(body)),
    ...[...schemaDocuments(members), ...predicateOperands(members)].map((doc) =>
      portability.scanAuthored(doc),
    ),
  ];

  for (const result of scans) {
    if (!result.ok) return result;
  }
  return { ok: true };
}

// The arbitrary-JSON operands a deterministic_predicate carries — open
// content in a digest-covered core position.
function predicateOperands(members: [string, Value][]): Value[] {
  const out: Value[] = [];
  const assertions = memberListOf(members, "evaluation_assertions");
  for (const assertion of assertions) {
    if (assertion.t !== "obj") continue;
    const kind = keyfind(assertion.v, "kind");
    if (kind === null || kind.t !== "str" || kind.v !== "deterministic_predicate") continue;
    const predicateValue = keyfind(assertion.v, "predicate");
    if (predicateValue === null || predicateValue.t !== "obj") continue;
    for (const operandName of ["value", "values"]) {
      const operand = keyfind(predicateValue.v, operandName);
      if (operand !== null) out.push(operand);
    }
  }
  return out;
}

function schemaDocuments(members: [string, Value][]): Value[] {
  return [
    ...portSchemas(members, "input_ports"),
    ...portSchemas(members, "output_ports"),
    ...capabilitySchemas(members),
    ...assertionSchemas(members),
  ];
}

function portSchemas(members: [string, Value][], memberName: string): Value[] {
  const out: Value[] = [];
  for (const entry of memberListOf(members, memberName)) {
    if (entry.t !== "obj") continue;
    const found = keyfind(entry.v, "schema");
    if (found !== null) out.push(found);
  }
  return out;
}

function capabilitySchemas(members: [string, Value][]): Value[] {
  const out: Value[] = [];
  for (const entry of memberListOf(members, "capability_requirements")) {
    if (entry.t !== "obj") continue;
    for (const name of ["argument_schema", "result_schema"]) {
      const found = keyfind(entry.v, name);
      if (found !== null) out.push(found);
    }
  }
  return out;
}

function assertionSchemas(members: [string, Value][]): Value[] {
  const out: Value[] = [];
  for (const assertion of memberListOf(members, "evaluation_assertions")) {
    if (assertion.t !== "obj") continue;
    const kind = keyfind(assertion.v, "kind");
    if (kind === null || kind.t !== "str" || kind.v !== "output_schema") continue;
    const found = keyfind(assertion.v, "schema");
    if (found !== null) out.push(found);
  }
  return out;
}

// Value shapes over every other core string. Identifier-convention positions
// keep the exemption; everything else is strict.
function scanCoreStrings(members: [string, Value][]): VResult {
  for (const [name, value] of members) {
    if (EVIDENCE_MEMBERS.includes(name) || name === "extensions") continue;
    const result = coreMemberScan(name, value);
    if (!result.ok) return result;
  }
  return { ok: true };
}

function coreMemberScan(name: string, value: Value): VResult {
  switch (name) {
    case "input_ports":
    case "output_ports":
      return identifierPositions(value, ["name"]);
    case "capability_requirements":
      return identifierPositions(value, ["operation_family"]);
    case "effect_intents":
      return identifierPositions(value, ["logical_operation"]);
    case "evaluation_assertions":
      return identifierPositions(value, ["dataset", "member", "operation_family", "parameter"]);
    default:
      return portability.scanValue(value);
  }
}

// Element objects: ONLY the named identifier members are scanned here
// (exempting mode).
function identifierPositions(value: Value, names: string[]): VResult {
  if (value.t !== "arr") return { ok: true };
  for (const element of value.v) {
    if (element.t !== "obj") continue;
    for (const [name, memberValue] of element.v) {
      if (!names.includes(name)) continue;
      const result = portability.scanIdentifier(memberValue);
      if (!result.ok) return result;
    }
  }
  return { ok: true };
}

// The one free string inside an evidence entry: a secret-shaped key_id there
// must still red.
function scanEvidenceKeyIds(members: [string, Value][]): VResult {
  for (const entry of memberListOf(members, "signatures")) {
    const attrs = signatureAttributes(entry);
    if (!attrs.ok) continue; // unparseable entries already denied at the table
    const scanned = portability.scanValue({ t: "str", v: attrs.v.keyId });
    if (!scanned.ok) return scanned;
  }
  return { ok: true };
}

function memberListOf(members: [string, Value][], name: string): Value[] {
  const found = keyfind(members, name);
  return found !== null && found.t === "arr" ? found.v : [];
}

// ---- the Signature.attributes twin ---------------------------------------------------
//
// Shape-validated only — no signature checked. The TS signature twin keeps
// its parts parser private, so the artifact tables (blueprint/deployment/
// federation purpose checks, evidence key-id scans) share this projection.

export interface SignatureAttributes {
  contentDigest: digest.Digest;
  createdAt: string;
  keyId: string;
  purpose: "blueprint" | "deployment" | "federation-envelope";
}

const PURPOSES = new Set(["blueprint", "deployment", "federation-envelope"]);
const ENTRY_MEMBERS = ["protected", "signature", "signed_attributes"];
const HEADER_MEMBERS = ["alg", "b64", "crit", "kid"];
const ATTR_MEMBERS = ["algorithm", "content_digest", "created_at", "key_id", "purpose"];

function malformed(): { ok: false; e: string } {
  return { ok: false, e: "signature_malformed" };
}

export function signatureAttributes(entry: Value): { ok: true; v: SignatureAttributes } | { ok: false; e: string } {
  if (entry.t !== "obj") return malformed();
  const entryPairs = entry.v;

  const entryNames = entryPairs.map(([name]) => name).sort();
  if (
    entryNames.length !== 3 ||
    entryNames.join("\u0000") !== ENTRY_MEMBERS.join("\u0000")
  ) {
    return malformed();
  }

  const header = keyfind(entryPairs, "protected")!;
  const attrs = keyfind(entryPairs, "signed_attributes")!;
  const signatureBody = keyfind(entryPairs, "signature")!;

  // Header: exactly {alg, b64, crit, kid}; the one algorithm-unsupported
  // denial fires only when alg is a string naming another algorithm.
  if (header.t !== "obj") return malformed();
  const headerNames = header.v.map(([name]) => name).sort();
  if (headerNames.length !== 4 || headerNames.join("\u0000") !== HEADER_MEMBERS.join("\u0000")) {
    return malformed();
  }
  const alg = keyfind(header.v, "alg")!;
  if (alg.t === "str" && alg.v !== "EdDSA") {
    return { ok: false, e: "signature_algorithm_unsupported" };
  }
  if (alg.t !== "str") return malformed();
  const b64Flag = keyfind(header.v, "b64")!;
  if (b64Flag.t !== "bool" || b64Flag.v !== false) return malformed();
  const crit = keyfind(header.v, "crit")!;
  if (
    crit.t !== "arr" ||
    crit.v.length !== 1 ||
    crit.v[0]!.t !== "str" ||
    crit.v[0]!.v !== "b64"
  ) {
    return malformed();
  }
  const kid = keyfind(header.v, "kid")!;
  if (kid.t !== "str" || kid.v === "") return malformed();

  // Attributes: exactly the five closed members.
  if (attrs.t !== "obj") return malformed();
  const attrNames = attrs.v.map(([name]) => name).sort();
  if (attrNames.length !== 5 || attrNames.join("\u0000") !== ATTR_MEMBERS.join("\u0000")) {
    return malformed();
  }
  const algorithm = keyfind(attrs.v, "algorithm")!;
  if (algorithm.t === "str" && algorithm.v !== "Ed25519") {
    return { ok: false, e: "signature_algorithm_unsupported" };
  }
  if (algorithm.t !== "str") return malformed();
  const contentDigest = keyfind(attrs.v, "content_digest")!;
  if (contentDigest.t !== "str" || !digest.fromTagged(contentDigest.v).ok) return malformed();
  const createdAt = keyfind(attrs.v, "created_at")!;
  if (createdAt.t !== "str" || !Z_FORM.test(createdAt.v) || !validZFormDate(createdAt.v)) {
    return malformed();
  }
  const keyId = keyfind(attrs.v, "key_id")!;
  if (keyId.t !== "str" || keyId.v === "" || keyId.v.includes(".")) return malformed();
  const purpose = keyfind(attrs.v, "purpose")!;
  if (purpose.t !== "str" || !PURPOSES.has(purpose.v)) return malformed();

  if (kid.v !== keyId.v) return malformed();

  if (signatureBody.t !== "str") return malformed();
  const decodedSignature = b64.decodeStrict(signatureBody.v);
  if (!decodedSignature.ok || decodedSignature.v.length !== 64) return malformed();

  // canonical_input: both halves must re-encode (invalid UTF-8 in a
  // hand-built entry denies malformed).
  const headerJson = canonical.encode(header);
  const attrsJson = canonical.encode(attrs);
  if (!headerJson.ok || !attrsJson.ok) return malformed();

  const parsedDigest = digest.fromTagged(contentDigest.v);
  if (!parsedDigest.ok) return malformed();

  return {
    ok: true,
    v: {
      contentDigest: parsedDigest.v,
      createdAt: createdAt.v,
      keyId: keyId.v,
      purpose: purpose.v as SignatureAttributes["purpose"],
    },
  };
}

// DateTime.from_iso8601's field validation for the Z whole-second form.
export function validZFormDate(stamped: string): boolean {
  const year = Number(stamped.slice(0, 4));
  const month = Number(stamped.slice(5, 7));
  const day = Number(stamped.slice(8, 10));
  const hour = Number(stamped.slice(11, 13));
  const minute = Number(stamped.slice(14, 16));
  const second = Number(stamped.slice(17, 19));
  if (Number.isNaN(year) || month < 1 || month > 12 || day < 1 || hour > 23 || minute > 59 || second > 59) {
    return false;
  }
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day <= lengths[month - 1]!;
}
