// The compatibility surface — the mirror of AgentBlueprintProtocol.Compatibility:
// identity-exact or error. A manifest identity (one build_identities entry)
// is matched only by an observed identity carrying the EXACT
// (kind, name, version, digest) tuple; ranges deny
// compatibility_identity_inexact on BOTH sides; a manifest identity with no
// exact observed counterpart denies compatibility_entry_missing; duplicate
// candidates deny compatibility_duplicate_entry.

import type { Deployment } from "./deployment.ts";
import * as digest from "./digest.ts";
import { keyfind } from "./registry_engine.ts";
import type { Value } from "./value.ts";

export interface ObservedIdentity {
  kind: string | null;
  name: string | null;
  version: string | null;
  digest: string | null;
}

export interface Observed {
  identities: ObservedIdentity[];
}

type VResult = { ok: true } | { ok: false; e: string };

interface Identity {
  kind: string;
  name: string;
  version: string;
  digest: string;
}

const IDENTITY_KEYS = ["kind", "name", "version", "digest"] as const;
const EXACT_CHARSET = /^[A-Za-z0-9.+-]+$/;

export function verify(deployment: Deployment, observed: Observed): VResult {
  const manifest = manifestIdentities(deployment);
  if (!manifest.ok) return manifest;
  const validated = validatedObserved(observed.identities);
  if (!validated.ok) return validated;
  return matchManifest(manifest.v, validated.v);
}

// The exactness predicate (public on the twin): total over junk input — any
// non-conforming shape answers false.
export function exact(identity: { version: string | null }): boolean {
  const version = identity.version;
  if (typeof version !== "string") return false;
  const release = version.split("-")[0]!.split("+")[0]!;
  const segments = release.split(".");
  const lowered = version.toLowerCase();

  return (
    version !== "" &&
    EXACT_CHARSET.test(version) &&
    !["*", "latest"].includes(lowered) &&
    !segments.some((s) => ["x", "X", "*"].includes(s))
  );
}

// The manifest side: read build_identities with member indices. Absent
// member, non-array member, empty array, or a malformed entry denies typed.
function manifestIdentities(deployment: Deployment): { ok: true; v: Identity[] } | { ok: false; e: string } {
  if (deployment.value.t !== "obj") return { ok: false, e: "invalid_type" };
  const found = keyfind(deployment.value.v, "build_identities");
  if (found === null) return { ok: false, e: "missing_required_field" };
  if (found.t !== "arr") return { ok: false, e: "invalid_type" };
  if (found.v.length === 0) return { ok: false, e: "invalid_cardinality" };

  const out: Identity[] = [];
  for (const entry of found.v) {
    const identity = identityOf(entry);
    if (identity === null) return { ok: false, e: "invalid_type" };
    out.push(identity);
  }
  return { ok: true, v: out };
}

// Exactly the four members, every value a string.
function identityOf(entry: Value): Identity | null {
  if (entry.t !== "obj" || entry.v.length !== 4) return null;
  const identity: Record<string, string> = {};
  for (const key of IDENTITY_KEYS) {
    const found = keyfind(entry.v, key);
    if (found === null || found.t !== "str") return null;
    identity[key] = found.v;
  }
  return identity as unknown as Identity;
}

// The observed side: host-built, so every shape is checked here.
function validatedObserved(identities: ObservedIdentity[]): { ok: true; v: Identity[] } | { ok: false; e: string } {
  const out: Identity[] = [];
  for (const identity of identities) {
    const record = identity as unknown as Record<string, unknown>;
    const wellFormed =
      typeof record === "object" &&
      record !== null &&
      Object.keys(record).length === 4 &&
      IDENTITY_KEYS.every((key) => typeof record[key] === "string");
    if (!wellFormed) return { ok: false, e: "invalid_type" };
    const shaped = identity as unknown as Identity;
    if (!exact(shaped)) return { ok: false, e: "compatibility_identity_inexact" };
    out.push(shaped);
  }
  return { ok: true, v: out };
}

// Match, manifest member order: per identity — its own exactness, the
// unique-by name re-assertion, then the observed candidates with the exact
// tuple. None denies missing; many deny duplicate; one emits the check with
// the parsed observed digest.
function matchManifest(manifest: Identity[], observed: Identity[]): VResult {
  const seen = new Set<string>();
  for (const identity of manifest) {
    if (!exact(identity)) return { ok: false, e: "compatibility_identity_inexact" };
    if (seen.has(identity.name)) return { ok: false, e: "compatibility_duplicate_entry" };

    const candidates = observed.filter((o) => matches(identity, o));
    if (candidates.length === 0) return { ok: false, e: "compatibility_entry_missing" };
    if (candidates.length > 1) return { ok: false, e: "compatibility_duplicate_entry" };

    const parsed = digest.fromTagged(candidates[0]!.digest);
    if (!parsed.ok) return parsed;
    seen.add(identity.name);
  }
  return { ok: true };
}

function matches(identity: Identity, observed: Identity): boolean {
  return IDENTITY_KEYS.every((key) => identity[key] === observed[key]);
}
