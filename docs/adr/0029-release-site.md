# 0029: site publication after dispatched release

Status: Accepted

## Context

The static site names package versions and links to release artifacts. Its
deployed bytes must identify the source commit that supplied the packages.
A site deployment is the same act as a publication: one owner dispatch from
the default branch.

## Decision

Pages accepts only `workflow_dispatch`. It stages `site/` from the dispatched
default-branch commit and uploads static files without a site build.
No tag push or workflow event starts Pages.

Both jobs require both the actor and triggering actor to be an owner, and
both first refuse refs outside the default branch. Deployment uses Pages'
own `github-pages` environment. All runners are GitHub-hosted Ubuntu.
Checkout persists no credentials, and deployment does not cancel an in-flight
run. Each job has a timeout based on its measured green duration. This static
upload installs no runtime. Qualification is the separate `kci/**`-only CI
workflow, whose final `qualified` job gates landing.

## Consequences

Site publication follows registry publication by infra sequence. After a Publish
run, infra reads packages back, pushes the version tag at the published commit,
compares the package archive with the registry, and creates the GitHub release
from release-assets. It then dispatches Pages from the default branch. Links to
the new tag and release assets resolve after that sequence completes. The dispatch
deploys the default branch as it stands; tags themselves never deploy the site.
