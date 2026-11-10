// Self-check battery — the corpus-independent anchors:
// RFC 8785 Appendix B transcribed first-hand from the RFC (2026-08-23), the
// RFC's §3.2.2→§3.2.4 canonicalization sample, the §3.2.3 sort-order fixture,
// the integer-window matrix (mis-round lexeme included), the b64url strict/
// lenient matrices, and Ed25519 key acceptance. Exit 0 = all pass; exit 1 +
// a list = any failure.
//
// These run inside `verifier.agreement` (a divergence in either
// implementation must surface — RFC table ↔ TS emit ↔ native stringify).

import { number } from "./canonical.ts";
import { decode } from "./decode.ts";
import { encode } from "./canonical.ts";
import * as b64 from "./b64url.ts";
import { member, memberString } from "./corpus.ts";
import type { Value } from "./value.ts";
import {
  verify as sigVerify,
  toCompact,
  signingInput,
  strictSignature,
  usableEd25519Key,
  ED25519_CONSTANTS,
  KEY_OBJECT_CACHE_LIMIT,
  keyObjectCacheSize,
} from "./signature.ts";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { createPrivateKey, createPublicKey, sign as cryptoSign, verify as cryptoVerify } from "node:crypto";

const failures: string[] = [];
let checks = 0;

function check(name: string, got: unknown, want: unknown): void {
  checks++;
  if (got !== want) failures.push(`${name}: got ${String(got)} want ${String(want)}`);
}

// ---- RFC 8785 Appendix B (transcribed from the RFC, verbatim) -------------------

const APPENDIX_B: [string, string | null][] = [
  ["0000000000000000", "0"],
  ["8000000000000000", "0"], // minus zero
  ["0000000000000001", "5e-324"],
  ["8000000000000001", "-5e-324"],
  ["7fefffffffffffff", "1.7976931348623157e+308"],
  ["ffefffffffffffff", "-1.7976931348623157e+308"],
  ["4340000000000000", "9007199254740992"],
  ["c340000000000000", "-9007199254740992"],
  ["4430000000000000", "295147905179352830000"],
  ["7fffffffffffffff", null], // NaN — must error
  ["7ff0000000000000", null], // Infinity — must error
  ["44b52d02c7e14af5", "9.999999999999997e+22"],
  ["44b52d02c7e14af6", "1e+23"],
  ["44b52d02c7e14af7", "1.0000000000000001e+23"],
  ["444b1ae4d6e2ef4e", "999999999999999700000"],
  ["444b1ae4d6e2ef4f", "999999999999999900000"],
  ["444b1ae4d6e2ef50", "1e+21"],
  ["3eb0c6f7a0b5ed8c", "9.999999999999997e-7"],
  ["3eb0c6f7a0b5ed8d", "0.000001"],
  ["41b3de4355555553", "333333333.3333332"],
  ["41b3de4355555554", "333333333.33333325"],
  ["41b3de4355555555", "333333333.3333333"],
  ["41b3de4355555556", "333333333.3333334"],
  ["41b3de4355555557", "333333333.33333343"],
  ["becbf647612f3696", "-0.0000033333333333333333"],
  ["43143ff3c1cb0959", "1424953923781206.2"], // round to even
];

for (const [hex, expected] of APPENDIX_B) {
  const buffer = Buffer.alloc(8);
  buffer.writeBigUInt64BE(BigInt("0x" + hex));
  const value = buffer.readDoubleBE();
  if (expected === null) {
    let errored = false;
    try {
      number(value);
    } catch {
      errored = true;
    }
    check(`appendix-b ${hex} errors`, errored, true);
    continue;
  }
  check(`appendix-b ${hex}`, number(value), expected);
  // Three-way: native stringify must agree with the RFC table too.
  check(`appendix-b ${hex} native`, JSON.stringify(value), expected);
}

// ---- RFC 8785 §3.2.2 → §3.2.4 sample --------------------------------------------

const sampleInput = `{
    "numbers": [333333333.33333329, 1E30, 4.50,
                2e-3, 0.000000000000000000000000001],
    "string": "\\u20ac$\\u000F\\u000aA'\\u0042\\u0022\\u005c\\\\\\"\\/",
    "literals": [null, true, false]
  }`;
const sampleCanonical =
  '{"literals":[null,true,false],"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],' +
  '"string":"€$\\u000f\\nA\'B\\"\\\\\\\\\\"/"}';
const sampleHex =
  "7b226c69746572616c73223a5b6e756c6c2c747275652c66616c73655d2c226e756d62" +
  "657273223a5b3333333333333333332e333333333333332c31652b33302c342e352c" +
  "302e3030322c31652d32375d2c22737472696e67223a22e282ac245c75303030665c6e" +
  "4127425c225c5c5c5c5c222f227d";

const sampleDecoded = decode(sampleInput);
check("§3.2.2 sample decodes", sampleDecoded.ok, true);
if (sampleDecoded.ok) {
  const sampleEncoded = encode(sampleDecoded.v);
  check("§3.2.3 canonical output", sampleEncoded.ok && sampleEncoded.v, sampleCanonical);
  check(
    "§3.2.4 hex bytes",
    sampleEncoded.ok && Buffer.from(sampleEncoded.v, "utf8").toString("hex"),
    sampleHex,
  );
}

// ---- RFC 8785 §3.2.3 sort-order fixture ------------------------------------------

const sortInput = `{
    "\\u20ac": "Euro Sign",
    "\\r": "Carriage Return",
    "\\ufb33": "Hebrew Letter Dalet With Dagesh",
    "1": "One",
    "\\ud83d\\ude00": "Emoji: Grinning Face",
    "\\u0080": "Control",
    "\\u00f6": "Latin Small Letter O With Diaeresis"
  }`;
const expectedOrder = [
  "Carriage Return", // \r
  "One", // 1
  "Control", // U+0080
  "Latin Small Letter O With Diaeresis", // U+00F6
  "Euro Sign", // U+20AC
  "Emoji: Grinning Face", // U+1F600
  "Hebrew Letter Dalet With Dagesh", // U+FB33
];
const sortDecoded = decode(sortInput);
check("§3.2.3 fixture decodes", sortDecoded.ok, true);
if (sortDecoded.ok) {
  // Sorting happens at ENCODE (decode preserves member order) — assert the
  // canonical output's key order: \r < 1 < U+0080 < U+00F6 < U+20AC <
  // U+1F600 < U+FB33 (UTF-16 code units).
  const encoded = encode(sortDecoded.v);
  check("§3.2.3 encode succeeds", encoded.ok, true);
  if (encoded.ok) {
    // Extract values by splitting on '":"' boundaries of the flat object.
    const valuesInOrder: string[] = [];
    const body = encoded.v.slice(1, -1);
    for (const pair of body.split(",")) {
      const value = pair.slice(pair.indexOf('":') + 2);
      valuesInOrder.push(JSON.parse(value));
    }
    check(
      "§3.2.3 order values",
      JSON.stringify(valuesInOrder),
      JSON.stringify(expectedOrder),
    );
  }
}

