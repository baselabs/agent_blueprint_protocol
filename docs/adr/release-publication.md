# ADR: release publication

## Context

A release ships equal versions to Hex and npm and supplies the standalone verifier,
certified results, package archives, release notes, and SHA256SUMS for the GitHub
release. Registries can hold uploads for approval. Upload acceptance alone does not
prove publication or establish that the served bytes match the verified archives.

The [release identity](release-identity-semantics.md) and
[no-versioning](no-versioning-rule.md) records govern release identity.

## Decision

Publish accepts only an owner's `workflow_dispatch` from the default branch, with
no inputs. Both actor and triggering actor must be `corepay` or `palermo-git`.
Every job first refuses any other ref. Upload jobs use environment **`publish`**;
configure owner review and default-branch deployment protection there. Only npm's
upload job receives OIDC write permission. No job has contents write permission.
Installed-package checks have the same owner gate, `contents: read`, no environment,
and no key. Publication is serialized without cancelling an in-flight run.

Qualification remains separate: `kci/**` pushes run CI, and `qualified` requires
every job before landing moves the default branch. Qualification installs only
locally built ABP archives, never this package from its registry. All runtimes
come from `scripts/toolchain.sh` and `.tool-versions`, are installed strictly and
checked immediately; checkout uses `persist-credentials: false`, dependency
fetches use `--check-locked`, and no caches are written. Publishing runs on
GitHub-hosted Ubuntu; installed consumers run on Linux, macOS, and Windows.

1. **Verify the source and package names.** Derive equal versions from `mix.exs`
   and `package.json`. Refuse a remote `v<version>` tag and any package name that
   npm or Hex does not confirm exists. A first publication belongs to the owner;
   unknown registry state is refused. Keep all historical release tags for replay.
   Run the privacy guard, promotion check, and complete quality battery.
2. **Build and inspect the exact bytes.** Pack the npm kit, standalone verifier,
   certified results, and Hex package. Run the local consumer verification on
   both packages. ExDoc produces HTML and Markdown, without EPUB: EPUB zip
   entries carry build time. Archive docs with sorted entries, the commit's
   timestamp, numeric owner/group zero, and `gzip -n`, so redispatch rebuilds
   byte-identical docs. Print package and docs checksums.
3. **Plan missing uploads.** `scripts/npm_release_state.mjs` compares the npm
   version's `dist.integrity` with the built tgz. The shared
   `scripts/hex_release_state.exs` compares the signed registry's raw outer
   checksum and the stored docs tarball against the built bytes. Active, equal
   bytes are served; absent uploads are planned. Retired releases, differing
   bytes, malformed responses, and registry errors refuse. Docs without a
   package, or served Hex bytes without npm, refuse as inconsistent.
4. **Stage npm, then publish Hex.** Upload npm only when planned, using trusted
   publishing with provenance, and read its integrity back with bounded retries.
   Approve staged bytes on npmjs.com when required. The `npm-kit` job, with no
   environment and no key, compares the live npm integrity and the installed kit's
   report with the verified escript; `hex-publish` needs it. The shared command is
   `scripts/publish_hex_artifacts.exs [--organization ORG] NAME VERSION [--package ARCHIVE] [--docs DOCS]`.
   It receives only missing archives and uploads the package before docs. Run it
   with `mix run --no-mix-exs` from `verified-release`, without a `mix.exs`.
   A loaded Mix project is refused before reading the key. Hex's modules remain
   on the code path; nothing is compiled or rebuilt under the key. Store
   `HEX_API_KEY` as an environment secret, exposed only in the upload step's env.
   No response body, key, or authentication file is printed or persisted.
5. **Read both Hex uploads back.** The upload script checks under the key whether
   Hex already holds a requested package version before attempting upload. Held
   packages stop before docs; held docs also stop explicitly. The read-only
   state script requires package and docs to be served with the built bytes,
   retrying only absence, six attempts ten seconds apart. It never replaces bytes.
6. **Hand release assets to infra.** All consumer files leave the Hex publish job
   together as `release-assets`: the Hex tar, npm tgz, `verifier-<version>.tar.gz`,
   `certified-results.json`, `release-notes.md` from the dated CHANGELOG section,
   and SHA256SUMS over the other files. Internal `verified-release` transport
   carries inspected archives between jobs. No workflow creates a release or tag.
7. **Check installed consumers.** Publish's `smoke` and `livebooks` jobs need
   `verify` and `hex-publish`. They install the published packages and run their
   notebooks, doctests, snippets, TypeScript examples, and historical replay.
   The new tag is unnecessary; earlier release tags must remain available.
8. **Infra creates the release.** After read-back and the new tag at the dispatched
   SHA, infra compares the package archive with the registry and creates the
   GitHub release `v<version>` using the complete release assets. It then dispatches
   Pages from the default branch. Pages uses its own `github-pages` environment;
   no tag push or workflow event deploys it.

## Held releases and redispatch

A second dispatch on the same commit finishes a held release, uploading only what
is missing. Approve held npm uploads on npmjs.com or held Hex uploads on hex.pm,
then dispatch Publish again on that same commit. Already served equal bytes
succeed without uploading, including when all uploads are served: read-back,
installed-package checks, and release assets still complete. An existing remote
tag refuses a finished release. Differing bytes or retirement always refuse.
Upload errors leave accepted uploads intact; resolve the cause and redispatch.
Consumer verification uses the permanent GitHub release, never expiring run storage.
