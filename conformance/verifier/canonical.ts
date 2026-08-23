// RFC 8785 JCS encoder — the mirror of AgentBlueprintProtocol.Canonicalization.
//
// The ES6 number oracle lives HERE and only here: canonical
// number emission and the decoder's window admission share one decision, the
// same single-serializer rule the Elixir side enforces by having Json consume
// Canonicalization.number/1. Digits delegate to JSON.stringify (ECMA-262
// §7.1.12.1 IS the native behavior); structure, sorting, and escaping are
// hand-rolled so the corpus exercises this implementation, not V8's wholesale.
//
// Member sort: plain JS string comparison — `<` on strings is UTF-16 code-unit
// lexicographic, exactly RFC 8785 §3.2.3 (U+10000 sorts before U+FF3A).
//
// The decode ↔ canonical import cycle (verify needs decode; decode's window
// rule needs the number oracle) is a node-ESM circular import over hoisted
// function declarations — resolved at call time, never at module init.

import type { Bounds } from "./bounds.ts";
import { maximum } from "./bounds.ts";
import { decode } from "./decode.ts";
import type { Value } from "./value.ts";
import { err, ok, IJSON_MAX } from "./value.ts";

const SHORT_ESCAPES: Record<number, string> = {
  0x08: "b",
  0x09: "t",
  0x0a: "n",
  0x0c: "f",
  0x0d: "r",
};

export function encode(
  value: Value,
  bounds?: Bounds,
): { ok: true; v: string } | { ok: false; e: string } {
  const profile = bounds ?? maximum();
  const parts: string[] = [];
  const walked = walk(value, parts);
  if (!walked.ok) return walked;
  const out = parts.join("");
  if (Buffer.byteLength(out, "utf8") > profile.bytes) return err("ceiling:bytes");
  return ok(out);
}

export function verify(
  input: Buffer | string,
  bounds?: Bounds,
): { ok: true; v: Value } | { ok: false; e: string } {
  const decoded = decode(input, bounds);
  if (!decoded.ok) return decoded;
  const reEncoded = encode(decoded.v, bounds);
  if (!reEncoded.ok) return reEncoded;
  const original = typeof input === "string" ? input : input.toString("utf8");
  if (reEncoded.v === original) return ok(decoded.v);
  return err("non_canonical_bytes");
}

// ---- the ES6 number oracle ------------------------------------------------------

export function number(f: number): string {
  if (!Number.isFinite(f)) throw new Error("canonical.number: non-finite float");
  if (f === 0) return "0";
  if (f < 0) return "-" + number(-f);
  return JSON.stringify(f);
}

// ---- encode walk ----------------------------------------------------------------

function walk(value: Value, out: string[]): { ok: true } | { ok: false; e: string } {
  switch (value.t) {
    case "null":
      out.push("null");
      return ok(undefined);
    case "bool":
      out.push(value.v ? "true" : "false");
      return ok(undefined);
    case "int":
      if (!Number.isSafeInteger(value.v) || Math.abs(value.v) > IJSON_MAX) {
        return err("integer_magnitude");
      }
      out.push(String(value.v));
      return ok(undefined);
    case "float":
      out.push(number(value.v));
      return ok(undefined);
    case "str": {
      const escaped = escapeString(value.v);
      if (!escaped.ok) return escaped;
      out.push('"' + escaped.v + '"');
      return ok(undefined);
    }
    case "arr": {
      out.push("[");
      for (let i = 0; i < value.v.length; i++) {
        if (i > 0) out.push(",");
        const element = walk(value.v[i]!, out);
        if (!element.ok) return element;
      }
      out.push("]");
      return ok(undefined);
    }
    case "obj": {
      for (const [name] of value.v) {
        if (!validString(name)) return err("invalid_encoding");
      }
      const sorted = [...value.v].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
      for (let i = 1; i < sorted.length; i++) {
        if (sorted[i - 1]![0] === sorted[i]![0]) return err("duplicate_member");
      }
      out.push("{");
      for (let i = 0; i < sorted.length; i++) {
        if (i > 0) out.push(",");
        const key = escapeString(sorted[i]![0]);
        if (!key.ok) return key;
        out.push('"' + key.v + '":');
        const member = walk(sorted[i]![1], out);
        if (!member.ok) return member;
      }
      out.push("}");
      return ok(undefined);
    }
  }
}

function escapeString(s: string): { ok: true; v: string } | { ok: false; e: string } {
  if (!validString(s)) return err("invalid_encoding");
  let out = "";
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c === 0x22) out += '\\"';
    else if (c === 0x5c) out += "\\\\";
    else if (SHORT_ESCAPES[c] !== undefined) out += "\\" + SHORT_ESCAPES[c];
    else if (c < 0x20) out += "\\u" + c.toString(16).padStart(4, "0");
    else out += s[i];
  }
  return ok(out);
}

// Valid for canonical emission: no lone surrogates. JS strings built by the
// scanner are already UTF-8-validated; this is the fail-closed guard for
// directly-constructed values (the Elixir twin's String.valid? check).
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
