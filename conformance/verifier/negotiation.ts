// Negotiation — the mirror of AgentBlueprintProtocol.Negotiation: the
// evolution gate over protocol machinery only (protocol_revision →
// required_core_fields → extensions, precedence pinned), the host-pinned
// lifecycle-only registry view layered over the compiled registry, the
// extension region state machine (criticality before state for LIVE states),
// digest-pinned schema validation of critical bodies, and the
// reserved-semantics denylist over all extension bodies.

import * as canonical from "./canonical.ts";
import * as digest from "./digest.ts";
import { keyfind } from "./registry_engine.ts";
import { entry as compiledEntry, type RegState } from "./registry.ts";
import * as schema from "./schema.ts";
import type { Value } from "./value.ts";

export interface RegistryEntryInput {
  owner: string;
  criticality: "critical" | "optional";
  state: RegState;
  schemaDigest: string | null;
  a2aUri: string;
  promotedAtRevision: number | null;
}

export interface Support {
  revisions: Set<number>;
  coreFields: Set<string>;
  registry: Record<string, RegistryEntryInput>;
  schemas: Record<string, Value>;
}

export interface Outcome {
  protocolRevision: number;
  criticalExtensions: string[];
  quarantinedExtensions: string[];
  notices: string[];
}

type VResult = { ok: true } | { ok: false; e: string };

const BLUEPRINT_CORE_MEMBERS = [
  "blueprint_id",
  "capability_requirements",
  "ceilings",
  "classification_ceiling",
  "content_digest",
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
  "signatures",
  "attestations",
  "triggers",
];

const DEPLOYMENT_CORE_MEMBERS = [
  "authority_requirement",
  "blueprint_release",
  "build_identities",
  "data_bindings",
  "deployment_digest",
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
  "signatures",
  "attestations",
  "tool_bindings",
];

const BLUEPRINT_EVIDENCE_MEMBERS = ["content_digest", "signatures", "attestations"];
const DEPLOYMENT_EVIDENCE_MEMBERS = ["deployment_digest", "signatures", "attestations"];

interface ResolvedEntry {
  criticality: "critical" | "optional";
  state: RegState;
  schemaDigest: string | null;
}

// The protected families + the eight ceilings, snake and camel — stored
// NORMALIZED; kebab/upper/case-collapsed spellings converge at compare time.
const RESERVED_NAMES = new Set([
  "approval_trait",
  "approvaltrait",
  "authority_trait",
  "authoritytrait",
  "classification_ceiling",
  "classificationceiling",
  "disclosure_ceiling",
  "disclosureceiling",
  "effect_impact_ceiling",
  "effectimpactceiling",
  "max_attempts",
  "max_concurrency",
  "max_cost",
  "max_depth",
  "max_descendants",
  "max_elapsed_ms",
  "max_fan_out",
  "max_tokens",
  "maxattempts",
  "maxconcurrency",
  "maxcost",
  "maxdepth",
  "maxdescendants",
  "maxelapsedms",
  "maxfanout",
  "maxtokens",
]);

export function negotiate(artifact: Value, support: Support): { ok: true; v: Outcome } | { ok: false; e: string } {
  // Revision stays FIRST — a max+1 artifact reports its revision reason
  // before any other defect.
  const revision = revisionCheck(artifact, support);
  if (!revision.ok) return revision;

  const vocabulary = vocabularyOf(artifact);
  if (!vocabulary.ok) return vocabulary;

  const fields = requiredFieldsCheck(artifact, support, vocabulary.v);
  if (!fields.ok) return fields;

  const extensions = extensionsCheck(artifact, support);
  if (!extensions.ok) return extensions;

  return {
    ok: true,
    v: {
      protocolRevision: revision.v,
      criticalExtensions: extensions.v.critical,
      quarantinedExtensions: extensions.v.quarantined,
      notices: extensions.v.notices,
    },
  };
}

