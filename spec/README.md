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
| manifest version | the SHAPE version of the release-identity manifest (additive-only within a version) |
| verification semantics version | the release's computational meaning for previously-certified inputs — the semantics/census split's axis (the specification's Evolution clause) |
| digest identity | the closed digest scheme (canonical bytes, hash, domain separation, wire form), stable across every release |
| compatibility matrix | the certified verdict per prior census digest, replay-certified by the reference implementation's gate |
| verifier kit identity | the npm kit's name and version, bound to the Hex line |

These values are pinned per release in the reference implementation's
release metadata and asserted from live state by its release-candidate
check; a disagreement anywhere in the chain blocks the release. The
companion release history (one append-only row per release, the
manifest era onward) is verified against each release tag's actual
tree by the compatibility gate.
