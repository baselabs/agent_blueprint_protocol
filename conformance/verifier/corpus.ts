// The conformance-corpus loader and integrity verifier — the mirror of
// AgentBlueprintProtocol.Conformance.Corpus. No I/O: load() takes a path→bytes
// map; the CLI owns the filesystem. Every check is two-directional and fails
// with the twin's typed, value-free codes (exit 2 at the CLI):
//
//   index absent/undecodable/bad structure/non-canonical bytes/digest mismatch
//     → corpus_index_invalid
//   case file undecodable/wrong shape; case structure incl. malformed tamper,
//     verbatim ≠ derived, lying raw_file reference → corpus_case_invalid
//   per-file SHA-256 ≠ index → corpus_hash_mismatch
//   file-set inequality (either direction) → corpus_file_set_mismatch
//   case-id repeat or non-binary → corpus_case_id_duplicate
//   per-file or total count disagreement → corpus_count_mismatch
//   applicability shape / required-cell / observed-count failure
//     → corpus_applicability_incomplete
//   zero cases total → corpus_empty
//
// Integrity works over TAGGED values (pair-array members) so hostile member
// names never touch JS object semantics.

import * as b64 from "./b64url.ts";
import { encode } from "./canonical.ts";
import { decode } from "./decode.ts";
import * as digest from "./digest.ts";
import { registryDigest } from "./registry.ts";
import type { Value } from "./value.ts";

const INDEX_FORMAT = "agent-blueprint-protocol-conformance-corpus-index";
const CASE_FILE_FORMAT = "agent-blueprint-protocol-conformance-cases";

export const SURFACES = [
  "json.decode",
  "canonicalization.encode",
  "base64url.decode",
  "digest.tagged",
  "signature.verify",
  "schema.validate_instance",
  "blueprint.decode",
  "deployment.decode",
  "negotiation.negotiate",
  "extension.resolve",
  "bounds.new",
  "bounds_algebra.intersect",
  "portability.scan",
  "compatibility.verify",
  "federation.decode",
  "federation.verify_commitment",
] as const;

export const CLASSES = [
  "valid",
  "boundary_near",
  "exact_bound",
  "maximum_plus_one",
  "invalid_encoding",
  "invalid_duplicate",
  "invalid_type",
  "invalid_constraint",
  "invalid_cardinality",
  "unknown_member",
  "tamper_meaningful_byte",
  "digest_mismatch",
  "signature_invalid",
  "revision_above_max",
  "revision_below_min",
  "required_field_unsupported",
  "required_field_not_covered",
  "extension_unknown_critical",
  "extension_unknown_optional_roundtrip",
  "extension_criticality_conflict",
  "extension_schema_unavailable",
  "extension_deprecated_retained",
  "bound_widening_operational",
  "bound_widening_protected",
  "forbidden_portable_value",
  "compatibility_range_rejected",
  "binding_stale",
  "federation_state_unmappable",
  "federation_terminal_conflict",
  "audience_mismatch",
  "terminal_equivocation",
] as const;

