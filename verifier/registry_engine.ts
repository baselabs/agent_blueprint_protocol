import { isValue } from "./value.ts";
// The generic field-registry validate engine — the mirror of
// AgentBlueprintProtocol.Registry: ONE table-driven walk parameterized by the
// artifact layer's table. The engine knows tables, not domains. Failure
// precedence is pinned: member well-formedness → unknown_member (document
// order) → missing_required_field (table order) → invalid_type (table order)
// → invalid_constraint (table order) → invalid_cardinality (table order) →
// nested recursion (document order, child reasons propagate) → root hooks
// (table order). `:integer` is TAG-STRICT (a float, zero-fraction included,
// denies invalid_type).

import type { Value } from "./value.ts";

export type Kind =
  | "string"
  | "integer"
  | "float"
  | "boolean"
  | "number"
  | "any"
  | "custom"
  | { enum: Set<string> }
  | { array: Spec }
  | { object: { members: Spec[] } };

export type Check = (value: Value) => { ok: true } | { ok: false; e: string; subject?: (string|number)[] };
export type RootHook = (members: Map<string, Value>) => { ok: true } | { ok: false; e: string; subject?: (string|number)[] };

// name/required apply to table members (validate() reads them); array-element
// specs ({array: …} kinds) carry only kind/check — the walk reads those via
// elementOk(), never name/required — so both stay optional.
export interface Spec {
  name?: string;
  required?: boolean;
  kind: Kind;
  check?: Check;
  rootHook?: RootHook;
  minItems?: number;
  maxItems?: number;
  uniqueBy?: string | ":value";
}

export type VResult = { ok: true } | { ok: false; e: string; subject?: (string|number)[] };

// The table-builder helper (the twin's field/2): name + kind, required by
// default, keyword-style options.
export function field(name: string, kind: Kind, opts: Partial<Spec> = {}): Spec {
  return { name, required: true, kind, ...opts };
}

export function validate(table: Spec[], value: Value): VResult {
  if (!isValue(value) || !Array.isArray(table) || Array.from(table).some((spec) => !specShape(spec)) || value.t !== "obj") return { ok: false, e: "invalid_type" };
  const members = value.v;

  for (const [name] of members) {
    if (typeof name !== "string") return { ok: false, e: "invalid_type" };
  }
  const seen = new Set<string>();
  for (const [name] of members) {
    if (seen.has(name)) return { ok: false, e: "invalid_type" };
    seen.add(name);
  }

  const tableNames = new Set(table.map((spec) => spec.name));
  for (const [name] of members) {
    if (!tableNames.has(name)) return { ok: false, e: "unknown_member", subject: [] };
  }

  const present = new Set(members.map(([name]) => name));
  for (const spec of table) {
    // Table specs always come from field() (named); the ! mirrors that invariant.
    if (spec.required && !present.has(spec.name!)) return { ok: false, e: "missing_required_field", subject: [spec.name!] };
  }

  // Every table stage shares one walk: find the first spec (in table order)
  // whose present value fails.
  const stageFailure = (judge: (spec: Spec, value: Value) => { ok: false; e: string; subject?: (string|number)[] } | null): VResult => {
    for (const spec of table) {
      const found = keyfind(members, spec.name!);
      if (found === null) continue;
      const failure = judge(spec, found);
      if (failure !== null) return { ok: false, e: failure.e, subject: [spec.name!, ...(failure.subject ?? [])] };
    }
    return { ok: true };
  };

  const typeStage = stageFailure((spec, value) => (kindOk(spec.kind, value) ? null : { ok: false, e: "invalid_type" }));
  if (!typeStage.ok) return typeStage;

  const constraintStage = stageFailure((spec, value) => specConstraint(spec, value));
  if (!constraintStage.ok) return constraintStage;

  const cardinalityStage = stageFailure((spec, value) => arrayCardinality(spec, value));
  if (!cardinalityStage.ok) return cardinalityStage;

  const recursionStage = stageFailure((spec, value) => passNil(recurse(spec.kind, value)));
  if (!recursionStage.ok) return recursionStage;

  const memberMap = new Map(members);
  for (const spec of table) {
    if (spec.rootHook === undefined) continue;
    if (!memberMap.has(spec.name!)) continue;
    const result = spec.rootHook(memberMap);
    if (!result.ok) return {...result,subject:[spec.name!,...(result.subject??[])]};
  }

  return { ok: true };
}

function specShape(spec: Spec, depth = 0): boolean {
  if (!spec || typeof spec !== "object" || depth > 64) return false;
  if ((spec.check !== undefined && typeof spec.check !== "function") ||
      (spec.rootHook !== undefined && typeof spec.rootHook !== "function")) return false;
  const kind = spec.kind;
  if (typeof kind === "string") return ["string", "integer", "float", "boolean", "number", "any", "custom"].includes(kind);
  if (!kind || typeof kind !== "object") return false;
  if ("enum" in kind) return kind.enum instanceof Set;
  if ("array" in kind) return specShape(kind.array, depth + 1);
  if ("object" in kind) return !!kind.object && Array.isArray(kind.object.members) &&
    kind.object.members.every((member) => specShape(member, depth + 1));
  return false;
}

