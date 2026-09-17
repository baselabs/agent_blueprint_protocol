# ADR: the dependency-currency gate

Status: accepted (2026-09-16).

## Context

Nothing reds when a dependency sits below its latest resolvable release.
The existing audits own retirement and security advisories
(`hex.audit`, `deps.audit`); drift was invisible until a fresh resolution
or a late disclosure surfaced it.

## Decision

Latest-first: every resolvable drift is updated when it appears, and any
package deliberately held below latest is a pin with an inline reason in
mix.exs (identity contract, pending major jump, resolver conflict).
"We never bumped it" is not a reason.

The gate (`scripts/check_deps_currency.exs`, battery step
`deps.currency`):

- runs in the caller's working directory — no internal directory change
  — so CI gates each project from that project's own root;
- classifies on the RENDERED result table, never the exit code, because
  `mix hex.outdated` exits nonzero both on drift and on lookup failure;
  row statuses are anchored on trailing whitespace, which the table pads;
- treats a registry lookup that failed over to the local cache as an
  UNVERIFIED currency state that never passes, table or no table;
- names every resolvable drift in its failure output and exits nonzero;
- prints resolver-blocked drift with its requirement chain — those are
  the deliberate pins, and their reasons live inline in mix.exs.

The npm kit's development tooling follows the forward Node typings line
(`^25` in package.json): the kit targets Node >= 24, and the registry's
`latest` tag for those types sits on an older major line — the declared
range is the pin target, not the dist-tag.

## Consequences

- The build reds the day an update becomes resolvable; drift can no
  longer accumulate silently across releases.
- Retirement and advisories stay with the audit steps; currency owns
  only drift. After every dependency move, the full battery — including
  the conformance and agreement gates — re-runs on the moved set.
- The gate is fail-closed end to end: an unclassifiable table row, a
  missing table, or a failed per-package lookup is a failure, never a
  pass.
