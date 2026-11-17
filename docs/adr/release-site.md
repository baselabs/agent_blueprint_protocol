# ADR: site publication after dispatched release

## Context

The static site names package versions and links to release artifacts. Its
deployed bytes must identify the source commit that supplied the packages.

## Decision

Pages starts on completion of Publish and stages `site/` only when that run
succeeded. It checks that the source is this repository's default branch and
checks out the Publish run's `head_sha`, so an intervening branch update
cannot deploy different bytes. It uploads static files without a site build.
No tag push starts Pages. Manual default-branch dispatch remains available
and checks out the dispatch commit.

The deployment job requires both the actor and triggering actor to be an
owner and deploys in Pages' own `github-pages` environment. Both jobs first
refuse refs outside the default branch. All runners are GitHub-hosted Ubuntu.
Checkout persists no credentials, and deployment does not cancel an in-flight
run. Each job has a timeout based on its measured green duration. This static
upload installs no runtime. Qualification is the separate `kci/**`-only CI
workflow, whose final `qualified` job gates landing.

## Consequences

Automatic site publication follows successful registry publication and
installed-package checks. The DevOps owner reads the packages back, pushes
the version tag at the published commit, then publishes the GitHub draft.
Until that final act, links to the new tag or draft assets may not resolve.
A failed Publish run requires manual recovery and a Pages dispatch from the
published default-branch commit; tags themselves never deploy the site.
