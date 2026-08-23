// The bounds algebra — the mirror of AgentBlueprintProtocol.BoundsAlgebra:
// the pointwise narrowest intersection of three total bound sets over the
// closed 13-bound vocabulary. Scope families meet at the written-order
// minimum with marker-union retention; obligation families at the
// strictest value; operational numerics at the minimum; money at the minimum
// amount within one currency. A protected narrowing denies under the :deny
// posture (protected_bound_clamp_denied) or clamps with acknowledged evidence
// under :acknowledge. Effective values leave as the runner's projection:
// scopes {ordinal, markers(sorted)}, costs {amount, currency}, atoms as
// strings, numerics as numbers.

const IJSON_MAX = 9_007_199_254_740_991;

const LATTICES: Record<string, string[]> = {
  classification: ["public", "internal", "confidential", "restricted"],
  authority: ["none", "local_policy", "external_authority_required"],
  approval: ["none", "human_required", "separated_human_required"],
  impact: ["ordinary", "money", "authority", "secret"],
  disclosure: ["none", "summary", "detail", "full"],
};

const MARKERS = ["pci", "phi"];
const CURRENCY = /^[A-Z]{3}$/;

type BoundClass = "operational" | "protected";
type Family = "classification" | "authority" | "approval" | "impact" | "disclosure";

interface BoundDef {
  cls: BoundClass;
  kind: "pos_integer" | "cost" | { scope: Family; markers: true } | { scope: Family } | { obligation: Family };
}

// name → {class, value-kind}
const TABLE: Record<string, BoundDef> = {
  max_attempts: { cls: "operational", kind: "pos_integer" },
  max_concurrency: { cls: "operational", kind: "pos_integer" },
  max_depth: { cls: "operational", kind: "pos_integer" },
  max_descendants: { cls: "operational", kind: "pos_integer" },
  max_elapsed_ms: { cls: "operational", kind: "pos_integer" },
  max_fan_out: { cls: "operational", kind: "pos_integer" },
  max_tokens: { cls: "operational", kind: "pos_integer" },
  max_cost: { cls: "operational", kind: "cost" },
  classification_ceiling: { cls: "protected", kind: { scope: "classification", markers: true } },
  authority_trait: { cls: "protected", kind: { obligation: "authority" } },
  approval_trait: { cls: "protected", kind: { obligation: "approval" } },
  effect_impact_ceiling: { cls: "protected", kind: { obligation: "impact" } },
  disclosure_ceiling: { cls: "protected", kind: { scope: "disclosure" } },
};

// Name-sorted vocabulary (the clamps order).
const NAMES = Object.keys(TABLE).sort();

// Missing-member precedence, pinned: sources in role order; per source the
// seven numerics name-sorted, then max_cost, then the five protected
// name-sorted; the first missing member fires.
const MISSING_PRECEDENCE = [
  "max_attempts",
  "max_concurrency",
  "max_depth",
  "max_descendants",
  "max_elapsed_ms",
  "max_fan_out",
  "max_tokens",
  "max_cost",
  "approval_trait",
  "authority_trait",
  "classification_ceiling",
  "disclosure_ceiling",
  "effect_impact_ceiling",
];

const SOURCE_ORDER = ["blueprint", "deployment", "host"] as const;

// Internal value shapes: scopes {ordinal, markers: Set}, costs {amount,
// currency}, obligations/numerics as strings/numbers.
type BoundValue = number | string | { ordinal: string; markers: Set<string> } | { amount: number; currency: string };

interface Evidence {
  field: string;
  cls: BoundClass;
  requested: BoundValue;
  effective: BoundValue;
  source: "deployment" | "host";
  acknowledged: boolean;
}

type VResult = { ok: true } | { ok: false; e: string };

export function intersect(
  blueprint: Record<string, unknown>,
  deployment: Record<string, unknown>,
  host: Record<string, unknown>,
  posture: "acknowledge" | "deny",
): { ok: true; v: { effective: Record<string, unknown>; clamps: Evidence[] } } | { ok: false; e: string } {
  if (posture !== "acknowledge" && posture !== "deny") {
    return { ok: false, e: "invalid_constraint" };
  }

  const sources: Record<string, Record<string, BoundValue>> = {};
  for (const role of SOURCE_ORDER) {
    const raw = role === "blueprint" ? blueprint : role === "deployment" ? deployment : host;
    const built = buildSet(raw);
    if (!built.ok) return built;
    sources[role] = built.v;
  }

  // Totality under the pinned precedence (all three total over the 13).
  const total = totalOf(sources);
  if (!total.ok) return total;

  // The within-currency cost rule.
  const currencies = SOURCE_ORDER.map((role) => {
    const cost = sources[role]!["max_cost"] as { currency: string };
    return cost.currency;
  });
  if (new Set(currencies).size !== 1) {
    return { ok: false, e: "bound_unit_mismatch" };
  }

  return compose(sources, posture);
}

