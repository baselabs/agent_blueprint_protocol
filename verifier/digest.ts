// Domain-separated SHA-256 digests — the mirror of AgentBlueprintProtocol.Digest:
// preimage `separator || 0x00 || jcs_bytes` under the registered separator
// (protocol §5), tagged wire form "sha-256:<43-char unpadded base64url>".

import { createHash } from "node:crypto";
import * as b64 from "./b64url.ts";

export type Domain =
  | "blueprint_content"
  | "deployment_content"
  | "federation_envelope"
  | "signature"
  | "extension_schema"
  | "extension_registry"
  | "conformance_report"
  | "corpus_index";

export const SEPARATORS: Record<Domain, string> = {
  blueprint_content: "agent-blueprint-protocol/blueprint-content",
  deployment_content: "agent-blueprint-protocol/deployment-content",
  federation_envelope: "agent-blueprint-protocol/federation-envelope",
  signature: "agent-blueprint-protocol/signature",
  extension_schema: "agent-blueprint-protocol/extension-schema",
  extension_registry: "agent-blueprint-protocol/extension-registry",
  conformance_report: "agent-blueprint-protocol/conformance-report",
  corpus_index: "agent-blueprint-protocol/corpus-index",
};

const SIZES: Record<string, number> = { "sha-256": 32 };
const TAGS = Object.keys(SIZES);

export interface Digest {
  algorithm: "sha-256";
  bytes: Buffer;
}

export function of(data: Buffer): Digest;
export function of(data: unknown): Digest | { ok: false; e: string };
export function of(data: unknown): Digest | { ok: false; e: string } {
  if (!Buffer.isBuffer(data)) return { ok: false, e: "invalid_type" };
  return { algorithm: "sha-256", bytes: createHash("sha256").update(data).digest() };
}

export function hash(domain: Domain, data: Buffer): Digest;
export function hash(domain: unknown, data: unknown): Digest | { ok: false; e: string };
export function hash(domainInput: unknown, data: unknown): Digest | { ok: false; e: string } {
  const domain = domainInput as Domain;
  if (typeof domain !== "string" || !Object.hasOwn(SEPARATORS, domain) || !Buffer.isBuffer(data)) return { ok: false, e: "invalid_type" };
  return of(Buffer.concat([Buffer.from(SEPARATORS[domain], "utf8"), Buffer.from([0]), data]));
}

export function toTagged(digest: Digest): string;
export function toTagged(digest: unknown): string | { ok: false; e: string };
export function toTagged(input: unknown): string | { ok: false; e: string } {
  const digest = input as Digest;
  if (!digest || digest.algorithm !== "sha-256" || !Buffer.isBuffer(digest.bytes) || digest.bytes.length !== 32) return { ok: false, e: "invalid_type" };
  return "sha-256:" + b64.encode(digest.bytes);
}

export function fromTagged(
  input: string,
): { ok: true; v: Digest } | { ok: false; e: string } {
  if (typeof input !== "string") return { ok: false, e: "invalid_type" };
  const colon = input.indexOf(":");
  if (colon === -1) return { ok: false, e: "digest_encoding_invalid" };
  const tag = input.slice(0, colon);
  const body = input.slice(colon + 1);
  if (!TAGS.includes(tag)) return { ok: false, e: "digest_algorithm_unsupported" };
  const decoded = b64.decodeStrict(body);
  if (!decoded.ok) return { ok: false, e: "digest_encoding_invalid" };
  if (decoded.v.length !== SIZES[tag]) return { ok: false, e: "digest_encoding_invalid" };
  return { ok: true, v: { algorithm: "sha-256", bytes: decoded.v } };
}

// Constant-time equality over the digest bytes (the twin's xor-accumulate).
export function equal(a: Digest, b: Digest): boolean {
  if (!a || !b || !Buffer.isBuffer(a.bytes) || !Buffer.isBuffer(b.bytes)) return false;
  if (a.bytes.length !== b.bytes.length || a.algorithm !== b.algorithm) return false;
  let diff = 0;
  for (let i = 0; i < a.bytes.length; i++) diff |= a.bytes[i]! ^ b.bytes[i]!;
  return diff === 0;
}

export function verifyContent(
  domain: Domain,
  jcsBytes: Buffer,
  tagged: string,
): { ok: true } | { ok: false; e: string } {
  if (typeof domain !== "string" || !Object.hasOwn(SEPARATORS, domain) || !Buffer.isBuffer(jcsBytes)) return { ok: false, e: "invalid_type" };
  const declared = fromTagged(tagged);
  if (!declared.ok) return declared;
  if (equal(hash(domain, jcsBytes), declared.v)) return { ok: true };
  return { ok: false, e: "digest_mismatch" };
}
