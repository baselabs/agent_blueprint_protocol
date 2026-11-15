# ADR: shipped documentation is executed from the package

Status: accepted (2026-11-15).

## Context

Guides, notebooks and examples are part of what a consumer installs. Running
them against the source checkout proves only that the checkout works; a file
left out of the package, a path that exists only in the repository or an
example that prints key material still reaches consumers.

## Decision

- Example artifacts ship in `priv/examples` and documents read them through
  `Application.app_dir/2`, so they resolve in any installed copy.
- Every executable form of documentation runs against the built package in
  a fresh consumer project outside the checkout: the notebooks, the module
  doctests, the Elixir snippets in guides and the TypeScript examples. Each
  document gets its own consumer project. A code block that is deliberately
  partial is marked `fragment` and skipped; any other marking fails the gate
  instead of hiding unrunnable code.
- The interactive key examples run in a real interactive shell, and the gate
  fails if either generated key is disclosed in any rendering. Planted
  controls for a printed private key and a printed key tuple stay in the
  suite, so the detector is proven on every run.
- Shipped text carries no em or en dash. The covered set is derived from
  the package declarations (Hex files, documentation extras, npm files, kit
  build inputs and generated kit text, TypeScript sources, the site and issue
  templates) and the release title and notes the publish workflow writes, so
  a newly shipped file is covered without a list to update.
- After publication the same consumer examples run again from the archive
  fetched from the registry, as the [release publication](release-publication.md)
  record describes.

## Consequences

- A guide example that cannot run from the installed package fails the
  build, as does a document that names a file the package does not ship.
- Documentation changes carry the same gate as code changes.