// ---- integer-window matrix -------------------------------------------------------

// [lexeme, expected] — expected is "ok:<tag>:<number-string>" or the deny code.
const WINDOW: [string, string][] = [
  ["9007199254740992", "ok:float:9007199254740992"],
  ["-9007199254740992", "ok:float:-9007199254740992"],
  ["9007199254740993", "number_not_double_expressible"],
  ["-9007199254740993", "number_not_double_expressible"],
  ["9007199254740994", "ok:float:9007199254740994"],
  ["295147905179352830000", "ok:float:295147905179352830000"],
  ["999999999999999700000", "ok:float:999999999999999700000"],
  ["999999999999999900000", "ok:float:999999999999999900000"],
  ["295147905179352825856", "number_not_double_expressible"],
  ["73639773945516200000", "ok:float:73639773945516200000"], // mis-round bits 440FEFA841F21479
  ["1000000000000000000000", "number_not_double_expressible"], // 1e21: canonical is exponential
  ["18446744073709551616", "number_not_double_expressible"],
  ["1e400", "invalid_number"],
  ["-1e400", "invalid_number"],
  ["1e-400", "ok:float:0"], // underflow admits as 0 (Float.parse parity)
  ["999999999999999999999999999999999999", "number_not_double_expressible"],
];

for (const [lexeme, expected] of WINDOW) {
  const decoded = decode(lexeme);
  let got: string;
  if (!decoded.ok) got = decoded.e;
  else if (decoded.v.t === "float") got = "ok:float:" + number(decoded.v.v);
  else if (decoded.v.t === "int") got = `ok:int:${decoded.v.v}`;
  else got = "ok:other";
  check(`window ${lexeme}`, got, expected);
}

// ---- b64url matrices -------------------------------------------------------------

function strict(input: string): string {
  const decoded = b64.decodeStrict(input);
  return decoded.ok ? "ok:" + decoded.v.toString("latin1") : decoded.e;
}

check("b64 strict valid", strict("QQ"), "ok:A");
check("b64 strict empty", strict(""), "ok:");
check("b64 strict padded", strict("QQ=="), "base64url_padded");
check("b64 strict interior pad", strict("Q=Q"), "base64url_padded");
check("b64 strict bad char", strict("!!!"), "base64url_invalid");
check("b64 strict impossible length", strict("A"), "base64url_invalid");
check("b64 strict nonzero pad bits", strict("Qc"), "base64url_invalid"); // 0x41+0x07 → re-encode differs
check("b64 strict canonical pair", strict("QUJD"), "ok:ABC");

function lenient(input: string): string {
  const decoded = b64.decodeLenient(input);
  return decoded.ok ? "ok:" + decoded.v.toString("latin1") : decoded.e;
}

check("b64 lenient unpadded", lenient("QQ"), "ok:A");
check("b64 lenient padded", lenient("QQ=="), "ok:A"); // stdlib accepts padding
check("b64 lenient bad char", lenient("!!!"), "lenient_invalid");

// ---- Ed25519 key acceptance ---------------------------------------------------------

// Small-order / non-canonical / off-curve encodings — the libsodium
// ge25519_has_small_order list (provider constants) plus the y ∈ {1, p−1}
// pair an independent review found slipping through the twin's root==0 branch.
const UNUSABLE_HEX = [
  "0100000000000000000000000000000000000000000000000000000000000000", // identity (order 1)
  "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f", // order-2 point
  "0000000000000000000000000000000000000000000000000000000000000000", // y = 0
  "0000000000000000000000000000000000000000000000000000000000000080", // y = 0, sign set
  "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05",
  "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85",
  "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a",
  "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa",
  "0100000000000000000000000000000000000000000000000000000000000080", // identity, sign set
  "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", // y ≥ p
  "d7f0980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", // off-curve
];

for (const hex of UNUSABLE_HEX) {
  check(`ed25519 unusable ${hex.slice(0, 8)}…`, usableEd25519Key(Buffer.from(hex, "hex")), false);
}

// The RFC 8032 §7.1 TEST 1 public key — a legitimate main-subgroup point.
check(
  "ed25519 RFC8032 TEST1 pubkey usable",
  usableEd25519Key(Buffer.from("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "hex")),
  true,
);

// ---- Standard-JOSE cross-check: the stored JWS vectors ----------------------------

{
  const vectorsBytes = readFileSync(join(import.meta.dirname, "testdata", "jose-vectors.json"));
  const vectors = decode(vectorsBytes);
  check("jose vectors decode", vectors.ok, true);
  if (!vectors.ok || vectors.v.t !== "obj") {
    check("jose vectors shape", false, true);
  } else {
    const kat = member(vectors.v, "rfc8032_test1")!;
    const seedHex = memberString(kat, "seed_hex")!;
    const pubHex = memberString(kat, "public_key_hex")!;
    const sigHex = memberString(kat, "signature_hex")!;

    // Seed import via PKCS#8 DER wrap; derived public key must equal the
    // RFC's published literal (KAT 1).
    const seed = Buffer.from(seedHex, "hex");
    const der = Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]);
    const privateKey = createPrivateKey({ key: der, format: "der", type: "pkcs8" });
    const derivedJwk = createPublicKey(privateKey).export({ format: "jwk" }) as { x: string };
    check(
      "jose RFC8032 seed derives published pub",
      Buffer.from(derivedJwk.x!, "base64url").toString("hex"),
      pubHex,
    );

    // node's Ed25519 reproduces the RFC's published signature over the
    // empty TEST 1 message (KAT 2), and verifies it.
    const message = Buffer.from(memberString(kat, "message_hex") ?? "", "hex");
    const resigned = cryptoSign(null, message, privateKey);
    check("jose RFC8032 signature reproduced", resigned.toString("hex"), sigHex);
    check(
      "jose RFC8032 verify",
      cryptoVerify(
        null,
        message,
        createPublicKey({ key: { kty: "OKP", crv: "Ed25519", x: derivedJwk.x! }, format: "jwk" }),
        Buffer.from(sigHex, "hex"),
      ),
      true,
    );

    // The stored entries verify through the TS twin, match their compact
    // forms, and reconstruct per RFC 7515 App F with stock crypto.
    const publicKeyB64 = memberString(vectors.v, "public_key")!;
    const stockKey = createPublicKey({
      key: { kty: "OKP", crv: "Ed25519", x: publicKeyB64 },
      format: "jwk",
    });
    const keys = [{ keyId: "test-key", key: Buffer.from(publicKeyB64, "base64url") }];
    const entries = member(vectors.v, "entries")!;
    check("jose entries present", entries.t === "arr" && entries.v.length >= 2, true);
    for (const wrapped of entries.t === "arr" ? entries.v : []) {
      const entry = member(wrapped, "entry")!;
      const compact = memberString(wrapped, "compact")!;
      const purpose = memberString(member(entry, "signed_attributes")!, "purpose");
      const verified = sigVerify(entry, keys);
      const byteArrayResult = sigVerify(entry, keys.map((key) => ({ ...key, key: new Uint8Array(key.key) })));
      check(`jose byte-array key verifies (${purpose})`, byteArrayResult.ok, true);
      check(
        `jose entry verifies (${purpose})`,
        verified.ok && verified.v === "verified",
        true,
      );

      const mine = toCompact(entry);
      check("jose compact matches", mine.ok ? mine.v : "err", compact);

      const input = signingInput(entry);
      check("jose signing input ok", input.ok, true);
      if (input.ok) {
        check(
          "jose standard-reconstruction verify",
          cryptoVerify(null, Buffer.from(input.v, "utf8"), stockKey, Buffer.from(compact.split(".")[2]!, "base64url")),
          true,
        );
      }
    }

    // Tamper tripwire: a flipped signature byte must fail verification.
    const firstEntry = (entries.t === "arr" ? entries.v : [])[0]!;
    const tampered = flipSignatureByte(member(firstEntry, "entry")!);
    const tamperedResult = sigVerify(tampered, keys);
    check(
      "jose tampered signature denied",
      !tamperedResult.ok && tamperedResult.e === "signature_not_verified",
      true,
    );
  }
}

