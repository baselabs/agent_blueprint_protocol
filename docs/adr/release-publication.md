# ADR: release publication

## Context

A release ships the same version to two registries (the Hex package and the
npm verifier kit) and attaches the standalone verifier to a source release.
Both registries can hold a version for maintainer approval before it goes
live, and a version, once live, can never be replaced. Upload success does
not prove the live bytes are the verified bytes. A release created with the
workflow token starts no other workflow, so a check that waits for a release
event never runs.

The identity of a release is governed by the
[release identity](release-identity-semantics.md) and
[no-versioning](no-versioning-rule.md) records. This record governs the
publication transaction around that identity.

## Decision

Publication is one ordered, resumable transaction on a release tag:

1. **Verify the tagged source.** The complete quality battery runs on the
   tagged tree. A final version also requires its highest candidate tag and
   passes the candidate promotion check against it. The verified npm
   archive, Hex archive, standalone verifier and certified results are built
   once and carried forward as artifacts; later steps use those bytes.
2. **Stage npm.** The kit is staged through trusted publishing with
   provenance, on the `rc` distribution tag for a prerelease and `latest`
   for a final. Until a maintainer approves the staged version, the run
   fails on a named pending error: Hex and the source release do not run.
3. **Verify live npm.** The live npm integrity must equal the verified
   archive's digest. The live package is installed in an empty directory and
   its conformance report must equal the tagged escript's report.
4. **Publish Hex.** A rebuilt Hex archive must equal the verified archive
   byte for byte. Publication may leave the version staged for approval.
   The version is live only when the registry API lists it with the
   verified archive's checksum; until then the run fails on a named pending
   error before the source release.
5. **Create the source release.** It is created only after live, verified
   Hex, carrying the standalone verifier and certified results, and marked
   as a prerelease for a candidate.
6. **Verify the published release.** The release run calls the
   post-publication workflow directly. It installs the published npm kit and
   verifies its corpus on every supported platform, then fetches the
   published Hex archive and runs every shipped consumer example from it,
   with no checkout of the source tree. A failure turns the release run red.

A pending approval or a conflict never reports success: the run fails and
its error names what is pending, so no later job is skipped under a green
run. After an approval, the same workflow is rerun on the same tag: every
step recognizes a version that is already live or already staged and
resumes, and every live check still compares against the verified bytes. A
release tag never moves; a source correction needs a new candidate.

## Consequences

- A release has three distinct states: staged (awaiting approval),
  published (live and byte-verified in both registries, source release
  created) and verified (post-publication checks green). Only the last is
  a finished release.
- Approval is a maintainer act on each registry. The workflow holds no npm
  token; npm trusts this repository's publish workflow through OIDC. The Hex
  key is a repository secret read only by the Hex step.
- A staging slot already occupied by earlier bytes is reported, not
  verified; the live checks after approval catch any difference.