// The pinned 16×29 floor: per surface, required classes + the falsifiable
// n_a reason covering its complement.
const FLOOR: Record<string, { required: string[]; n_a: string }> = {
  "json.decode": {
    required: [
      "valid",
      "boundary_near",
      "exact_bound",
      "maximum_plus_one",
      "invalid_encoding",
      "invalid_duplicate",
      "invalid_type",
    ],
    n_a: "all artifact/negotiation/signature/bounds/federation classes - no such semantics reach the byte decoder",
  },
  "canonicalization.encode": {
    required: [
      "valid",
      "boundary_near",
      "exact_bound",
      "maximum_plus_one",
      "invalid_encoding",
      "tamper_meaningful_byte",
    ],
    n_a: "decode-side and artifact-layer classes - encoder consumes the tagged algebra only",
  },
  "base64url.decode": {
    required: ["valid", "invalid_encoding", "exact_bound"],
    n_a: "all others - pure codec",
  },
  "digest.tagged": {
    required: ["valid", "invalid_encoding", "digest_mismatch", "tamper_meaningful_byte"],
    n_a: "artifact/negotiation classes - digest layer sees bytes + tags only",
  },
  "signature.verify": {
    required: [
      "valid",
      "signature_invalid",
      "tamper_meaningful_byte",
      "invalid_encoding",
      "invalid_constraint",
    ],
    n_a: "bounds/federation/artifact classes - verification sees JWS inputs only",
  },
  "schema.validate_instance": {
    required: ["valid", "invalid_type", "invalid_constraint", "maximum_plus_one", "invalid_cardinality"],
    n_a: "signature/digest/federation classes - instance validation is schema-local",
  },
  "blueprint.decode": {
    required: [
      "valid",
      "unknown_member",
      "invalid_type",
      "invalid_constraint",
      "invalid_cardinality",
      "maximum_plus_one",
      "forbidden_portable_value",
      "tamper_meaningful_byte",
    ],
    n_a: "federation/compatibility classes - deployment-side; revision classes owned by negotiation surface",
  },
  "deployment.decode": {
    required: [
      "valid",
      "unknown_member",
      "invalid_type",
      "invalid_constraint",
      "invalid_cardinality",
      "maximum_plus_one",
      "forbidden_portable_value",
      "tamper_meaningful_byte",
      "digest_mismatch",
      "binding_stale",
      "compatibility_range_rejected",
    ],
    n_a: "federation state classes - no task semantics",
  },
  "negotiation.negotiate": {
    required: [
      "valid",
      "revision_above_max",
      "revision_below_min",
      "required_field_unsupported",
      "required_field_not_covered",
      "extension_unknown_critical",
      "extension_criticality_conflict",
      "extension_schema_unavailable",
      "invalid_constraint",
      "invalid_cardinality",
    ],
    n_a: "byte/signature classes - negotiation consumes decoded headers",
  },
  "extension.resolve": {
    required: [
      "valid",
      "extension_unknown_critical",
      "extension_unknown_optional_roundtrip",
      "extension_criticality_conflict",
      "extension_deprecated_retained",
      "forbidden_portable_value",
      "invalid_constraint",
    ],
    n_a: "revision classes - owned by negotiation",
  },
  "bounds.new": {
    required: ["valid", "exact_bound", "maximum_plus_one", "invalid_type"],
    n_a: "artifact classes - parse-ceiling struct only",
  },
  "bounds_algebra.intersect": {
    required: [
      "valid",
      "bound_widening_operational",
      "bound_widening_protected",
      "invalid_type",
      "invalid_constraint",
    ],
    n_a: "byte/signature classes - algebra consumes typed bound sets",
  },
  "portability.scan": {
    required: ["valid", "forbidden_portable_value"],
    n_a: "all others - single-purpose guard",
  },
  "compatibility.verify": {
    required: ["valid", "compatibility_range_rejected", "invalid_constraint"],
    n_a: "byte classes",
  },
  "federation.decode": {
    required: [
      "valid",
      "federation_state_unmappable",
      "unknown_member",
      "invalid_type",
      "forbidden_portable_value",
    ],
    n_a: "bounds classes - envelope carries commitments, not bound sets",
  },
  "federation.verify_commitment": {
    required: [
      "valid",
      "audience_mismatch",
      "federation_terminal_conflict",
      "terminal_equivocation",
      "signature_invalid",
    ],
    n_a: "decode classes - consumes decoded commitments",
  },
};

export interface LoadedCorpus {
  index: Value; // tagged object
  indexBytes: Buffer;
  cases: { path: string; cases: CaseObj[] }[]; // file order: sorted by path
  data: Map<string, Value>; // schemas/ + vectors/ decoded
  raws: Map<string, Buffer>;
  caseIds: Set<string>;
  identity: string; // tagged corpus digest
}

export interface CaseObj {
  id: string;
  surface: string;
  klass: string;
  input: Value; // tagged object
  expected: Value; // tagged object
  tamper: TamperSpec | null;
  raw: Value; // the full case object
}

export interface TamperSpec {
  baseCase: string;
  byteIndex: number;
  target: string | null;
  xor: number;
}

type LoadResult = { ok: true; v: LoadedCorpus } | { ok: false; e: string };

const indexInvalid = () => ({ ok: false as const, e: "corpus_index_invalid" });
const caseInvalid = () => ({ ok: false as const, e: "corpus_case_invalid" });

