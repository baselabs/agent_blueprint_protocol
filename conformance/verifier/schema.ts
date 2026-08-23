// Bounded JSON Schema 2020-12 dialect + instance validator — the mirror of
// AgentBlueprintProtocol.Schema: the closed 16-keyword subset, positional
// keyword recognition, document-local $ref (RFC 6901 pointers), the 512
// complexity ceiling, application-edge cycle denial, and evaluation in the
// pinned canonical keyword order with (schema-node, instance-location)
// memoization. Numbers compare by mathematical value across the int/float
// tags; string lengths count codepoints.

import type { Value } from "./value.ts";
import { err, ok } from "./value.ts";

const DIALECT = "https://json-schema.org/draft/2020-12/schema";
const CEILING = 512;

const TYPE_NAMES = new Set(["null", "boolean", "object", "array", "number", "string", "integer"]);

// Canonical evaluation order — the FIRST failure in this sequence is the
// reported reason, independent of document member order.
const KEYWORD_ORDER = [
  "$ref",
  "type",
  "enum",
  "const",
  "minimum",
  "maximum",
  "minLength",
  "maxLength",
  "minItems",
  "maxItems",
  "required",
  "properties",
  "items",
  "additionalProperties",
  "oneOf",
] as const;

const SCHEMA_VALUED = ["items", "additionalProperties"];
const NAME_MAP_VALUED = ["properties", "$defs"];

export function dialect(): string {
  return DIALECT;
}

export interface ParsedSchema {
  root: Value;
  pointers: Map<string, Value>; // JSON-pointer-path key → schema-position term
}

export function parse(
  value: Value,
  dialectId: string,
): { ok: true; v: ParsedSchema } | { ok: false; e: string } {
  if (dialectId !== DIALECT) return err("schema_dialect_unknown");
  if (!rootShape(value)) return err("schema_invalid_shape");
  if (!wellFormed(value)) return err("schema_keyword_value_invalid");

  const walked = walk(value, [], meter0(), new Map(), [], true);
  if (!walked.ok) return walked;
  const { acc, pointers, edges } = walked.v;

  for (const [, tokens] of edges) {
    if (!pointers.has(pathKey(tokens))) return err("schema_ref_unresolvable");
  }

  if (!cycleFree(pointers)) return err("schema_ref_cycle");

  return ok({ root: value, pointers });
}

export function validateInstance(
  schema: Value,
  instance: Value,
  dialectId: string,
): { ok: true } | { ok: false; e: string } {
  if (dialectId !== DIALECT) return err("schema_dialect_unknown");
  const parsed = parse(schema, DIALECT);
  if (!parsed.ok) return parsed;
  if (!wellFormed(instance)) return err("invalid_type");
  const result = evaluate(parsed.v.root, instance, [], new Map(), parsed.v.pointers);
  if (result.ok) return ok(undefined);
  return err(result.e);
}

// Structural equality per core §4.2.2 (public on the twin; Predicate consumes
// the one equality law): numbers by mathematical value across tags, strings
// codepoint-for-codepoint, arrays order-sensitive, objects order-blind with
// equal member counts.
export function equal(a: Value, b: Value): boolean {
  if (
    (a.t === "int" || a.t === "float") &&
    (b.t === "int" || b.t === "float")
  ) {
    return a.v === b.v;
  }
  if (a.t !== b.t) return false;
  switch (a.t) {
    case "null":
      return true;
    case "bool":
    case "str":
      return a.v === (b as typeof a).v;
    case "arr":
      return (
        b.t === "arr" &&
        a.v.length === b.v.length &&
        a.v.every((x, i) => equal(x, b.v[i]!))
      );
    case "obj":
      if (b.t !== "obj") return false;
      if (a.v.length !== b.v.length) return false;
      return a.v.every(([name, value]) => {
        const other = b.v.find(([n]) => n === name);
        return other !== undefined && equal(value, other[1]);
      });
  }
}

// ---- gates ----------------------------------------------------------------------

function rootShape(value: Value): boolean {
  return value.t === "obj" || value.t === "bool";
}

