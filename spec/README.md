# Agent Blueprint Protocol — specification directory

This directory holds the normative specification of the Agent Blueprint
Protocol (`protocol.md`), kept deliberately self-contained: no build
tool, package manager, or repository context is needed to read it. The
license terms for this tree ship beside it (`LICENSE`, `NOTICE`).

## Extraction

The specification is extraction-ready. The two paths that constitute a
standalone specification tree are this directory and the conformance
corpus:

```bash
git filter-repo --path spec/ --path priv/conformance
```

The result renders with no dangling references: the document cites the
conformance corpus and the extension registry **by digest** (the pinned
values inside `priv/conformance/index.json`, which extracts beside this
tree), never by a repository-relative path that would dangle once
extracted. The repository's own build asserts this on every run, and
its continuous-integration workflow re-proves the extraction against
the filter command above.

## Release identity chain

Every release pins the specification and its evidence together:

| Field | Meaning |
|---|---|
| specification digest | SHA-256 over the framed, path-sorted files of this directory |
| package version | the reference-implementation release this specification certifies |
| corpus digest · registry digest | the conformance corpus and compiled registry this release ships |
| corpus index hash | SHA-256 of the corpus index bytes |

These values are pinned per release in the reference implementation's
release metadata and asserted from live state by its release-candidate
check; a disagreement anywhere in the chain blocks the release.