export function load(map: Map<string, Buffer>): LoadResult {
  const indexBytes = map.get("index.json");
  if (indexBytes === undefined) return indexInvalid();

  const decodedIndex = decode(indexBytes);
  if (!decodedIndex.ok || decodedIndex.v.t !== "obj") return indexInvalid();
  const index = decodedIndex.v;

  const structure = verifyStructure(index);
  if (!structure.ok) return structure;

  const canonicalBytes = verifyCanonicalBytes(index, indexBytes);
  if (!canonicalBytes.ok) return canonicalBytes;

  const corpusDigestOk = verifyCorpusDigest(index);
  if (!corpusDigestOk.ok) return corpusDigestOk;

  if (memberString(index, "registry_digest") !== registryDigest()) {
    return indexInvalid();
  }

  const totalCases = memberNumber(index, "total_cases");
  if (totalCases === null) return indexInvalid();
  if (totalCases === 0) return { ok: false, e: "corpus_empty" };

  const files = orderedFiles(index);
  const loaded = loadFiles(files, map);
  if (!loaded.ok) return loaded;

  const fileSet = verifyFileSet(files, map);
  if (!fileSet.ok) return fileSet;

  const hashes = verifyHashes(files, map);
  if (!hashes.ok) return hashes;

  const counts = verifyCounts(index, loaded.v.cases);
  if (!counts.ok) return counts;

  const caseIds = verifyCaseIds(loaded.v.cases);
  if (!caseIds.ok) return caseIds;

  const validity = verifyCaseValidity(loaded.v.cases);
  if (!validity.ok) return validity;

  const applicability = verifyApplicability(index, loaded.v.cases);
  if (!applicability.ok) return applicability;

  const rawBindings = verifyRawBindings(loaded.v.cases, loaded.v.raws);
  if (!rawBindings.ok) return rawBindings;

  return {
    ok: true,
    v: {
      index,
      indexBytes,
      cases: loaded.v.cases,
      data: loaded.v.data,
      raws: loaded.v.raws,
      caseIds: new Set(loaded.v.cases.flatMap((file) => file.cases.map((c) => c.id))),
      identity: digest.toTagged(corpusDigestOf(index)),
    },
  };
}

// ---- structure -------------------------------------------------------------------

function verifyStructure(index: Value): LoadResult | { ok: true } {
  if (index.t !== "obj") return indexInvalid();
  if (memberString(index, "format") !== INDEX_FORMAT) return indexInvalid();

  const revision = memberNumber(index, "protocol_revision");
  if (revision === null || revision < 1 || !Number.isInteger(revision)) return indexInvalid();

  if (memberNumber(index, "total_cases") === null) return indexInvalid();

  const fingerprints = member(index, "public_key_fingerprints");
  if (fingerprints === null || fingerprints.t !== "arr") return indexInvalid();

  if (typeof memberString(index, "registry_digest") !== "string") return indexInvalid();
  if (typeof memberString(index, "corpus_digest") !== "string") return indexInvalid();

  const files = member(index, "files");
  if (files === null || files.t !== "arr") return indexInvalid();

  const paths: unknown[] = [];
  for (const entry of files.v) {
    if (entry.t !== "obj") return indexInvalid();
    const path = memberString(entry, "path");
    const hash = memberString(entry, "sha256_base64url");
    const cases = memberNumber(entry, "cases");
    if (typeof path !== "string" || typeof hash !== "string" || cases === null || !Number.isInteger(cases) || cases < 0) {
      return indexInvalid();
    }
    paths.push(path);
  }
  if (new Set(paths).size !== paths.length) return indexInvalid();
  for (const path of paths) {
    if (!pathAllowed(path as string)) return indexInvalid();
  }

  if (member(index, "applicability")?.t !== "obj") return indexInvalid();

  return { ok: true };
}

function pathAllowed(path: string): boolean {
  const allowed = (prefix: string, ext: string) =>
    path.startsWith(prefix + "/") && path.endsWith(ext);
  return (
    allowed("cases", ".json") ||
    allowed("schemas", ".json") ||
    allowed("vectors", ".json") ||
    allowed("raw", ".raw")
  );
}

function verifyCanonicalBytes(index: Value, indexBytes: Buffer): LoadResult | { ok: true } {
  const encoded = encode(index);
  if (!encoded.ok) return indexInvalid();
  if (Buffer.from(encoded.v, "utf8").equals(indexBytes)) return { ok: true };
  return indexInvalid();
}

function corpusDigestOf(index: Value): digest.Digest {
  const without = objWithout(index, "corpus_digest");
  const encoded = encode(without);
  if (!encoded.ok) throw new Error("index must re-encode");
  return digest.hash("corpus_index", Buffer.from(encoded.v, "utf8"));
}

