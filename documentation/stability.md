# Stability and support

Both packages follow Semantic Versioning on one 1.x release line. The Hex
and npm versions, including prerelease identifiers, are equal. A version marked `rc` is a prerelease; npm selects it through the `rc` tag. A final release does
not change certified behavior from its candidate.

The stable surfaces are:

- The Elixir modules and functions documented on HexDocs.
- The TypeScript package-root exports and their documented types. Internal
  modules are inaccessible through package deep imports.
- Documented CLI modes and exit codes, the aggregate report, per-case
  results and unsigned claim formats, and the execution protocol.
- Error-code spelling and meaning, and value-free denial subjects.
- Artifact member vocabulary and signed bytes within each protocol revision.
- Registry lifecycle rules for entries the release ships; those namespaces deprecate and never retire within a
  major. Optional-to-critical promotion requires a protocol revision.
- Corpus growth within a verification-semantics version is additive only.
  Released cases, fixture signatures, identities and history rows are immutable.

Wire revision governs what artifacts may say. Verification-semantics version
governs computation over previously certified inputs. Package semver governs
the supported APIs and distributions. Census digests identify the exact
corpus and registry. These axes do not substitute for one another.
A security correction that changes verification semantics names the change through that version and its release history.

Deprecations are announced in a minor release and removed no earlier than
the next major. Prerelease versions can correct the candidate contract
before final publication.

| Surface | Supported versions | Platforms |
|---|---|---|
| Elixir compatibility jobs | Elixir 1.19 / OTP 28; Elixir 1.20 / OTP 27 or 28 | Linux |
| Elixir library and contributor platform jobs | Elixir 1.20 / OTP 29 / Node 24 | Linux, macOS, Windows |
| TypeScript library, CLI, and harness | Node 24 and 26; TypeScript 5.0.2 or newer | Linux, macOS, Windows |

Exact toolchain patch pins are in [CI](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.1-rc.1/.github/workflows/ci.yml).

The 1.0 line and the 0.8 transition line receive security fixes. Older lines do not. Reports are handled on a
best-effort basis; there is no guaranteed response time. Added runtime
versions and changes to maintained release lines are announced in release notes; the 1.x runtime floors never rise. The [security
policy](../SECURITY.md) defines reporting; the [upgrading guide](upgrading.md)
defines identity-aware upgrades. CI runs every listed platform job.

## Evolution within 1.x

Minor releases add opt-in capabilities while preserving existing bytes,
defaults, required inputs, and documented return contracts. New protocol
revisions have their own member and algorithm sets; every earlier revision
remains accepted for the whole major. New signature algorithms enter only
through a new revision. New registry namespaces, federation profiles,
conformance surfaces and cases, CLI modes and flags, notices, evidence
check kinds and detail variants, and supported runtimes can arrive in 1.x.
A new corpus is a new census: an earlier claim remains valid for its exact
corpus digest. Corpus file-count and total-byte caps are runner tooling
limits, separate from artifact limits, and may rise in a minor release.

An incompatible federation envelope uses a new registered critical namespace
beside the existing profiles. Existing profiles never retire during 1.x.
The existing envelope format stays unchanged. A successor execution protocol is explicitly selected; harnesses
and adapters keep execution version 1 throughout 1.x.

`ErrorCode` and the meaning of every code are closed for all of 1.x.
New mechanisms reuse an existing code whose meaning fits or wait for 2.0.
Inputs certified under a released census keep their verdicts at the same
verification-semantics version. A security correction or registry change
that moves a verdict increments that version, declares it in the release
history, and records prior-census equivalence or divergence. Artifact member
sets and signed-byte formats for existing revisions stay fixed. Every
released results document, claim, and corpus keeps its format.

Node 24 and Elixir 1.19 remain the floors throughout 1.x. The library retains
support for the OTP majors supported at 1.0: 27, 28, and 29, with compatible
Elixir builds. TypeScript 5.0.2 is the compiler floor, checked with NodeNext
resolution, `skipLibCheck: false`, and no Node global declarations.
Additional runtime versions expand this set. The OTP check in `config/` and the exact toolchain pins apply only to development in a checkout; `config/` is not in the Hex package.

## Consumer compatibility

Switch exhaustively on `ErrorCode`; its union stays closed. Treat notices,
evidence surfaces and check kinds, detail variants, and returned signature
algorithm and purpose names as open sets. Exported `KNOWN_*` constants name
known TypeScript values without closing those sets. Inputs retain their
strict types. Look up facts by name, keep a default branch, and never treat
an unknown entry as proof. Match Elixir structs only on the fields used:

```elixir
case result do
  {:ok, %AgentBlueprintProtocol.Evidence{checks: checks}} ->
    Enum.find(checks, fn
      %{surface: :signatures, verified: true} -> true
      _ -> false
    end)
  {:error, %AgentBlueprintProtocol.Error{code: code}} -> {:error, code}
end
```

```ts
import { KNOWN_NOTICES, type Notice } from "@agent-blueprint-protocol/verifier";
function isDeprecated(notice: Notice): boolean {
  switch (notice) {
    case KNOWN_NOTICES.extension_deprecated: return true;
    default: return false;
  }
}
```

The [TypeScript guide](typescript.md) demonstrates the exhaustive error
switch. Ignore unknown additive release-manifest members, but reject an
unknown equivalence claim. Treat every unknown nonzero harness exit as
failure. No unknown notice or evidence entry proves a check you recognize.
