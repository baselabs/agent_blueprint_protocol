// The closed, portable boolean predicate algebra — the mirror of
// AgentBlueprintProtocol.Predicate's validate/2 (the shape walk the Blueprint
// root hook consumes): closed operator world, per-operator operand members,
// the 256-node ceiling, and the pinned per-node check order
// (op presence → op value → unknown member → missing operand → operand
// type/cardinality → path[0] → node ceiling, counted depth-first on entry).

import type { Value } from "./value.ts";

const NODE_CEILING = 256;

type Reason =
  | "predicate_op_unknown"
  | "predicate_path_unresolved"
  | "predicate_nodes_exceeded"
  | "unknown_member"
  | "missing_required_field"
  | "invalid_type"
  | "invalid_cardinality";

type VResult = { ok: true } | { ok: false; e: Reason };

const FOLD_OPS = ["and", "or"];
const NOT_OPS = ["not"];
const COMPARE_OPS = ["eq", "ne", "lt", "lte", "gt", "gte"];
const MEMBER_OPS = ["in"];
const PRESENCE_OPS = ["present", "absent"];
const ARG_OPS = [...FOLD_OPS, ...NOT_OPS];
const PATH_OPS = [...COMPARE_OPS, ...MEMBER_OPS, ...PRESENCE_OPS];

// operand name lists per operator
const OPERANDS: Record<string, string[]> = {
  and: ["args"],
  or: ["args"],
  not: ["args"],
  eq: ["path", "value"],
  ne: ["path", "value"],
  lt: ["path", "value"],
  lte: ["path", "value"],
  gt: ["path", "value"],
  gte: ["path", "value"],
  in: ["path", "values"],
  present: ["path"],
  absent: ["path"],
};

export function validate(predicate: Value, portNames: string[]): VResult {
  const ports = new Set(portNames);
  const result = shape(predicate, ports, 0);
  return result.ok ? { ok: true } : { ok: false, e: result.e };
}

// ---- shape walk -----------------------------------------------------------------------

function shape(predicate: Value, ports: Set<string>, count: number): { ok: true; v: number } | { ok: false; e: Reason } {
  if (predicate.t !== "obj") return { ok: false, e: "invalid_type" };
  const members = predicate.v;

  if (count + 1 > NODE_CEILING) return { ok: false, e: "predicate_nodes_exceeded" };
  if (!noDuplicateMembers(members)) return { ok: false, e: "invalid_type" };

  const op = opOf(members);
  if (!op.ok) return op;

  const closed = closedMembers(members, op.v);
  if (!closed.ok) return closed;

  const present = operandsPresent(members, op.v);
  if (!present.ok) return present;

  return operandShapes(members, op.v, ports, count + 1);
}

function noDuplicateMembers(members: [string, Value][]): boolean {
  const names = new Set<string>();
  for (const [name] of members) {
    if (typeof name !== "string") return false;
    if (names.has(name)) return false;
    names.add(name);
  }
  return true;
}

function opOf(members: [string, Value][]): { ok: true; v: string } | { ok: false; e: Reason } {
  const found = keyfind(members, "op");
  if (found === null) return { ok: false, e: "missing_required_field" };
  if (found.t !== "str") return { ok: false, e: "invalid_type" };
  return { ok: true, v: found.v };
}

function closedMembers(members: [string, Value][], op: string): VResult {
  const operands = OPERANDS[op];
  if (operands === undefined) return { ok: false, e: "predicate_op_unknown" };
  const allowed = new Set(["op", ...operands]);
  for (const [name] of members) {
    if (!allowed.has(name)) return { ok: false, e: "unknown_member" };
  }
  return { ok: true };
}

function operandsPresent(members: [string, Value][], op: string): VResult {
  for (const name of OPERANDS[op]!) {
    if (keyfind(members, name) === null) return { ok: false, e: "missing_required_field" };
  }
  return { ok: true };
}

function operandShapes(
  members: [string, Value][],
  op: string,
  ports: Set<string>,
  count: number,
): { ok: true; v: number } | { ok: false; e: Reason } {
  if (ARG_OPS.includes(op)) {
    const args = arrayMember(members, "args");
    if (!args.ok) return args;
    if (!arityOk(op, args.v.length)) return { ok: false, e: "invalid_cardinality" };
    return argShapes(args.v, ports, count);
  }

  // path ops
  const path = pathMember(members, ports);
  if (!path.ok) return path;
  if (op === "in") {
    const values = valuesMember(members);
    if (!values.ok) return values;
  }
  return { ok: true, v: count };
}

function arityOk(op: string, n: number): boolean {
  if (FOLD_OPS.includes(op)) return n >= 1;
  return n === 1; // not
}

function argShapes(
  items: Value[],
  ports: Set<string>,
  count: number,
): { ok: true; v: number } | { ok: false; e: Reason } {
  let acc = count;
  for (const item of items) {
    const result = shape(item, ports, acc);
    if (!result.ok) return result;
    acc = result.v;
  }
  return { ok: true, v: acc };
}

function arrayMember(members: [string, Value][], name: string): { ok: true; v: Value[] } | { ok: false; e: Reason } {
  const found = keyfind(members, name);
  if (found !== null && found.t === "arr") return { ok: true, v: found.v };
  return { ok: false, e: "invalid_type" };
}

function pathMember(members: [string, Value][], ports: Set<string>): VResult {
  const found = keyfind(members, "path");
  if (found === null || found.t !== "arr") return { ok: false, e: "invalid_type" };
  const segments = found.v;
  if (segments.length === 0) return { ok: false, e: "invalid_type" };
  if (!segments.every((s) => s.t === "str")) return { ok: false, e: "invalid_type" };
  const root = (segments[0] as { t: "str"; v: string }).v;
  return ports.has(root) ? { ok: true } : { ok: false, e: "predicate_path_unresolved" };
}

function valuesMember(members: [string, Value][]): VResult {
  const found = keyfind(members, "values");
  if (found === null || found.t !== "arr") return { ok: false, e: "invalid_type" };
  if (!found.v.every(wellFormed)) return { ok: false, e: "invalid_type" };
  return { ok: true };
}

// `value`/`values` operands carry arbitrary tagged JSON; they must still be
// well-formed tagged values or evaluate-time equality would crash.
function wellFormed(value: Value): boolean {
  switch (value.t) {
    case "null":
    case "bool":
    case "int":
    case "float":
    case "str":
      return true;
    case "arr":
      return value.v.every(wellFormed);
    case "obj":
      return value.v.every(([name, member]) => typeof name === "string" && wellFormed(member));
  }
}

function keyfind(members: [string, Value][], name: string): Value | null {
  const found = members.find(([key]) => key === name);
  return found ? found[1] : null;
}
