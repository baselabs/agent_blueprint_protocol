// Detached JWS verification — the mirror of AgentBlueprintProtocol.Signature:
// RFC 7515 compact + RFC 7797 b64=false unencoded detached payload, Ed25519
// via node:crypto (one-shot verify arg order on node ≥ 24 is
// (algorithm, data, key, signature) — probed on v25.9.0), and the
// small-order / off-curve public-key rejection the twin added after the
// found live (:crypto AND OpenSSL both accept small-order keys
// with all-zero signatures — a universal forgery), and the strict
// signature rule (R canonical and not small-order, S < L) checked before
// node:crypto, so the verdict never depends on the runtime's backend.
//
// Attestations (verify_attestation) are not mirrored: no corpus surface
// dispatches them and the kind registry is empty by design.

import { createPublicKey, verify as cryptoVerify, type KeyObject } from "node:crypto";
import * as b64 from "./b64url.ts";
import { encode } from "./canonical.ts";
import * as digest from "./digest.ts";
import type { Value } from "./value.ts";
import { member, memberString } from "./corpus.ts";

const PURPOSES = new Set(["blueprint", "deployment", "federation-envelope"]);
const CREATED_AT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;

export interface PublicKey {
  keyId: string;
  key: Buffer; // raw 32-byte Ed25519 encoding
}

type VerifyResult = { ok: true; v: "verified" } | { ok: false; e: string };

function malformed(): { ok: false; e: string } {
  return { ok: false, e: "signature_malformed" };
}

export function verify(entry: Value, keys: PublicKey[]): VerifyResult {
  const parts = parseParts(entry);
  if (!parts.ok) return parts;
  const input = parts.v.headerB64 + "." + parts.v.payload;
  return check(input, parts.v.signature, parts.v.keyId, keys);
}

export function signingInput(entry: Value): { ok: true; v: string } | VerifyResult {
  const parts = parseParts(entry);
  if (!parts.ok) return parts;
  return { ok: true, v: parts.v.headerB64 + "." + parts.v.payload };
}

// RFC 7515 detached compact: BASE64URL(JCS(protected)) .. BASE64URL(sig),
// empty payload segment (Appendix F).
export function toCompact(entry: Value): { ok: true; v: string } | VerifyResult {
  const parts = parseParts(entry);
  if (!parts.ok) return parts;
  return { ok: true, v: parts.v.headerB64 + "." + "." + b64.encode(parts.v.signature) };
}

interface Parts {
  headerB64: string;
  payload: string;
  signature: Buffer;
  keyId: string;
}

