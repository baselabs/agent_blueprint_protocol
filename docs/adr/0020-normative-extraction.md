# 0020: the normative tree extracts on its own

Status: Accepted

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
- JSON schemas under `spec/grammar/derived` are generated from the CDDL
  grammar, never edited by hand.

## Consequences

- Specification text that needs implementation detail links to the
  implementation's published documentation by URL, not by repository path.
- Regenerate derived schemas after changing the CDDL.
