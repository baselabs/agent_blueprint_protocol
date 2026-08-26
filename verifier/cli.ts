// The verifier CLI — the mirror of AgentBlueprintProtocol.Conformance.Cli:
// `--corpus <dir>` is REQUIRED (no default, so a vacuous run is impossible);
// exit 0 agreement, 1 disagreement, 2 usage error or corpus integrity
// failure. Report bytes go to stdout with NO trailing newline — including
// on exit 1 (disagreement still prints the report; the escript's
// IO.binwrite parity). Exit 3 marks an internal invariant (outside the
// 0/1/2 contract, exactly as an escript crash is — loud, never laundered
// into "disagreement").

import { readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { join } from "node:path";
import { load } from "./corpus.ts";
import { toBytes } from "./report.ts";
import { run } from "./runner.ts";

const USAGE = "usage: node conformance/verifier/cli.ts --corpus <dir>";
const BYTE_CAP = 5_000_000;

function main(argv: string[]): number {
  if (!(argv.length === 2 && argv[0] === "--corpus" && argv[1] !== "" && typeof argv[1] === "string")) {
    process.stderr.write(USAGE + "\n");
    return 2;
  }
  const dir = argv[1]!;

  let map: Map<string, Buffer>;
  try {
    map = readCorpus(dir);
  } catch {
    process.stderr.write(
      "corpus unreadable: a file is missing, unreadable, or over the byte ceiling\n",
    );
    return 2;
  }

  const corpus = load(map);
  if (!corpus.ok) {
    // Value-free by construction: the code names the corpus's own state.
    // The ":" prefix mirrors the escript's inspect(error.code) formatting.
    process.stderr.write("corpus integrity failure: :" + corpus.e + "\n");
    return 2;
  }

  const results = run(corpus.v);
  const bytes = toBytes(corpus.v.identity, results);

  // exitCode (not process.exit) so piped stdout drains before exit.
  process.stdout.write(bytes);
  const agreed = results.flat().filter((r) => r.agree).length;
  return agreed === results.flat().length && agreed > 0 ? 0 : 1;
}

// Reads EVERY file under the corpus directory — dotfiles included — so the
// loader's file-set equality sees exactly what the directory carries.
// Per-file size cap at the Bounds byte ceiling; a hostile corpus directory
// cannot exhaust memory or crash past the exit-code contract. Directory
// symlinks are followed (Path.wildcard parity).
function readCorpus(dir: string): Map<string, Buffer> {
  const map = new Map<string, Buffer>();
  const visited = new Set<string>();
  const walk = (current: string) => {
    // Cycle bound: directory symlinks repeat their realpath; a repeat is
    // skipped so the walk terminates inside the corpus-error contract.
    const real = realpathSync(current);
    if (visited.has(real)) return;
    visited.add(real);
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const path = join(current, entry.name);
      if (entry.isDirectory() || (entry.isSymbolicLink() && statSync(path).isDirectory())) {
        walk(path);
      } else {
        const info = statSync(path);
        // Regular files only: a FIFO/socket/device planted in the corpus
        // directory would block readFileSync past the exit contract — skip
        // it and let the loader's file-set equality deny (loud, not a hang).
        if (info.isFile()) {
          if (info.size > BYTE_CAP) throw new Error("over byte ceiling");
          map.set(path.slice(dir.length + 1), readFileSync(path));
        }
      }
    }
  };
  // A missing (or non-directory) corpus root yields an EMPTY map — the
  // loader then denies corpus_index_invalid, exactly as the escript's
  // empty-wildcard path does (integrity failure, not unreadable).
  if (!existsDirectory(dir)) return map;
  walk(dir);
  return map;
}

function existsDirectory(dir: string): boolean {
  try {
    return statSync(dir).isDirectory();
  } catch {
    return false;
  }
}

try {
  process.exitCode = main(process.argv.slice(2));
} catch (error) {
  process.stderr.write("verifier internal error: " + (error as Error).message + "\n");
  process.exitCode = 3;
}
