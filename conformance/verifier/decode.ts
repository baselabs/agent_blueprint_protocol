// Bounded JSON scanner — the mirror of AgentBlueprintProtocol.Json over
// Erlang's :json decoder. Own scanner (JSON.parse keeps LAST duplicate, the
// proven divergence the design names), every ceiling enforced, duplicate members
// rejected, the integer window admitted through the one ES6 oracle.
//
// Check ORDER mirrors the twin exactly (corpus expectations pin precedence):
//   bytes ceiling → parse (structure) → per-member/element guards
//   (members/key/items/nodes) → sink (number resolution then string size) →
//   duplicate rejection at container close → trailing bytes at root.
// A STRUCTURAL parse failure classifies by whole-input UTF-8 validity (the
// twin's classify_parse_error): invalid_encoding when any byte is bad, else
// invalid_syntax. Ceiling/code failures carry their own reason verbatim —
// the twin throws those from inside :json's hooks with the reason attached.

import type { Bounds } from "./bounds.ts";
import { maximum } from "./bounds.ts";
import { number } from "./canonical.ts";
import type { Value } from "./value.ts";
import { err, ok } from "./value.ts";

// Thrown for ceiling/code denials — reason rides the exception.
export class CodeFail extends Error {
  readonly code: string;
  constructor(code: string) {
    super(code);
    this.code = code;
  }
}

// Thrown for structural parse failures — classified by input validity.
export class SyntaxFail extends Error {}

export function decode(
  input: Buffer | string,
  bounds?: Bounds,
): { ok: true; v: Value } | { ok: false; e: string } {
  if (typeof input !== "string" && !Buffer.isBuffer(input)) return err("invalid_type");

  const bytes = typeof input === "string" ? Buffer.from(input, "utf8") : input;
  const profile = bounds ?? maximum();

  if (bytes.length > profile.bytes) return err("ceiling:bytes");

  const validUtf8 = isUtf8(bytes);
  const s = new Scanner(bytes, profile);

  try {
    const value = s.parseRoot();
    return ok(value);
  } catch (e) {
    if (e instanceof CodeFail) return err(e.code);
    if (e instanceof SyntaxFail) return err(validUtf8 ? "invalid_syntax" : "invalid_encoding");
    throw e;
  }
}

const WS = new Set([0x20, 0x09, 0x0a, 0x0d]);

class Scanner {
  pos = 0;
  nodes = 0;
  depth = 0;
  private readonly b: Buffer;
  private readonly bounds: Bounds;

  constructor(b: Buffer, bounds: Bounds) {
    this.b = b;
    this.bounds = bounds;
  }

  private eof(): boolean {
    return this.pos >= this.b.length;
  }

  private peek(): number {
    return this.b[this.pos]!;
  }

  private skipWs(): void {
    while (!this.eof() && WS.has(this.peek())) this.pos++;
  }

  parseRoot(): Value {
    this.skipWs();
    if (this.eof()) throw new SyntaxFail();
    const value = this.parseValue();
    this.skipWs();
    if (!this.eof()) throw new SyntaxFail(); // trailing bytes
    this.bumpNodes();
    return this.sink(value);
  }

  private parseValue(): Value {
    if (this.eof()) throw new SyntaxFail();
    const c = this.peek();
    if (c === 0x7b) return this.parseObject();
    if (c === 0x5b) return this.parseArray();
    if (c === 0x22) return { t: "str", v: this.parseString() };
    if (c === 0x74) return this.parseLiteral("true", { t: "bool", v: true });
    if (c === 0x66) return this.parseLiteral("false", { t: "bool", v: false });
    if (c === 0x6e) return this.parseLiteral("null", { t: "null" });
    if (c === 0x2d || (c >= 0x30 && c <= 0x39)) return this.parseNumber();
    throw new SyntaxFail();
  }

  private parseLiteral(word: string, value: Value): Value {
    for (let i = 0; i < word.length; i++) {
      if (this.eof() || this.peek() !== word.charCodeAt(i)) throw new SyntaxFail();
      this.pos++;
    }
    return value;
  }

  // Containers guard depth at ENTRY (live depth, root container = 1).
  private parseArray(): Value {
    this.enter();
    this.pos++; // '['
    const items: Value[] = [];
    this.skipWs();
    if (!this.eof() && this.peek() === 0x5d) {
      this.pos++;
      this.leave();
      return { t: "arr", v: items };
    }
    for (;;) {
      this.skipWs();
      const element = this.parseValue();
      this.guard(items.length + 1, this.bounds.items, "items");
      this.bumpNodes();
      items.push(this.sink(element));
      this.skipWs();
      if (this.eof()) throw new SyntaxFail();
      if (this.peek() === 0x2c) {
        this.pos++;
        continue;
      }
      if (this.peek() === 0x5d) {
        this.pos++;
        this.leave();
        return { t: "arr", v: items };
      }
      throw new SyntaxFail();
    }
  }

