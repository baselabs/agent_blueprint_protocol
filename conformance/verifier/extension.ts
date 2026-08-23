// The positional extension envelope — the mirror of AgentBlueprintProtocol.Extension:
// {"critical": {ns → body}, "optional": {ns → body}}, shared by both artifact
// tables as a table check and by the scans as the open-region walk.

import type { Value } from "./value.ts";

const IDENTIFIER_BYTES = 512;
const CEILING_EXTENSIONS = 32;

const NAMESPACE = /^[a-z0-9][a-z0-9.-]*\/[a-z0-9][a-z0-9.-]*$/;

type VResult = { ok: true } | { ok: false; e: string };

// The envelope shape check a table carries: exactly critical + optional
// regions, namespace form, total cardinality, no namespace in both.
export function envelopeOk(value: Value): VResult {
  if (value.t !== "obj") return { ok: false, e: "invalid_type" };
  const members = value.v;

  const names = members.map(([name]) => name).sort();
  if (names.length !== 2 || names[0] !== "critical" || names[1] !== "optional") {
    // A single missing half is a missing member; anything else unknown.
    const raw = members.map(([name]) => name);
    if (raw.length === 1 && (raw[0] === "critical" || raw[0] === "optional")) {
      return { ok: false, e: "missing_required_field" };
    }
    return { ok: false, e: "unknown_member" };
  }

  const namespaces: string[] = [];
  for (const [, regionValue] of members) {
    if (regionValue.t !== "obj") return { ok: false, e: "invalid_type" };
    for (const [ns] of regionValue.v) {
      if (!namespaceForm(ns)) return { ok: false, e: "extension_namespace_invalid" };
      namespaces.push(ns);
    }
  }

  if (namespaces.length > CEILING_EXTENSIONS) return { ok: false, e: "invalid_cardinality" };

  if (new Set(namespaces).size !== namespaces.length) return { ok: false, e: "extension_duplicate" };

  return { ok: true };
}

// Every {namespace, body} pair in the envelope, both regions, in document
// order — the scan's walk over the open region. `members` is the ROOT member
// list (the "extensions" member is located by name).
export function bodies(members: [string, Value][]): [string, Value][] {
  const out: [string, Value][] = [];
  const extensions = memberValue(members, "extensions");
  if (extensions === null || extensions.t !== "obj") return out;
  for (const [, regionValue] of extensions.v) {
    if (regionValue.t !== "obj") continue;
    for (const [ns, body] of regionValue.v) out.push([ns, body]);
  }
  return out;
}

// The critical region's namespace set for THIS value — the authored-channel
// tie (a validated-critical list must sit inside this set).
export function criticalNamespaces(members: [string, Value][]): Set<string> {
  const out = new Set<string>();
  const extensions = memberValue(members, "extensions");
  if (extensions === null || extensions.t !== "obj") return out;
  for (const [region, regionValue] of extensions.v) {
    if (region !== "critical" || regionValue.t !== "obj") continue;
    for (const [ns] of regionValue.v) out.add(ns);
  }
  return out;
}

function namespaceForm(ns: string): boolean {
  return Buffer.byteLength(ns, "utf8") <= IDENTIFIER_BYTES && NAMESPACE.test(ns);
}

function memberValue(members: [string, Value][], name: string): Value | null {
  const found = members.find(([key]) => key === name);
  return found ? found[1] : null;
}
