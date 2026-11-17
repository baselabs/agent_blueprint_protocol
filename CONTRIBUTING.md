# Contributing

Contributions use the Developer Certificate of Origin: sign commits with `git commit -s`.
No contributor license agreement is required. See [LICENSE](LICENSE) for Apache-2.0.

## Prerequisites

Use Elixir 1.19 or newer with OTP 27, 28, or 29. Install Node.js 24 or newer for the TypeScript verifier and package checks. The source checkout declares the exact development toolchain pins.

## Clean-checkout setup

Install the declared development toolchain, including Elixir 1.19+ with supported OTP and Node.js 24+. Keep the repository release tags available because compatibility replay checks released versions. Fetch missing tags with `git fetch --tags origin` (and unshallow a shallow checkout first with `git fetch --unshallow origin`). Then prepare both toolchains:

```sh
mix deps.get
npm ci --ignore-scripts --no-audit --no-fund
npm run build
```

A standalone `mix typescript.guide` check also requires the npm dependencies and generated package from `npm run build`.

## Local checks

Run focused tests for the files you change and their direct dependents in the source checkout. Other useful checks include:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix docs --warnings-as-errors
mix typescript.guide
```

CI builds both consumer packages and runs their own notebook, doctest, Elixir
snippet, and TypeScript example gates on Linux, macOS, and Windows before a tag.
Run that same gate locally after `npm run build`:

```sh
VERSION=$(node -p "require('./dist/package/package.json').version")
mix hex.build --output package.tar
npm pack ./dist/package --ignore-scripts --pack-destination .
elixir scripts/consumer_examples.exs --local package.tar "agent-blueprint-protocol-verifier-$VERSION.tgz"
```

Remove the two archives after verification. Local mode consumes those exact
builds without contacting either package registry. For a published version,
use `elixir scripts/consumer_examples.exs --registry VERSION` with that release's
version. Registry mode checks the Hex API release checksum and npm
`dist.integrity` before extraction.
The tagged checkout supplies the driver; the extracted Hex package supplies all
four gates, and both packages supply their own example documents. Both modes
extract archives in-process and run the same gates over the extracted bytes.

To run the corpus from the repository checkout:

```sh
mix conformance.verify
```

The command prints a canonical aggregate report. Exit `0` means agreement, `1` means disagreement, `2` means invalid usage or corpus data, and `3` means an internal error.

Run the complete quality checks with:

```sh
mix quality
```

The coverage threshold is 100% coverage.

The build-free publication privacy guard runs separately in the repository's pre-push hook and CI. Both run `elixir scripts/check_public_privacy.exs scripts/public_privacy.json`. The command requires `ABP_PUBLIC_PRIVACY_HMAC_KEY` in its environment. CI supplies it from a repository secret only to that step. Builds and tests need no publication key.

Regenerate release metadata after specification, corpus, or registry changes with `mix run scripts/generate_release_metadata.exs`.

## Releases

A release is one act. Text that names a version's install commands, documentation links, tag, or notebook install targets lands as part of that version's release act, not ahead of it. The release commit carries the version bump, the release metadata, and all of that text together; it is tagged and published in one sequence. Until then, `main` names only versions that are already published, because a version's install, documentation, tag, and notebook targets do not exist before its release.

The tag starts the publish workflow. It runs the complete quality battery on the tagged tree, then uses npm trusted publishing to stage the package. A maintainer reviews and approves the staged version through npm's Staged Packages interface. The version becomes installable after approval. Local `npm publish` is not part of this release process.

Until the staged version is approved, the release run fails at the npm live check with an error naming the pending version; Hex and the GitHub release do not run. After approval, check the published version with `npm view @agent-blueprint-protocol/verifier version`, then rerun the workflow on the same tag. It verifies the installed kit against the tagged artifact and publishes Hex. If Hex holds the version for approval, the run fails with an error naming it; approve it on hex.pm and rerun the workflow on the same tag again; the GitHub release is created only once the live Hex package matches the verified archive. The [release publication](docs/adr/release-publication.md) record states the whole sequence. The same run then calls the postpublish workflow, which installs the published packages and runs every consumer example and notebook on Linux, macOS, and Windows. A failure there turns the release run red.

## Next steps

- [Quickstart](documentation/quickstart.md)
- [TypeScript guide](documentation/typescript.md)
- [Conformance guide](documentation/conformance.md)
- [Stability policy](documentation/stability.md)
