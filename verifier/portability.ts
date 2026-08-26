// The never-portable structural guard — the mirror of AgentBlueprintProtocol.Portability:
// member-name and value-shape denylists over tagged values, four walks
// (scan / scanAuthored / scanIdentifier / scanValue) with the position-scoped
// identifier exemption. Deny reason everywhere: forbidden_portable_value.

import type { Value } from "./value.ts";

// The 34-name member denylist, verbatim, stored NORMALIZED (snake +
// case-folded, kebab folded in at compare time) so camel, kebab, and
// SCREAMING forms of one denied name converge.
const DENIED_NAMES_SOURCE = [
  "secret",
  "secrets",
  "private_key",
  "privateKey",
  "api_key",
  "apiKey",
  "token",
  "password",
  "passphrase",
  "credential",
  "credentials",
  "tenant_id",
  "tenantId",
  "org_id",
  "orgId",
  "user_id",
  "userId",
  "account_id",
  "accountId",
  "grantId",
  "primaryKey",
  "databaseUrl",
  "connectionString",
  "engineId",
  "billingAccount",
  "grant",
  "grant_id",
  "decision",
  "endpoint",
  "url",
  "uri",
  "href",
  "dsn",
  "connection_string",
  "database_url",
  "primary_key",
  "row_id",
  "billing_account",
  "engine",
  "engine_id",
  "provider_key",
];

const DENIED_NAMES = new Set(
  DENIED_NAMES_SOURCE.flatMap((name) => {
    const normalized = name.toLowerCase().replaceAll("-", "_");
    const folded = normalized.replaceAll("_", "");
    return folded === normalized ? [normalized] : [normalized, folded];
  }),
);

const PEM_MARKER = "-----BEGIN";
const MIN_SIGNATURE_CHARS = 43;
const SECRET_ENTROPY_BYTES = 24; // separator-free floor (the AES-128 hex class)
const SEPARATOR_BEARING_ENTROPY_BYTES = 32; // the base64url calibration

const HEX_CHUNK = /^[0-9a-fA-F]{1,2}$/;
const UUID_SHAPE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const B64URL = /^[A-Za-z0-9_-]+$/;
// RFC 3986 scheme + "://" + non-empty authority, or the scheme-less
// network-path reference anchored at string start.
const NETWORK_URI = /[A-Za-z][A-Za-z0-9+.-]*:\/\/[^/\s#?]+|^\/\/[^/\s#?]+/;
const LOWER_IDENTIFIER = /^[a-z0-9_-]+$/;
const UPPER_IDENTIFIER = /^[A-Z0-9_-]+$/;

type ScanResult = { ok: true } | { ok: false; e: "forbidden_portable_value" };

const forbidden = (): ScanResult => ({ ok: false, e: "forbidden_portable_value" });

// Names + values, identifier exemption OFF (extension bodies).
export function scan(value: Value): ScanResult {
  return walk(value, true, false);
}

// Names + values, identifier exemption ON (authored JSON: schemas, predicate operands).
export function scanAuthored(value: Value): ScanResult {
  return walk(value, true, true);
}

// Values only, identifier exemption ON (the protocol's identifier positions).
export function scanIdentifier(value: Value): ScanResult {
  return walk(value, false, true);
}

// Values only, exemption OFF (every other string position).
export function scanValue(value: Value): ScanResult {
  return walk(value, false, false);
}

function deniedName(name: string): boolean {
  const normalized = name.toLowerCase().replaceAll("-", "_");
  return DENIED_NAMES.has(normalized);
}

function walk(value: Value, names: boolean, exempt: boolean): ScanResult {
  switch (value.t) {
    case "obj": {
      if (names && value.v.some(([name]) => deniedName(name))) return forbidden();
      for (const [, member] of value.v) {
        if (!walk(member, names, exempt).ok) return forbidden();
      }
      return { ok: true };
    }
    case "arr": {
      for (const item of value.v) {
        if (!walk(item, names, exempt).ok) return forbidden();
      }
      return { ok: true };
    }
    case "str":
      if (exempt && identifierStyle(value.v)) return { ok: true };
      return forbiddenValue(value.v) ? forbidden() : { ok: true };
    default:
      return { ok: true };
  }
}

// ---- value shapes -------------------------------------------------------------------

function forbiddenValue(s: string): boolean {
  return !uuidShaped(s) && structuralSecret(s);
}

function uuidShaped(s: string): boolean {
  return UUID_SHAPE.test(s);
}

function structuralSecret(s: string): boolean {
  return (
    s.includes(PEM_MARKER) ||
    compactJws(s) ||
    NETWORK_URI.test(s) ||
    rawKeyMaterial(s) ||
    paddedStandardB64(s) ||
    colonHexFingerprint(s)
  );
}

// Pad-identified standard base64 (1-6 "=" at 32+ chars), or unpadded
// standard-alphabet runs at the 43-char calibration.
function paddedStandardB64(s: string): boolean {
  return /^[A-Za-z0-9+/]{32,}={1,6}$/.test(s) || /^[A-Za-z0-9+/]{43,}$/.test(s);
}

// 1-2 hex digits per ":" chunk, 24+ CHUNKS — each chunk is one byte in the
// SSH-fingerprint / EUI form, so zero-stripped one-digit chunks count fully.
function colonHexFingerprint(s: string): boolean {
  const chunks = s.split(":");
  return chunks.length >= 24 && chunks.every((chunk) => HEX_CHUNK.test(chunk));
}

// RFC 7797 detached form carries an EMPTY payload segment; the header is
// never empty, the signature carries the ≥32-byte weight.
function compactJws(s: string): boolean {
  const parts = s.split(".");
  if (parts.length !== 3) return false;
  const [header, payload, signature] = parts as [string, string, string];
  return (
    b64url(header) &&
    header.length > 0 &&
    (payload === "" || b64url(payload)) &&
    b64url(signature) &&
    Buffer.byteLength(signature, "utf8") >= MIN_SIGNATURE_CHARS
  );
}

function rawKeyMaterial(s: string): boolean {
  return b64url(s) && decodedBytes(s) >= entropyFloor(s);
}

function entropyFloor(s: string): number {
  return s.includes("-") || s.includes("_")
    ? SEPARATOR_BEARING_ENTROPY_BYTES
    : SECRET_ENTROPY_BYTES;
}

function b64url(s: string): boolean {
  return B64URL.test(s);
}

// One case, digits, and at least one `_` or `-` separator. POSITION-SCOPED:
// the artifact layer's call for positions whose convention it owns.
function identifierStyle(s: string): boolean {
  return (
    (s.includes("_") || s.includes("-")) &&
    (LOWER_IDENTIFIER.test(s) || UPPER_IDENTIFIER.test(s))
  );
}

// Unpadded base64url length: 4k → 3k bytes, 4k+2 → 3k+1, 4k+3 → 3k+2.
function decodedBytes(s: string): number {
  const size = Buffer.byteLength(s, "utf8");
  switch (size % 4) {
    case 0:
      return Math.floor((size * 3) / 4);
    case 2:
      return Math.floor(((size - 2) * 3) / 4) + 1;
    case 3:
      return Math.floor(((size - 3) * 3) / 4) + 2;
    default:
      return 0;
  }
}