function parseParts(entry: Value): { ok: true; v: Parts } | { ok: false; e: string } {
  if (entry.t !== "obj") return malformed();
  const names = entry.v.map(([k]) => k).sort();
  if (
    names.length !== 3 ||
    names[0] !== "protected" ||
    names[1] !== "signature" ||
    names[2] !== "signed_attributes"
  ) {
    return malformed();
  }

  const header = member(entry, "protected")!;
  const attrs = member(entry, "signed_attributes")!;

  // Header: exactly {alg, b64, crit, kid}; alg must be EdDSA (the twin's one
  // algorithm-unsupported denial in the header), b64 exactly false, crit
  // exactly ["b64"], kid a non-empty string.
  if (header.t !== "obj") return malformed();
  const headerNames = header.v.map(([k]) => k).sort();
  if (headerNames.length !== 4 || headerNames.join() !== "alg,b64,crit,kid") {
    return malformed();
  }
  const alg = member(header, "alg");
  if (alg !== null && alg.t === "str" && alg.v !== "EdDSA") {
    return { ok: false, e: "signature_algorithm_unsupported" };
  }
  if (alg === null || alg.t !== "str") return malformed();
  const b64Flag = member(header, "b64");
  if (b64Flag === null || b64Flag.t !== "bool" || b64Flag.v !== false) return malformed();
  const crit = member(header, "crit");
  if (
    crit === null ||
    crit.t !== "arr" ||
    crit.v.length !== 1 ||
    crit.v[0]!.t !== "str" ||
    crit.v[0]!.v !== "b64"
  ) {
    return malformed();
  }
  const kid = member(header, "kid");
  if (kid === null || kid.t !== "str" || kid.v === "") return malformed();

  // Attributes: exactly the five closed members.
  if (attrs.t !== "obj") return malformed();
  const attrNames = attrs.v.map(([k]) => k).sort();
  if (
    attrNames.length !== 5 ||
    attrNames.join() !== "algorithm,content_digest,created_at,key_id,purpose"
  ) {
    return malformed();
  }
  const algorithm = member(attrs, "algorithm");
  if (algorithm !== null && algorithm.t === "str" && algorithm.v !== "Ed25519") {
    return { ok: false, e: "signature_algorithm_unsupported" };
  }
  if (algorithm === null || algorithm.t !== "str") return malformed();

  const contentDigest = memberString(attrs, "content_digest");
  if (contentDigest === null || !digest.fromTagged(contentDigest).ok) return malformed();

  const createdAt = memberString(attrs, "created_at");
  if (createdAt === null || !CREATED_AT.test(createdAt) || !validZFormDate(createdAt)) {
    return malformed();
  }

  const keyId = memberString(attrs, "key_id");
  if (keyId === null || keyId === "" || keyId.includes(".")) return malformed();

  const purpose = memberString(attrs, "purpose");
  if (purpose === null || !PURPOSES.has(purpose)) return malformed();

  if (kid.v !== keyId) return malformed();

  const signatureBody = member(entry, "signature");
  if (signatureBody === null || signatureBody.t !== "str") return malformed();
  const decodedSignature = b64.decodeStrict(signatureBody.v);
  if (!decodedSignature.ok || decodedSignature.v.length !== 64) return malformed();

  const headerJson = encode(header);
  const attrsJson = encode(attrs);
  if (!headerJson.ok || !attrsJson.ok) return malformed();

  return {
    ok: true,
    v: {
      headerB64: b64.encode(Buffer.from(headerJson.v, "utf8")),
      payload: attrsJson.v,
      signature: decodedSignature.v,
      keyId,
    },
  };
}

// DateTime.from_iso8601's field validation for the Z whole-second form:
// regex passes still fail on impossible dates (2026-02-31).
function validZFormDate(stamped: string): boolean {
  const year = Number(stamped.slice(0, 4));
  const month = Number(stamped.slice(5, 7));
  const day = Number(stamped.slice(8, 10));
  const hour = Number(stamped.slice(11, 13));
  const minute = Number(stamped.slice(14, 16));
  const second = Number(stamped.slice(17, 19));
  if (month < 1 || month > 12 || day < 1 || hour > 23 || minute > 59 || second > 59) {
    return false;
  }
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day <= lengths[month - 1]!;
}

function check(
  input: string,
  signature: Buffer,
  keyId: string,
  keys: PublicKey[],
): VerifyResult {
  const candidates = keys.filter((key) => key.keyId === keyId);
  if (candidates.length === 0) return { ok: false, e: "signature_key_unsupported" };

  // usableEd25519Key owns the 32-byte length rule (a second length test
  // here would be redundant and could be deleted with no verdict moving).
  const usable = candidates.filter((key) => usableEd25519Key(key.key));
  if (usable.length === 0) return { ok: false, e: "signature_algorithm_unsupported" };

  if (!strictSignature(signature)) return { ok: false, e: "signature_not_verified" };

  const inputBytes = Buffer.from(input, "utf8");
  for (const key of usable) {
    if (cryptoVerify(null, inputBytes, keyObject(key.key), signature)) {
      return { ok: true, v: "verified" };
    }
  }
  return { ok: false, e: "signature_not_verified" };
}

// Parsed KeyObjects are cached per raw key, bounded at
// KEY_OBJECT_CACHE_LIMIT entries: when full, the oldest insertion is
// evicted, so a long-lived process verifying under many keys holds at
// most that many KeyObjects.
export const KEY_OBJECT_CACHE_LIMIT = 256;
const keyObjectCache = new Map<string, KeyObject>();

export function keyObjectCacheSize(): number {
  return keyObjectCache.size;
}

function keyObject(raw: Buffer): KeyObject {
  const x = raw.toString("base64url");
  const cached = keyObjectCache.get(x);
  if (cached !== undefined) return cached;
  const key = createPublicKey({ key: { kty: "OKP", crv: "Ed25519", x }, format: "jwk" });
  if (keyObjectCache.size >= KEY_OBJECT_CACHE_LIMIT) {
    keyObjectCache.delete(keyObjectCache.keys().next().value!);
  }
  keyObjectCache.set(x, key);
  return key;
}