// The tagged-value well-formedness gate (decoder output always passes; this
// is the fail-closed guard for hand-built terms).
function wellFormed(value: Value): boolean {
  switch (value.t) {
    case "null":
    case "bool":
    case "int":
    case "float":
      return true;
    case "str":
      return validString(value.v);
    case "arr":
      return value.v.every(wellFormed);
    case "obj": {
      const seen = new Set<string>();
      for (const [name, member] of value.v) {
        if (typeof name !== "string" || !validString(name) || seen.has(name)) return false;
        if (!wellFormed(member)) return false;
        seen.add(name);
      }
      return true;
    }
  }
}

function validString(s: string): boolean {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      const next = s.charCodeAt(i + 1);
      if (!(next >= 0xdc00 && next <= 0xdfff)) return false;
      i++;
    } else if (c >= 0xdc00 && c <= 0xdfff) {
      return false;
    }
  }
  return true;
}

// ---- positional walk: keyword validation, metering, pointers, ref edges -----------

interface Meter {
  nodes: number;
  keywords: number;
  branches: number;
  depth: number;
}

function meter0(): Meter {
  return { nodes: 0, keywords: 0, branches: 0, depth: 0 };
}

function meterSum(m: Meter): number {
  return m.nodes + m.keywords + m.branches + 4 * m.depth;
}

function pathKey(path: string[]): string {
  return JSON.stringify(path);
}

interface Walked {
  acc: Meter;
  pointers: Map<string, Value>;
  edges: [string, string[]][];
}

type WalkResult = { ok: true; v: Walked } | { ok: false; e: string };

function walk(
  term: Value,
  path: string[],
  acc: Meter,
  pointers: Map<string, Value>,
  edges: [string, string[]][],
  validate: boolean,
): WalkResult {
  const stepped: Meter = {
    ...acc,
    nodes: acc.nodes + 1,
    depth: Math.max(acc.depth, path.length + 1),
  };

  if (term.t === "obj") {
    if (validate && meterSum(stepped) > CEILING) return err("schema_complexity_exceeded");
    const next = new Map(pointers);
    next.set(pathKey(path), term);
    return walkMembers(term.v, path, stepped, next, edges, validate);
  }

  if (term.t === "bool") {
    const next = new Map(pointers);
    next.set(pathKey(path), term);
    return ok({ acc: stepped, pointers: next, edges });
  }

  return ok({ acc: stepped, pointers, edges });
}

function walkMembers(
  members: [string, Value][],
  path: string[],
  acc: Meter,
  pointers: Map<string, Value>,
  edges: [string, string[]][],
  validate: boolean,
): WalkResult {
  if (members.length === 0) return ok({ acc, pointers, edges });

  const [[key, value], ...tail] = members;
  const counted: Meter = { ...acc, keywords: acc.keywords + 1 };

  if (validate && !allowedKey(key)) return err("schema_keyword_not_allowed");
  if (validate) {
    const judged = validateValue(key, value);
    if (!judged.ok) return judged;
  }

  const descended = descend(key, value, path, counted, pointers, edges, validate);
  if (!descended.ok) return descended;

  if (validate && meterSum(descended.v.acc) > CEILING) return err("schema_complexity_exceeded");
  return walkMembers(tail, path, descended.v.acc, descended.v.pointers, descended.v.edges, validate);
}

function allowedKey(key: string): boolean {
  return (KEYWORD_ORDER as readonly string[]).includes(key) || key === "$defs";
}

function schemaShape(value: Value): boolean {
  return value.t === "obj" || value.t === "bool";
}

