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

[CONTRIBUTING.md](CONTRIBUTING.md) describes setup and contributor commands.
