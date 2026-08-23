// Parse ceilings — the mirror of AgentBlueprintProtocol.Bounds: the immutable
// profile maxima and the tighten-only override rule (unknown key denies
// `unknown_bound`; a non-positive, non-integer, or super-maximum value denies
// `ceiling:<field>`).

export interface Bounds {
  bytes: number;
  depth: number;
  members: number;
  items: number;
  nodes: number;
  string: number;
  key: number;
  number_lexeme: number;
}

export const MAXIMA: Bounds = {
  bytes: 5_000_000,
  depth: 64,
  members: 1_000,
  items: 10_000,
  nodes: 200_000,
  string: 100_000,
  key: 1_000,
  number_lexeme: 64,
};

const FIELDS = Object.keys(MAXIMA) as (keyof Bounds)[];

export function maximum(): Bounds {
  return { ...MAXIMA };
}

// Overrides arrive as a plain object of string keys (corpus case input); an
// off-lattice key passes through untouched so the denial comes from this
// module, not from a pre-filtering caller.
export function coerce(overrides: unknown): { ok: true; v: Bounds } | { ok: false; e: string } {
  if (overrides === null || typeof overrides !== "object" || Array.isArray(overrides)) {
    return { ok: false, e: "invalid_type" };
  }
  const source = overrides as Record<string, unknown>;
  const out = maximum();

  for (const key of Object.keys(source)) {
    if (!FIELDS.includes(key as keyof Bounds)) return { ok: false, e: "unknown_bound" };
  }
  for (const key of FIELDS) {
    if (!(key in source)) continue;
    const value = source[key];
    if (
      typeof value !== "number" ||
      !Number.isInteger(value) ||
      value < 1 ||
      value > MAXIMA[key]
    ) {
      return { ok: false, e: `ceiling:${key}` };
    }
    out[key] = value;
  }
  return { ok: true, v: out };
}