// Independent affine Edwards arithmetic for the checks below
// (complete addition on -x^2 + y^2 = 1 + d x^2 y^2; d derived, not copied).
const ED_P_CHECK = 2n ** 255n - 19n;
function edMod(v: bigint): bigint {
  return ((v % ED_P_CHECK) + ED_P_CHECK) % ED_P_CHECK;
}
function edPow(base: bigint, exponent: bigint): bigint {
  let result = 1n;
  let b = edMod(base);
  let e = exponent;
  while (e > 0n) {
    if (e & 1n) result = (result * b) % ED_P_CHECK;
    b = (b * b) % ED_P_CHECK;
    e >>= 1n;
  }
  return result;
}
function edInv(v: bigint): bigint {
  return edPow(v, ED_P_CHECK - 2n);
}
const ED_D_CHECK = edMod(-121665n * edInv(121666n));
type EdPoint = { x: bigint; y: bigint };
function edAdd(a: EdPoint, b: EdPoint): EdPoint {
  const t = edMod(ED_D_CHECK * a.x * b.x * a.y * b.y);
  return {
    x: edMod((a.x * b.y + a.y * b.x) * edInv(1n + t)),
    y: edMod((a.y * b.y + a.x * b.x) * edInv(1n - t)),
  };
}
function edScalarMult(n: bigint, point: EdPoint): EdPoint {
  let result: EdPoint = { x: 0n, y: 1n };
  let addend = point;
  let k = n;
  while (k > 0n) {
    if (k & 1n) result = edAdd(result, addend);
    addend = edAdd(addend, addend);
    k >>= 1n;
  }
  return result;
}
function edIsNeutral(point: EdPoint): boolean {
  return point.x === 0n && point.y === 1n;
}
function edBasePoint(): EdPoint {
  const y = edMod(4n * edInv(5n));
  const x2 = edMod((y * y - 1n) * edInv(ED_D_CHECK * y * y + 1n));
  let x = edPow(x2, (ED_P_CHECK + 3n) / 8n);
  if (edMod(x * x - x2) !== 0n) x = edMod(x * edPow(2n, (ED_P_CHECK - 1n) / 4n));
  return { x: x % 2n === 0n ? x : ED_P_CHECK - x, y };
}
function edEncode(point: EdPoint): Buffer {
  const out = Buffer.alloc(32);
  let v = point.y | ((point.x & 1n) << 255n);
  for (let i = 0; i < 32; i++) {
    out[i] = Number(v & 0xffn);
    v >>= 8n;
  }
  return out;
}

// ---- Ed25519 curve constants, re-derived from the curve definition ----------------
//
// RFC 8032 5.1: p = 2^255 - 19, d = -121665/121666 mod p, L = 2^252 + c;
// p = 5 mod 8, so 2^((p-1)/4) is a square root of -1.

{
  const p = 2n ** 255n - 19n;
  const powMod = (base: bigint, exponent: bigint): bigint => {
    let result = 1n;
    let b = ((base % p) + p) % p;
    let e = exponent;
    while (e > 0n) {
      if (e & 1n) result = (result * b) % p;
      b = (b * b) % p;
      e >>= 1n;
    }
    return result;
  };
  const d = (((-121665n * powMod(121666n, p - 2n)) % p) + p) % p;
  check("ed25519 constant p", ED25519_CONSTANTS.p === p, true);
  check("ed25519 constant d", ED25519_CONSTANTS.d === d, true);
  check("ed25519 constant sqrt(-1)", ED25519_CONSTANTS.sqrtM1 === powMod(2n, (p - 1n) / 4n), true);
  // L is pinned on the curve, not against a second copy of the literal:
  // [L]B is the neutral element, [L - 1]B is not, and 2^252 < L < 2^253.
  const base = edBasePoint();
  check("ed25519 base point encoding", edEncode(base).toString("hex"), "58" + "66".repeat(31));
  check("ed25519 constant L: [L]B = O", edIsNeutral(edScalarMult(ED25519_CONSTANTS.l, base)), true);
  check("ed25519 constant L: [L-1]B != O", edIsNeutral(edScalarMult(ED25519_CONSTANTS.l - 1n, base)), false);
  check("ed25519 constant L: size", 2n ** 252n < ED25519_CONSTANTS.l && ED25519_CONSTANTS.l < 2n ** 253n, true);

  // Every honestly generated public key is a usable main-subgroup point,
  // and an honest signature under it verifies through the twin.
  let rejectedKeys = 0;
  let rejectedSignatures = 0;
  for (let i = 0; i < 256; i++) {
    const seed = createHash("sha256").update(`self-check-key-${i}`).digest();
    const privateKey = createPrivateKey({
      key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]),
      format: "der",
      type: "pkcs8",
    });
    const x = (createPublicKey(privateKey).export({ format: "jwk" }) as { x: string }).x;
    const raw = Buffer.from(x, "base64url");
    if (!usableEd25519Key(raw)) rejectedKeys++;
    const signature = cryptoSign(null, Buffer.from(`message-${i}`), privateKey);
    if (!strictSignature(signature)) rejectedSignatures++;
  }
  check("ed25519 generated honest keys usable (rejected of 256)", rejectedKeys, 0);
  check("ed25519 generated honest signatures strict (rejected of 256)", rejectedSignatures, 0);
}

// ---- strict signature rule: R canonical and not small-order, S < L ---------------
//
// The key holder (RFC 8032 TEST 1 seed) builds R = the identity with
// S = k*a mod L: the cofactorless equation holds, so node:crypto alone
// accepts it, and the twin must deny it before the backend. Every other
// weak R (the small-order set, non-canonical encodings) and S >= L must
// deny too. L, p, and the clamped scalar are derived here from RFC 8032 5.1.

