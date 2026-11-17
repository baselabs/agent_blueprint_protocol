# Agent instructions

```sh
mix deps.get
npm ci --ignore-scripts --no-audit --no-fund
npm run build
mix quality
```

Requirements:

- Install the toolchain in `.tool-versions`.
- Keep historical release tags (`refs/tags/v*`) available for compatibility replay.
- Publish is dispatched from the default branch without inputs, never by pushing a tag.
  It refuses occupied versions, verifies both archives, and publishes through environment
  `publish`. DevOps reads packages back before pushing the version tag at the run's SHA
  and publishing its GitHub draft. See [release publication](docs/adr/release-publication.md).
- Publication guards run at the point of publication: the pre-push hook
  and CI run the same command,
  `elixir scripts/check_public_privacy.exs scripts/public_privacy.json`.
  The command requires `ABP_PUBLIC_PRIVACY_HMAC_KEY` in its environment;
  CI supplies it from a repository secret. Builds and tests need no
  publication key.

## Build and test

- Build: `mix compile --warnings-as-errors`, then
  `npm ci --ignore-scripts --no-audit --no-fund && npm run build` for the kit.
- Covering tests: `mix test <test files for the changed modules and their direct callers>`.
- Suite-wide changes (spec, corpus, registry, release metadata, workflows, shared test
  support): land through `kimosabe-land`, whose push to `kci/<sha>` runs `ci.yml` in full
  before `main` moves. The full suite runs in CI only.

[CONTRIBUTING.md](CONTRIBUTING.md) describes setup and contributor commands.
