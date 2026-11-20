# Agent instructions

```sh
mix deps.get --check-locked
npm ci --ignore-scripts --no-audit --no-fund
npm run build
mix quality
```

Requirements:

- Install the toolchain in `.tool-versions`.
- Keep historical release tags (`refs/tags/v*`) available for compatibility replay.
- Publish is dispatched from the default branch without inputs, never by pushing a tag.
  It refuses differing served package bytes and existing tags, keeps served docs, verifies
  both archives, and publishes only missing uploads through environment `publish`.
  A second dispatch on the same commit finishes a held release. DevOps reads packages back,
  tags the published commit printed from served docs provenance, creates the GitHub release
  from `release-assets` including the served docs, and dispatches Pages, which deploys only by dispatch. See [release publication](docs/adr/release-publication.md).
- Publication guards run at the point of publication: the pre-push hook
  and CI run the same command,
  `elixir scripts/check_public_privacy.exs scripts/public_privacy.json`.
  The command requires `ABP_PUBLIC_PRIVACY_HMAC_KEY` in its environment;
  CI supplies it from a repository secret. Builds and tests need no
  publication key.

## CI/CD and releases

What infra requires of every product is written once, in the infra repository:
`baselabs/docs/ci.md`, section "What infra requires of every product", on its default branch
(`git -C ~/Developer/infra fetch -q origin; git -C ~/Developer/infra show origin/main:baselabs/docs/ci.md`).
Re-read it whenever you touch a workflow, Dockerfile, release script or secret. It is not copied
here.

- This session's part ends at the default branch. Land through `kimosabe-land` and nothing else.
  Never release, deploy, publish, tag a version, dispatch a workflow, push an image by hand, or
  handle a release, publish or CI key. When something should go out, send infra-1 one message:
  repository, full commit, what goes out, and anything it needs.
- Write your own workflow changes. Before landing any change to `.github/`, a Dockerfile, a
  release script or anything that touches a secret, send infra-1 the branch and head and wait for
  its review. Any CI/CD, runner, box or key problem goes to infra-1, not around it.
- Nothing that compiles or tests runs on the owner's Mac. This public repository never uses
  the build box or an organization runner: its checks run only in CI on pinned GitHub-hosted
  runners.
- Never list process arguments: no `ps` with `args` or `-f`, no `/proc/*/cmdline`; use
  `ps -eo pid,etimes,pcpu,comm`. A secret never appears on a command line, in a log or in a
  message; if you see one exposed, tell infra-1 where it sits without copying the value.
- Messages to infra-1: one message per result, complete enough to act on without a reply. No
  acknowledgements and no status notes.
- Every brief to a child agent carries these rules.

## Build and test

- Commands below run only in CI on GitHub-hosted runners.
- Build: `mix compile --warnings-as-errors`, then
  `npm ci --ignore-scripts --no-audit --no-fund && npm run build` for the kit.
- Covering tests: `mix test <test files for the changed modules and their direct callers>`.
- Suite-wide changes (spec, corpus, registry, release metadata, workflows, shared test
  support): land through `kimosabe-land`, whose push to `kci/<sha>` runs `ci.yml` in full
  before `main` moves. The full suite runs in CI only.

[CONTRIBUTING.md](CONTRIBUTING.md) describes setup and contributor commands.