function validateValue(key: string, value: Value): { ok: true } | { ok: false; e: string } {
  const invalid = err("schema_keyword_value_invalid");
  switch (key) {
    case "type":
      if (value.t === "str") return TYPE_NAMES.has(value.v) ? ok(undefined) : invalid;
      if (value.t === "arr") {
        if (!value.v.every((x) => x.t === "str")) return invalid;
        const names = value.v.map((x) => (x as { t: "str"; v: string }).v);
        if (names.length === 0) return invalid;
        if (new Set(names).size !== names.length) return invalid;
        return names.every((n) => TYPE_NAMES.has(n)) ? ok(undefined) : invalid;
      }
      return invalid;
    case "enum":
      return value.t === "arr" ? ok(undefined) : invalid;
    case "const":
      return ok(undefined);
    case "minimum":
    case "maximum":
      return value.t === "int" || value.t === "float" ? ok(undefined) : invalid;
    case "minLength":
    case "maxLength":
    case "minItems":
    case "maxItems":
      if (value.t === "int") return value.v >= 0 ? ok(undefined) : invalid;
      if (value.t === "float") return value.v >= 0 && value.v === Math.trunc(value.v) ? ok(undefined) : invalid;
      return invalid;
    case "required": {
      if (value.t !== "arr") return invalid;
      if (!value.v.every((x) => x.t === "str")) return invalid;
      const names = value.v.map((x) => (x as { t: "str"; v: string }).v);
      return new Set(names).size === names.length ? ok(undefined) : invalid;
    }
    case "properties":
    case "$defs":
      return value.t === "obj" ? ok(undefined) : invalid;
    case "items":
    case "additionalProperties":
      return schemaShape(value) ? ok(undefined) : invalid;
    case "oneOf":
      if (value.t !== "arr" || value.v.length === 0) return invalid;
      return value.v.every(schemaShape) ? ok(undefined) : invalid;
    case "$ref":
      return value.t === "str" ? ok(undefined) : invalid;
    default:
      return invalid;
  }
}

function descend(
  key: string,
  value: Value,
  path: string[],
  acc: Meter,
  pointers: Map<string, Value>,
  edges: [string, string[]][],
  validate: boolean,
): WalkResult {
  if (key === "$ref" && value.t === "str") {
    const tokens = refTokens(value.v);
    if (tokens === null) return err("schema_keyword_not_allowed");
    return ok({ acc, pointers, edges: [[pathKey(path), tokens], ...edges] });
  }

  if (key === "oneOf" && value.t === "arr") {
    // the branch array itself is a document node — count it
    const bumped: Meter = {
      ...acc,
      branches: acc.branches + value.v.length,
      nodes: acc.nodes + 1,
      depth: Math.max(acc.depth, path.length + 2),
    };
    return walkIndexed(value.v, 0, key, path, bumped, pointers, edges, validate);
  }

  if (NAME_MAP_VALUED.includes(key) && value.t === "obj") {
    // the name map itself is a document node — count it, then walk its
    // schema-position values
    const bumped: Meter = {
      ...acc,
      nodes: acc.nodes + 1,
      depth: Math.max(acc.depth, path.length + 2),
    };
    return walkNamed(value.v, key, path, bumped, pointers, edges, validate);
  }

  if (SCHEMA_VALUED.includes(key)) {
    if (schemaShape(value)) {
      return walk(value, [...path, key], acc, pointers, edges, validate);
    }
    return ok({ acc: meterData(value, path.length + 2, acc), pointers, edges });
  }

  // Everything else (type/enum/const/number/required values) is data:
  // nodes only, no keywords inside.
  return ok({ acc: meterData(value, path.length + 2, acc), pointers, edges });
}

function walkIndexed(
  branches: Value[],
  index: number,
  key: string,
  path: string[],
  acc: Meter,
  pointers: Map<string, Value>,
  edges: [string, string[]][],
  validate: boolean,
): WalkResult {
  if (index >= branches.length) return ok({ acc, pointers, edges });
  const sub = branches[index]!;
  if (schemaShape(sub)) {
    const walked = walk(sub, [...path, key, String(index)], acc, pointers, edges, validate);
    if (!walked.ok) return walked;
    return walkIndexed(branches, index + 1, key, path, walked.v.acc, walked.v.pointers, walked.v.edges, validate);
  }
  if (validate) return err("schema_keyword_value_invalid");
  return walkIndexed(
    branches,
    index + 1,
    key,
    path,
    meterData(sub, path.length + 2, acc),
    pointers,
    edges,
    validate,
  );
}