{
  const L = 2n ** 252n + 27742317777372353535851937790883648493n;
  const P = 2n ** 255n - 19n;
  const leInt = (bytes: Buffer): bigint => {
    let n = 0n;
    for (let i = bytes.length - 1; i >= 0; i--) n = (n << 8n) | BigInt(bytes[i]!);
    return n;
  };
  const leBytes = (n: bigint): Buffer => {
    const out = Buffer.alloc(32);
    let v = n;
    for (let i = 0; i < 32; i++) {
      out[i] = Number(v & 0xffn);
      v >>= 8n;
    }
    return out;
  };

  const vectors = decode(readFileSync(join(import.meta.dirname, "testdata", "jose-vectors.json")));
  if (!vectors.ok || vectors.v.t !== "obj") {
    check("strict: jose vectors shape", false, true);
  } else {
    const seed = Buffer.from(memberString(member(vectors.v, "rfc8032_test1")!, "seed_hex")!, "hex");
    const publicKey = Buffer.from(memberString(vectors.v, "public_key")!, "base64url");
    const keys = [{ keyId: "test-key", key: publicKey }];
    const entries = member(vectors.v, "entries")!;
    const entry = member((entries.t === "arr" ? entries.v : [])[0]!, "entry")!;
    const input = signingInput(entry);
    const inputBytes = Buffer.from(input.ok ? input.v : "", "utf8");

    const digest = createHash("sha512").update(seed).digest();
    let a = leInt(digest.subarray(0, 32));
    a = (a & ~7n & ((1n << 255n) - 1n)) | (1n << 254n);

    const keyHolder = (r: Buffer): Buffer => {
      const k =
        leInt(createHash("sha512").update(Buffer.concat([r, publicKey, inputBytes])).digest()) % L;
      return Buffer.concat([r, leBytes((k * a) % L)]);
    };
    const withSignature = (signature: Buffer): Value => ({
      t: "obj",
      v: (entry as { t: "obj"; v: [string, Value][] }).v.map(([k, v]) =>
        k === "signature" ? [k, { t: "str" as const, v: signature.toString("base64url") }] : [k, v]),
    });
    // Denied through verify AND refused by the strict predicate itself:
    // the predicate check is what keeps each clause red-capable on a
    // runtime whose backend already rejects the same bytes.
    const denied = (signature: Buffer): boolean => {
      const result = sigVerify(withSignature(signature), keys);
      return !result.ok && result.e === "signature_not_verified" && !strictSignature(signature);
    };
    const stockKey = createPublicKey({
      key: { kty: "OKP", crv: "Ed25519", x: publicKey.toString("base64url") },
      format: "jwk",
    });

    const identity = Buffer.from("01" + "00".repeat(31), "hex");
    const forged = keyHolder(identity);
    // The backend's own verdict on this signature is runtime-dependent
    // (observed: node 22.23.1 accepts it, node 24.19.0 rejects it, OTP's
    // :crypto accepts it), which is exactly why the twin rules on R and S
    // before the backend. The construction itself is certified by the
    // corpus generator, which asserts OTP accepts its identity-R case.
    void cryptoVerify(null, inputBytes, stockKey, forged);
    check("strict: identity-R key-holder signature denied", denied(forged), true);

    const SMALL_ORDER_HEX = [
      "0100000000000000000000000000000000000000000000000000000000000000",
      "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
      "0000000000000000000000000000000000000000000000000000000000000000",
      "0000000000000000000000000000000000000000000000000000000000000080",
      "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a",
      "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa",
      "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05",
      "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85",
    ];
    for (const hex of SMALL_ORDER_HEX) {
      check(`strict: small-order R ${hex.slice(0, 8)}… denied`, denied(keyHolder(Buffer.from(hex, "hex"))), true);
    }

    const NON_CANONICAL = [
      leBytes(P), // y = p
      leBytes(P + 1n), // y = p + 1 (the identity's y, unreduced)
      leBytes((1n << 255n) - 1n), // all-ones y
      leBytes(1n | (1n << 255n)), // identity, sign bit set
      leBytes((P - 1n) | (1n << 255n)), // order-2 point, sign bit set
    ];
    for (const r of NON_CANONICAL) {
      check(`strict: non-canonical R ${r.toString("hex").slice(0, 8)}… denied`, denied(keyHolder(r)), true);
    }

    const honest = cryptoSign(
      null,
      inputBytes,
      createPrivateKey({
        key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]),
        format: "der",
        type: "pkcs8",
      }),
    );
    const honestR = honest.subarray(0, 32);
    const honestS = leInt(honest.subarray(32));
    for (const [label, s] of [["L", L], ["L + 1", L + 1n], ["honest S + L", honestS + L]] as const) {
      check(`strict: S = ${label} denied`, denied(Buffer.concat([honestR, leBytes(s)])), true);
    }
    const honestResult = sigVerify(withSignature(honest), keys);
    check("strict: honest signature verifies", honestResult.ok && honestResult.v === "verified", true);
    check("strict: honest signature passes the strict predicate", strictSignature(honest), true);
  }
}

// ---- key usability, through verify (key facts come before the R/S rule) -------
//
// check() must deny an unusable matched key with
// signature_algorithm_unsupported before it looks at the signature. The
// forged signature under the identity key (R = [r]B, S = r) passes the
// strict signature rule and satisfies [S]B = R + [k]A for A = O, so only
// the key rule stands between it and a verified verdict.

