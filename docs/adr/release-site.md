# ADR: Release-tag site publication

## Context

The static site names package versions and links to release artifacts. Its deployed bytes must identify the source ref that supplies them.

## Decision

The Pages workflow automatically deploys `site/` on tags matching `v*`, never on a `main` push. It uploads the checked-out static files without a site build. Manual workflow dispatch remains available and publishes the selected ref through the same upload and deployment jobs.

## Consequences

Automatic site publication follows release tags. A manual deployment uses the selected checkout's version text and links, so ref selection determines the published content.