function walkNamed(
  subs: [string, Value][],
  key: string,
  path: string[],
  acc: Meter,
  pointers: Map<string, Value>,
  edges: [string, string[]][],
  validate: boolean,
): WalkResult {
  if (subs.length === 0) return ok({ acc, pointers, edges });
  const [[name, sub], ...tail] = subs;
  if (schemaShape(sub)) {
    const walked = walk(sub, [...path, key, name], acc, pointers, edges, validate);
    if (!walked.ok) return walked;
    return walkNamed(tail, key, path, walked.v.acc, walked.v.pointers, walked.v.edges, validate);
  }
  if (validate) return err("schema_keyword_value_invalid");
  return walkNamed(tail, key, path, meterData(sub, path.length + 2, acc), pointers, edges, validate);
}

function meterData(value: Value, depth: number, acc: Meter): Meter {
  const bumped: Meter = { ...acc, nodes: acc.nodes + 1, depth: Math.max(acc.depth, depth) };
  if (value.t === "arr") {
    return value.v.reduce((inner, item) => meterData(item, depth + 1, inner), bumped);
  }
  if (value.t === "obj") {
    return value.v.reduce((inner, [, member]) => meterData(member, depth + 1, inner), bumped);
  }
  return bumped;
}

// ---- $ref pointers (RFC 6901) ------------------------------------------------------

// null = :not_allowed (non-pointer forms); otherwise the token list.
function refTokens(ref: string): string[] | null {
  if (ref === "#") return [];
  if (!ref.startsWith("#")) return null;
  const rest = ref.slice(1);
  if (!rest.startsWith("/")) return null;
  const tokens = rest.split("/").slice(1);
  const decoded: string[] = [];
  for (const token of tokens) {
    const unescaped = unescapeToken(token);
    if (unescaped === null) return null;
    decoded.push(unescaped);
  }
  return decoded;
}

// ~1 → "/" before ~0 → "~" in ONE left-to-right pass; "~" not followed by 0
// or 1 is not an RFC 6901 escape.
function unescapeToken(token: string): string | null {
  let out = "";
  for (let i = 0; i < token.length; i++) {
    const c = token[i]!;
    if (c === "~") {
      const next = token[i + 1];
      if (next === "0") {
        out += "~";
        i++;
      } else if (next === "1") {
        out += "/";
        i++;
      } else {
        return null;
      }
    } else {
      out += c;
    }
  }
  return out;
}

// ---- application-edge cycle check ---------------------------------------------------

function cycleFree(pointers: Map<string, Value>): boolean {
  return dfs([], new Set(), new Set(), pointers);
}

function dfs(
  path: string[],
  visiting: Set<string>,
  visited: Set<string>,
  pointers: Map<string, Value>,
): boolean {
  const key = pathKey(path);
  if (visiting.has(key)) return false;
  if (visited.has(key)) return true;

  const nextVisiting = new Set(visiting);
  nextVisiting.add(key);

  for (const child of children(path, pointers)) {
    if (!dfs(child, nextVisiting, visited, pointers)) return false;
  }
  visited.add(key);
  return true;
}

function children(path: string[], pointers: Map<string, Value>): string[][] {
  const term = pointers.get(pathKey(path));
  if (term === undefined || term.t !== "obj") return [];
  const out: string[][] = [];
  for (const [name, value] of term.v) {
    if (name === "properties" && value.t === "obj") {
      for (const [propertyName] of value.v) out.push([...path, "properties", propertyName]);
    } else if (name === "items") {
      out.push([...path, "items"]);
    } else if (name === "additionalProperties") {
      out.push([...path, "additionalProperties"]);
    } else if (name === "oneOf" && value.t === "arr") {
      value.v.forEach((_, i) => out.push([...path, "oneOf", String(i)]));
    } else if (name === "$ref" && value.t === "str") {
      const tokens = refTokens(value.v);
      if (tokens !== null) out.push(tokens);
    }
  }
  return out;
}

// ---- evaluation (memoized on schema term + instance location) ------------------------

type EvalResult = { ok: true } | { ok: false; e: string };

