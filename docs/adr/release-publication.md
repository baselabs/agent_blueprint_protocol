# ADR: release publication

## Context

A release ships equal versions to Hex and npm and attaches the standalone
verifier and certified results to a GitHub release. Registries can require
approval, and upload success does not prove that the live bytes match the
verified archives. DevOps dispatches publication as an owner, reads packages
back, and only then pushes the version tag, publishes the draft, and
dispatches the site.

The identity of a release is governed by the
[release identity](release-identity-semantics.md) and
[no-versioning](no-versioning-rule.md) records. This record governs publication.

## Decision

Publish accepts only `workflow_dispatch`, with no inputs. Every publishing
job first refuses a ref outside the repository's default branch. The source
version comes from `mix.exs` and must equal `package.json`, checked by
`scripts/release_artifact_info.mjs version` in verify and passed to subsequent
jobs through its output. The shared `scripts/toolchain.sh` reader takes
defaults and compatibility lanes from `.tool-versions`; setup uses those
exact versions, with strict BEAM selection, installed-version checks, and
caching disabled. Qualification is separate: only `kci/**` pushes start CI,
and its final `qualified` job requires every other job to succeed before
`kimosabe-land` moves the default branch.

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
   The quality gate builds docs with warnings as errors before packaging.
   Build both archives, the standalone verifier, and certified results.
   Run `scripts/verify_release_packages.exs --local HEX.tar NPM.tgz` on the
   built archives before uploading them as `verified-release` run artifacts.
   Preserve the packed npm comparison and escript agreement check.
3. **Stage npm through trusted publishing.** Publish the verified npm
   archive with provenance, using `rc` for a prerelease and `latest` for a
   final. A conflict or pending approval fails the run, naming the partial
   state. Once live, npm's integrity must match the verified archive, and
   its installed verifier report must equal the dispatched escript's report.
4. **Publish Hex to public hexpm.** The shared script
   `scripts/publish_hex_artifacts.exs [--organization ORG] NAME VERSION ARCHIVE DOCS`
   confirms version absence with the pinned Hex client's release API, then
   uploads the exact verified Hex archive and the documentation archive
   prepared by verify. The call names `agent_blueprint_protocol` with no
   organization, which is the public repository. It never rebuilds the
   package. `HEX_API_KEY` exists only in this step's environment; it is never
   passed on a command line, printed, or saved. Pending approval or a conflict fails. The public Hex
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
7. **Finish as DevOps.** After the dispatch, read both registries back and
   compare with this run's verified archives. Push `v<version>` at the
   dispatched SHA only after those checks, then publish the existing draft.
   Tags remain immutable historical inputs for later compatibility replay.
8. **Deploy Pages by dispatch.** A site deployment is the same act as a
   publication: one owner dispatch of Pages from the default branch, made
   by DevOps after the read-back. Both Pages jobs carry the owner condition
   and refuse other refs first. Deployment uses the protected
   `github-pages` environment. Neither Pages nor postpublish starts from a
   tag push or a workflow event.

## Partial-state recovery

Redispatch is a fresh publication attempt, never a resume operation. If npm
is live but Hex is absent, preflight reports npm's occupied status alongside
Hex and tag status and refuses before uploading anything. A staged slot may
not appear in the public registry API; its upload conflict still fails and
never becomes a successful skip. Unknown registry state also fails closed.

DevOps inspects the failed run, has any pending staged uploads approved,
downloads that run's `verified-release` artifacts, and reads back any live
archives to verify their integrity. Complete missing uploads, documentation,
or draft assets by hand with those exact verified bytes; rerun postpublish
by its version-input dispatch. Then perform the tag, draft, and Pages
steps above. Do not replace live bytes, rebuild for recovery, or redispatch
Publish against an occupied version. This deliberately trades automatic
resumption for an explicit boundary around irreversible partial publication.

## Registry and environment setup

- The repository owner repoints npmjs.com's trusted publisher to this
  repository, `publish.yml`, and environment **`publish`**, replacing
  **`GH TP for ABP`**; DevOps raises it. The registry binds all three;
  changing YAML alone does not update npm. No npm token is used. Retain the
  registry's maintainer approval and publishing protections.
- DevOps stores `HEX_API_KEY` as an environment secret in **`publish`**,
  scoped to publishing this public package and its docs. The privacy guard's
  HMAC remains a step-scoped repository secret.
- DevOps protects **`publish`** with owner review and default-branch deployment
  restrictions, covering registry uploads and drafting. Pages deployment
  stays in `github-pages`, restricted to the default branch.
