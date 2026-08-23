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
import { verify as sigVerify, toCompact, signingInput, usableEd25519Key } from "./signature.ts";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
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

function flipSignatureByte(entry: Value): Value {
  const signature = memberString(entry, "signature")!;
  const flipped =
    signature.slice(0, 10) + (signature[10] === "A" ? "B" : "A") + signature.slice(11);
  return {
    t: "obj",
    v: entry.v.map(([k, v]) => (k === "signature" ? [k, { t: "str" as const, v: flipped }] : [k, v])),
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

// ---- summary --------------------------------------------------------------------

if (failures.length > 0) {
  process.stderr.write(`self-checks FAILED (${failures.length}/${checks}):\n`);
  for (const failure of failures) process.stderr.write("  " + failure + "\n");
  process.exitCode = 1;
} else {
  process.stdout.write(`self-checks ok (${checks})\n`);
}
