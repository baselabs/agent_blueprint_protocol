# Contributing

This guide is for people changing the protocol, its implementations, or its documentation. You will be able to run focused checks and prepare a contribution.

Contributions use the Developer Certificate of Origin. Sign commits with `git commit -s`. No contributor license agreement is required. The project uses Apache-2.0; see [LICENSE](LICENSE).

## Prerequisites

Use Elixir 1.19 or newer with OTP 27, 28, or 29. Install Node.js 24 or newer for the TypeScript verifier and package checks. The development toolchain versions are listed in `.tool-versions`.

## Clean-checkout setup

Install the toolchain listed in `.tool-versions`, including Elixir 1.19+ with supported OTP and Node.js 24+. Keep the repository release tags available because compatibility replay checks released versions. Fetch missing tags with `git fetch --tags origin` (and unshallow a shallow checkout first with `git fetch --unshallow origin`). Then prepare both toolchains:

```sh
mix deps.get
npm ci --ignore-scripts --no-audit --no-fund
npm run build
```

A standalone `mix typescript.guide` check also requires the npm dependencies and generated package from `npm run build`.

## Local checks

Run focused checks for the files you change. For example:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test test/architecture
mix docs --warnings-as-errors
mix typescript.guide
```

The public examples have checks of their own. The Elixir documentation examples and Livebook cells run through tests. `mix typescript.guide` installs the packed npm kit in a scratch project and checks the TypeScript guide's import example.

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

The publication privacy guard runs separately in the pre-push hook and CI with the same build-free command: `elixir scripts/check_public_privacy.exs scripts/public_privacy.json`. The hook obtains its key from the credential store and CI supplies its own secret only to that step. Builds and tests need no publication key.

The suite currently defines 997 tests (64 properties). The coverage threshold is 100% coverage.

## CI jobs

The [CI workflow](.github/workflows/ci.yml) defines these jobs:

- **Workflow syntax** runs `actionlint` on Ubuntu 24.04.
- **Secret scan** runs `gitleaks` over full repository history on Ubuntu 24.04.
- **Specification extraction** filters the repository to `spec/` and `priv/conformance/`. It then checks the standalone copy.
- **Compatibility** runs on Ubuntu 24.04 with Node 24.19.0. Its entries are Elixir 1.19.6 / OTP 28.5, Elixir 1.20.4 / OTP 28.5, and Elixir 1.20.4 / OTP 27.3.4.17. Each entry runs `mix test` and `mix conformance.verify`.
- **Quality** runs on Ubuntu 24.04 with Node 24.19.0, Elixir 1.20.3, and OTP 29.0.3. It runs these commands:

  ```sh
  npm ci --ignore-scripts --no-audit --no-fund
  npm run build
  mix quality
  ```

  This Linux job alone enforces the 100% coverage threshold.
- **Platforms** run on Ubuntu 24.04, macOS 15, and Windows 2025. Each uses Node 24.19.0, Elixir 1.20.3, and OTP 29.0.3. These runs do not enable coverage instrumentation.

  ```sh
  node scripts/check_checkout.mjs
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

Package support details are in the [stability policy](documentation/stability.md).

## Propose a change

- **Behavior changes:** include a focused example or corpus case that shows the expected result.
- **Specification changes:** update `spec/` and the documents that explain the affected public behavior. Keep the specification normative.
- **Extension registrations:** follow [registry operations](spec/registry/OPERATIONS.md).
- **Documentation:** keep examples runnable or label excerpts. The documentation mirror checks Elixir result examples, the Livebook tests its cells, and the TypeScript guide check uses the packed kit.

When specification text, the corpus, or the registry changes, regenerate the release metadata:

```sh
MIX_ENV=test mix run --no-start scripts/generate_release_metadata.exs
```

## npm package releases

The tagged GitHub Actions workflow uses npm trusted publishing to stage the package. A maintainer reviews and approves the staged version through npm's Staged Packages interface. The version becomes installable after approval. Local `npm publish` is not part of this release process.

After approval, check the published version with `npm view @agent-blueprint-protocol/verifier version`. The release workflow verifies the installed kit against the tagged artifact before announcing completion.

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