{
  const vectors = decode(readFileSync(join(import.meta.dirname, "testdata", "jose-vectors.json")));
  if (!vectors.ok || vectors.v.t !== "obj") {
    check("keys: jose vectors shape", false, true);
  } else {
    const goodKey = Buffer.from(memberString(vectors.v, "public_key")!, "base64url");
    const entries = member(vectors.v, "entries")!;
    const entry = member((entries.t === "arr" ? entries.v : [])[0]!, "entry")!;
    const withSignature = (signature: Buffer): Value => ({
      t: "obj",
      v: (entry as { t: "obj"; v: [string, Value][] }).v.map(([k, v]) =>
        k === "signature" ? [k, { t: "str" as const, v: signature.toString("base64url") }] : [k, v]),
    });
    const verdict = (signature: Buffer | null, keys: { keyId: string; key: Buffer }[]): string => {
      const result = sigVerify(signature === null ? entry : withSignature(signature), keys);
      return result.ok ? result.v : result.e;
    };
    const P = 2n ** 255n - 19n;
    const leBytes = (n: bigint): Buffer => {
      const out = Buffer.alloc(32);
      let v = n;
      for (let i = 0; i < 32; i++) {
        out[i] = Number(v & 0xffn);
        v >>= 8n;
      }
      return out;
    };

    const r = 123456789n;
    const forged = Buffer.concat([edEncode(edScalarMult(r, edBasePoint())), leBytes(r)]);
    const identityKey = Buffer.from("01" + "00".repeat(31), "hex");
    check("keys: forged signature passes the strict signature rule", strictSignature(forged), true);
    check(
      "keys: identity key with R = [r]B, S = r denied before the signature",
      verdict(forged, [{ keyId: "test-key", key: identityKey }]),
      "signature_algorithm_unsupported",
    );

    const SMALL_ORDER_KEYS = [
      "0100000000000000000000000000000000000000000000000000000000000000",
      "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
      "0000000000000000000000000000000000000000000000000000000000000000",
      "0000000000000000000000000000000000000000000000000000000000000080",
      "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a",
      "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa",
      "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05",
      "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85",
    ];
    for (const hex of SMALL_ORDER_KEYS) {
      check(
        `keys: small-order key ${hex.slice(0, 8)}… denied through verify`,
        verdict(null, [{ keyId: "test-key", key: Buffer.from(hex, "hex") }]),
        "signature_algorithm_unsupported",
      );
    }
    const BAD_KEYS: [string, Buffer][] = [
      ["y = p", leBytes(P)],
      ["off-curve", Buffer.from("d7f0980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "hex")],
      ["31 bytes", goodKey.subarray(0, 31)],
    ];
    for (const [label, key] of BAD_KEYS) {
      check(`keys: ${label} key denied through verify`, verdict(null, [{ keyId: "test-key", key }]), "signature_algorithm_unsupported");
    }
    check(
      "keys: zero key with an all-zero signature is a key fact first",
      verdict(Buffer.alloc(64), [{ keyId: "test-key", key: Buffer.alloc(32) }]),
      "signature_algorithm_unsupported",
    );
    check(
      "keys: an unusable key beside the good key still verifies",
      verdict(null, [
        { keyId: "test-key", key: identityKey },
        { keyId: "test-key", key: goodKey },
      ]),
      "verified",
    );
    check("keys: no supplied key for the key_id", verdict(null, [{ keyId: "other", key: goodKey }]), "signature_key_unsupported");
  }
}

// ---- the strict rule runs inside check(), before the backend ---------------------
//
// On a runtime whose backend already rejects every byte string the strict
// rule rejects (node 24.19.0 does, for the corpus and the checks above),
// deleting the call in check() changes no verdict, so it is pinned
// structurally: within check(), the key rule, then the strict signature
// rule, then the backend call, in that order.

{
  const here = existsSync(join(import.meta.dirname, "signature.ts")) ? "signature.ts" : "signature.js";
  const source = readFileSync(join(import.meta.dirname, here), "utf8");
  const start = source.indexOf("function check(");
  const body = start < 0 ? "" : source.slice(start, source.indexOf("\n}\n", start));
  const keyRule = body.indexOf("usableEd25519Key(key.key)");
  const strictRule = body.indexOf("if (!strictSignature(signature)) return");
  const backend = body.indexOf("cryptoVerify(");
  check("order: check() applies the key rule", keyRule >= 0, true);
  check("order: check() applies the strict signature rule", strictRule >= 0, true);
  check("order: key rule, then strict rule, then backend", keyRule < strictRule && strictRule < backend, true);
}

// ---- the key-object cache is bounded --------------------------------------------

{
  const keys: { keyId: string; key: Buffer }[] = [];
  for (let i = 0; i < KEY_OBJECT_CACHE_LIMIT + 44; i++) {
    const seed = createHash("sha256").update(`cache-key-${i}`).digest();
    const privateKey = createPrivateKey({
      key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]),
      format: "der",
      type: "pkcs8",
    });
    const x = (createPublicKey(privateKey).export({ format: "jwk" }) as { x: string }).x;
    keys.push({ keyId: "test-key", key: Buffer.from(x, "base64url") });
  }
  const vectors = decode(readFileSync(join(import.meta.dirname, "testdata", "jose-vectors.json")));
  const entries = vectors.ok && vectors.v.t === "obj" ? member(vectors.v, "entries")! : null;
  const entry = entries !== null && entries.t === "arr" ? member(entries.v[0]!, "entry")! : null;
  if (entry === null) {
    check("cache: jose entry", false, true);
  } else {
    // Every candidate key is tried (none verifies this entry), so each one
    // passes through the cache.
    const result = sigVerify(entry, keys);
    check("cache: unrelated keys do not verify", !result.ok && result.e === "signature_not_verified", true);
    check("cache: size stays at the limit", keyObjectCacheSize(), KEY_OBJECT_CACHE_LIMIT);
  }
}

function flipSignatureByte(entry: Value): Value {
  const signature = memberString(entry, "signature")!;
  const flipped =
    signature.slice(0, 10) + (signature[10] === "A" ? "B" : "A") + signature.slice(11);
  return {
    t: "obj",
    // flipSignatureByte walks signature entries (objects) only.
    v: (entry as { t: "obj"; v: [string, Value][] }).v.map(([k, v]) =>
      k === "signature" ? [k, { t: "str" as const, v: flipped }] : [k, v]),
  };
}

// ---- bounds-algebra obligation meet (the corpus-invisible direction) ---------------
//
// The frozen corpus never varies an obligation bound across sources (all
// five intersect cases carry identical values), so meet-direction errors are
// invisible to corpus agreement. These vectors pin it: obligation families
// (authority_trait/approval_trait/effect_impact_ceiling) meet at the
// STRICTEST value (max lattice index), fixed and
// verified against the live Elixir (both deny protected_bound_clamp_denied).

{
  const boundsAlgebra = await import("./bounds_algebra.ts");
  const base = (over: Record<string, unknown>) =>
    Object.assign(
      {
        approval_trait: "none",
        authority_trait: "none",
        classification_ceiling: { ordinal: "public", markers: [] },
        disclosure_ceiling: "summary",
        effect_impact_ceiling: "ordinary",
        max_attempts: 3,
        max_concurrency: 2,
        max_depth: 8,
        max_descendants: 64,
        max_elapsed_ms: 60000,
        max_fan_out: 4,
        max_tokens: 100000,
        max_cost: { amount: 1000, currency: "USD" },
      },
      over,
    );

  const widenedAuthority = base({ authority_trait: "external_authority_required" });
  const widenedApproval = base({ approval_trait: "human_required" });

  const r1 = boundsAlgebra.intersect(base({}), base({}), widenedAuthority, "deny");
  check(
    "obligation meet: authority widening denied",
    r1.ok ? "ok" : r1.e,
    "protected_bound_clamp_denied",
  );

  const r2 = boundsAlgebra.intersect(base({}), base({}), widenedApproval, "deny");
  check(
    "obligation meet: approval widening denied",
    r2.ok ? "ok" : r2.e,
    "protected_bound_clamp_denied",
  );

  const r3 = boundsAlgebra.intersect(base({}), base({}), widenedAuthority, "acknowledge");
  check(
    "obligation meet: acknowledged clamp emitted",
    r3.ok ? `clamps=${r3.v.clamps.length}` : r3.e,
    "clamps=1",
  );
}


// ---- prior-census loader mode (the compatibility-replay anchors) -----------------
//
// A synthetic prior-shaped census — corpus-independent, exactly as this
// battery requires — proving the TS prior-census mode's red arms: the
// ordinary loader still binds the registry digest; the prior mode
// suspends exactly that binding (and the compiled-floor totality) while
// keeping the census's OWN integrity chain. Mirrors the Elixir
// corpus_test prior-census describe block.

