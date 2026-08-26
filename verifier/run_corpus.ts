// The corpus harness: loads ../priv/conformance from the filesystem into a
// path→bytes map (recursive, dotfiles included), verifies it through
// corpus.load, executes every case through runner.run, and prints per-case
// results plus the agreement summary. Exit 0 iff 86/86 agree.

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import * as corpus from "./corpus.ts";
import * as runner from "./runner.ts";

const CORPUS_ROOT = join(import.meta.dirname, "..", "..", "priv", "conformance");

function loadCorpusFiles(root: string): Map<string, Buffer> {
  const map = new Map<string, Buffer>();
  const walk = (dir: string, prefix: string): void => {
    for (const entry of readdirSync(dir)) {
      const absolute = join(dir, entry);
      const relative = prefix === "" ? entry : prefix + "/" + entry;
      if (statSync(absolute).isDirectory()) {
        walk(absolute, relative);
        continue;
      }
      map.set(relative, readFileSync(absolute));
    }
  };
  walk(root, "");
  return map;
}

const files = loadCorpusFiles(CORPUS_ROOT);
const loaded = corpus.load(files);
if (!loaded.ok) {
  process.stderr.write(`corpus load failed: ${loaded.e}\n`);
  process.exit(2);
}

const results = runner.run(loaded.v);

let total = 0;
let agreed = 0;
const disagreements: { id: string; detail: string }[] = [];

for (const file of results) {
  for (const result of file) {
    total++;
    if (result.agree) {
      agreed++;
      process.stdout.write(`ok       ${result.caseId}\n`);
    } else {
      const detail = explain(result.caseId, file.path);
      disagreements.push({ id: result.caseId, detail });
      process.stdout.write(`DISAGREE ${result.caseId}\n`);
    }
  }
}

// Re-execute each disagreement to surface expected vs got.
function explain(caseId: string, _path: string): string {
  const all = loaded.v.cases.flatMap((f) => f.cases);
  const caseObj = all.find((c) => c.id === caseId);
  if (caseObj === undefined) return "case not found";
  const expectedCode = corpus.memberString(caseObj.expected, "code");
  const executed = runner.execute(caseObj, loaded.v.data, loaded.v.raws);
  const got =
    executed.actual.ok
      ? "valid: " + JSON.stringify(executed.actual.v)
      : "invalid: " + executed.actual.e;
  const want = expectedCode !== null ? `invalid: ${expectedCode}` : "valid: " + JSON.stringify(projectExpectation(caseObj));
  return `  expected ${want}\n  got      ${got}`;
}

function projectExpectation(caseObj: corpus.CaseObj): unknown {
  if (caseObj.expected.t !== "obj") return null;
  const out: Record<string, unknown> = {};
  for (const [key, value] of caseObj.expected.v) {
    out[key] = value.t === "str" ? value.v : value.t;
  }
  return out;
}

process.stdout.write(`\ntotal ${total} | agreed ${agreed} | disagreed ${total - agreed}\n`);
for (const d of disagreements) {
  process.stdout.write(`${d.id}\n${d.detail}\n`);
}

if (agreed !== total || total === 0) {
  process.exit(1);
}
