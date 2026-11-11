# Stability and support

Both packages follow Semantic Versioning on one 1.x release line. The Hex
and npm versions, including prerelease identifiers, are equal. An rc version
is a prerelease; npm selects it through the `rc` tag. A final release does
not change certified behavior from its candidate.

The stable surfaces are:

- The Elixir public modules and functions pinned by the public API census.
- The TypeScript package-root exports and their documented types. Internal
  modules are inaccessible through package deep imports.
- Documented CLI modes and exit codes, the aggregate report, per-case
  results and unsigned claim formats, and the execution protocol.
- Error-code spelling and meaning, and value-free denial subjects.
- Artifact member vocabulary and signed bytes within each protocol revision.
- Registry lifecycle rules; namespaces deprecate and never retire within a
  major. Optional-to-critical promotion requires a protocol revision.
- Corpus growth within a verification-semantics version is additive only.
  Released cases, fixture signatures, identities and history rows are immutable.

Wire revision governs what artifacts may say. Verification-semantics version
governs computation over previously certified inputs. Package semver governs
the supported APIs and distributions. Census digests identify the exact
corpus and registry. These axes do not substitute for one another.

Deprecations are announced in a minor release and removed no earlier than
the next major. A security correction that changes verification semantics
names the change through that version and its release history. Prerelease
versions can correct the candidate contract before final publication.

| Surface | Supported versions | Platforms |
|---|---|---|
| Elixir compatibility jobs | Elixir 1.19 / OTP 28; Elixir 1.20 / OTP 27 or 28 | Linux |
| Elixir library and contributor platform jobs | Elixir 1.20 / OTP 29 / Node 24 | Linux, macOS, Windows |
| TypeScript library and CLI | Node 24 | Linux, macOS, Windows |
| Maintainer release tooling | pinned toolchain; POSIX shell, Go, Git | Linux |

Exact toolchain patch pins are in [CI](https://github.com/baselabs/agent_blueprint_protocol/blob/main/.github/workflows/ci.yml).

The current 1.0 line, including its candidate, and the 0.8 transition line
receive security fixes. Older lines do not. Reports are handled on a
best-effort basis; there is no guaranteed response time. Changes to supported
lines and runtime floors are announced in release notes. The [security
policy](../SECURITY.md) defines reporting; the [upgrading guide](upgrading.md)
defines identity-aware upgrades. CI exercises supported platform jobs; a
listed platform is a support commitment, not a claim about an unexecuted
local run.