// ---- strict Ed25519: the point rule and the scalar rule (RFC 8032 §5.1) ----------
//
// One point rule (usableEd25519Key) for the public key A and the
// signature's R alike: canonical encoding, on the curve, not small-order.
// The scalar rule: S < L (RFC 8032 5.1.7 step 1). Both run before
// node:crypto, whose own verdict on a small-order R differs by runtime
// (node 22.23.1 accepts R = the identity with S = k*a mod L under an
// honest key; node 24.19.0 rejects it) — mirrors the Elixir twin.

const ED_L = 2n ** 252n + 27742317777372353535851937790883648493n;

export function strictSignature(signature: Buffer): boolean {
  if (signature.length !== 64) return false;
  return leInt(signature.subarray(32)) < ED_L && usableEd25519Key(signature.subarray(0, 32));
}

function leInt(bytes: Buffer): bigint {
  let n = 0n;
  for (let i = bytes.length - 1; i >= 0; i--) n = (n << 8n) | BigInt(bytes[i]!);
  return n;
}

const ED_P = 2n ** 255n - 19n;
const ED_D =
  37095705934669439343138083508754565189542113879843219016388785533085940283555n;
const ED_SQRT_M1 =
  19681161376707505956807079304988542015446066515923890162744021073123829784752n;

// The literals, exposed so the self-check battery can re-derive each one
// from the curve definition (d = -121665/121666, sqrt(-1) = 2^((p-1)/4),
// L = 2^252 + c) and assert equality — a mistyped digit reds there.
export const ED25519_CONSTANTS = { p: ED_P, d: ED_D, sqrtM1: ED_SQRT_M1, l: ED_L } as const;

function modPow(base: bigint, exponent: bigint): bigint {
  let result = 1n;
  let b = base % ED_P;
  let e = exponent;
  while (e > 0n) {
    if (e & 1n) result = (result * b) % ED_P;
    b = (b * b) % ED_P;
    e >>= 1n;
  }
  return result;
}

export function usableEd25519Key(encoding: Buffer): boolean {
  if (encoding.length !== 32) return false;
  const yRaw = encoding.readBigUInt64LE(0) | (encoding.readBigUInt64LE(8) << 64n) |
    (encoding.readBigUInt64LE(16) << 128n) | (encoding.readBigUInt64LE(24) << 192n);
  // RFC 8032 5.1.2: bit 255 carries the sign of x; the low 255 bits are y.
  const signX = ((yRaw >> 255n) & 1n) === 1n;
  const y = yRaw & ((1n << 255n) - 1n);

  if (y >= ED_P) return false; // non-canonical y

  const yy = (y * y) % ED_P;
  const denominator = (ED_D * yy + 1n) % ED_P;
  const x2 = ((yy - 1n) * modPow(denominator, ED_P - 2n)) % ED_P;

  // p = 2^255 - 19 is 5 mod 8: sqrt is a^((p+3)/8), corrected by sqrt(-1)
  // when z^2 = -a. (a^((p+1)/4) is INVALID for this p.)
  const z = modPow(x2, (ED_P + 3n) / 8n);

  let root: bigint | null;
  if ((z * z - x2) % ED_P === 0n) root = z;
  else if ((z * z + x2) % ED_P === 0n) root = (z * ED_SQRT_M1) % ED_P;
  else root = null;

  if (root === null) return false; // not on the curve
  // root == 0 happens iff y ∈ {1, p−1} — the identity (order 1) and the
  // order-2 point: non-canonical when sign-set, small-order when sign-clear;
  // both reject (mirrors the Elixir fix found by this mirror's torsion battery).
  if (root === 0n) return false;

  const rootOdd = root % 2n === 1n;
  const x = signX === rootOdd ? root : ED_P - root;
  return !smallOrder(x, y);
}

// x = 0 never reaches this test: it means root == 0, which
// usableEd25519Key already rejected, so an `x === 0n` clause here would be
// unreachable and untestable (mirrors the Elixir twin).
function smallOrder(x: bigint, y: bigint): boolean {
  const ySqrtM1 = (y * ED_SQRT_M1) % ED_P;
  return y === 0n || ySqrtM1 === x || ySqrtM1 === ED_P - x;
}
