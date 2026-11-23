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
- Publish is dispatched from the default branch with one required `release_commit`, a full
  40-hex lowercase SHA reachable from that branch with a successful `qualified` check. It builds that
  commit, refuses differing served package bytes and existing tags, keeps served docs, and
  publishes only missing uploads through environment `publish`. Redispatch the same
  `release_commit` to finish a held release. DevOps reads packages back,
  tags the published commit printed from served docs provenance, creates the GitHub release
  from `release-assets` including the served docs, and dispatches Pages, which deploys only by dispatch. See [release publication](docs/adr/0021-release-publication.md).
- Publication guards run at the point of publication: the pre-push hook
  and CI run the same command,
  `elixir scripts/check_public_privacy.exs scripts/public_privacy.json`.
  The command requires `ABP_PUBLIC_PRIVACY_HMAC_KEY` in its environment;
  CI supplies it from a repository secret. Builds and tests need no
  publication key.

## CI/CD and releases

What the infrastructure owner requires of every product is written once, in its CI
requirements document; the local agent file under the git-excluded planning directory says where
it is. Re-read it whenever you touch a workflow, Dockerfile, release script or secret. It is not
copied here.

- This session's part ends at the default branch. Land through the landing tool and nothing
  else. Never release, deploy, publish, tag a version, dispatch a workflow, push an image by hand,
  or handle a release, publish or CI key. When something should go out, send the infrastructure
  owner one message: repository, full `release_commit`, what goes out, and anything it needs.
  Keep the version commit landable as a landing head, or name a later `qualified` commit with
  the same declared version and package bytes; send that SHA with the release request.
- Write your own workflow changes. Before landing any change to `.github/`, a Dockerfile, a
  release script or anything that touches a secret, send the infrastructure owner the branch and
  head and wait for its review. Any CI/CD, runner, build box or key problem goes to it, not
  around it.
- Nothing that compiles or tests runs on the owner's Mac. This public repository never uses
  the build box or an organization runner: its checks run only in CI on pinned GitHub-hosted
  runners.
- Never list process arguments: no `ps` with `args` or `-f`, no `/proc/*/cmdline`; use
  `ps -eo pid,etimes,pcpu,comm`. A secret never appears on a command line, in a log or in a
  message; if you see one exposed, tell the infrastructure owner where it sits without copying
  the value.
- Messages to the infrastructure owner: one message per result, complete enough to act on
  without a reply. No acknowledgements and no status notes.
- Every brief to a child agent carries these rules.

## Build and test

- Commands below run only in CI on GitHub-hosted runners.
- Build: `mix compile --warnings-as-errors`, then
  `npm ci --ignore-scripts --no-audit --no-fund && npm run build` for the kit.
- Covering tests: `mix test <test files for the changed modules and their direct callers>`.
- Suite-wide changes (spec, corpus, registry, release metadata, workflows, shared test
  support): land through the landing tool, whose push to `kci/<sha>` runs `ci.yml` in full
  before `main` moves. The full suite runs in CI only.
- A landing is done only when it is clean; cleanup is its last step, not a later task.
  The landing tool removes `kci/<sha>` and retires the landed source branches locally and on
  origin; never delete a landed branch by hand. When it reports the change landed with cleanup
  incomplete, run its sweep and settle anything it still reports before reporting the landing.
  It clears its own run evidence; never delete that by hand. Before reporting the landing:
  this checkout is on `main` at the landed head; no branch the change used remains;
  `git worktree list` shows only this checkout; and the change's outputs are gone (any
  `cover/`, `doc/`, `dist/`, `tmp/`, `artifacts/` or `erl_crash.dump`).
  `git status --short --ignored` then shows nothing the change created beyond dependency caches
  (`deps/`, `_build/`, `node_modules/`).

[CONTRIBUTING.md](CONTRIBUTING.md) describes setup and contributor commands.