function evaluate(
  schema: Value,
  instance: Value,
  loc: string[],
  memo: Map<Value, Map<string, EvalResult>>,
  pointers: Map<string, Value>,
): EvalResult {
  if (schema.t === "bool") {
    return schema.v ? ok(undefined) : err("invalid_type");
  }

  const locKey = JSON.stringify(loc);
  const byLoc = memo.get(schema);
  if (byLoc !== undefined) {
    const cached = byLoc.get(locKey);
    if (cached !== undefined) return cached;
  }

  const result = evalKeywords(schema, instance, loc, memo, pointers);
  if (!byLoc) memo.set(schema, new Map());
  memo.get(schema)!.set(locKey, result);
  return result;
}

function evalKeywords(
  schema: Value & { t: "obj" },
  instance: Value,
  loc: string[],
  memo: Map<Value, Map<string, EvalResult>>,
  pointers: Map<string, Value>,
): EvalResult {
  for (const keyword of KEYWORD_ORDER) {
    const value = fetch(schema, keyword);
    if (value === null) continue;
    const result = evalKeyword(keyword, schema, value, instance, loc, memo, pointers);
    if (!result.ok) return result;
  }
  return ok(undefined);
}

function fetch(schema: Value & { t: "obj" }, key: string): Value | null {
  const found = schema.v.find(([name]) => name === key);
  return found ? found[1] : null;
}

function evalKeyword(
  keyword: string,
  schema: Value & { t: "obj" },
  value: Value,
  instance: Value,
  loc: string[],
  memo: Map<Value, Map<string, EvalResult>>,
  pointers: Map<string, Value>,
): EvalResult {
  switch (keyword) {
    case "$ref": {
      const tokens = refTokens((value as { t: "str"; v: string }).v)!;
      const target = pointers.get(pathKey(tokens))!;
      return evaluate(target, instance, loc, memo, pointers);
    }
    case "type": {
      const names = typeNames(value);
      return names.some((n) => typeMatches(n, instance)) ? ok(undefined) : err("invalid_type");
    }
    case "enum": {
      const elements = (value as { t: "arr"; v: Value[] }).v;
      return elements.some((e) => equal(e, instance)) ? ok(undefined) : err("invalid_constraint");
    }
    case "const":
      return equal(value, instance) ? ok(undefined) : err("invalid_constraint");
    case "minimum":
    case "maximum": {
      if (instance.t !== "int" && instance.t !== "float") return ok(undefined);
      const limit = value.v;
      const pass = keyword === "minimum" ? instance.v >= limit : instance.v <= limit;
      return pass ? ok(undefined) : err("invalid_constraint");
    }
    case "minLength":
    case "maxLength": {
      if (instance.t !== "str") return ok(undefined);
      const limit = zeroFraction(value);
      const length = countCodepoints(instance.v);
      const pass = keyword === "minLength" ? length >= limit : length <= limit;
      return pass ? ok(undefined) : err("invalid_constraint");
    }
    case "minItems":
    case "maxItems": {
      if (instance.t !== "arr") return ok(undefined);
      const limit = zeroFraction(value);
      const pass = keyword === "minItems" ? instance.v.length >= limit : instance.v.length <= limit;
      return pass ? ok(undefined) : err("invalid_cardinality");
    }
    case "required": {
      if (instance.t !== "obj") return ok(undefined);
      const names = (value as { t: "arr"; v: Value[] }).v.map(
        (x) => (x as { t: "str"; v: string }).v,
      );
      const all = names.every((n) => instance.v.some(([name]) => name === n));
      return all ? ok(undefined) : err("invalid_cardinality");
    }
    case "properties": {
      if (instance.t !== "obj") return ok(undefined);
      return evalPresentProperties(
        (value as { t: "obj"; v: [string, Value][] }).v,
        instance.v,
        loc,
        memo,
        pointers,
      );
    }
    case "items": {
      if (instance.t !== "arr") return ok(undefined);
      return evalItems(instance.v, 0, value, loc, memo, pointers);
    }
    case "additionalProperties": {
      if (instance.t !== "obj") return ok(undefined);
      return evalClosure(schema, value, instance.v, loc, memo, pointers);
    }
    case "oneOf": {
      const branches = (value as { t: "arr"; v: Value[] }).v;
      const [passes] = countPasses(branches, instance, loc, memo, pointers, 0);
      return passes === 1 ? ok(undefined) : err("invalid_cardinality");
    }
    default:
      return ok(undefined);
  }
}

