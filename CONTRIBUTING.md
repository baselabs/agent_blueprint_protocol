# Contributing

Contributions use the Developer Certificate of Origin: sign commits with `git commit -s`.
No contributor license agreement is required. See [LICENSE](LICENSE) for Apache-2.0.

## Prerequisites

Use Elixir 1.19 or newer with OTP 27, 28, or 29. Install Node.js 24 or newer for the TypeScript verifier and package checks. The source checkout declares the exact development toolchain pins.

## Clean-checkout setup

Install the declared development toolchain, including Elixir 1.19+ with supported OTP and Node.js 24+. Keep the repository release tags available because compatibility replay checks released versions. Fetch missing tags with `git fetch --tags origin` (and unshallow a shallow checkout first with `git fetch --unshallow origin`). Then prepare both toolchains:

```sh
mix deps.get --check-locked
npm ci --ignore-scripts --no-audit --no-fund
npm run build
```

A standalone `mix typescript.guide` check also requires the npm dependencies and generated package from `npm run build`.

## CI and checks

Qualification starts only on a push to `kci/**`. Landing moves the default
branch only after `qualified` has required every other job to succeed.
Pull requests, default-branch pushes, tags, and dispatches do not start CI.
This public repository uses pinned GitHub-hosted runners; builds and tests
run only in CI, never on the owner's Mac or the build box. Workstation checks
are limited to static inspection, actionlint, and the shell toolchain reader.

`scripts/toolchain.sh` is the only reader of `.tool-versions`. CI reads its
defaults and compatibility lanes once in `toolchain`; runtime setup uses
those outputs, strict BEAM versions, and installed-version checks. Publish
and postpublish use the same reader. CI also runs:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix docs --warnings-as-errors
mix typescript.guide
```

CI builds both consumer packages and runs their own notebook, doctest, Elixir
snippet, and TypeScript example gates on Linux, macOS, and Windows before a tag,
then replays every earlier release census and the signed 0.8.x goldens through
the installed Hex and npm verifiers. The corresponding CI verification after
`npm run build` is:

```sh
VERSION=$(node scripts/release_artifact_info.mjs version)
mix hex.build --output package.tar
npm pack ./dist/package --ignore-scripts --pack-destination .
elixir scripts/verify_release_packages.exs --local package.tar "agent-blueprint-protocol-verifier-$VERSION.tgz"
```

Remove the two archives after verification. Local mode consumes those exact
builds without contacting either package registry. For a published version,
use `elixir scripts/verify_release_packages.exs --registry VERSION` with that
release's version. Registry mode checks the Hex API release checksum and npm
`dist.integrity` before extraction.
The extracted Hex package supplies all four gates, and both packages supply
their own example documents. Both modes extract archives in-process and run the
same gates over the extracted bytes. The replay reads released inputs from the
checkout's Git tags; keep those tags available in either mode. The Hex package
also ships `scripts/consumer_examples.exs`, which runs the four package gates
alone and loads nothing outside the package.

Code fences use only the language as their info string. Mark a non-runnable excerpt with `<!-- fragment -->` on the line directly before its opening fence. The comment stays invisible in rendered documentation; the package example gates skip that block. Any other fence info suffix is an error, even on a marked fragment.

The example gallery and README compare every displayed JSON member with the `priv/examples` file linked in the same section, including signatures. A reading excerpt can select complete top-level members with an `<!-- example-fields: member_name other_member -->` comment directly before its JSON fence; every selected member is compared in full.

To run the corpus from the repository checkout:

```sh
mix conformance.verify
```

The command prints a canonical aggregate report. Exit `0` means agreement, `1` means disagreement, `2` means invalid usage or corpus data, and `3` means an internal error.

CI runs the complete quality checks with:

```sh
mix quality
```

The coverage threshold is 100% coverage.

The build-free publication privacy guard runs separately in the repository's pre-push hook and CI. Both run `elixir scripts/check_public_privacy.exs scripts/public_privacy.json`. The command requires `ABP_PUBLIC_PRIVACY_HMAC_KEY` in its environment. CI supplies it from a repository secret only to that step. Builds and tests need no publication key.

Regenerate release metadata after specification, corpus, or registry changes with `mix run scripts/generate_release_metadata.exs`.

## Releases

A release commit carries the equal Hex and npm version, release metadata,
and all versioned install commands, documentation links, and notebook targets.
DevOps dispatches **Publish** as an owner from the default branch with no inputs.
The run derives the version from `mix.exs`, checks it against `package.json`,
using `scripts/release_artifact_info.mjs version`, and refuses if that version
is already on either registry or already tagged. Both package names must
already exist: a first publication is the owner's decision.
It verifies the dispatched commit with the complete quality battery and runs
both built archives through the local consumer verification before publishing
those exact archives. Local `npm publish` is not part of this process.

npm uses trusted publishing with provenance in environment `publish`, followed
by Hex publication to public hexpm through the shared script
`scripts/publish_hex_artifacts.exs [--organization ORG] NAME VERSION ARCHIVE DOCS`.
That script runs from the verified archives' directory, where no project is
loaded, and uploads the verified package and docs through the pinned Hex
client's API. Both live packages must match the verified
archives. The GitHub release remains a draft named `v<version>`, targeted at
the dispatched SHA, with the standalone verifier and certified results attached.
The run never creates or pushes a tag. Postpublish verifies installed packages
on Linux, macOS, and Windows using historical tags; the new tag is not required.
Pages deploys only by an owner's dispatch from the default branch.

Pending approvals, upload conflicts, and partial publication fail the run.
Redispatch does not resume: occupied versions refuse. DevOps has staged bytes
approved, reads back live archives, and completes missing steps by hand with the
failed run's `verified-release` artifacts, then dispatches postpublish with the
version. After every Publish run, DevOps reads packages back, pushes the version
tag at the published SHA, publishes the existing draft, and dispatches Pages.

Before the first dispatch, the repository owner repoints npmjs.com's trusted
publisher to this repository, `publish.yml`, and environment `publish`, which
DevOps raises. DevOps places `HEX_API_KEY` in that environment and configures
owner review and default-branch environment protection for uploads, drafts, and
Pages. The
[release publication](docs/adr/release-publication.md) record gives the sequence,
refusal policy, recovery procedure, and registry setup.

## Next steps

- [Quickstart](documentation/quickstart.md)
- [TypeScript guide](documentation/typescript.md)
- [Conformance guide](documentation/conformance.md)
- [Stability policy](documentation/stability.md)
