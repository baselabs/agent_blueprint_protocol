# The conformance runner protocol

What a third-party implementor needs to execute the ABP conformance
corpus unaided — the wire formats and contracts the verifier
implements (extracted from the implementation, which is normative by
test: the release gate requires byte-identical reports between the
Elixir escript and this TypeScript verifier).

## Corpus layout

A corpus directory carries:

- `index.json` — the corpus identity header: `format`
  (`agent-blueprint-protocol-conformance-index`), `protocol_revision`,
  `total_cases`, `corpus_digest`, `registry_digest`, the per-file
  `files` hash map (path → sha256 of raw bytes), and the
  `applicability` floor (surface × class → case count or `n_a`).
- `cases/<surface>.json` — one file per surface, a `cases` array;
  each case: `id` (unique), `class`, `surface`, `expected` (verdict +
  code or `valid: true`), and `input` (surface-specific; the decode
  surfaces carry `text` — the exact wire bytes).
- `vectors/*.json` — golden artifacts and RFC 8785 number vectors.
- `schemas/*.json` — shipped schema documents.

Integrity is load-time: exact file set (both directions), per-file
hashes, count, id-uniqueness, applicability totality. A corpus that
cannot prove its own integrity refuses to run — a vacuous green is
impossible.

## Report format

The report is a single-line JSON object, JCS-canonical (members
sorted), no trailing newline, on stdout:

```json
{"agreed":94,"agreement":true,"corpus_digest":"sha-256:…","disagreed":0,"exit_status":0,"format":"agent-blueprint-protocol-conformance-report","total":94}
```

- `agreed`/`disagreed` — per-case verdict agreement between the
  implementation under test and the corpus's expected verdicts.
- `agreement` — true iff `disagreed == 0`.
- `exit_status` — 0 agreement, 1 disagreement (the report still
  prints), 2 usage error or corpus integrity failure. An internal
  invariant exits 3 — loud, never laundered into "disagreement".

Two implementations over the same corpus MUST produce byte-identical
report bytes (including the digest member, which covers the index);
that is the agreement contract the release gate enforces.