// Adjacency (core §10.3.2.3): additionalProperties sees only the sibling
// `properties` member of the SAME schema object; false is the closure itself
// and reports the closure class.
function evalClosure(
  schema: Value & { t: "obj" },
  sub: Value,
  members: [string, Value][],
  loc: string[],
  memo: Map<Value, Map<string, EvalResult>>,
  pointers: Map<string, Value>,
): EvalResult {
  const adjacentMember = fetch(schema, "properties");
  const adjacent =
    adjacentMember !== null && adjacentMember.t === "obj"
      ? adjacentMember.v.map(([name]) => name)
      : [];
  const additional = members.filter(([name]) => !adjacent.includes(name));

  if (sub.t === "bool") {
    if (sub.v) return ok(undefined);
    return additional.length === 0 ? ok(undefined) : err("invalid_cardinality");
  }
  return evalAdditional(additional, sub, loc, memo, pointers);
}

function evalPresentProperties(
  subs: [string, Value][],
  members: [string, Value][],
  loc: string[],
  memo: Map<Value, Map<string, EvalResult>>,
  pointers: Map<string, Value>,
): EvalResult {
  for (const [name, sub] of subs) {
    const found = members.find(([memberName]) => memberName === name);
    if (found === undefined) continue;
    const result = evaluate(sub, found[1], [name, ...loc], memo, pointers);
    if (!result.ok) return result;
  }
  return ok(undefined);
}

function evalItems(
  items: Value[],
  index: number,
  sub: Value,
  loc: string[],
  memo: Map<Value, Map<string, EvalResult>>,
  pointers: Map<string, Value>,
): EvalResult {
  if (index >= items.length) return ok(undefined);
  const result = evaluate(items[index]!, sub, [String(index), ...loc], memo, pointers);
  if (!result.ok) return result;
  return evalItems(items, index + 1, sub, loc, memo, pointers);
}

function evalAdditional(
  additional: [string, Value][],
  sub: Value,
  loc: string[],
  memo: Map<Value, Map<string, EvalResult>>,
  pointers: Map<string, Value>,
): EvalResult {
  for (const [name, value] of additional) {
    const result = evaluate(sub, value, [name, ...loc], memo, pointers);
    if (!result.ok) return result;
  }
  return ok(undefined);
}

function countPasses(
  branches: Value[],
  instance: Value,
  loc: string[],
  memo: Map<Value, Map<string, EvalResult>>,
  pointers: Map<string, Value>,
  count: number,
): [number, Map<Value, Map<string, EvalResult>>] {
  if (branches.length === 0 || count >= 2) return [count, memo];
  const result = evaluate(branches[0]!, instance, loc, memo, pointers);
  const nextCount = result.ok ? count + 1 : count;
  return countPasses(branches.slice(1), instance, loc, memo, pointers, nextCount);
}

function typeNames(value: Value): string[] {
  if (value.t === "str") return [value.v];
  return value.v.map((x) => (x as { t: "str"; v: string }).v);
}

function typeMatches(name: string, instance: Value): boolean {
  switch (name) {
    case "null":
      return instance.t === "null";
    case "boolean":
      return instance.t === "bool";
    case "object":
      return instance.t === "obj";
    case "array":
      return instance.t === "arr";
    case "string":
      return instance.t === "str";
    case "number":
      return instance.t === "int" || instance.t === "float";
    case "integer":
      return instance.t === "int" || (instance.t === "float" && instance.v === Math.trunc(instance.v));
    default:
      return false;
  }
}

// RFC 8259 characters = codepoints (never graphemes, never UTF-16 units).
function countCodepoints(s: string): number {
  let count = 0;
  for (const _ of s) count++;
  return count;
}

function zeroFraction(value: Value): number {
  return value.t === "int" ? value.v : Math.trunc(value.v);
}