// ---- stages --------------------------------------------------------------------------

function specConstraint(spec: Spec, value: Value): { ok: false; e: string; subject?: (string|number)[] } | null {
  if (typeof spec.kind === "object" && "enum" in spec.kind) {
    if (value.t === "str") return spec.kind.enum.has(value.v) ? null : { ok: false, e: "invalid_constraint" };
  }
  if (spec.check !== undefined) {
    const result = spec.check(value);
    return result.ok ? null : result;
  }
  return null;
}

function arrayCardinality(spec: Spec, value: Value): { ok: false; e: string; subject?: (string|number)[] } | null {
  if (value.t !== "arr") return null;
  if (spec.minItems !== undefined && value.v.length < spec.minItems) {
    return { ok: false, e: "invalid_cardinality" };
  }
  if (spec.maxItems !== undefined && value.v.length > spec.maxItems) {
    return { ok: false, e: "invalid_cardinality" };
  }
  if (duplicateKeys(spec.uniqueBy, value.v)) return { ok: false, e: "invalid_cardinality" };
  return null;
}

// Uniqueness over raw values: object elements participate through the named
// member; scalar elements participate whole (uniqueBy: ":value").
function duplicateKeys(uniqueBy: string | ":value" | undefined, items: Value[]): boolean {
  if (uniqueBy === undefined) return false;
  if (uniqueBy === ":value") {
    return items.some((item, i) => items.slice(0, i).some((other) => termEqual(item, other)));
  }
  const keys: Value[] = [];
  for (const item of items) {
    if (item.t !== "obj") continue;
    const found = keyfind(item.v, uniqueBy);
    if (found !== null) keys.push(found);
  }
  return keys.some((key, i) => keys.slice(0, i).some((other) => termEqual(key, other)));
}

function passNil(result: VResult): { ok: false; e: string; subject?: (string|number)[] } | null {
  return result.ok ? null : result;
}

// ---- recursion ----------------------------------------------------------------------

function recurse(kind: Kind, value: Value): VResult {
  if (typeof kind === "object" && "array" in kind) {
    if (value.t !== "arr") return { ok: true };
    for (const [index, item] of value.v.entries()) {
      const result = elementOk(kind.array, item);
      if (!result.ok) return {...result,subject:[index,...(result.subject??[])]};
    }
    return { ok: true };
  }
  if (typeof kind === "object" && "object" in kind) {
    if (value.t !== "obj") return { ok: true };
    return validate(kind.object.members, value);
  }
  return { ok: true };
}

function elementOk(spec: Spec, value: Value): VResult {
  if (!kindOk(spec.kind, value)) return { ok: false, e: "invalid_type" };
  const constraint = specConstraint(spec, value);
  if (constraint !== null) return constraint;
  return recurse(spec.kind, value);
}

// ---- kinds --------------------------------------------------------------------------

function kindOk(kind: Kind, value: Value): boolean {
  switch (kind) {
    case "string":
      return value.t === "str";
    case "integer":
      return value.t === "int";
    case "float":
      return value.t === "float";
    case "boolean":
      return value.t === "bool";
    case "number":
      return value.t === "int" || value.t === "float";
    case "any":
      return wellFormed(value);
    case "custom":
      return true;
  }
  if (typeof kind === "object" && "enum" in kind) return value.t === "str";
  if (typeof kind === "object" && "array" in kind) return value.t === "arr";
  if (typeof kind === "object" && "object" in kind) return value.t === "obj";
  return false;
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

// ---- helpers -------------------------------------------------------------------------

export function keyfind(members: [string, Value][], name: string): Value | null {
  if (!Array.isArray(members) || Array.from(members).some((pair) => !Array.isArray(pair) || pair.length !== 2 || typeof pair[0] !== "string")) return null;
  const found = members.find(([key]) => key === name);
  return found ? found[1] : null;
}

// Elixir `=:=` term equality over the tagged algebra: tags are strict
// (int 5 and float 5.0 are distinct), object member ORDER is significant.
export function termEqual(a: Value, b: Value): boolean {
  return isValue(a) && isValue(b) && termEqualAt(a, b);
}

function termEqualAt(a: Value, b: Value): boolean {
  if (a.t !== b.t) return false;
  switch (a.t) {
    case "null":
      return true;
    case "bool":
    case "int":
    case "float":
    case "str":
      return a.v === (b as typeof a).v;
    case "arr":
      return (
        b.t === "arr" &&
        a.v.length === b.v.length &&
        a.v.every((x, i) => termEqualAt(x, b.v[i]!))
      );
    case "obj":
      return (
        b.t === "obj" &&
        a.v.length === b.v.length &&
        a.v.every((pair, i) => {
          const other = b.v[i]!;
          return pair[0] === other[0] && termEqualAt(pair[1], other[1]);
        })
      );
  }
}