function verifyCorpusDigest(index: Value): LoadResult | { ok: true } {
  if (digest.toTagged(corpusDigestOf(index)) === memberString(index, "corpus_digest")) {
    return { ok: true };
  }
  return indexInvalid();
}

// ---- file loading ------------------------------------------------------------------

interface LoadedFiles {
  cases: { path: string; cases: CaseObj[] }[];
  data: Map<string, Value>;
  raws: Map<string, Buffer>;
}

function orderedFiles(index: Value): { path: string; cases: number; sha: string }[] {
  const files = member(index, "files")!;
  return files.v
    .map((entry) => ({
      path: memberString(entry, "path")!,
      cases: memberNumber(entry, "cases")!,
      sha: memberString(entry, "sha256_base64url")!,
    }))
    .sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
}

function classifyFile(path: string): "cases" | "raw" | "data" {
  if (path.startsWith("cases/")) return "cases";
  if (path.startsWith("raw/")) return "raw";
  return "data";
}

function loadFiles(files: { path: string }[], map: Map<string, Buffer>): { ok: true; v: LoadedFiles } | LoadResult {
  const cases: { path: string; cases: CaseObj[] }[] = [];
  const data = new Map<string, Value>();
  const raws = new Map<string, Buffer>();

  for (const entry of files) {
    const bytes = map.get(entry.path);
    if (bytes === undefined) return { ok: false, e: "corpus_file_set_mismatch" };
    const kind = classifyFile(entry.path);

    if (kind === "raw") {
      raws.set(entry.path, bytes);
      continue;
    }

    const decoded = decode(bytes);
    if (!decoded.ok) return caseInvalid();

    if (kind === "data") {
      data.set(entry.path, decoded.v);
      continue;
    }

    if (decoded.v.t !== "obj") return caseInvalid();
    if (memberString(decoded.v, "format") !== CASE_FILE_FORMAT) return caseInvalid();
    const caseArray = member(decoded.v, "cases");
    if (caseArray === null || caseArray.t !== "arr") return caseInvalid();

    const parsed: CaseObj[] = [];
    for (const raw of caseArray.v) {
      if (raw.t !== "obj") return caseInvalid();
      const parsedCase = parseCase(raw);
      if (parsedCase === null) return caseInvalid();
      parsed.push(parsedCase);
    }
    cases.push({ path: entry.path, cases: parsed });
  }

  return { ok: true, v: { cases, data, raws } };
}

function parseCase(raw: Value): CaseObj | null {
  if (raw.t !== "obj") return null;
  const id = memberString(raw, "id");
  const surface = memberString(raw, "surface");
  const klass = memberString(raw, "class");
  const input = member(raw, "input");
  const expected = member(raw, "expected");
  if (
    typeof id !== "string" ||
    typeof surface !== "string" ||
    typeof klass !== "string" ||
    !input ||
    input.t !== "obj" ||
    !expected ||
    expected.t !== "obj"
  ) {
    return null;
  }
  const tamperRaw = member(raw, "tamper");
  let tamper: TamperSpec | null = null;
  if (tamperRaw !== null && tamperRaw.t === "obj") {
    const base = memberString(tamperRaw, "base_case");
    const byteIndex = memberNumber(tamperRaw, "byte_index");
    const xor = memberNumber(tamperRaw, "xor");
    const target = memberString(tamperRaw, "target");
    if (typeof base !== "string" || byteIndex === null || !Number.isInteger(byteIndex) || byteIndex < 0 || xor === null || !Number.isInteger(xor) || xor <= 0) {
      return null;
    }
    tamper = { baseCase: base, byteIndex, target: typeof target === "string" ? target : null, xor };
  }
  return { id, surface, klass, input, expected, tamper, raw };
}

// ---- file-set + hashes ---------------------------------------------------------------

function verifyFileSet(files: { path: string }[], map: Map<string, Buffer>): LoadResult | { ok: true } {
  const declared = new Set(files.map((f) => f.path));
  const present = new Set([...map.keys()].filter((k) => k !== "index.json"));
  if (declared.size === present.size && [...declared].every((p) => present.has(p))) {
    return { ok: true };
  }
  return { ok: false, e: "corpus_file_set_mismatch" };
}