// The artifact kind resolves through MACHINERY only: which digest member the
// value carries selects the vocabulary. Neither member is an absent-machinery
// deny; both is an undecidable kind.
function vocabularyOf(
  value: Value,
): { ok: true; v: { core: string[]; evidence: string[] } } | { ok: false; e: string } {
  const deployment = memberOf(value, "deployment_digest");
  const blueprint = memberOf(value, "content_digest");

  const deploymentString = deployment !== null && deployment.t === "str";
  const blueprintString = blueprint !== null && blueprint.t === "str";

  if (deploymentString && blueprintString) return { ok: false, e: "invalid_type" };
  if (deploymentString) return { ok: true, v: { core: DEPLOYMENT_CORE_MEMBERS, evidence: DEPLOYMENT_EVIDENCE_MEMBERS } };
  if (blueprintString) return { ok: true, v: { core: BLUEPRINT_CORE_MEMBERS, evidence: BLUEPRINT_EVIDENCE_MEMBERS } };
  if (deployment !== null || blueprint !== null) return { ok: false, e: "invalid_type" };
  return { ok: false, e: "missing_required_field" };
}

// ---- revision (first in the pinned order) -------------------------------------------

function revisionCheck(value: Value, support: Support): { ok: true; v: number } | { ok: false; e: string } {
  const found = memberOf(value, "protocol_revision");
  if (found === null) return { ok: false, e: "missing_required_field" };
  if (found.t !== "int") return { ok: false, e: "invalid_type" };
  if (found.v < 1) return { ok: false, e: "invalid_constraint" };
  if (!support.revisions.has(found.v)) return { ok: false, e: "protocol_revision_unsupported" };
  return { ok: true, v: found.v };
}

// ---- required_core_fields (second) -----------------------------------------------------

function requiredFieldsCheck(
  value: Value,
  support: Support,
  vocabulary: { core: string[]; evidence: string[] },
): VResult {
  const found = memberOf(value, "required_core_fields");
  if (found === null) return { ok: false, e: "missing_required_field" };
  if (found.t !== "arr") return { ok: false, e: "invalid_type" };

  for (const item of found.v) {
    if (item.t !== "str") return { ok: false, e: "invalid_type" };
    const name = item.v;
    if (!vocabulary.core.includes(name)) return { ok: false, e: "required_core_field_unsupported" };
    if (vocabulary.evidence.includes(name)) return { ok: false, e: "required_core_field_not_digest_covered" };
    if (!support.coreFields.has(name)) return { ok: false, e: "required_core_field_unsupported" };
  }
  return { ok: true };
}

// ---- extensions (third) ------------------------------------------------------------------

interface ExtensionFlow {
  critical: string[];
  quarantined: string[];
  notices: string[];
}

function extensionsCheck(value: Value, support: Support): { ok: true; v: ExtensionFlow } | { ok: false; e: string } {
  const found = memberOf(value, "extensions");
  if (found === null) return { ok: false, e: "missing_required_field" };
  if (found.t !== "obj") return { ok: false, e: "invalid_type" };
  const regions = found.v;

  // Both regions present, both objects — anything else is malformed machinery.
  const names = regions.map(([name]) => name).sort();
  const allObjects = regions.every(([, region]) => region.t === "obj");
  if (names.length !== 2 || names[0] !== "critical" || names[1] !== "optional" || !allObjects) {
    return { ok: false, e: "invalid_type" };
  }

  const reserved = reservedSemanticsCheck(regions);
  if (!reserved.ok) return reserved;

  const critical = regionNamespaces(regions, "critical");
  const optional = regionNamespaces(regions, "optional");

  const flow: ExtensionFlow = { critical: [], quarantined: [], notices: [] };

  for (const ns of critical) {
    const judgment = criticalJudgment(ns, regions, support);
    if (!judgment.ok) return judgment;
    flow.critical.push(ns);
    if (judgment.deprecated) flow.notices.push("extension_deprecated");
  }

  for (const ns of optional) {
    const judgment = optionalJudgment(ns, support);
    if (typeof judgment === "object" && "error" in judgment) return { ok: false, e: judgment.error };
    if (judgment === "quarantine") {
      flow.quarantined.push(ns);
      flow.notices.push("extension_unknown_optional_retained");
    } else if (judgment.notice !== null) {
      flow.notices.push(judgment.notice);
    }
  }

  return { ok: true, v: flow };
}

