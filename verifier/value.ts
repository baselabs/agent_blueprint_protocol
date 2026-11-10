// The closed tagged value algebra — the mirror of AgentBlueprintProtocol.Json's
// value() union. Objects are pair-arrays so member order, "__proto__" keys, and
// integer-like keys keep byte-level semantics (no JS object coercion anywhere).
//
// Errors are value-free strings in the runner's projected form ("duplicate_member",
// "ceiling:depth", …) — the same vocabulary the Elixir side projects for comparison.

export type Value =
  | { t: "null" }
  | { t: "bool"; v: boolean }
  | { t: "int"; v: number }
  | { t: "float"; v: number }
  | { t: "str"; v: string }
  | { t: "arr"; v: Value[] }
  | { t: "obj"; v: [string, Value][] };

export type Result<T> = { ok: true; v: T } | { ok: false; e: string };

export const ok = <T>(v: T): Result<T> => ({ ok: true, v });
export const err = (e: string): Result<never> => ({ ok: false, e });

export const nil: Value = { t: "null" };
export const bool = (v: boolean): Value => ({ t: "bool", v });
export const int = (v: number): Value => ({ t: "int", v });
export const float = (v: number): Value => ({ t: "float", v });
export const str = (v: string): Value => ({ t: "str", v });
export const arr = (v: Value[]): Value => ({ t: "arr", v });
export const obj = (v: [string, Value][]): Value => ({ t: "obj", v });

// The I-JSON / RFC 8785 §3.1 magnitude bound mirrored from the decoder.
export const IJSON_MAX = 9_007_199_254_740_991;

// Deep equality over the tagged algebra. Numbers compare numerically
// (int 2 equals float 2.0 — Elixir's `==` semantics, which the runner's
// expectation comparison relies on); ±0 are equal.
// Host-built tagged values are bounded before recursive projections or comparisons.
export function isValue(value: unknown): value is Value {
  return isValueAt(value, 0);
}

function isValueAt(value: unknown, depth: number): value is Value {
  if (value === null || typeof value !== "object" || depth > 64) return false;
  const v = value as Value;
  switch (v.t) {
    case "null": return true;
    case "bool": return typeof v.v === "boolean";
    case "int": return Number.isSafeInteger(v.v);
    case "float": return typeof v.v === "number" && Number.isFinite(v.v);
    case "str": return typeof v.v === "string" && Buffer.from(v.v).toString("utf8") === v.v;
    case "arr":
      if (!Array.isArray(v.v)) return false;
      for (const item of v.v) if (!isValueAt(item, depth + 1)) return false;
      return true;
    case "obj": {
      if (!Array.isArray(v.v)) return false;
      const seen = new Set<string>();
      for (const pair of v.v) {
        if (!Array.isArray(pair) || pair.length !== 2 || typeof pair[0] !== "string" ||
            Buffer.from(pair[0]).toString("utf8") !== pair[0] || seen.has(pair[0])) return false;
        seen.add(pair[0]);
        if (!isValueAt(pair[1], depth + 1)) return false;
      }
      return true;
    }
    default: return false;
  }
}

export function sameValue(a: Value, b: Value): boolean {
  return isValue(a) && isValue(b) && sameValueAt(a, b);
}

function sameValueAt(a: Value, b: Value): boolean {
  if (a.t !== b.t) {
    if ((a.t === "int" || a.t === "float") && (b.t === "int" || b.t === "float")) {
      return a.v === b.v;
    }
    return false;
  }
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
        a.v.length === (b as typeof a).v.length && a.v.every((x, i) => sameValueAt(x, (b as typeof a).v[i]!))
      );
    case "obj":
      return (
        a.v.length === (b as typeof a).v.length &&
        a.v.every((pair, i) => {
          const other = (b as typeof a).v[i]!;
          return pair[0] === other[0] && sameValueAt(pair[1]!, other[1]!);
        })
      );
  }
}

// The plain JS projection (runner expectations, corpus data files).
export type Plain = null | boolean | number | string | Plain[] | { [k: string]: Plain };

export function toPlain(v: Value): Plain | { ok: false; e: string } {
  return isValue(v) ? toPlainAt(v) : { ok: false, e: "invalid_type" };
}

function toPlainAt(v: Value): Plain {
  switch (v.t) {
    case "null":
      return null;
    case "bool":
    case "int":
    case "float":
    case "str":
      return v.v;
    case "arr":
      return v.v.map(toPlainAt);
    case "obj":
      // Null prototype: "__proto__" and friends stay plain members.
      const out: { [k: string]: Plain } = Object.create(null);
      for (const [k, member] of v.v) out[k] = toPlainAt(member);
      return out;
  }
}

export function fromPlain(p: Plain): Value | { ok: false; e: string } {
  const result = fromPlainAt(p, 0);
  return result.ok ? result.v : result;
}

function fromPlainAt(p: unknown, depth: number): Result<Value> {
  if (depth > 64) return err("invalid_type");
  if (p === null) return ok(nil);
  if (typeof p === "boolean") return ok(bool(p));
  if (typeof p === "number") return Number.isFinite(p) && (!Number.isInteger(p) || Number.isSafeInteger(p))
    ? ok(Number.isInteger(p) ? int(p) : float(p)) : err("invalid_type");
  if (typeof p === "string") return Buffer.from(p).toString("utf8") === p ? ok(str(p)) : err("invalid_type");
  if (Array.isArray(p)) {
    const items: Value[] = [];
    for (const item of p) {
      const result = fromPlainAt(item, depth + 1);
      if (!result.ok) return result;
      items.push(result.v);
    }
    return ok(arr(items));
  }
  if (typeof p !== "object" || (Object.getPrototypeOf(p) !== null && Object.getPrototypeOf(p) !== Object.prototype)) return err("invalid_type");
  const members: [string, Value][] = [];
  for (const [key, member] of Object.entries(p)) {
    if (Buffer.from(key).toString("utf8") !== key) return err("invalid_type");
    const result = fromPlainAt(member, depth + 1);
    if (!result.ok) return result;
    members.push([key, result.v]);
  }
  return ok(obj(members));
}