function sha256B64(bytes: Buffer): string {
  return digest.of(bytes).bytes.toString("base64url");
}

function verifyHashes(files: { path: string; sha: string }[], map: Map<string, Buffer>): LoadResult | { ok: true } {
  for (const entry of files) {
    const bytes = map.get(entry.path);
    if (bytes === undefined || sha256B64(bytes) !== entry.sha) {
      return { ok: false, e: "corpus_hash_mismatch" };
    }
  }
  return { ok: true };
}

// ---- counts ---------------------------------------------------------------------------

function verifyCounts(index: Value, cases: { path: string; cases: CaseObj[] }[]): LoadResult | { ok: true } {
  const perFile = new Map(cases.map((file) => [file.path, file.cases.length]));
  const files = member(index, "files")!;
  let total = 0;
  for (const entry of files.v) {
    const path = memberString(entry, "path")!;
    const declaredCases = memberNumber(entry, "cases")!;
    if (path.startsWith("cases/")) {
      const observed = perFile.get(path);
      if (observed === undefined || observed !== declaredCases) {
        return { ok: false, e: "corpus_count_mismatch" };
      }
      total += declaredCases;
    } else if (declaredCases !== 0) {
      return { ok: false, e: "corpus_count_mismatch" };
    }
  }
  if (total !== memberNumber(index, "total_cases")) {
    return { ok: false, e: "corpus_count_mismatch" };
  }
  return { ok: true };
}

// ---- case ids + validity -----------------------------------------------------------------

function verifyCaseIds(cases: { cases: CaseObj[] }[]): LoadResult | { ok: true } {
  const ids = cases.flatMap((file) => file.cases.map((c) => c.id));
  return new Set(ids).size === ids.length ? { ok: true } : { ok: false, e: "corpus_case_id_duplicate" };
}

function verifyCaseValidity(cases: { cases: CaseObj[] }[]): LoadResult | { ok: true } {
  const all = cases.flatMap((file) => file.cases);
  const byId = new Map(all.map((c) => [c.id, c]));

  for (const caseObj of all) {
    if (!(SURFACES as readonly string[]).includes(caseObj.surface)) return caseInvalid();
    if (!(CLASSES as readonly string[]).includes(caseObj.klass)) return caseInvalid();
    // A verdict-only valid expectation agrees with any ok-map — the vacuous
    // green; a valid case must pin at least one projection field.
    if (caseObj.expected.t === "obj") {
      const verdict = memberString(caseObj.expected, "verdict");
      if (verdict === "valid" && caseObj.expected.v.length === 1) return caseInvalid();
    }
    if (!verifyOneTamper(caseObj, byId)) return caseInvalid();
  }
  return { ok: true };
}

// A tamper case's verbatim artifact must byte-equal the re-derived
// base-with-one-meaningful-byte-flip on the ADDRESSED target.
function verifyOneTamper(caseObj: CaseObj, byId: Map<string, CaseObj>): boolean {
  if (caseObj.tamper === null) return true;
  const { baseCase, byteIndex, target, xor } = caseObj.tamper;
  const base = byId.get(baseCase);
  if (base === undefined) return false;

  const baseBytes = tamperTargetBytes(base.input, target);
  const verbatimBytes = tamperTargetBytes(caseObj.input, target);
  if (baseBytes === null || verbatimBytes === null) return false;
  if (byteIndex >= baseBytes.length) return false;

  const derived = Buffer.from(baseBytes);
  derived[byteIndex] = derived[byteIndex]! ^ xor;
  return derived.equals(verbatimBytes);
}

function tamperTargetBytes(input: Value, target: string | null): Buffer | null {
  if (input.t !== "obj") return null;
  if (target === null) {
    const text = memberString(input, "text");
    if (typeof text === "string") return Buffer.from(text, "utf8");
    const encoded = memberString(input, "base64url");
    if (typeof encoded === "string") {
      const decoded = b64.decodeLenient(encoded);
      return decoded.ok ? decoded.v : null;
    }
    return null;
  }
  if (target === "input.text") {
    const text = memberString(input, "text");
    return typeof text === "string" ? Buffer.from(text, "utf8") : null;
  }
  if (target === "input.base64url") {
    const encoded = memberString(input, "base64url");
    if (typeof encoded !== "string") return null;
    const decoded = b64.decodeLenient(encoded);
    return decoded.ok ? decoded.v : null;
  }
  if (target === "input.entry") {
    const entry = memberString(input, "entry");
    return typeof entry === "string" ? Buffer.from(entry, "utf8") : null;
  }
  return null;
}

