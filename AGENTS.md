# Agent instructions

## Build and test contract

The gate is the CI quality job's commands, run on the exact tree before any
push or landing. CI is not the first run of the gate.

```sh
mix deps.get
npm ci --ignore-scripts --no-audit --no-fund
npm run build
mix quality
```

`mix quality` is the whole battery: dependency audits, formatting,
compilation with warnings as errors, strict Credo, the suite with the 100%
coverage threshold, the conformance corpus and its mutation gate, the npm kit
and TypeScript checks, verifier agreement, the compatibility replay, Dialyzer,
documentation, and the specification and release checks. There is no smaller
pre-push subset.

Requirements:

- The toolchain in `.tool-versions`.
- The repository's release tags (`refs/tags/v*`), because the compatibility
  replay certifies against released censuses. A checkout without them
  refuses with a named reason.
- Publication guards run at the point of publication: the pre-push hook
  and CI run the same command,
  `elixir scripts/check_public_privacy.exs scripts/public_privacy.json`.
  The hook receives its key from the credential store; CI uses its own
  secret. The gate on the build machine builds and tests and needs no key.

[CONTRIBUTING.md](CONTRIBUTING.md) describes each CI job.