  private parseObject(): Value {
    this.enter();
    this.pos++; // '{'
    const members: [string, Value][] = [];
    this.skipWs();
    if (!this.eof() && this.peek() === 0x7d) {
      this.pos++;
      this.leave();
      return { t: "obj", v: members };
    }
    for (;;) {
      this.skipWs();
      if (this.eof() || this.peek() !== 0x22) throw new SyntaxFail();
      const key = this.parseString();
      this.skipWs();
      if (this.eof() || this.peek() !== 0x3a) throw new SyntaxFail();
      this.pos++;
      this.skipWs();
      const value = this.parseValue();
      this.guard(members.length + 1, this.bounds.members, "members");
      if (Buffer.byteLength(key, "utf8") > this.bounds.key) {
        throw new CodeFail("ceiling:key");
      }
      this.bumpNodes();
      members.push([key, this.sink(value)]);
      this.skipWs();
      if (this.eof()) throw new SyntaxFail();
      if (this.peek() === 0x2c) {
        this.pos++;
        continue;
      }
      if (this.peek() === 0x7d) {
        this.pos++;
        this.leave();
        this.rejectDuplicates(members);
        return { t: "obj", v: members };
      }
      throw new SyntaxFail();
    }
  }

  // Strings: escapes per RFC 8259; raw control bytes and unpaired surrogate
  // escapes are parse failures; UTF-8 validity is enforced per byte sequence
  // (the whole-input flag only classifies, as the twin does).
  private parseString(): string {
    this.pos++; // '"'
    let out = "";
    let chunkStart = this.pos;

    const flush = () => {
      if (this.pos > chunkStart) {
        const slice = this.b.subarray(chunkStart, this.pos);
        if (!isUtf8(slice)) throw new SyntaxFail();
        out += slice.toString("utf8");
      }
    };

    for (;;) {
      if (this.eof()) throw new SyntaxFail();
      const c = this.peek();
      if (c === 0x22) {
        flush();
        this.pos++;
        return out;
      }
      if (c === 0x5c) {
        flush();
        this.pos++;
        if (this.eof()) throw new SyntaxFail();
        const e = this.peek();
        this.pos++;
        switch (e) {
          case 0x22: out += '"'; break;
          case 0x5c: out += "\\"; break;
          case 0x2f: out += "/"; break;
          case 0x62: out += "\b"; break;
          case 0x66: out += "\f"; break;
          case 0x6e: out += "\n"; break;
          case 0x72: out += "\r"; break;
          case 0x74: out += "\t"; break;
          case 0x75: {
            const unit = this.hex4();
            if (unit >= 0xd800 && unit <= 0xdbff) {
              if (this.b[this.pos] !== 0x5c || this.b[this.pos + 1] !== 0x75) {
                throw new SyntaxFail();
              }
              this.pos += 2;
              const low = this.hex4();
              if (!(low >= 0xdc00 && low <= 0xdfff)) throw new SyntaxFail();
              out += String.fromCharCode(unit, low);
            } else if (unit >= 0xdc00 && unit <= 0xdfff) {
              throw new SyntaxFail();
            } else {
              out += String.fromCharCode(unit);
            }
            break;
          }
          default:
            throw new SyntaxFail();
        }
        chunkStart = this.pos;
        continue;
      }
      if (c < 0x20) throw new SyntaxFail();
      if (c < 0x80) {
        this.pos++;
        continue;
      }
      const len = utf8Len(c);
      if (len === 0 || this.pos + len > this.b.length) throw new SyntaxFail();
      for (let i = 1; i < len; i++) {
        if ((this.b[this.pos + i]! & 0xc0) !== 0x80) throw new SyntaxFail();
      }
      this.pos += len;
    }
  }

  private hex4(): number {
    let value = 0;
    for (let i = 0; i < 4; i++) {
      if (this.eof()) throw new SyntaxFail();
      const c = this.peek();
      this.pos++;
      const digit = hexValue(c);
      if (digit < 0) throw new SyntaxFail();
      value = value * 16 + digit;
    }
    return value;
  }

  // Numbers: RFC 8259 grammar; the lexeme is carried raw for the sink.
  private parseNumber(): RawNumber {
    const start = this.pos;
    if (this.peek() === 0x2d) this.pos++;
    if (this.eof()) throw new SyntaxFail();
    if (this.peek() === 0x30) {
      this.pos++;
      if (!this.eof() && this.peek() >= 0x30 && this.peek() <= 0x39) throw new SyntaxFail();
    } else if (this.peek() >= 0x31 && this.peek() <= 0x39) {
      while (!this.eof() && this.peek() >= 0x30 && this.peek() <= 0x39) this.pos++;
    } else {
      throw new SyntaxFail();
    }
    let isFloat = false;
    if (!this.eof() && this.peek() === 0x2e) {
      isFloat = true;
      this.pos++;
      if (this.eof() || this.peek() < 0x30 || this.peek() > 0x39) throw new SyntaxFail();
      while (!this.eof() && this.peek() >= 0x30 && this.peek() <= 0x39) this.pos++;
    }
    if (!this.eof() && (this.peek() === 0x65 || this.peek() === 0x45)) {
      isFloat = true;
      this.pos++;
      if (!this.eof() && (this.peek() === 0x2b || this.peek() === 0x2d)) this.pos++;
      if (this.eof() || this.peek() < 0x30 || this.peek() > 0x39) throw new SyntaxFail();
      while (!this.eof() && this.peek() >= 0x30 && this.peek() <= 0x39) this.pos++;
    }
    return { raw: "number", lexeme: this.b.toString("utf8", start, this.pos), isFloat };
  }