// ---- applicability ------------------------------------------------------------------------

function verifyApplicability(index: Value, cases: { cases: CaseObj[] }[]): LoadResult | { ok: true } {
  const applicability = member(index, "applicability")!;
  if (applicability.t !== "obj") return { ok: false, e: "corpus_applicability_incomplete" };

  const surfaceKeys = new Set(applicability.v.map(([k]) => k));
  const expectedSurfaces = new Set(SURFACES as readonly string[]);
  if (surfaceKeys.size !== expectedSurfaces.size || ![...expectedSurfaces].every((s) => surfaceKeys.has(s))) {
    return { ok: false, e: "corpus_applicability_incomplete" };
  }

  const leavesBySurface = new Map<string, Map<string, Value>>();
  for (const [surface, leaves] of applicability.v) {
    if (leaves.t !== "obj") return { ok: false, e: "corpus_applicability_incomplete" };
    const classKeys = new Set(leaves.v.map(([k]) => k));
    const expectedClasses = new Set(CLASSES as readonly string[]);
    if (classKeys.size !== expectedClasses.size || ![...expectedClasses].every((c) => classKeys.has(c))) {
      return { ok: false, e: "corpus_applicability_incomplete" };
    }
    leavesBySurface.set(surface, new Map(leaves.v));
  }

  for (const [surface, floor] of Object.entries(FLOOR)) {
    const leaves = leavesBySurface.get(surface)!;
    for (const required of floor.required) {
      const leaf = leaves.get(required);
      if (leaf === undefined || leaf.t !== "int" || leaf.v < 1) {
        return { ok: false, e: "corpus_applicability_incomplete" };
      }
    }
  }

  const observed = new Map<string, number>();
  for (const file of cases) {
    for (const caseObj of file.cases) {
      const key = caseObj.surface + "\u0000" + caseObj.klass;
      observed.set(key, (observed.get(key) ?? 0) + 1);
    }
  }

  for (const surface of SURFACES) {
    const leaves = leavesBySurface.get(surface)!;
    for (const klass of CLASSES) {
      const leaf = leaves.get(klass)!;
      const observedCount = observed.get(surface + "\u0000" + klass) ?? 0;
      if (leaf.t === "int") {
        if (observedCount !== leaf.v) return { ok: false, e: "corpus_applicability_incomplete" };
      } else if (leaf.t === "obj") {
        const reason = memberString(leaf, "n_a");
        if (typeof reason !== "string" || reason === "" || observedCount !== 0) {
          return { ok: false, e: "corpus_applicability_incomplete" };
        }
      } else {
        return { ok: false, e: "corpus_applicability_incomplete" };
      }
    }
  }

  return { ok: true };
}

// ---- raw bindings -----------------------------------------------------------------------------

function verifyRawBindings(cases: { cases: CaseObj[] }[], raws: Map<string, Buffer>): LoadResult | { ok: true } {
  for (const file of cases) {
    for (const caseObj of file.cases) {
      if (caseObj.input.t !== "obj") continue;
      const rawPath = memberString(caseObj.input, "raw_file");
      if (rawPath === null) continue;
      const refHash = memberString(caseObj.input, "sha256_base64url");
      const bytes = raws.get(rawPath);
      if (bytes === undefined || typeof refHash !== "string") return caseInvalid();
      if (sha256B64(bytes) !== refHash) return caseInvalid();
    }
  }
  return { ok: true };
}

// ---- tagged-object helpers ----------------------------------------------------------------------

export function member(container: Value, key: string): Value | null {
  if (container.t !== "obj") return null;
  const found = container.v.find(([k]) => k === key);
  return found ? found[1] : null;
}

export function memberString(container: Value, key: string): string | null {
  const found = member(container, key);
  return found !== null && found.t === "str" ? found.v : null;
}

export function memberNumber(container: Value, key: string): number | null {
  const found = member(container, key);
  if (found === null) return null;
  if (found.t === "int" || found.t === "float") return found.v;
  return null;
}

function objWithout(container: Value, drop: string): Value {
  if (container.t !== "obj") return container;
  return { t: "obj", v: container.v.filter(([k]) => k !== drop) };
}
