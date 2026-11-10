// Two base64url decoders, mirroring the substrate's split (design note Q3b):
//
// - decodeStrict: the package codec's exact matrix (AgentBlueprintProtocol.Base64Url) —
//   `=` anywhere → `base64url_padded`; non-alphabet → `base64url_invalid`;
//   a spelling that is not the byte-exact encoding of its own decoded bytes
//   (impossible lengths, non-zero pad bits) → `base64url_invalid`.
//
// - decodeLenient: stdlib `Base.url_decode64/2` parity for the RUNNER's
//   internal sites (corpus input bytes, keys, byte-fallback, tamper targets):
//   accepts trailing padding and non-zero pad bits, rejects non-alphabet
//   characters. NEVER `Buffer.from(s, "base64url")`, which silently skips
//   invalid characters.

const ALPHABET = /^[A-Za-z0-9_-]*$/;

export function encode(data: Buffer): string;
export function encode(data: unknown): string | { ok: false; e: string };
export function encode(data: unknown): string | { ok: false; e: string } {
  if (!Buffer.isBuffer(data)) return { ok: false, e: "invalid_type" };
  return data.toString("base64url");
}

export type StrictErr = "base64url_padded" | "base64url_invalid" | "invalid_type";

export function decodeStrict(input: string): { ok: true; v: Buffer } | { ok: false; e: StrictErr } {
  if (typeof input !== "string") return { ok: false, e: "invalid_type" };
  if (input.includes("=")) return { ok: false, e: "base64url_padded" };
  if (!ALPHABET.test(input)) return { ok: false, e: "base64url_invalid" };
  if (input.length % 4 === 1) return { ok: false, e: "base64url_invalid" };
  const decoded = Buffer.from(input, "base64url");
  if (encode(decoded) !== input) return { ok: false, e: "base64url_invalid" };
  return { ok: true, v: decoded };
}

const LENIENT = /^[A-Za-z0-9_-]+={0,2}$/;

export function decodeLenient(input: string): { ok: true; v: Buffer } | { ok: false; e: "lenient_invalid" | "invalid_type" } {
  if (typeof input !== "string") return { ok: false, e: "invalid_type" };
  if (!LENIENT.test(input)) return { ok: false, e: "lenient_invalid" };
  if (input.length % 4 === 1) return { ok: false, e: "lenient_invalid" };
  return { ok: true, v: Buffer.from(input, "base64url") };
}
