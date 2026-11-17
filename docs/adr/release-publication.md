# ADR: release publication

## Context

A release ships equal versions to Hex and npm and attaches the standalone
verifier and certified results to a GitHub release. Registries can require
approval, and upload success does not prove that the live bytes match the
verified archives. The DevOps owner dispatches publication, reads packages
back, and only then pushes the version tag and publishes the draft.

The identity of a release is governed by the
[release identity](release-identity-semantics.md) and
[no-versioning](no-versioning-rule.md) records. This record governs publication.

## Decision

Publish accepts only `workflow_dispatch`, with no inputs. Every publishing
job first refuses a ref outside the repository's default branch. The source
version comes from `mix.exs` and must equal `package.json`. One reader takes
the first-listed development toolchain from `.tool-versions`; setup uses
those exact versions, with strict BEAM selection and caching disabled.

Publishing jobs use environment `publish`. Both the actor and triggering
actor must be `corepay` or `palermo-git`. Within Publish, only npm receives
OIDC permission; only the draft job receives repository contents write permission. The
workflow serializes publications and never cancels one in flight. Publish
and Pages use GitHub-hosted Ubuntu; postpublish retains Linux, macOS, and
Windows consumers.

1. **Refuse occupied state before publication.** Check the version-specific
   public npm and Hex endpoints and `git ls-remote --tags origin` for
   `refs/tags/v<version>`. Any occupied registry version or tag refuses the
   run. Only a registry HTTP not-found response establishes absence; network
   failures and unexpected statuses refuse. Repeat before npm uploads, and
   check Hex and tag absence again after npm is live.
2. **Verify the dispatched commit.** Keep the complete quality battery,
   privacy check, and final-release promotion check against the highest
   candidate tag. Fetch dependencies with `mix deps.get --check-locked`.
   Build both archives, the standalone verifier, and certified results.
   Run `scripts/verify_release_packages.exs --local HEX.tar NPM.tgz` on the
   built archives before uploading them as `verified-release` run artifacts.
   Preserve the packed npm comparison and escript agreement check.
3. **Stage npm through trusted publishing.** Publish the verified npm
   archive with provenance, using `rc` for a prerelease and `latest` for a
   final. A conflict or pending approval fails the run, naming the partial
   state. Once live, npm's integrity must match the verified archive, and
   its installed verifier report must equal the dispatched escript's report.
4. **Publish Hex to public hexpm.** The pinned Hex client's archive API
   uploads the exact verified Hex archive and the documentation archive
   prepared by verify. It never rebuilds the package. `HEX_API_KEY` exists
   only in this step's environment; it is never passed on a command line,
   printed, or saved. Pending approval or a conflict fails. The public Hex
   release must match the verified archive's checksum before drafting.
5. **Create a draft without a tag.** Use `gh release create --draft --target`
   with the dispatched commit SHA, naming the draft `v<version>`, and attach
   the standalone verifier tarball and `certified-results.json`. Explicit
   draft creation leaves it unpublished after asset upload; the CLI sends
   `draft: true` and `target_commitish` to the release API. Check remote tag
   absence before and after drafting. The workflow never creates or pushes
   a tag or publishes the draft. Run artifacts retain the same assets for
   recovery if drafting or asset upload fails.
6. **Verify installed packages.** Call postpublish after the draft exists.
   Its reusable call and version-input dispatch install the published npm
   kit and both checksum-verified archives on Linux, macOS, and Windows.
   They run every shipped consumer example and notebook and replay earlier
   censuses and signed historical goldens through both installed packages.
   The replay enumerates existing manifest-era tags and filters versions
   newer than the installed package; it does not require the new tag.
7. **Deploy Pages from that commit.** Pages follows a successful Publish
   `workflow_run` and checks out that run's `head_sha`, rather than a newer
   default-branch head. Manual default-branch dispatch remains available.
   Its deployment uses the same protected `publish` environment. Neither
   Pages nor postpublish starts from a tag push.
8. **Finish as the owner.** Read both registries back and compare with this
   run's verified archives. Push `v<version>` at the dispatched SHA only
   after those checks, then publish the existing draft. Tags remain
   immutable historical inputs for later compatibility replay.

## Partial-state recovery

Redispatch is a fresh publication attempt, never a resume operation. If npm
is live but Hex is absent, preflight reports npm's occupied status alongside
Hex and tag status and refuses before uploading anything. A staged slot may
not appear in the public registry API; its upload conflict still fails and
never becomes a successful skip. Unknown registry state also fails closed.

The owner inspects the failed run, approves any pending staged uploads,
downloads that run's `verified-release` artifacts, and reads back any live
archives to verify their integrity. Complete missing uploads, documentation,
or draft assets by hand with those exact verified bytes; rerun postpublish
by its version-input dispatch and dispatch Pages from the published commit
if the failed Publish run did not deploy it. Then perform the tag and draft
steps above. Do not replace live bytes, rebuild for recovery, or redispatch
Publish against an occupied version. This deliberately trades automatic
resumption for an explicit boundary around irreversible partial publication.

## Registry and environment setup owned by DevOps

- Repoint npmjs.com's trusted publisher to this repository, `publish.yml`,
  and environment **`publish`**, replacing **`GH TP for ABP`**. The registry
  binds all three; changing YAML alone does not update npm. No npm token is
  used. Retain the registry's maintainer approval and publishing protections.
- Store `HEX_API_KEY` as an environment secret in **`publish`**, scoped to
  publishing this public package and its docs. The privacy guard's HMAC
  remains a step-scoped repository secret.
- Protect **`publish`** with owner review and default-branch deployment
  restrictions, covering registry uploads and drafting. Pages deployment
  stays in `github-pages`, restricted to the default branch.
