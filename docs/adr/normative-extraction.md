# ADR: the normative tree extracts on its own

Status: accepted (2026-11-15).

## Context

The specification and its conformance corpus are meant to stand apart from
the reference implementation: another implementer, a standards body or a
mirror should be able to take them without the package. A citation into the
implementation's repository, or a grammar schema edited by hand, would make
the normative text depend on this tree.

## Decision

- `spec/` and `priv/conformance` together form the normative tree. Every
  link in it resolves inside it, every named section citation names a pinned
  external standard or a document inside it, and its markdown carries no
  path that climbs out of it.
- Continuous integration extracts exactly those two paths from a scratch
  clone with `git filter-repo` and runs the extraction check over the
  result, so the property is tested on the real extraction for every change.
  The same check runs over a local copy of the two paths.
- The JSON schemas under `spec/grammar/derived` are derived from the CDDL
  grammar and never edited by hand. The grammar derivation check fails when
  a derived schema differs from what the grammar produces.

## Consequences

- Specification text that needs implementation detail links to the
  implementation's published documentation by URL, not by repository path.
- A grammar change is made in the CDDL and the derived schemas are
  regenerated in the same change.