// The host-pinned view is LIFECYCLE-ONLY over compiled entries: state may be
// supplied, but criticality and the schema digest pin are the registry's
// alone. Entries for namespaces the registry does not carry pass through as
// given (the host-supplied registration surface).
function resolveEntry(namespace: string, support: Support): ResolvedEntry | null {
  const override = support.registry[namespace];
  if (override !== undefined) {
    const valid =
      (override.criticality === "critical" || override.criticality === "optional") &&
      ["reserved", "active", "deprecated", "retired"].includes(override.state);
    if (valid) {
      const compiled = compiledEntry(namespace);
      if (compiled !== null) {
        return { criticality: compiled.criticality, state: override.state, schemaDigest: compiled.schema_digest };
      }
      return {
        criticality: override.criticality,
        state: override.state,
        schemaDigest: override.schemaDigest,
      };
    }
  }
  const compiled = compiledEntry(namespace);
  if (compiled === null) return null;
  return { criticality: compiled.criticality, state: compiled.state, schemaDigest: compiled.schema_digest };
}

function regionNamespaces(regions: [string, Value][], name: string): string[] {
  const found = regions.find(([key]) => key === name);
  if (found === undefined || found[1].t !== "obj") return [];
  return found[1].v.map(([ns]) => ns);
}

function regionBody(regions: [string, Value][], name: string, namespace: string): Value | null {
  const found = regions.find(([key]) => key === name);
  if (found === undefined || found[1].t !== "obj") return null;
  const body = found[1].v.find(([ns]) => ns === namespace);
  return body ? body[1] : null;
}

function criticalJudgment(
  ns: string,
  regions: [string, Value][],
  support: Support,
): ({ ok: true; deprecated: boolean } | { ok: false; e: string }) {
  const entry = resolveEntry(ns, support);
  if (entry === null) return { ok: false, e: "extension_unknown_critical" };

  if (entry.state === "retired") return { ok: false, e: "extension_retired" };
  if (entry.state === "reserved") return { ok: false, e: "extension_unknown_critical" };

  if (entry.criticality !== "critical") return { ok: false, e: "extension_criticality_conflict" };

  const body = regionBody(regions, "critical", ns)!;
  const checked = criticalBodyCheck(entry, body, support, ns);
  if (!checked.ok) return checked;

  return { ok: true, deprecated: entry.state === "deprecated" };
}

function criticalBodyCheck(entry: ResolvedEntry, body: Value, support: Support, namespace: string): VResult {
  if (entry.schemaDigest === null) return { ok: false, e: "extension_schema_unavailable" };
  const schemaDocument = support.schemas[namespace];
  if (schemaDocument === undefined) return { ok: false, e: "extension_schema_unavailable" };

  // The pin: JCS of the parsed document under the extension-schema domain.
  const parsed = schema.parse(schemaDocument, schema.dialect());
  if (!parsed.ok) return parsed;
  const jcs = canonical.encode(parsed.v.root);
  if (!jcs.ok) return jcs;
  const tagged = digest.toTagged(digest.hash("extension_schema", Buffer.from(jcs.v, "utf8")));
  if (tagged !== entry.schemaDigest) return { ok: false, e: "extension_schema_digest_mismatch" };

  return schema.validateInstance(schemaDocument, body, schema.dialect());
}

type OptionalJudgment =
  | { error: string }
  | "quarantine"
  | { notice: string | null };

function optionalJudgment(ns: string, support: Support): OptionalJudgment {
  const entry = resolveEntry(ns, support);
  if (entry === null) return "quarantine";

  switch (entry.state) {
    case "retired":
      return { notice: "extension_retired" };
    case "reserved":
      return { notice: "extension_unknown_optional_retained" };
    case "deprecated":
      if (entry.criticality === "optional") return { notice: "extension_deprecated" };
      return { error: "extension_criticality_conflict" };
    case "active":
      if (entry.criticality === "optional") return { notice: null };
      return { error: "extension_criticality_conflict" };
  }
}

// ---- reserved-semantics denylist --------------------------------------------------------

function reservedSemanticsCheck(regions: [string, Value][]): VResult {
  for (const [, region] of regions) {
    if (region.t !== "obj") continue;
    for (const [, body] of region.v) {
      if (boundShapedWalk(body)) return { ok: false, e: "extension_payload_forbidden" };
    }
  }
  return { ok: true };
}

function reservedShape(name: string): string {
  return name.toLowerCase().replaceAll("-", "_");
}

function boundShapedWalk(value: Value): boolean {
  switch (value.t) {
    case "obj":
      return value.v.some(([name, member]) => RESERVED_NAMES.has(reservedShape(name)) || boundShapedWalk(member));
    case "arr":
      return value.v.some(boundShapedWalk);
    default:
      return false;
  }
}

function memberOf(value: Value, name: string): Value | null {
  if (value.t !== "obj") return null;
  return keyfind(value.v, name);
}
