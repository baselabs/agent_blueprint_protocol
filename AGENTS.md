# Agent instructions

```sh
mix deps.get
npm ci --ignore-scripts --no-audit --no-fund
npm run build
mix quality
```

Requirements:

- Install the toolchain in `.tool-versions`.
- Keep release tags (`refs/tags/v*`) available for compatibility replay.
- Publication guards run at the point of publication: the pre-push hook
  and CI run the same command,
  `elixir scripts/check_public_privacy.exs scripts/public_privacy.json`.
  The hook receives its key from the credential store; CI uses its own
  secret. The gate on the build machine builds and tests and needs no key.

## Build and test

- Build: `mix compile --warnings-as-errors`, then
  `npm ci --ignore-scripts --no-audit --no-fund && npm run build` for the kit.
- Covering tests: `mix test <test files for the changed modules and their direct callers>`.
- Suite-wide changes (spec, corpus, registry, release metadata, workflows, shared test
  support): land through `kimosabe-land`, whose push to `kci/<sha>` runs `ci.yml` in full
  before `main` moves. The full suite runs in CI only.

[CONTRIBUTING.md](CONTRIBUTING.md) describes setup and contributor commands.