  // The sink: number resolution then string-size bounding, exactly at the
  // point a value settles into its container (or the root).
  private sink(value: Value | RawNumber): Value {
    if (isRawNumber(value)) {
      const lexeme = value.lexeme;
      if (Buffer.byteLength(lexeme, "utf8") > this.bounds.number_lexeme) {
        throw new CodeFail("ceiling:number_lexeme");
      }
      if (value.isFloat) {
        const parsed = Number(lexeme);
        if (!Number.isFinite(parsed)) throw new CodeFail("invalid_number");
        return { t: "float", v: parsed };
      }
      if (beyondIjsonMax(lexeme)) {
        // Integer window: admit iff the correctly-rounded double's own
        // canonical ES6 form IS the lexeme (mis-round reference:
        // 73639773945516200000 = bits 440FEFA841F21479; Number(lexeme) is
        // the correctly-rounded parse, Float.parse's equivalent).
        const parsed = Number(lexeme);
        if (number(parsed) !== lexeme) {
          throw new CodeFail("number_not_double_expressible");
        }
        return { t: "float", v: parsed };
      }
      return { t: "int", v: normalizeZero(Number(lexeme)) };
    }
    if (value.t === "str" && Buffer.byteLength(value.v, "utf8") > this.bounds.string) {
      throw new CodeFail("ceiling:string");
    }
    return value;
  }

  private rejectDuplicates(members: [string, Value][]): void {
    const seen = new Set<string>();
    for (const [key] of members) {
      if (seen.has(key)) throw new CodeFail("duplicate_member");
      seen.add(key);
    }
  }

  private enter(): void {
    this.depth++;
    if (this.depth > this.bounds.depth) throw new CodeFail("ceiling:depth");
  }
  private leave(): void {
    this.depth--;
  }

  private guard(observed: number, ceiling: number, name: string): void {
    if (observed > ceiling) throw new CodeFail("ceiling:" + name);
  }

  private bumpNodes(): void {
    this.nodes++;
    if (this.nodes > this.bounds.nodes) throw new CodeFail("ceiling:nodes");
  }
}

// The internal number token: a lexeme pending sink validation. Never escapes
// the scanner (parseValue returns it only into container push paths, and the
// root sink resolves it before returning).
interface RawNumber {
  raw: "number";
  lexeme: string;
  isFloat: boolean;
}

function isRawNumber(v: Value | RawNumber): v is RawNumber {
  return (v as RawNumber).raw === "number";
}

// ---- helpers ---------------------------------------------------------------------

function normalizeZero(v: number): number {
  return v === 0 ? 0 : v;
}

function beyondIjsonMax(lexeme: string): boolean {
  const abs = lexeme.startsWith("-") ? lexeme.slice(1) : lexeme;
  if (abs.length !== 16) return abs.length > 16;
  return abs > "9007199254740991";
}

function hexValue(c: number): number {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  return -1;
}

function utf8Len(firstByte: number): number {
  if ((firstByte & 0xe0) === 0xc0) return 2;
  if ((firstByte & 0xf0) === 0xe0) return 3;
  if ((firstByte & 0xf8) === 0xf0) return 4;
  return 0;
}

// Strict UTF-8 validation: rejects overlong forms, surrogates, > U+10FFFF.
export function isUtf8(bytes: Buffer): boolean {
  let i = 0;
  while (i < bytes.length) {
    const c = bytes[i]!;
    if (c < 0x80) {
      i++;
      continue;
    }
    const len = utf8Len(c);
    if (len === 0 || i + len > bytes.length) return false;
    for (let j = 1; j < len; j++) {
      if ((bytes[i + j]! & 0xc0) !== 0x80) return false;
    }
    if (len === 2 && c < 0xc2) return false;
    if (len === 3 && c === 0xe0 && bytes[i + 1]! < 0xa0) return false;
    if (len === 3 && c === 0xed && bytes[i + 1]! >= 0xa0) return false;
    if (len === 4 && c === 0xf0 && bytes[i + 1]! < 0x90) return false;
    if (len === 4 && c === 0xf4 && bytes[i + 1]! >= 0x90) return false;
    if (len === 4 && c > 0xf4) return false;
    i += len;
  }
  return true;
}
