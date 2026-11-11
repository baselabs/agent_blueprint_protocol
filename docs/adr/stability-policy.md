# ADR: Stability policy

Status: accepted (2026-11-10).

## Context

Two distributions share artifact identities and need an explicit compatibility contract.

## Decision

Both packages use one Semantic Versioning line. The stability policy freezes the pinned Elixir census, package-root TypeScript API, documented CLI modes and formats, errors, wire revisions and registry lifecycle. Deprecations arrive in a minor and removals wait for the next major; namespaces do not retire within a major.

## Consequences

Corpus growth is additive within a semantics version. Security maintenance and runtime/platform support are stated separately from protocol revision.

## Evolution within the major

Minor releases preserve existing bytes, defaults, required inputs, and
return contracts. The additive paths are opt-in protocol revisions with
separate member and algorithm sets, new namespaces and federation profiles,
conformance surfaces and census cases, CLI modes and flags, explicitly
selected execution versions, notices, evidence check kinds and detail
variants, and runtime support. Earlier revisions, federation profiles, and
execution version 1 remain supported for the whole major. A successor
federation profile uses a new critical namespace and binds its identity
into its commitment preimage; the current envelope remains unchanged.

Error codes and meanings remain closed throughout 1.x. Inputs certified
under a released census keep their verdicts at the same verification-semantics
version. A security correction or registry addition that moves a verdict
increments that version, declares it in the release history, and records
prior-census equivalence or divergence. Artifact member sets and signed-byte
formats for existing revisions, and released results, claims, and corpus
formats remain fixed. Claims remain valid for their exact census digest. Corpus I/O
caps are tooling limits that may rise independently of artifact limits.
Node 24, Elixir 1.19, supported library OTP majors 27/28/29, and TypeScript
5.0.2 remain supported throughout 1.x. Contributor pins and the checkout OTP
gate are separate from the shipped library requirements.

Consumer examples in the stability and upgrading guides distinguish the
closed error set from open notices and evidence identifiers, partial struct
matching, additive manifest members, fail-closed equivalence claims, and
nonzero harness exits. Public TypeScript output types and packed-consumer
checks enforce that distinction without widening input types.
