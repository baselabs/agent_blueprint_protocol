# ADR: compiled-in extension registry

Status: accepted (2026-08-20); closes the package-boundary
contradiction of record (see below).

## Context

The extension registry could ship as a data file loaded at runtime, or
as compiled-in module data. The package-boundary decision's early draft
listed a registry directory gaining a seat in the Hex archive — a line
that predates the registry decision itself, leaving two contradictory
statements of record.

## Decision

The registry is COMPILED-IN data (module attributes in
`lib/agent_blueprint_protocol/extension_registry.ex`): registry content
is a code release. No registry directory exists, none ships in the
archive, and drift between shipped code and shipped registry is
unrepresentable. A beam-census gate asserts no shipped module touches
the filesystem, which a file-loading registry would violate.

Contradiction closure: the early "package.files gains `priv/registry`"
line is superseded by this decision. The archive's registry-relevant
addition is exactly `docs/protocol.md` (the normative protocol
document) and the previously frozen set; the requirement map records
the reconciliation.

Registry pinning for artifact verification uses `build_identities`
(kind `extension`, digest-exact) — an artifact stays verifiable against
a registry that legitimately gained entries after it was produced. The
registry's own digest is bound into the corpus index, not into
artifacts.

## Consequences

Entry changes (add, promote, deprecate, retire) are owner-made code
changes: changelog-recorded, ADR-recorded, and reviewable as diffs.
Owners register namespaces when real; no placeholder third-party
entries ship. The compiled form also gives the second-language verifier
a stable, corpus-anchored view of registry semantics.

## Amendment 2026-08-23 — owner identity superseded

The original decision published real owner identities (project and
domain names) as first-release registry content. Superseded by user
directive the same release cycle: the package is public, and public
content reveals no internal names. Registry data now uses RFC 2606
example-class values (`com.example.*` namespaces, `Example*` owners,
`example.com` declaration URIs); the real names are banned bytes in the
publish guard. Everything else in this ADR (compiled-in form, digest
binding, state machine) stands unchanged. The 2026-08-23 registry edit
moved `ExtensionRegistry.digest/0`'s pinned value consciously, per the
corpus-registry binding test.
