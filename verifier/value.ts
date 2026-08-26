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
export function sameValue(a: Value, b: Value): boolean {
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
      return a.v === b.v;
    case "arr":
      return (
        a.v.length === b.v.length && a.v.every((x, i) => sameValue(x, b.v[i]!))
      );
    case "obj":
      return (
        a.v.length === b.v.length &&
        a.v.every((pair, i) => {
          const other = b.v[i]!;
          return pair[0] === other[0] && sameValue(pair[1]!, other[1]!);
        })
      );
  }
}

// The plain JS projection (runner expectations, corpus data files).
export type Plain = null | boolean | number | string | Plain[] | { [k: string]: Plain };

export function toPlain(v: Value): Plain {
  switch (v.t) {
    case "null":
      return null;
    case "bool":
    case "int":
    case "float":
    case "str":
      return v.v;
    case "arr":
      return v.v.map(toPlain);
    case "obj":
      // Null prototype: "__proto__" and friends stay plain members.
      const out: { [k: string]: Plain } = Object.create(null);
      for (const [k, member] of v.v) out[k] = toPlain(member);
      return out;
  }
}

export function fromPlain(p: Plain): Value {
  if (p === null) return nil;
  if (typeof p === "boolean") return bool(p);
  if (typeof p === "number") return Number.isInteger(p) ? int(p) : float(p);
  if (typeof p === "string") return str(p);
  if (Array.isArray(p)) return arr(p.map(fromPlain));
  return obj(
    Object.entries(p).map(([k, member]) => [k, fromPlain(member)] as [string, Value]),
  );
}