// ---- construction ------------------------------------------------------------------
//
// The TS runner passes corpus bound-set objects through verbatim (the Elixir
// runner pre-filters unknown member names to :invalid_type at add_bound_entry;
// here that delegated filter runs first, then BoundSet.new's value checks).

function buildSet(raw: Record<string, unknown>): { ok: true; v: Record<string, BoundValue> } | { ok: false; e: string } {
  const out: Record<string, BoundValue> = {};
  for (const [name, value] of Object.entries(raw)) {
    if (!(name in TABLE)) return { ok: false, e: "invalid_type" };
    const built = buildBound(name, value);
    if (!built.ok) return built;
    out[name] = built.v;
  }
  return { ok: true, v: out };
}

function buildBound(name: string, raw: unknown): { ok: true; v: BoundValue } | { ok: false; e: string } {
  const def = TABLE[name]!;
  const kind = def.kind;

  if (kind === "pos_integer") {
    if (typeof raw === "number" && Number.isInteger(raw) && raw > 0 && raw <= IJSON_MAX) {
      return { ok: true, v: raw };
    }
    return { ok: false, e: "bound_value_invalid" };
  }

  if (kind === "cost") {
    if (isPlainObject(raw) && Object.keys(raw).length === 2) {
      const record = raw as Record<string, unknown>;
      const amount = record["amount"];
      const currency = record["currency"];
      if (
        typeof amount === "number" && Number.isInteger(amount) && amount > 0 && amount <= IJSON_MAX &&
        typeof currency === "string" && CURRENCY.test(currency)
      ) {
        return { ok: true, v: { amount, currency } };
      }
    }
    return { ok: false, e: "bound_value_invalid" };
  }

  if (typeof kind === "object" && "markers" in kind) {
    if (isPlainObject(raw) && Object.keys(raw).length === 2) {
      const record = raw as Record<string, unknown>;
      const ordinal = record["ordinal"];
      const markersRaw = record["markers"];
      if (
        typeof ordinal === "string" && LATTICES[kind.scope]!.includes(ordinal) &&
        Array.isArray(markersRaw) && markersRaw.every((m) => typeof m === "string" && MARKERS.includes(m))
      ) {
        return { ok: true, v: { ordinal, markers: new Set(markersRaw as string[]) } };
      }
    }
    return { ok: false, e: "bound_value_invalid" };
  }

  if (typeof kind === "object" && "scope" in kind) {
    const lattice = LATTICES[kind.scope]!;
    if (typeof raw === "string" && lattice.includes(raw)) {
      return { ok: true, v: raw };
    }
    return { ok: false, e: "bound_value_invalid" };
  }

  // obligation: a bare lattice atom
  const lattice = LATTICES[(kind as { obligation: Family }).obligation]!;
  if (typeof raw === "string" && lattice.includes(raw)) {
    return { ok: true, v: raw };
  }
  return { ok: false, e: "bound_value_invalid" };
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// ---- totality ----------------------------------------------------------------------

function totalOf(sources: Record<string, Record<string, BoundValue>>): VResult {
  for (const role of SOURCE_ORDER) {
    const set = sources[role]!;
    const present = new Set(Object.keys(set));
    const expected = new Set(NAMES);
    const extra = [...present].filter((name) => !expected.has(name));
    if (extra.length > 0) return { ok: false, e: "bound_unknown" };

    if (present.size === expected.size && NAMES.every((n) => present.has(n))) {
      // re-validate present values (bypassed-set parity)
      for (const name of NAMES) {
        const value = set[name]!;
        const rebuilt = rebuild(name, value);
        if (!rebuilt.ok) return rebuilt;
      }
      continue;
    }

    for (const name of MISSING_PRECEDENCE) {
      if (present.has(name)) {
        const rebuilt = rebuild(name, set[name]!);
        if (!rebuilt.ok) return rebuilt;
      } else {
        return { ok: false, e: TABLE[name]!.cls === "operational" ? "missing_ceiling" : "bound_source_missing" };
      }
    }
  }
  return { ok: true };
}

// Values already validated at buildSet; this mirrors the twin's per-source
// re-validation of struct-bypassed sets (always :ok on this path).
function rebuild(name: string, value: BoundValue): VResult {
  const projected = projectValue(value);
  return buildBound(name, projected).ok ? { ok: true } : { ok: false, e: "bound_value_invalid" };
}

// ---- the meet -----------------------------------------------------------------------

function compose(
  sources: Record<string, Record<string, BoundValue>>,
  posture: "acknowledge" | "deny",
): { ok: true; v: { effective: Record<string, unknown>; clamps: Evidence[] } } | { ok: false; e: string } {
  const effective: Record<string, unknown> = {};
  const clamps: Evidence[] = [];

  for (const name of NAMES) {
    const def = TABLE[name]!;
    const requested = sources.blueprint[name]!;
    const met = meet(name, sources);

    if (boundValueEqual(met, requested)) {
      effective[name] = projectValue(met);
      continue;
    }

    if (def.cls === "protected" && posture === "deny") {
      return { ok: false, e: "protected_bound_clamp_denied" };
    }

    clamps.push({
      field: name,
      cls: def.cls,
      requested,
      effective: met,
      source: attribution(name, sources, met),
      acknowledged: def.cls === "protected" && posture === "acknowledge",
    });
    effective[name] = projectValue(met);
  }

  return { ok: true, v: { effective, clamps } };
}

function meet(name: string, sources: Record<string, Record<string, BoundValue>>): BoundValue {
  const kind = TABLE[name]!.kind;
  const values = SOURCE_ORDER.map((role) => sources[role]![name]!);

  if (kind === "cost") {
    const amounts = values.map((v) => (v as { amount: number }).amount);
    const currency = (sources.blueprint["max_cost"] as { currency: string }).currency;
    return { amount: Math.min(...amounts), currency };
  }

  if (kind === "pos_integer") {
    return Math.min(...(values as number[]));
  }

  if (typeof kind === "object" && "markers" in kind) {
    const lattice = LATTICES[kind.scope]!;
    const ordinal = values
      .map((v) => (v as { ordinal: string }).ordinal)
      .reduce((a, b) => (lattice.indexOf(a) <= lattice.indexOf(b) ? a : b));
    const markers = new Set<string>();
    for (const v of values) {
      for (const m of (v as { markers: Set<string> }).markers) markers.add(m);
    }
    return { ordinal, markers };
  }

  if (typeof kind === "object" && "scope" in kind) {
    const lattice = LATTICES[kind.scope]!;
    return (values as string[]).reduce((a, b) => (lattice.indexOf(a) <= lattice.indexOf(b) ? a : b));
  }

  // obligation: the strictest (max lattice index) wins
  const lattice = LATTICES[kind.obligation]!;
  return (values as string[]).reduce((a, b) => (lattice.indexOf(a) >= lattice.indexOf(b) ? a : b));
}

// The non-blueprint source whose value IS the effective; ties and composites
// attribute :host (the live policy is the operative constraint).
function attribution(
  name: string,
  sources: Record<string, Record<string, BoundValue>>,
  effective: BoundValue,
): "deployment" | "host" {
  if (boundValueEqual(sources.host[name]!, effective)) return "host";
  if (boundValueEqual(sources.deployment[name]!, effective)) return "deployment";
  return "host";
}

function boundValueEqual(a: BoundValue, b: BoundValue): boolean {
  if (typeof a === "number" || typeof b === "number") return a === b;
  if (typeof a === "string" || typeof b === "string") return a === b;
  if (isScope(a) && isScope(b)) {
    return a.ordinal === b.ordinal && a.markers.size === b.markers.size && [...a.markers].every((m) => b.markers.has(m));
  }
  if (isCost(a) && isCost(b)) return a.amount === b.amount && a.currency === b.currency;
  return false;
}

function isScope(v: BoundValue): v is { ordinal: string; markers: Set<string> } {
  return typeof v === "object" && v !== null && "ordinal" in v && "markers" in v;
}

function isCost(v: BoundValue): v is { amount: number; currency: string } {
  return typeof v === "object" && v !== null && "amount" in v && "currency" in v;
}

// The runner's project_bound_value: scopes as {ordinal, markers sorted};
// costs as {amount, currency}; the rest as carried.
function projectValue(value: BoundValue): unknown {
  if (isScope(value)) return { ordinal: value.ordinal, markers: [...value.markers].sort() };
  if (isCost(value)) return { amount: value.amount, currency: value.currency };
  return value;
}
