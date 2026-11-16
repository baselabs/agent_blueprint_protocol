# ADR: shipped documentation is executed from the package

## Context

Guides, notebooks, and examples are part of the installed package.
Their resources must resolve from that package, and interactive examples
must never disclose generated key material.

## Decision

- Example artifacts ship in `priv/examples` and documents read them through
  `Application.app_dir/2`, so they resolve in any installed copy.
- Interactive key examples run in a real shell and disclose neither key.
  The disclosure detector covers rendered keys and key tuples.
