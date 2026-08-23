// The report builder — the mirror of AgentBlueprintProtocol.Conformance.Report:
// refuses vacuous green (agreement requires total > 0 AND zero disagreements)
// and emits deterministic JCS report bytes identity-bound to the corpus.

import { encode } from "./canonical.ts";
import { bool, int, obj, str } from "./value.ts";

const FORMAT = "agent-blueprint-protocol-conformance-report";

export interface CaseResult {
  caseId: string;
  agree: boolean;
}

export interface Report {
  agreement: boolean;
  exitStatus: 0 | 1;
  total: number;
  agreed: number;
  disagreed: number;
}

export function build(results: CaseResult[][]): Report {
  const all = results.flat();
  const total = all.length;
  const agreed = all.filter((r) => r.agree).length;
  const disagreed = total - agreed;
  const agreement = total > 0 && disagreed === 0;
  return { agreement, exitStatus: agreement ? 0 : 1, total, agreed, disagreed };
}

export function toBytes(corpusIdentity: string, results: CaseResult[][]): string {
  const report = build(results);
  const encoded = encode(
    obj([
      ["format", str(FORMAT)],
      ["agreement", bool(report.agreement)],
      ["exit_status", int(report.exitStatus)],
      ["total", int(report.total)],
      ["agreed", int(report.agreed)],
      ["disagreed", int(report.disagreed)],
      ["corpus_digest", str(corpusIdentity)],
    ]),
  );
  if (!encoded.ok) throw new Error("report must encode");
  return encoded.v;
}
