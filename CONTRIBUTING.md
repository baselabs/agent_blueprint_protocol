# Contributing

This guide is for people changing the protocol, its implementations, or its documentation. You will be able to run focused checks and prepare a contribution.

Contributions use the Developer Certificate of Origin. Sign commits with `git commit -s`. No contributor license agreement is required. The project uses Apache-2.0; see [LICENSE](LICENSE).

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

Consumer examples run outside the checkout against real archives. `mix livebooks.package` runs every notebook against a built Hex archive. `mix doctests.package` runs every shipped module's doctests in a scratch consumer Mix project. `mix snippets.package` runs Elixir blocks from README, the guides, and the cheatsheet in that consumer; blocks share bindings within each document. `mix typescript.package` packs and installs the npm tarball and runs every JavaScript and TypeScript example in the npm README and TypeScript guide. All four gates are part of `mix quality` and remove their scratch directories on success and failure.

An `elixir` fence is runnable. Mark a partial example or configuration excerpt with `elixir fragment`; use `text` for output and `sh` for shell commands. The same `fragment` suffix applies to `js` and `ts` excerpts. All unmarked runtime blocks must run; a failing block fails the gate. TypeScript examples are independent programs. The postpublish workflow fetches both packages from the registries for the released version and runs these same generic gates from the published archive, without a source checkout. Every release run calls it, and a maintainer can run it for any released version.

To run the corpus from the repository checkout:

```sh
mix conformance.verify
```

The command prints a canonical aggregate report. Exit `0` means agreement, `1` means disagreement, `2` means invalid usage or corpus data, and `3` means an internal error.

After the bootstrap, run the complete pre-push gate:

```sh
mix quality
```

The complete pre-push gate is `mix quality`; focused checks help during editing but do not replace it. The package's `mix quality` alias runs dependency audits, formatting, compilation, strict Credo, tests with the configured coverage threshold, conformance checks, the npm kit build, TypeScript checks, Dialyzer, documentation, specification checks, and release checks. CI runs this alias in its Linux quality job.

The build-free publication privacy guard runs separately in the repository's pre-push hook and CI. Both execute the same guard with the same repository-fingerprint configuration. The hook obtains its key from the credential store and CI supplies its own secret only to that step. Builds and tests need no publication key.

The suite currently defines 1026 tests (64 properties). The coverage threshold is 100% coverage.

## CI jobs

CI runs every gate for pushes to `main` or `kci/**`, including documentation-only changes, and for every pull request.

The repository's CI workflow defines these jobs:

- **Workflow syntax** runs `actionlint` on Ubuntu 24.04.
- **Secret scan** runs `gitleaks` over full repository history on Ubuntu 24.04.
- **Specification extraction** filters the repository to `spec/` and `priv/conformance/`. It then checks the standalone copy.
- **Compatibility** runs on Ubuntu 24.04 with Node 24.19.0. Its entries are Elixir 1.19.6 / OTP 28.5, Elixir 1.20.4 / OTP 28.5, and Elixir 1.20.4 / OTP 27.3.4.17. Each entry builds the npm kit, then runs the tests and `mix conformance.verify`.
- **Quality** runs on Ubuntu 24.04 with Node 24.19.0, Elixir 1.20.3, and OTP 29.0.3. It runs these commands:

  ```sh
  npm ci --ignore-scripts --no-audit --no-fund
  npm run build
  mix quality
  ```

  This Linux job alone enforces the 100% coverage threshold.
- **Platforms** run on Ubuntu 24.04, macOS 15, and Windows 2025. Each uses Node 24.19.0, Elixir 1.20.3, and OTP 29.0.3. These runs first verify the checkout and do not enable coverage instrumentation.

  ```sh
  mix deps.get
  mix compile --warnings-as-errors
  npm ci --ignore-scripts --no-audit --no-fund
  npm run build
  node dist/kit/cli.mjs
  mix test --seed 42
  mix conformance.verify
  mix conformance.product
  mix typescript.guide
  ```

Every job in every workflow declares a job time limit, about three times its longest observed run. That limit is the bound against a hang. Test modules that build the project or pack the kit carry no fixed test limit of their own, because their duration depends on the runner. A fixed test limit is used only where finishing inside it is the requirement under test.

Package support details are in the [stability policy](documentation/stability.md).

## Propose a change

- **Behavior changes:** include a focused example or corpus case that shows the expected result.
- **Specification changes:** update `spec/` and the documents that explain the affected public behavior. Keep the specification normative.
- **Extension registrations:** follow [registry operations](spec/registry/OPERATIONS.md).
- **Documentation:** keep examples runnable or label excerpts. The documentation mirror checks Elixir result examples, the Livebook tests its cells, and the TypeScript guide check uses the packed kit. Shipped text uses no em or en dash; use a colon, a comma, parentheses or a new sentence. The gate covers every file the packages ship and the release title.

When specification text, the corpus, or the registry changes, regenerate the release metadata with the source checkout's metadata generator. It derives the current specification, registry, corpus, and package identities and synchronizes the current release-history row.

## Releases

A release is one act. Text that names a version's install commands, documentation links, tag, or notebook install targets lands as part of that version's release act, not ahead of it. The release commit carries the version bump, the release metadata, and all of that text together; it is tagged and published in one sequence. Until then, `main` names only versions that are already published, because a version's install, documentation, tag, and notebook targets do not exist before its release.

The tag starts the publish workflow. It runs the complete quality battery on the tagged tree, then uses npm trusted publishing to stage the package. A maintainer reviews and approves the staged version through npm's Staged Packages interface. The version becomes installable after approval. Local `npm publish` is not part of this release process.

Until the staged version is approved, the release run fails at the npm live check with an error naming the pending version; Hex and the GitHub release do not run. After approval, check the published version with `npm view @agent-blueprint-protocol/verifier version`, then rerun the workflow on the same tag. It verifies the installed kit against the tagged artifact and publishes Hex. If Hex holds the version for approval, the run fails with an error naming it; approve it on hex.pm and rerun the workflow on the same tag again; the GitHub release is created only once the live Hex package matches the verified archive. The [release publication](docs/adr/release-publication.md) record states the whole sequence. The same run then calls the postpublish workflow, which installs the published packages and runs every consumer example and notebook on Linux, macOS, and Windows. A failure there turns the release run red.

## Glossary

- **Check:** an automated comparison that fails when an expected condition does not hold.
- **Gate:** a check that must pass before a release step can continue.
- **CI job:** one named unit of work in a workflow, such as `quality` or `compatibility`.
- **Coverage threshold:** the minimum percentage required by the configured coverage check.
- **Conformance corpus:** the inputs and expected results used to compare verifier implementations.
- **Release metadata:** the public file that records the package version and current specification, registry, and corpus identities.

## Next steps

- [Quickstart](documentation/quickstart.md)
- [TypeScript guide](documentation/typescript.md)
- [Conformance guide](documentation/conformance.md)
- [Stability policy](documentation/stability.md)