import { load, loadPriorCensus } from "./corpus.ts";
import * as digest from "./digest.ts";
import { arr, int, obj, str, nil, bool } from "./value.ts";

function sha256B64Of(bytes: Buffer | string): string {
  return createHash("sha256").update(bytes).digest("base64url");
}

interface Fixture {
  map: Map<string, Buffer>;
  corpusDigest: string;
}

// Builds a one-case census bound to a FOREIGN registry digest, with an
// applicability map covering only its own cells (a prior floor's shape).
function priorCensusFixture(overrides?: {
  caseClass?: string;
  applicability?: Value;
}): Fixture {
  const klass = overrides?.caseClass ?? "valid";

  const caseFile = obj([
    ["format", str("agent-blueprint-protocol-conformance-cases")],
    [
      "cases",
      arr([
        obj([
          ["id", str("prior-json-" + klass)],
          ["surface", str("json.decode")],
          ["class", str(klass)],
          ["input", obj([["text", str("{}")]])],
          [
            "expected",
            obj([
              ["verdict", str("valid")],
              ["value", str("{}")],
            ]),
          ],
        ]),
      ]),
    ],
  ]);

  const caseBytes = encode(caseFile);
  if (!caseBytes.ok) throw new Error("fixture: case file must encode");
  const caseBytesUtf8: string = caseBytes.v;

  const foreignRegistry = "sha-256:" + "A".repeat(43);

  const applicability =
    overrides?.applicability ??
    obj([
      [
        "json.decode",
        obj([
          ["valid", int(1)],
          ["unknown_member", obj([["n_a", str("not required at this floor")]])],
        ]),
      ],
    ]);

  const baseMembers: [string, Value][] = [
    ["format", str("agent-blueprint-protocol-conformance-corpus-index")],
    ["protocol_revision", int(1)],
    [
      "files",
      arr([
        obj([
          ["path", str("cases/json-decode.json")],
          ["sha256_base64url", str(sha256B64Of(caseBytesUtf8))],
          ["cases", int(1)],
        ]),
      ]),
    ],
    ["total_cases", int(1)],
    ["public_key_fingerprints", arr([])],
    ["applicability", applicability],
    ["registry_digest", str(foreignRegistry)],
  ];

  const withoutDigest = encode(obj(baseMembers));
  if (!withoutDigest.ok) throw new Error("fixture: index must encode");

  const corpusDigest = digest.toTagged(
    digest.hash("corpus_index", Buffer.from(withoutDigest.v, "utf8")),
  );

  const indexBytes = encode(obj([...baseMembers, ["corpus_digest", str(corpusDigest)]]));
  if (!indexBytes.ok) throw new Error("fixture: index must re-encode");

  const map = new Map<string, Buffer>();
  map.set("index.json", Buffer.from(indexBytes.v, "utf8"));
  map.set("cases/json-decode.json", Buffer.from(caseBytesUtf8, "utf8"));
  return { map, corpusDigest };
}

{
  const fixture = priorCensusFixture();

  const ordinary = load(fixture.map);
  check(
    "prior census: ordinary loader binds the registry digest (red arm)",
    ordinary.ok ? "ok" : ordinary.e,
    "corpus_index_invalid",
  );

  const prior = loadPriorCensus(fixture.map);
  check("prior census: prior mode loads a foreign-registry census", prior.ok ? "ok" : prior.e, "ok");
  if (prior.ok) {
    check("prior census: identity is the recomputed corpus digest", prior.v.identity, fixture.corpusDigest);
  }

  // Tamper the file's BYTES while keeping it decodable (the id string),
  // so the per-file hash is the check that fires.
  const tampered = new Map(fixture.map);
  tampered.set(
    "cases/json-decode.json",
    Buffer.from(
      fixture.map.get("cases/json-decode.json")!.toString("utf8").replace("prior-json-valid", "tampered-case-id"),
      "utf8",
    ),
  );
  const hashRed = loadPriorCensus(tampered);
  check(
    "prior census: own per-file hashes still red",
    hashRed.ok ? "ok" : hashRed.e,
    "corpus_hash_mismatch",
  );

  const shrunkFloor = priorCensusFixture({ caseClass: "a_class_the_current_floor_dropped" });
  const classRed = loadPriorCensus(shrunkFloor.map);
  check(
    "prior census: a case outside the compiled class set still denies",
    classRed.ok ? "ok" : classRed.e,
    "corpus_case_invalid",
  );

  // The census's OWN applicability, self-inconsistent: the "valid" cell is
  // marked n_a while the case sits in it.
  const inconsistent = priorCensusFixture({
    applicability: obj([
      [
        "json.decode",
        obj([
          ["valid", obj([["n_a", str("wrongly marked")]])],
          ["unknown_member", obj([["n_a", str("not required at this floor")]])],
        ]),
      ],
    ]),
  });
  const applicabilityRed = loadPriorCensus(inconsistent.map);
  check(
    "prior census: an n_a cell carrying a case reds",
    applicabilityRed.ok ? "ok" : applicabilityRed.e,
    "corpus_applicability_incomplete",
  );

  // The other census-relative direction: an observed case whose cell is
  // absent from the census's own applicability map (a dropped leaf).
  const unmarked = priorCensusFixture({
    applicability: obj([
      [
        "json.decode",
        obj([
          ["unknown_member", obj([["n_a", str("not required at this floor")]])],
        ]),
      ],
    ]),
  });
  const unmarkedRed = loadPriorCensus(unmarked.map);
  check(
    "prior census: a case whose cell is absent from applicability reds",
    unmarkedRed.ok ? "ok" : unmarkedRed.e,
    "corpus_applicability_incomplete",
  );
}

// ---- hostile input boundaries ----------------------------------------------------

import * as portability from "./portability.ts";
import * as predicate from "./predicate.ts";
import * as federation from "./federation.ts";
import * as boundsAlgebra from "./bounds_algebra.ts";
import * as bounds from "./bounds.ts";
import * as runner from "./runner.ts";

function resultCode(run: () => { ok: boolean; e?: string }): string {
  try {
    const result = run();
    return result.ok ? "valid" : result.e!;
  } catch (error) {
    return error instanceof Error ? `raised ${error.name}` : "raised";
  }
}

for (const name of ["constructor", "toString", "__proto__", "hasOwnProperty"]) {
  check(`predicate: unknown operator ${name}`, resultCode(() => predicate.validate(obj([["op", str(name)]]), [])), "predicate_op_unknown");
  check(`state: unknown A2A spelling ${name}`, resultCode(() => federation.fromA2aState(name)), "invalid_constraint");
  check(`state: unknown MCP spelling ${name}`, resultCode(() => federation.fromMcpState(name)), "invalid_constraint");
  check(`bounds: unknown member ${name}`, resultCode(() => boundsAlgebra.intersect(Object.fromEntries([[name, 1]]), {}, {}, "deny")), "invalid_type");
  check(`parse ceilings: unknown member ${name}`, resultCode(() => bounds.coerce(Object.fromEntries([[name, 1]]))), "unknown_bound");
}

const inheritedBounds = bounds.coerce(Object.create({ depth: 1 }));
check("parse ceilings: inherited values are absent", inheritedBounds.ok && inheritedBounds.v.depth, bounds.maximum().depth);

for (const text of ['"\\udc00"', '{"a":"\\udfff"}', '{"\\udc00":1}', '"\\ud800A"', '"\\uZZZZ"']) {
  check("decode: invalid Unicode escape", resultCode(() => decode(text)), "invalid_syntax");
}

const originalNetworkUri = /[A-Za-z][A-Za-z0-9+.-]*:\/\/[^/\t\n\v\f\r #?]+|^\/\/[^/\t\n\v\f\r #?]+/;
const uriInputs = [
  "1a://x", "+a://x", "1.a://x", "a://:x", "//x", "a://é", "a://\u00a0",
  "123+.-://x", "://x", "a://", "a://#x", "a://?x", "a:///x", "a:// x", "x//x", "//?", "a://#b://?c://",
];
const uriTokens = ["a", "Z", "1", "+", "-", ".", "://", "//", "/", " ", "#", "?", "é", "\t"];
for (const input of ["a://\u00a0", "a://\u3000", "a://\u2028x", "a://\ufeff", "//\u00a0", "//\u3000"]) {
  check(`portability: non-ASCII space begins an authority ${JSON.stringify(input)}`, portability.scanValue(str(input)).ok, false);
}
let uriSeed = 17;
for (let sample = 0; sample < 1000; sample++) {
  let input = "";
  for (let part = 0; part < sample % 9; part++) {
    uriSeed = (Math.imul(uriSeed, 1664525) + 1013904223) >>> 0;
    input += uriTokens[uriSeed % uriTokens.length]!;
  }
  uriInputs.push(input);
}
for (const input of uriInputs) {
  check(`portability: URI grammar ${JSON.stringify(input)}`, !portability.scanValue(str(input)).ok, originalNetworkUri.test(input));
}

// JavaScript exposes no regex reduction counter. One second per maximum-length
// string leaves ample CPU headroom while catching repeated scheme backtracking.
for (const [input, denied] of [
  ["a".repeat(99_996) + "://#", false],
  ["a".repeat(100_000), true],
  ["a://#".repeat(20_000), false],
  ["1.".repeat(49_998) + "://x", false],
] as [string, boolean][]) {
  const started = performance.now();
  check("portability: maximum-length scan verdict", !portability.scanValue(str(input)).ok, denied);
  check("portability: maximum-length scan under one second", performance.now() - started < 1000, true);
}

function inputCase(surface: string, input: Value, expected: Value): import("./corpus.ts").CaseObj {
  return { id: "example-input", surface, klass: "invalid_type", input, expected, tamper: null, raw: obj([]) };
}

for (const name of ["constructor", "toString", "__proto__", "hasOwnProperty"]) {
  const result = runner.execute(inputCase("bounds.new", obj([["bounds", obj([[name, int(1)]])]]), obj([["verdict", str("invalid")], ["code", str("unknown_bound")]])), new Map(), new Map());
  check(`runner: unknown ceiling member ${name}`, result.actual.ok ? "valid" : result.actual.e, "unknown_bound");
}

for (const [name, value] of [
  ["max_cost", Object.assign(Object.create({ amount: 1, currency: "USD" }), { extra: 1, other: 2 })],
  ["classification_ceiling", Object.assign(Object.create({ ordinal: "public", markers: [] }), { extra: 1, other: 2 })],
] as [string, unknown][]) {
  check(`bounds: inherited ${name} members deny`, resultCode(() => boundsAlgebra.intersect({ [name]: value }, {}, {}, "deny")), "bound_value_invalid");
}

for (const [text, projection] of [
  ["null", obj([["verdict", str("valid")], ["__proto__", obj([])]])],
  ['{"other":1}', obj([["verdict", str("valid")], ["value", obj([["__proto__", obj([])]])]])],
] as [string, Value][]) {
  check("runner: inherited expectation members never agree", runner.execute(inputCase("json.decode", obj([["text", str(text)]]), projection), new Map(), new Map()).agree, false);
}

import * as negotiation from "./negotiation.ts";
const exampleNamespace = "com.example/host";
const exampleSchema = obj([["type", str("object")]]);
const exampleSchemaBytes = encode(exampleSchema);
if (!exampleSchemaBytes.ok) throw new Error("invalid example schema");
const exampleEntry: negotiation.RegistryEntryInput = {
  owner: "ExampleHost", criticality: "critical", state: "active",
  schemaDigest: digest.toTagged(digest.hash("extension_schema", Buffer.from(exampleSchemaBytes.v))),
  a2aUri: "https://example.com/extensions/host", promotedAtRevision: null,
};
const exampleArtifact = obj([
  ["content_digest", str("example")], ["protocol_revision", int(1)], ["required_core_fields", arr([])],
  ["extensions", obj([["critical", obj([[exampleNamespace, obj([])]])], ["optional", obj([])]])],
]);
check("negotiation: inherited registration is absent", resultCode(() => negotiation.negotiate(exampleArtifact, {
  revisions: new Set([1]), coreFields: new Set(), registry: Object.create({ [exampleNamespace]: exampleEntry }), schemas: {},
})), "extension_unknown_critical");
check("negotiation: inherited schema is absent", resultCode(() => negotiation.negotiate(exampleArtifact, {
  revisions: new Set([1]), coreFields: new Set(), registry: { [exampleNamespace]: exampleEntry }, schemas: Object.create({ [exampleNamespace]: exampleSchema }),
})), "extension_schema_unavailable");

import * as compatibility from "./compatibility.ts";
const exampleIdentity = { kind: "tool", name: "example", version: "1.0.0", digest: digest.toTagged(digest.of(Buffer.from("example"))) };
const observedWithInheritedMembers = Object.assign(Object.create(exampleIdentity), { one: 1, two: 2, three: 3, four: 4 });
const exampleDeployment = { value: obj([["build_identities", arr([obj(Object.entries(exampleIdentity).map(([key, value]) => [key, str(value)]))])]]) };
check("compatibility: inherited identity members deny", resultCode(() => compatibility.verify(exampleDeployment, { identities: [observedWithInheritedMembers] })), "invalid_type");

import * as blueprint from "./blueprint.ts";

// Direct inputs exercise boundaries that JSON bytes cannot carry.
import { MAXIMA } from "./bounds.ts";
check("bounds: immutable maxima", Object.isFrozen(MAXIMA), true);
check("decode: empty overrides retain depth", resultCode(() => decode("[".repeat(65) + "0" + "]".repeat(65), {})), "ceiling:depth");
check("decode: partial overrides retain strings", resultCode(() => decode(JSON.stringify("x".repeat(100_001)), { bytes: 200_000 })), "ceiling:string");
check("decode: unknown overrides deny", resultCode(() => decode("0", { example: 1 })), "unknown_bound");
check("encode: unknown overrides deny", resultCode(() => encode(nil, { example: 1 })), "unknown_bound");
check("decode: lone surrogate input", resultCode(() => decode('"\ud800"')), "invalid_encoding");
check("encode: non-finite float", resultCode(() => encode({ t: "float", v: NaN })), "invalid_number");
let deepValue: Value = nil;
for (let i = 0; i < 20_000; i++) deepValue = arr([deepValue]);
check("encode: deep values deny", resultCode(() => encode(deepValue)), "ceiling:depth");
const broadValue = obj([["example", arr(Array.from({ length: 201 }, () => arr(Array.from({ length: 1_000 }, () => nil))))]]);
check("federation: total nodes", resultCode(() => federation.fromValue(broadValue)), "ceiling:nodes");
check("signature: byte arrays are accepted as bytes", resultCode(() => ({ ok: usableEd25519Key(new Uint8Array(32) as Buffer), e: "unusable" })), "unusable");

import * as schema from "./schema.ts";
check("schema: deep instance denies", resultCode(() => schema.validateInstance(bool(true), deepValue, schema.dialect())), "invalid_type");
check("schema: maximum-size arrays validate without exhausting the stack", resultCode(() => schema.validateInstance(obj([["items", bool(true)]]), arr(Array.from({ length: 10_000 }, () => nil)), schema.dialect())), "valid");
check("schema: malformed scalar denies", resultCode(() => schema.validateInstance(bool(true), { t: "float", v: NaN }, schema.dialect())), "invalid_type");
check("blueprint: malformed options deny", resultCode(() => blueprint.fromValue(obj([]), [] as unknown as {})), "invalid_type");
check("signature: missing keys deny", resultCode(() => sigVerify(nil, null as unknown as [])), "invalid_type");
check("signature: malformed member list denies", resultCode(() => sigVerify({ t: "obj", v: [null] } as unknown as Value, [])), "invalid_type");
check("encode: malformed tagged scalar denies", resultCode(() => encode({ t: "bool", v: 1 } as unknown as Value)), "invalid_type");
check("encode: malformed object member denies", resultCode(() => encode({ t: "obj", v: [null] } as unknown as Value)), "invalid_type");
check("encode: partial overrides retain depth", resultCode(() => encode(arr([arr([])]), { depth: 1 })), "ceiling:depth");

const exampleSchemaItems = obj([["items", obj([["enum", arr([str("match"), str("x".repeat(90_000))])]])]]);
check("schema: shared enum payload validates across locations", resultCode(() => schema.validateInstance(exampleSchemaItems, arr(Array.from({ length: 1_600 }, () => str("match"))), schema.dialect())), "valid");
for (const bad of [null, 1, { t: "arr", v: null }, { t: "obj", v: [null] }] as unknown as Value[]) {
  check("encode: malformed host values deny", resultCode(() => encode(bad)), "invalid_type");
  check("blueprint: malformed host values deny", resultCode(() => blueprint.fromValue(bad)), "invalid_type");
}
check("portability: deep values deny", resultCode(() => portability.scan(deepValue)), "ceiling:depth");
check("portability: malformed members deny", resultCode(() => portability.scan({ t: "obj", v: [null] } as unknown as Value)), "invalid_type");
import * as values from "./value.ts";
import * as deployment from "./deployment.ts";
import * as extension from "./extension.ts";
import * as corpusApi from "./corpus.ts";
import * as report from "./report.ts";
import * as registryEngine from "./registry_engine.ts";
import * as signatures from "./signature.ts";
import * as decoder from "./decode.ts";

check("schema: deep equality denies", schema.equal(deepValue, deepValue), false);
check("value: deep equality denies", values.sameValue(deepValue, deepValue), false);
check("value: deep tagged projection denies", (values.toPlain(deepValue) as { e: string }).e, "invalid_type");
let deepPlain: values.Plain = null;
for (let i = 0; i < 20_000; i++) deepPlain = [deepPlain];
check("value: deep plain projection denies", (values.fromPlain(deepPlain) as { e: string }).e, "invalid_type");
const cyclicValue: Value = arr([]);
if (cyclicValue.t === "arr") cyclicValue.v.push(cyclicValue);
check("value: cyclic equality denies", values.sameValue(cyclicValue, cyclicValue), false);
check("value: cyclic projection denies", (values.toPlain(cyclicValue) as { e: string }).e, "invalid_type");
check("schema: cyclic equality denies", schema.equal(cyclicValue, cyclicValue), false);
const cyclicPlain: values.Plain[] = [];
cyclicPlain.push(cyclicPlain);
check("value: cyclic plain projection denies", (values.fromPlain(cyclicPlain) as { e: string }).e, "invalid_type");
check("value: valid projection", JSON.stringify(values.toPlain(obj([["x", arr([int(1), nil])]]))), '{"x":[1,null]}');
check("value: valid plain conversion", JSON.stringify(values.fromPlain({ x: [1, null] })), JSON.stringify(obj([["x", arr([int(1), nil])]])));

const hostShapes: unknown[] = [null, undefined, 1, "x", Symbol("example"), {}, [], Array(1), new Set([1]), new Map(),
  { t: "arr", v: null }, { t: "obj", v: [null] }, { t: "arr", v: Array(1) }, { t: "obj", v: Array(1) }, { t: "str", v: 1 }, { t: "bad" }, nil, obj([]),
  { value: null }, { value: obj([]) }, new Map([["index.json", null]])];
for (const [moduleName, api] of Object.entries({ b64, blueprint, deployment, compatibility, boundsAlgebra,
    corpusApi, decoder, digest, extension, federation, negotiation, portability, predicate, registryEngine,
    report, runner, schema, signatures, values })) {
  for (const [name, fn] of Object.entries(api)) {
    if (typeof fn !== "function" || name === "CodeFail" || name === "SyntaxFail") continue;
    const call = fn as (...args: unknown[]) => unknown;
    for (const bad of hostShapes) {
      const args = Array.from({ length: call.length }, () => bad);
      let raised = false;
      try { call(...args); } catch { raised = true; }
      check(`${moduleName}.${name}: malformed arguments return`, raised, false);
    }
  }
}

for (const kind of [null, undefined, { enum: [] }, { array: null }, { object: null }, { object: { members: null } }]) {
  check("registry: malformed descriptors deny", resultCode(() => registryEngine.validate(
    [{ name: "example", kind } as unknown as registryEngine.Spec], obj([["example", nil]]))), "invalid_type");
}
check("registry: malformed check denies", resultCode(() => registryEngine.validate(
  [{ name: "example", kind: "any", check: 1 } as unknown as registryEngine.Spec], obj([["example", nil]]))), "invalid_type");

// ---- summary --------------------------------------------------------------------

if (failures.length > 0) {
  process.stderr.write(`self-checks FAILED (${failures.length}/${checks}):\n`);
  for (const failure of failures) process.stderr.write("  " + failure + "\n");
  process.exitCode = 1;
} else {
  process.stdout.write(`self-checks ok (${checks})\n`);
}
