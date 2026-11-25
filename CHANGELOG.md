# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2026-11-25

### Procedure identity

- Register `io.github.baselabs/procedure` as a critical Deployment Manifest
  extension. The manifest digest covers the declaration and its host-defined
  profile.
- Bind observed instances, builds and committed documents to the Deployment
  and attempt in both verifiers. Reconcile runs the binding stage when the
  critical extension is present.
- Add procedure cases for carrier rejection, signed reconcile and before-send
  and returned-run verification.

### Added

- Expose a canonical digest of the federation mapping rows in Elixir and
  TypeScript. Terminal receipt verification accepts an optional receiver pin
  against the signed compatibility references.
- Add four signed conformance cases covering mapping pin agreement, a
  different digest, legacy verification, and an absent mapping reference.

## [1.1.2] - 2026-11-24

Promotes 1.1.2-rc.3 without changes. The specification cites the IETF SCITT
architecture and the first adopted Internet-Draft on dialog management from the
IETF agentproto working group. The [ARD mapping](docs/ard-mapping.md) pins AI
Catalog v0.9.0. The final-release promotion check lets only inert repository
metadata differ between a candidate and its final release, and every artifact
the release workflows upload sets its own retention.

Library and verifier behavior, protocol revision 1, and verification semantics 4
are unchanged from 1.1.1. The corpus contains 626 cases, digest
`sha-256:uwbwaxugSBQKC_3Byy86_3N-Z6RBCBvW7rP79SGmSLE`; the registry digest is
`sha-256:hreDA2_XbV5J9geMJDDYG5BB42AGkh9jmQ9bqHe8kRk`; the specification digest
is `sha-256:abHJVFEUdUJqDEXhMAPRqd7UzYulY3kgvxRbOlSHKVY`.

## [1.1.2-rc.3] - 2026-11-24

### Fixed

- Every artifact the Publish and Pages workflows upload now sets its own
  retention: one day for artifacts handed to a later job in the same run, and
  seven days for the consumer release assets read after the run. None falls
  back to the repository default.

Library, verifier, specification, corpus, and registry bytes are unchanged
from 1.1.2-rc.2.

## [1.1.2-rc.2] - 2026-11-24

### Fixed

- The final-release promotion check now lets the repository metadata
  `.github/dependabot.yml` and `.github/ISSUE_TEMPLATE/` differ between a
  candidate and its final release. Workflows stay frozen. The release identity
  decision record states the boundary.
- The Publish workflow test rejects local actions and references to `.github/`
  paths.

Library, verifier, specification, corpus, and registry bytes are unchanged
from 1.1.2-rc.1.

## [1.1.2-rc.1] - 2026-11-23

- Cite RFC 9943, the IETF SCITT architecture, in the informative references.
- Describe the IETF agentproto working group's dialog management work and cite
  its first adopted Internet-Draft.
- Pin AI Catalog v0.9.0 in the [ARD mapping](docs/ard-mapping.md).

Library and verifier behavior, protocol revision 1, verification semantics 4,
and the corpus and registry digests are unchanged from 1.1.1. The
specification digest is `sha-256:abHJVFEUdUJqDEXhMAPRqd7UzYulY3kgvxRbOlSHKVY`.

## [1.1.1] - 2026-11-23

Promotes 1.1.1-rc.1 without changes. Published decision records now cover
protocol and product design under numbered file names. The public roadmap is
available in `docs/ROADMAP.md`.

Library and verifier behavior, protocol revision 1, and verification semantics 4
are unchanged from 1.1.0. The corpus contains 626 cases, digest
`sha-256:uwbwaxugSBQKC_3Byy86_3N-Z6RBCBvW7rP79SGmSLE`; the registry digest is
`sha-256:hreDA2_XbV5J9geMJDDYG5BB42AGkh9jmQ9bqHe8kRk`; the specification digest
is `sha-256:kr7Wtl2ZNdTpSBKqBk3xmE57saO9q_Y8T-kmn_S7PKc`.

## [1.1.1-rc.1] - 2026-11-23

### Changed

- Published decision records now cover protocol and product design only, under
  numbered file names; update links to their new paths.
  The public roadmap is available in `docs/ROADMAP.md`.

## [1.1.0] - 2026-11-17

Promotes 1.1.0-rc.5 without changes. Changes since 1.0.1, detailed in the
candidate entries below:

- Revision-specific member vocabularies for Blueprint Core, Deployment Manifest
  and Federation TaskEnvelope in Elixir and TypeScript (1.1.0-rc.1).
- The validity periods of the signing key and the signature are host-owned in
  both verifiers. Every evidence value lists `signature_created_at`,
  `lifecycle_state` and `signature_time_validity` in `not_verified`
  (1.1.0-rc.3). This moves the verification-semantics version from 3 to 4.
  Evidence compared with 1.0.x output differs: reconcile evidence gains
  `signature_time_validity`, and evidence from construction, compatibility
  verification and TypeScript import verification gains all three entries. The
  1.0.x census (`sha-256:0B_9tnAAo05n3bWVvnIPDxFeqEr2XhJoDdaxNJv0_9A`) is
  declared `not_equivalent`. Update stored evidence comparisons as the Upgrading
  guide describes.
- Release verification replays every earlier release census and the signed
  0.8.x golden artifacts through the installed Hex and npm packages, and the Hex
  package runs its own consumer gates without a checkout (1.1.0-rc.3).
- Documentation, examples and consumer commands work as published on HexDocs,
  GitHub and npm, on Linux, macOS and Windows (1.1.0-rc.3 to 1.1.0-rc.5).
- Security maintenance moves from 1.0.x to 1.1.x; the 0.8 transition line
  remains supported.

Protocol revision 1 is unchanged. The corpus contains 626 cases, digest
`sha-256:uwbwaxugSBQKC_3Byy86_3N-Z6RBCBvW7rP79SGmSLE`; the registry digest is
`sha-256:hreDA2_XbV5J9geMJDDYG5BB42AGkh9jmQ9bqHe8kRk`; the specification digest
is `sha-256:kr7Wtl2ZNdTpSBKqBk3xmE57saO9q_Y8T-kmn_S7PKc`.

## [1.1.0-rc.5] - 2026-11-17

### Fixed

- Package and release gates now stream child output or name the command before it starts, so a stalled step is identifiable.

## [1.1.0-rc.4] - 2026-11-17

### Fixed

- Non-runnable Elixir and TypeScript excerpts render as code blocks on HexDocs and GitHub. Their fragment marking is now an invisible comment before a bare-language fence; both package example gates honor it and reject fence suffixes.
- The migration checklist distinguishes verification semantics `3` at 1.0 from `4` in 1.1 and links the upgrade guidance.
- Both TypeScript migration tables distinguish aggregate reports from per-case results and show the CLI command for canonical aggregate-report bytes.
- The signed Blueprint displayed in the example gallery matches its shipped source, including its signature. The gallery now shows the complete Federation TaskEnvelope, and documented example JSON is checked against its named source files.
- The npm README runs the locally installed CLI through a version-pinned `npx` command.
- The external-exchange walkthrough starts its adapter with `node`, copies the corpus with Node, and uses quoting that works on Linux, macOS, and Windows. It explains direct execution without a shell and how to launch Windows batch files. Missing or unstartable adapters now receive a named startup diagnostic while retaining exit `18` (`early_exit`).
- The published TypeScript declarations no longer carry an orphan receiving-context comment.

Protocol revision 1, verification semantics 4, and the specification, corpus, and registry digests are unchanged from 1.1.0-rc.3.

## [1.1.0-rc.3] - 2026-11-16

### Changed

The validity periods of the signing key and the signature are host-owned in
both verifiers. `signature_time_validity` now always appears in
`Evidence.not_verified`, after `signature_created_at` and `lifecycle_state`.
Reconcile never judges creation time, lifecycle state or validity periods; the
host does. Specification section 13 states this. The Elixir
`Evidence.host_owned` type names every host-owned fact, and the TypeScript
`KNOWN_EVIDENCE_SURFACES` gains `signature_time_validity`.

The three time facts are now host-owned in every evidence value, not only in
reconcile's. Evidence from Elixir `Evidence.build/1` and
`Compatibility.verify/2`, and from the TypeScript import verification, now lists
`signature_created_at`, `lifecycle_state` and `signature_time_validity` in
`not_verified`. A consumer that compares that evidence with 1.1.0-rc.2 output
sees these three additional entries.

Specification text that described repository process rather than the protocol
is removed: the foundation transition's trigger list and its list of
capabilities not included, the registration steps in the registry operations
guide, and the notes on repository checks in the three CDDL grammar headers.
The grammar rules are unchanged.

### Added

Release verification replays every earlier release census and the signed 0.8.x
golden artifacts through the installed Hex and npm packages, so a published
package is checked against release history and not only against the source
tree. `scripts/verify_release_packages.exs` runs that replay with the package
gates from a tagged checkout. The Hex package's own
`scripts/consumer_examples.exs` runs the four package gates without a checkout.

The TypeScript verifier is checked against the pinned stock JOSE library for both
Ed25519 algorithm spellings, `EdDSA` and `Ed25519`.

The producer guide and the glossary gain JSON examples, which run as packaged
examples.

### Fixed

Consumer package verification works on Windows. Package documents are found
with the package root as the lookup's working directory, so a temporary path's
backslashes are never read as glob syntax.

Post-publication verification checks out the calling ref. A release run uses
its tag's driver and replay. A manual run can verify any package that ships its
own consumer gates, and the driver names any gate a package lacks.

### Compatibility

Protocol revision 1 is unchanged. The verification-semantics version moves from
3 to 4: reconcile outputs certified under earlier censuses now carry
`signature_time_validity` in `not_verified`. The release claims the 1.1.0-rc.2
census (`sha-256:0B_9tnAAo05n3bWVvnIPDxFeqEr2XhJoDdaxNJv0_9A`) and the
`sha-256:oYnkSmTkHGk4AmZ8Sul99_6KYJUIuj2SN2GZAiT1glw` census `not_equivalent`;
the earlier censuses remain `diverged_by_registry_census`. The corpus contains
626 cases, digest `sha-256:uwbwaxugSBQKC_3Byy86_3N-Z6RBCBvW7rP79SGmSLE`; the
registry digest is unchanged at
`sha-256:hreDA2_XbV5J9geMJDDYG5BB42AGkh9jmQ9bqHe8kRk`; the specification digest
is `sha-256:kr7Wtl2ZNdTpSBKqBk3xmE57saO9q_Y8T-kmn_S7PKc`.

### Security

This project publishes one npm package, `@agent-blueprint-protocol/verifier`.
Install nothing under the unscoped name `agent-blueprint-protocol`: two
placeholder versions published there on 2026-11-03 contained no code and were
withdrawn the same day.

## [1.1.0-rc.2] - 2026-11-15

Library and verifier behavior, the protocol revision, the verification-semantics
version (3), the corpus, the registry and the specification are unchanged from
1.1.0-rc.1. The corpus contains 626 cases, digest
`sha-256:0B_9tnAAo05n3bWVvnIPDxFeqEr2XhJoDdaxNJv0_9A`; the registry digest is
`sha-256:hreDA2_XbV5J9geMJDDYG5BB42AGkh9jmQ9bqHe8kRk`; the specification digest
is `sha-256:GgsMn83Cm0ZjYecBGwiwUy4bqwcKW3zfDzkRQ87yHsw`.

## [1.1.0-rc.1] - 2026-11-15

### Added

Adds revision-specific member vocabularies for Blueprint Core (18), Deployment
Manifest (19), and Federation TaskEnvelope (23) in Elixir and TypeScript, read
from their decoder tables. Unsupported integer revisions and invalid types
return the same typed refusals in both implementations.

Examples ship as installed application resources. Documentation links pin this
release, HexDocs extras resolve to rendered pages, and the public ExDoc footer
remains enabled.

### Changed

Security maintenance moves from 1.0.x to 1.1.x. Consumers on 1.0.x should upgrade to 1.1.x; the 0.8 transition line remains supported.

### Compatibility

Protocol revision 1 and verification-semantics version 3 are unchanged. The corpus
contains 626 cases, digest `sha-256:0B_9tnAAo05n3bWVvnIPDxFeqEr2XhJoDdaxNJv0_9A`;
the registry digest is `sha-256:hreDA2_XbV5J9geMJDDYG5BB42AGkh9jmQ9bqHe8kRk`.
Verification behavior is unchanged. Specification edits correct producer digest insertion instructions, clarify the two valid `as_of` policies, make the foundation inventory self-contained, and repair links and wording. The Deployment grammar and derived JSON Schema now accept exactly `none` with a null age or `required` with a positive integer age in milliseconds, matching both implementations.

## [1.0.1] - 2026-11-12

Promotes 1.0.1-rc.1 without changes. The specification's licensing note is
simplified to the Apache-2.0 license, the Developer Certificate of Origin
sign-off and copyright. The npm README ships the installed-package walkthrough.
Library and verifier behavior, the protocol revision, the verification-semantics
version (3), the corpus and the registry are unchanged from 1.0.0. The corpus
contains 626 cases, digest `sha-256:0B_9tnAAo05n3bWVvnIPDxFeqEr2XhJoDdaxNJv0_9A`; the registry digest is
`sha-256:hreDA2_XbV5J9geMJDDYG5BB42AGkh9jmQ9bqHe8kRk`; the specification digest is
`sha-256:9hm2GIG5FVX4-gGMFeJpVJfK3GMTi1TeePRopSF0r7w`.

## [1.0.1-rc.1] - 2026-11-12

The specification's licensing note is simplified to the Apache-2.0 license, the Developer Certificate of Origin sign-off and copyright.
The npm README now ships the installed-package walkthrough.
Library and verifier behavior are unchanged. The corpus contains 626 cases,
digest `sha-256:0B_9tnAAo05n3bWVvnIPDxFeqEr2XhJoDdaxNJv0_9A`; the registry digest is `sha-256:hreDA2_XbV5J9geMJDDYG5BB42AGkh9jmQ9bqHe8kRk`;
the specification digest is `sha-256:9hm2GIG5FVX4-gGMFeJpVJfK3GMTi1TeePRopSF0r7w`.

## [1.0.0] - 2026-11-11

The 1.0 release of the Agent Blueprint Protocol. It promotes 1.0.0-rc.3
without changes: library and verifier behavior, the protocol revision,
the verification-semantics version (3), the corpus, the registry and the
specification are those of 1.0.0-rc.3. The corpus contains 626 cases,
digest `sha-256:0B_9tnAAo05n3bWVvnIPDxFeqEr2XhJoDdaxNJv0_9A`; the registry
digest is `sha-256:hreDA2_XbV5J9geMJDDYG5BB42AGkh9jmQ9bqHe8kRk`; the
specification digest is `sha-256:jh2uy3FU7ApQmFtPHHK3YY041sDgWrICmS8Hz-LaAGE`.

## [1.0.0-rc.3] - 2026-11-11

The specification no longer names a candidate version in its text. Library and
verifier behavior, the protocol revision, the verification-semantics version
(3), the corpus and the registry are unchanged from 1.0.0-rc.2. The corpus contains
626 cases, digest `sha-256:0B_9tnAAo05n3bWVvnIPDxFeqEr2XhJoDdaxNJv0_9A`; the registry digest is `sha-256:hreDA2_XbV5J9geMJDDYG5BB42AGkh9jmQ9bqHe8kRk`; the specification digest
is `sha-256:jh2uy3FU7ApQmFtPHHK3YY041sDgWrICmS8Hz-LaAGE`.

## [1.0.0-rc.2] - 2026-11-11

Documentation corrections cover the README, npm package README, guides, Livebooks,
and site. The npm package description states the verifier checks. The unused
TypeScript `Context` type is no longer exported; no exported function accepted it.

The shipped registry contains only the protocol's federation registrations:
`io.github.baselabs/federation` (active) and `com.example/federation`
(deprecated), both critical and schema-pinned. Hosts that negotiated the five
earlier product example namespaces supply their own entries through the host
support registry and provide the schema documents they hold. Compiled entries
retain their criticality and schema pins under host overrides. The product
schema and product-specific projection fixture are removed.

The registry digest changes and verification-semantics version is now 3;
protocol revision remains 1. All six prior censuses, covering 0.3.0 through
0.8.4 and 1.0.0-rc.1, are declared `diverged_by_registry_census`. In each,
`negotiation-estate-contract-valid` now denies `extension_unknown_critical`;
the digest-mismatch, schema-absent, and tier-bound cases deny the same code;
the criticality-conflict case becomes valid with the optional body quarantined;
and `extension-resolve-estate-deprecated-retained` changes from a deprecated
notice to unknown-optional quarantine. For 1.0.0-rc.1, the two
`*-deprecated-optional-notice` cases also report unknown-optional quarantine,
and `reconcile-deprecated-optional` changes its extension evidence from
retained to quarantined and removes it from the retained list. All other
prior-census projections remain equivalent. Compatibility replay checks these
changes against the registry difference, including composed imports.

Generic host registrations replace the earlier examples in the current corpus.
The corpus contains 626 cases, including 22 new host lifecycle and schema-pin
cases. Its digest is `sha-256:0B_9tnAAo05n3bWVvnIPDxFeqEr2XhJoDdaxNJv0_9A`;
the registry digest is `sha-256:hreDA2_XbV5J9geMJDDYG5BB42AGkh9jmQ9bqHe8kRk`.

The obsolete verifier runner redirect is removed from the repository and
the standalone archive. The runner contract is `spec/conformance/runner.md`.

## [1.0.0-rc.1] - 2026-11-11

### Breaking

- TypeScript imports use the package root. Previous `dist/verifier/blueprint.js`
  `decode` becomes `decodeBlueprint`; Deployment and federation `decode` become
  `decodeDeployment` and `decodeFederationEnvelope`. Internal `negotiate`,
  `intersect`, signature and compatibility `verify`, corpus `load`, runner
  `run`, and report builders map to root `negotiate`, `intersect`,
  `verifySignature`, `verifyCompatibility`, `loadCorpus`, `runCorpus`,
  `buildReport`, and `buildResultsDocument`. Deep paths no longer resolve;
  public results use `value` and typed `error` members. The TypeScript guide
  lists the complete migration, including artifact `canonicalBytes`.

- All fallible public Elixir operations return `{:error, %Error{}}`.
  Decoder ceilings carry `{:ceiling, key}` in `Error.code`; value-returning
  helpers retain their success form and declare the failure branch.
  Denial details are `nil`, including protected-clamp denials; acknowledged
  clamp results retain their typed evidence.
- Evidence marks unsigned artifacts and skipped observations unverified.
  Typed signature details identify distinct verifying keys; binding details
  list checks performed and skipped. Unverified surfaces are explicit.
- `Signature.verify/2` returns verified signed attributes in both languages.
  Repeated signer key identifiers deny `invalid_constraint` during structure validation.
- Implementation modules and helper functions are hidden from the public API.
- The registry digest changes for the controlled federation registration.
  Verification-semantics version is 2; protocol revision remains 1.

### Changed

- The 1.x evolution contract preserves existing revisions and error codes,
  keeps runtime and compiler floors, and defines additive paths for new
  revisions, profiles, execution versions, and evidence identifiers.
- Detached signatures accept dotted key identifiers under RFC 7797 §5.1.
  Monetary amounts consistently count millionths of a currency unit.
- Federation carriage describes native reconstruction; discovery signature
  envelopes remain distinct. The EU AI Act guide states the enacted dates.
- TypeScript output identifiers are open with known-value constants;
  packed declarations support TypeScript 5.0.2 and newer. Node 26 joins
  the platform matrix while Node 24 remains the runtime floor.

- The specification separates protocol requirements from implementation notes
  and states the byte, grammar, lattice, predicate and schema profiles with
  pinned normative references.

- Byte-error precedence and malformed conformance inputs agree across the
  implementations. Binding evidence requires every descriptor observation
  and a complete age check before reporting those checks verified.
- Dotted key identifiers are accepted in detached signatures.
- Revision 1 accepts `EdDSA` and `Ed25519` protected-header identifiers;
  producers SHOULD emit `Ed25519`. Existing signed bytes remain valid.
- `io.github.baselabs/federation` is active with the existing schema pin.
  `com.example/federation` is deprecated and remains supported throughout
  1.x. Both carrier spellings verify; ambiguous double carriage denies.
- Registration checks MCP metadata key syntax. Artifact namespace decoding
  remains unchanged. Prerelease versions retain their complete identity
  across Hex, npm, release metadata, comparisons, and install instructions.

### Added

- A conformance product: bounded case schemas, a normative runner contract,
  reconcile and predicate cases, canonical certified results, an external
  execution harness and adapters, and unsigned implementation claims.
- A package-root TypeScript library with typed import evidence, exhaustive
  errors, isolated consumer declarations, and its own package README.
- A stability and deprecation policy for both packages on Linux, macOS, and Windows.

- Mixed-order Ed25519 vectors distinguish the required cofactorless equation
  from cofactored verification, without rejecting mixed-order points.
- Corpus cases cover algorithm spellings, duplicate signers, both federation
  namespaces, and effect impact as an obligation.
- Error descriptions distinguish overlapping conditions; evidence explicitly
  names timestamp and lifecycle facts it does not establish.

### Documentation

- Added `architecture.md`, `positioning.md`, `compose-and-sign.md`,
  `handling-errors.md`, `reading-evidence.md`, `verifying-in-ci.md`,
  `verifying-releases.md`, `security-model.md`, and `extensions.md`.
- Added `cheatsheet.cheatmd`; rewrote `examples.md` and expanded `errors.md` and `faq.md`.
- Reworked the Blueprint, Deployment, portability, federation, and
  evidence-commitment concept guides.
- Reworked `producer.md` and `host-integration.md` to link the new how-to guides.
- Merged extension authoring and registry reference material into `extensions.md`.
- Updated the Federation carrier mapping reference.
- Added five standalone Livebook walkthroughs for the tour, producing artifacts, host import,
  extensions and federation, and conformance and attacks. Each notebook runs with persisted
  outputs and is included in the Hex package.

The corpus contains 604 cases, digest
`sha-256:oYnkSmTkHGk4AmZ8Sul99_6KYJUIuj2SN2GZAiT1glw`; registry
`sha-256:d98vF3duE_8P7N5aGLrmaqcj3uSDf0NsI4dzF7bXBDg`.
Prior released verdicts remain equivalent. The
`negotiation-estate-contract-valid` case now projects the
`extension_deprecated` notice for the legacy federation namespace.

## [0.8.4] - 2026-11-10

### Fixed

- Portability checks cover predicate arguments and path segments at every depth
  and every signature key identifier in both implementations.
- Schema evaluation memoizes by schema location, avoiding repeated hashing of
  large enum payloads. Federation reconstruction counts nodes across siblings.
- Malformed host arguments return typed, value-free denials through the
  existing result channels. Direct canonical encoding enforces all structural
  ceilings, including container size, string and key lengths, node count, and
  depth, and rejects non-finite numbers. Producers cannot emit values that
  verifiers refuse to decode.
- Conformance readers require regular files, reject symlinks, and cap the
  entire directory at 1,000 entries and 5,000,000 bytes. Both CLIs state whether
  the corpus matches the release-certified digest without changing report bytes.
- The TypeScript decoder retains all ceilings for partial bounds, rejects
  unknown bounds and lone-surrogate string input, and exposes immutable maxima.
- The installed CLI accepts relative and absolute corpus paths with trailing
  separators, reports help and version with exit 0, and keeps unknown arguments
  at exit 2. Importing the optional corpus entry performs no filesystem access.
- Malformed host arguments and hand-built values deny with the code of the
  first violated rule; no verdict for decoded bytes changes.

The corpus contains 199 cases, digest
`sha-256:305LYavPWYaZP_pYGcZBPploy27btWTyMhiKd7XiRb8`; registry
`sha-256:FG2f38K0hba8tTP7iUaw7vHjgcnN_5F5Mp0v4G6UDVs`; specification digest
`sha-256:YfVuNANOdTyQD2rXtXPbonyguVQBCZQheb9WCv4DR8E`. Protocol revision and
`verification_semantics_version` remain 1.

## [0.8.3] - 2026-11-10

### Fixed: security

- Hostile JSON containing lone surrogate escapes or malformed Unicode escapes
  could raise an exception in the Elixir decoder. Every decode surface now
  returns a value-free denial, matching the independent verifier.
- Hostile input could consume seconds of CPU in both verifiers' portability
  scan. Network URI detection now takes linear work and preserves the
  existing scheme and authority rules.
- The TypeScript verifier treated a non-ASCII space after `://` as the end
  of a network authority, where the reference implementation denies it. Both
  now deny, and corpus cases hold the agreement.
- Hostile member names could crash or mislead the TypeScript verifier through
  prototype-chain lookups. Input-keyed tables and dictionaries now use only
  their own properties, including predicate operators, transport states,
  bounds, recovery operations, extension support, and result comparisons.

The corpus contains 190 cases, digest
`sha-256:SvJLvMwXdYQZBjOrklsQSHQRX8PhxPHOv23C2rmFazQ`; registry
`sha-256:FG2f38K0hba8tTP7iUaw7vHjgcnN_5F5Mp0v4G6UDVs`; specification digest
`sha-256:UDRV0o-JUWvHBZPiODetlEQYHALStnIOlWI4qZKxUcc`. Protocol revision and
`verification_semantics_version` remain 1.

## [0.8.2] - 2026-11-05

### Fixed: documentation

- Correction to an earlier entry: bare `npx agent-blueprint-protocol` and
  `npx verifier` work only where `@agent-blueprint-protocol/verifier` is
  installed. Elsewhere, npx looks the bare name up on the public registry,
  where it is not this project's. Use `npx @agent-blueprint-protocol/verifier`.

### Added: documentation

- A Livebook walkthrough, `docs/livebooks/abp-walkthrough.livemd`, ships in the
  package and on HexDocs. It composes and signs a Blueprint, negotiates
  extensions, binds a Deployment Manifest, reconciles the pair, runs the corpus,
  and demonstrates signature, digest, key, and canonical-byte denials.
- The README opens with a first-verification example, and the TypeScript guide
  with an import example.

### Changed: documentation

- npm kit commands in the README, TypeScript guide, and landing page explain
  how to inspect the published kit version.
- Corrected guides: the Deployment binding check has six ordered stages; the
  echo example has 16 members; the kit has four modes and two bin names; the
  error guide lists the `{:ceiling, key}` decoder-limit family; SECURITY.md
  names the vulnerability-report form. The evidence-commitments guide cites
  AI Act articles 12, 25(4), and 26 and Regulation (EU) 2026/1744, which moved
  the high-risk application dates.
- Removed duplicated sentences from eighteen module docs. The comments
  on small-order keys in `Signature` and the TypeScript verifier now say
  exactly what the backends accept: under the identity key, R = identity
  with S = 0 verifies for every message; under the all-zero key, the
  all-zero signature verifies for about one message in four.
- The errata table's release boundaries now name the recording date
  instead of a concrete version ("every release published before
  2026-10-13 that ships this specification"), so each row stays true and
  accurate at later releases without rewording. The corrections'
  substance is unchanged; the specification digest moves with the
  rewording (the digest covers the whole extracted specification,
  errata included), which is recorded in the release history;
  `verification_semantics_version` stays 1.

This is a documentation-only release; the public API, the registry, and
the corpus are unchanged from 0.8.1, and `spec/protocol.md` is
byte-identical. Corpus: 129 cases, digest
`sha-256:WOZcBfvCW88L6TG_66vxG1fw0QN8cCXrJxveqHgI8a4`; registry
`sha-256:FG2f38K0hba8tTP7iUaw7vHjgcnN_5F5Mp0v4G6UDVs`; specification
digest `sha-256:aBgeih79woOR7YmJ_OBhyFgKU0j2euO-eieJKxLVDeA`.

## [0.8.1] - 2026-10-14

### Fixed

- Strict Ed25519 signature checks: reject small-order or non-canonical
  R and S >= L before verification. `Signature.verify/2` now holds the
  signature's R to the same point rule as the trusted key (canonical
  encoding, on the curve, not small-order) and requires S below the
  group order, before the cryptographic backend is called, so the
  verdict no longer depends on the backend's own checks. These
  rejections deny with the existing `:signature_not_verified`; the
  error vocabulary is unchanged.
- The npm verifier kit applies the same strict rule before
  `node:crypto`. Its public-key check also carried a mistyped digit in
  the curve constant d, so it rejected about half of all honest Ed25519
  public keys with `signature_algorithm_unsupported` where the Elixir
  verifier verifies them; the constant is corrected and re-derived from
  the curve definition in the kit's self-checks.

- The npm verifier kit's key-object cache (one parsed key per raw
  public key) is bounded at 256 entries, evicting the oldest; it grew
  without limit before.
- The npm tarball no longer ships `dist/verifier/self_checks.*`: the
  repository self-check battery reads test data that never shipped, so the packed copy could not run. The kit's documented
  commands (the bin over the embedded corpus, `--corpus`, `--artifact`,
  and the importable modules) are unchanged.

### Changed: corpus and specification

- The conformance corpus grows from 96 to 129 cases, all on
  `signature.verify`. Signature-rule cases: R = the identity with
  S = k*a under an honest key (built by the key holder), each of the
  eight small-order R encodings, five non-canonical R encodings, S = L,
  S = L - 1, and the honest S + L, plus a valid signature under a
  second honest key. Key-rule cases: each of the eight small-order
  keys, a y = p key, an off-curve key, a 31-byte key, a `key_id` with
  no supplied key, the identity key with R = [r]B and S = r (which the
  backend's equation alone accepts), a zero key with an all-zero
  signature, a small-order key with a malformed two-byte signature body
  (envelope parsing comes first: `signature_malformed`), and an unusable
  key beside a good one. Every case whose
  signature decodes to 64 bytes also pins `expected.strict_signature`,
  the strict rule's verdict on those bytes, and both verifiers'
  runners compare their own rule to it, so the agreement sees each
  clause of the rule even where the backend rejects the same bytes.
  Both verifiers agree on every case. The prior censuses (94 cases,
  0.3.0 through 0.5.0; 96 cases, 0.6.0 through 0.8.0) both replay as
  `equivalent`; `verification_semantics_version` stays 1.
- `spec/protocol.md` §6 states the strict R and S rule normatively and
  the exact order of the checks (envelope parsing, then the key facts,
  then the signature rule, then the equation) and that a matched key
  not exactly 32 bytes long is unusable, and two statements now match
  the implementation:
  the signing input is the RFC 7797 input `BASE64URL(JCS(protected))
  || "." || JCS(signed_attributes)`, and a matched key that is not
  usable Ed25519 (small-order included) denies
  `signature_algorithm_unsupported` (`signature_key_unsupported` is
  only for a `key_id` with no supplied key). Both corrections are
  recorded in `spec/errata.md`, as is the `spec/protocol.md` §5 separator table, which
  now lists the extension-schema and extension-registry separators. The conformance
  specification describes these verification rules.

The public API and the registry are unchanged. Corpus: 129 cases, digest
`sha-256:WOZcBfvCW88L6TG_66vxG1fw0QN8cCXrJxveqHgI8a4`; registry
`sha-256:FG2f38K0hba8tTP7iUaw7vHjgcnN_5F5Mp0v4G6UDVs`; specification
digest `sha-256:CsVC7jVvA2ZP0NA6D5_h94A_ryb6F795h7ZpSo66CBA`.

## [0.8.0] - 2026-09-24

### Added

- The release manifest is a versioned public contract (`manifest_version: 2`),
  with verification semantics, digest identity, supported revisions, prior
  census verdicts, and the npm kit identity. The kit embeds the same manifest.
- `priv/release-history.json` maps each manifest-era release to its corpus,
  registry, specification, and verification-semantics identities. Semantics
  version 1 spans the manifest era through this release.
- `Corpus.load_prior_census/1` and TypeScript `--prior-corpus` load each released
  census using its own integrity rules, independently of the current registry
  and applicability floor. Ordinary conformance loading retains those bindings.
- The specification states the semantics/census law and released-identity
  immutability. The upgrading guide separates replay identity from provenance
  metadata. Wire revision, verification semantics, and release identity remain
  independent axes.
- The 0.6.0 corpus change also rotated the golden fixture signature over
  unchanged covered bytes. Its verdicts remain equivalent.

Corpus:
96 cases, digest
`sha-256:vMyREM8ggUqVvGG0y2e4Gf-KmpksJjnx2eF8UjtpVP8`; registry
`sha-256:FG2f38K0hba8tTP7iUaw7vHjgcnN_5F5Mp0v4G6UDVs`; specification
digest `sha-256:yC0gV-zIn8J8bXI5gV0dQyPmgEQgVsH6k7YOlkis37Q`.

## [0.7.1] - 2026-09-16

### Changed

- The Elixir requirement widens from 1.20 to 1.19. The supported OTP set is
  27/28/29. The Hex package does not ship checkout configuration.

The library surface, conformance corpus, registry, and specification are
byte-identical to 0.7.0.

Corpus: 96 cases, digest
`sha-256:vMyREM8ggUqVvGG0y2e4Gf-KmpksJjnx2eF8UjtpVP8`; registry
`sha-256:FG2f38K0hba8tTP7iUaw7vHjgcnN_5F5Mp0v4G6UDVs`; specification
digest `sha-256:UkpTfB07D8H8xxtuqDysU-xIXFCKovkaUn7_aiR-tAs`.

## [0.7.0] - 2026-09-14

### Changed

- The verifier publishes as `@agent-blueprint-protocol/verifier`. The 0.6.0
  package name (`@rjpalermo/agent-blueprint-protocol`) is retired; npm no longer
  serves it. npm and Hex retain the same version.
- The bin gains a `verifier` alias alongside `agent-blueprint-protocol`.

The corpus and registry are unchanged from 0.6.0; the specification digest
changes with the kit identity.

Corpus: 96 cases, digest
`sha-256:vMyREM8ggUqVvGG0y2e4Gf-KmpksJjnx2eF8UjtpVP8`; registry
`sha-256:FG2f38K0hba8tTP7iUaw7vHjgcnN_5F5Mp0v4G6UDVs`; specification
digest `sha-256:UkpTfB07D8H8xxtuqDysU-xIXFCKovkaUn7_aiR-tAs`.

## [0.6.0] - 2026-09-14

### Added

- The npm verifier includes JavaScript, TypeScript declarations, an embedded
  corpus, and a CLI, with zero runtime dependencies and Node.js 24 or newer.
- `--artifact <file>` verifies one JSON file against all three artifact kinds,
  naming the valid kind or each kind's typed denial.
- Consumer guides cover TypeScript, ARD discovery mapping, EU AI Act evidence,
  and derived Blueprint cards. The npm version matches the Hex release.
- Signed and extension-bearing Blueprint examples are byte-exact corpus cases.

### Changed

- The corpus grows from 94 to 96 cases with signed and extension-bearing inputs.

The conformance corpus is 96 cases, digest
`sha-256:vMyREM8ggUqVvGG0y2e4Gf-KmpksJjnx2eF8UjtpVP8`; registry digest
`sha-256:FG2f38K0hba8tTP7iUaw7vHjgcnN_5F5Mp0v4G6UDVs`; specification
digest `sha-256:iBllJ-J8aoWUaYKI7VAqjIfXx9bqwNqWXFO4nxBTCfM`.

## [0.5.0] - 2026-09-12

### Fixed

- Corrected onboarding install pins that named an unsupported release line.
- macOS Finder artifacts are excluded from specification and corpus identity
  walks, preserving identities across platforms.

### Added

- Community support includes issue templates, GitHub Discussions, SUPPORT.md,
  and contribution guidance.
- Quickstart examples decode the shipped echo artifact and round-trip its
  canonical bytes before demonstrating typed denials.
- Host integration examples show protected-clamp denial and acknowledged
  evidence from `reconcile/3`.
- A host-side detached-JWS Ed25519 signing recipe; the package remains verify-only.
- The federation-envelope example and grouped documentation sidebar.

The conformance corpus is unchanged at 94 cases, digest
`sha-256:sg6Fo7p8nZpJDzxFn4dXHBWgbGvEvtOk-7t3m7OT7Yo`; registry digest
`sha-256:FG2f38K0hba8tTP7iUaw7vHjgcnN_5F5Mp0v4G6UDVs`; specification
digest `sha-256:LSSVPdBlOwb844Eg0NQ71ju-sCiBv2_wgRp9RV5Vf0U`.

## [0.4.1] - 2026-08-26

### Fixed: verification posture hardening

- The specification includes a foundation-transition asset inventory.

The conformance corpus is unchanged at 94 cases, digest
`sha-256:sg6Fo7p8nZpJDzxFn4dXHBWgbGvEvtOk-7t3m7OT7Yo`; registry digest
`sha-256:FG2f38K0hba8tTP7iUaw7vHjgcnN_5F5Mp0v4G6UDVs`; specification
digest `sha-256:LSSVPdBlOwb844Eg0NQ71ju-sCiBv2_wgRp9RV5Vf0U`.

## [0.4.0] - 2026-08-26

### Added: examples gallery + minutes-long quickstart

- Complete, byte-exact example artifact pairs with member-by-member annotations.
- A quickstart from dependency setup to verification in `iex`.
- Thirteen adopter guides cover artifacts, extensions, host integration,
  producing, portability, errors, federation, upgrading, and common questions.

The conformance corpus is unchanged at 94 cases, digest
`sha-256:sg6Fo7p8nZpJDzxFn4dXHBWgbGvEvtOk-7t3m7OT7Yo`; registry digest
`sha-256:FG2f38K0hba8tTP7iUaw7vHjgcnN_5F5Mp0v4G6UDVs`.

## [0.3.0] - 2026-08-26

### Added: the specification corpus (normative hardening + governance)

The normative specification is a specification in the standards sense:

- RFC 2119/8174 conformance language throughout (BCP 14 boilerplate,
  MUST/MUST NOT/SHOULD/SHOULD NOT/MAY used where load-bearing), a
  terminology section, and a normative Conformance clause (corpus
  pass + byte-identical report agreement + release identity pinning;
  partial conformance is not conformance).
- Member grammar for all three artifacts (18 Blueprint Core, 19
  Deployment Manifest, 23 Federation TaskEnvelope members) with
  cardinalities, types, constraints, and the pinned failure
  precedence; the full 74-code error semantics table (raised when /
  subject / host action).
- Security considerations with a corpus-traceable threat model; privacy
  considerations as the data-minimization profile with honest limits;
  the positioning boundary (AI Catalog owns discovery + identity +
  attestation; this protocol owns the portable contract layer).
- Normative RFC 8610 CDDL grammars with derived JSON Schemas.
- `spec/registry/registry.json` is the canonical registry source.
- Governance documents cover Apache-2.0 licensing, DCO sign-off, foundation
  transition, registry operations, and errata.
- `priv/release-metadata.json` identifies the specification, package, corpus,
  registry, and corpus index.
- The specification and corpus form a self-contained normative tree.

The conformance corpus is unchanged at 94 cases, digest
`sha-256:sg6Fo7p8nZpJDzxFn4dXHBWgbGvEvtOk-7t3m7OT7Yo`; registry digest
`sha-256:FG2f38K0hba8tTP7iUaw7vHjgcnN_5F5Mp0v4G6UDVs`.

## [0.2.1] - 2026-08-25

### Fixed: public documentation credibility

- README install pin corrected to the current release line (`~> 0.2.1`;
  the previous `~> 0.1.0` excluded every 0.2.x release in Hex
  requirement semantics).
- SECURITY.md's supported-version table names the 0.2.x line (0.1.x is
  no longer supported; upgrade to the current line).
- Changelog citations now use self-contained prose.
- `spec/protocol.md` states the producer surface explicitly in its
  shipped-surface section (`Blueprint.from_value/2`,
  `Deployment.from_value/2`, the per-artifact `content_digest/1` and
  `canonical_bytes/1`), resolving the pointer the producer-surface ADR
  relied on.
- The federation mapping's pinned sources now carry canonical
  repository URLs, each pinned by plain SHA-1 of the served bytes
  (A2A `lf.a2a.v1` line at commit `cfc9d34b`; the MCP Tasks extension
  draft at commit `0d0a6bd4`).
- README install and status guidance is written for external readers.

The conformance corpus is unchanged at 94 cases, digest
`sha-256:sg6Fo7p8nZpJDzxFn4dXHBWgbGvEvtOk-7t3m7OT7Yo`; registry digest
`sha-256:FG2f38K0hba8tTP7iUaw7vHjgcnN_5F5Mp0v4G6UDVs`.

## [0.2.0] - 2026-08-25

### Added: product-extension registration

- The extension registry registers `com.example.platform/estate-contract`
  (owner `ExamplePlatform`, **critical**, active, never promoted), the first
  product-owned critical namespace with an authored schema digest pin, riding
  the `:authored_extensions` validated channel: critical bodies validate
  against a host-supplied schema whose `extension_schema` JCS digest matches
  the registry pin, then thread into `from_value/2` as authored content. The
  schema document covers the asset materialization window (`definition
  {name, version}` + nullable `window_days`) and the objective condition AST
  (leaves `materialization_present` / `materialization_stale` /
  `materialization_count_within`; composites `and`/`or` n-ary, `not` unary),
  hand-tiered as uniform-depth strict tiers because the bounded dialect denies
  `$ref` cycles; portable condition depth is three composite tiers
  (metered complexity 417/512; the single free-form string (`definition.name`) is bounded to 128 bytes by the schema itself, the bound on the authored channel's unscanned surface). See `docs/adr/0009-product-extension-registration.md`.
- The schema document ships as corpus data; the library records its canonical
  schema digest pin.
- The conformance corpus grows 88 → 94 cases: the validated-channel cells
  (valid attach with matching schema, schema absent, digest mismatch,
  criticality conflict, the tier-bound deny) and the deprecated-optional
  retention cell; two new applicability classes (`extension_schema_unavailable`,
  `extension_deprecated_retained`); the floor is now 16 surfaces × 31 classes /
  90 required cells. Corpus digest
  `sha-256:sg6Fo7p8nZpJDzxFn4dXHBWgbGvEvtOk-7t3m7OT7Yo`; registry digest
  `sha-256:FG2f38K0hba8tTP7iUaw7vHjgcnN_5F5Mp0v4G6UDVs`.
- `docs/adr/0008-producer-surface.md` records the producer-surface disposition: the
  documented per-artifact constructors ARE the intended producer surface for
  hosts; the facade stays a verification facade.

### Deprecated

- `com.example.platform/estate` (the placeholder optional namespace) is
  `deprecated`: its payload role (a condition body carried verbatim as a free
  object) is superseded by the schema-validated channel. Optional bodies in
  existing artifacts remain verifiable, retained with a typed
  `extension_deprecated` notice.

### Fixed

- The schema bounds `definition.name` to 128 bytes, including bodies validated
  through the authored-extension channel.
- The TypeScript schema validator now evaluates array `items` with the correct
  schema and instance arguments, matching the Elixir implementation.

### Changed

- The normative protocol header and README introduction were reconciled to the
  live public 0.1.x package state (obsolete pre-publication/release-candidate
  framing removed).

## [0.1.1] - 2026-08-23

### Changed: documentation packaging (no code change)

- The Hex archive and hexdocs now ship the seven architecture decision
  records (`docs/adr`), and `docs/federation-mapping.md` joins the
  hexdocs extras, matching the house packaging convention of the
  published `bounded_authority_protocol` package.
- README restructured to the house convention: Installation directly
  after the introduction, a function-level "What it provides" section,
  and the documentation packaging boundary stated.

## [0.1.0] - 2026-08-23

Initial public release: the Agent Blueprint Protocol, its Elixir
reference implementation, the conformance corpus, and the
second-language verifier.

### Normative documentation

- `spec/protocol.md`: the normative protocol document (ships in the Hex
  archive): artifacts and the closed member registries, bounded bytes
  and the integer window, RFC 8785 canonicalization, domain-separated
  digests, the detached-JWS envelope, evolution and extension rules, the
  compiled registry's first-release entries, the bounds algebra laws,
  the 74-code error vocabulary, the evidence contract, and the
  conformance corpus identity (88 cases at the recorded digest).
- `docs/adr` (repository-side decision records): the seven
  decisions of record:
  the non-authorizing boundary, the detached JWS envelope, the
  two-consumer amendment, deny-default protected-bound clamps, the
  compiled-in registry (closing the package-boundary contradiction of
  record), the federation lanes, and the no-versioning rule.
- README Status and Installation rewritten to the published 0.1.0
  state.

### Second-language verifier

- `conformance/verifier/`: the repo-side TypeScript verifier (Node ≥ 24,
  `node:` builtins only, zero npm runtime deps; never in the Hex archive):
  an independent recomputation of every corpus surface and integrity check,
  with a CLI byte-compatible with the Elixir escript (`--corpus` required;
  exit 0/1/2; report bytes on stdout, no trailing newline).
- The stored detached-JWS vectors are KAT-
  anchored to RFC 8032 §7.1 TEST 1, verified Elixir-signed → node-verified
  in both detached and compact forms.
- `Signature`: small-order key rejection hardened: the identity (order 1)
  and order-2 encodings no longer pass `usable_ed25519_key?`.
- `Federation.decode`: an empty claim value or compatibility identity now
  denies `:invalid_constraint` instead of raising `FunctionClauseError`
  (typed denial replaces the exception).
- `Conformance.Runner`: a malformed observed identity element denies typed
  `:invalid_type` instead of raising.
- Corpus regenerated to 88 cases (digest
  `sha-256:QsRbWGreygTJ0m47csgfpwYtoNId3FbjNP49sK-X-MY`), including two
  obligation-varying intersection cases.

### Conformance corpus subsystem

- `Conformance.{Corpus,Runner,Report,Cli}`: the portable conformance corpus:
  pure loader with the 16×29 applicability floor compiled in, two-directional
  integrity with typed errors (corpus-registry and corpus-digest bindings,
  tamper verbatim-vs-derived audits, vacuous-green refusal), a code-level
  shape-agnostic runner over all 16 surfaces, a JCS report bound to the corpus
  identity, and an escript CLI (`--corpus` required; exit 0/1/2).
- `priv/conformance/`: 86 shipped cases, full-registry goldens (evidence
  members included), RFC 8785 vectors, deterministic key fixtures.
- `ExtensionRegistry.digest/0` (+ the `:extension_registry` digest domain):
  the corpus-registry binding.
- Facade: `canonical_bytes/1` (the named canonicalize gap) and typed
  `negotiate`/`intersect` rims. Decode surfaces deny typed on non-binary
  input (was a `FunctionClauseError` raise).
- Eight new error codes: the seven corpus integrity codes + the recorded
  `:corpus_case_invalid` addition.

### Added

- Federation profile: `AgentBlueprintProtocol.Federation` with
  the 23-member `TaskEnvelope` (one wire member per logical field of the
  protocol's federation seam; decoded through the shared registry engine,
  canonical-before-semantics, cross-field rules, and a per-member
  portability pass where an authority-shaped identity claim denies
  `:nonportable_content`); the lossy-aware A2A/MCP state codecs
  (UNSPECIFIED denies at intake; crossing into MCP denies for
  rejected/submitted/auth_required; cancellation is never a terminal
  receipt); the carrier placement laws for both transports
  (`Task.metadata[a2a_uri]` on A2A, `_meta[namespace]` on MCP; the
  `_meta` key grammar forbids a URI key); `terminal_commitment/1` over
  the seven commitment components; and `verify_commitment/2` with the signature
  BINDING step (the signed content digest must name the receiving
  envelope's covered bytes: an honestly-signed statement naming a
  different digest is evidence over THAT digest), the
  issuer/subject/audience comparison (`:audience_mismatch`), and
  `:federation_terminal_conflict` on any divergence between receipts for
  one task identity. Facade rows `decode_federation_envelope/2` and
  `federation_mapping/0` (the 23-row mapping as data, bijective with the
  envelope's members). Published mapping doc
  `docs/federation-mapping.md` with the pinned live sources, the A2A
  primary / MCP draft-tracking flag and revisit trigger, and the
  ttlMs-is-not-an-execution-bound, AUTH_REQUIRED-is-not-authorization,
  and AgentCard protobuf pre-normalization notes.
- Federation hardening: a
  signature whose signed `purpose` is not `federation-envelope` never
  verifies a federation receipt (the symmetric cross-surface purpose gap, closed
  on this surface; cross-surface signature lifting denied
  `:invalid_constraint`); the receipt's `kid`/`key_id` positions are
  portability-scanned strict (PEM/hex secrets deny
  `:forbidden_portable_value`; the signature blob stays deliberately
  opaque; every honest signature is entropy-dense and never survives
  verification without the key); `terminal_commitment/1` and
  `verify_commitment/2` are total over hand-built structs (typed denials
  replace raises on absent/non-string members and malformed commitment
  spellings); the carrier-reconstruction lane re-imposes the decoder's
  member/item/node/string/depth ceilings and the UTF-8 gate on hand-built
  carrier maps; duplicate regulated markers deny `:invalid_cardinality`.
  Receiver posture documented (purpose pinning, key-ids-as-labels,
  keys-are-not-issuers, replay-is-receiver-policy).
- Federation residual hardening: `Federation.Context` gains
  `issuer_key_sets`: per-issuer key attribution where the receipt's
  claimed (and binding-proven) `issuer` member selects the signature key
  pool, with strictest-wins precedence over the flat pool and deny-all
  for an empty map (cross-attribution now denies by mechanism), and
  `created_after`/`created_before` freshness pins over the SIGNED
  `created_at` (receiver-supplied inclusive window, Z-form double-gated,
  checked after conflict detection so equivocation still reports
  `:federation_terminal_conflict`). Fixes a live crash the adversarial
  pass reproduced: `verify_commitment` with the Context's `keys: nil`
  default raised `FunctionClauseError`; nil/malformed pools now deny
  `:invalid_type` typed. Attribution-miss denials name the issuer
  subject; a value-free structural guard pins every federation denial's
  subject to schema shape with nil detail. Signature-blob opacity ruled
  irreducible in-package (honest signatures are entropy-dense); the
  boundary is shape-checked, never echoed, and never survives
  verification without the key.
- Error vocabulary: `:forbidden_portable_value` is now declared and
  emitted through per-site literals; the federation codes
  `:federation_state_unmappable`, `:federation_mapping_conflict`,
  `:nonportable_content`, `:audience_mismatch`, and
  `:federation_terminal_conflict` declared exactly as emitted.

- Reconcile hardening: the
  composed pass gates non-object artifact roots at the canonical stage
  (typed denial, never a raise); `Reconcile.Inputs` drops the unused
  observed-identities field (the eight-stage pass performs no
  compatibility verification; hosts call `verify_compatibility/2`;
  explicit contract change); the portability stage mirrors each
  artifact's own per-position scan modes (authored schema documents and
  predicate operands, the blueprint's five identifier member tables,
  strict elsewhere) instead of strict-scanning everything; `Evidence
  .build/1` validates every field's shape and denies struct inputs
  typed; compatibility re-asserts the identity manifest's cardinality
  and closed four-member entries, and case-folds range tags (LATEST
  denies like latest); signatures checks carry the entry count as
  detail; the two facade delegates deny typed on malformed
  arguments.
- Reconcile, compatibility, and the evidence record:
  `AgentBlueprintProtocol.Reconcile.reconcile/3`, the one call per
  import, running the pinned stage order canonical → digest →
  negotiation → structure → portability → signatures → bind → bounds,
  each stage reject-or-annotate, never repair, under host-supplied
  `Reconcile.Inputs` (host policy bounds, negotiation support, trusted
  public keys, observed build identities, the protected-clamp posture,
  and the bind-time observations). The signature stage BINDS each
  entry's signed `content_digest` to the artifact's recomputed digest,
  an honestly-signed statement naming a different digest is evidence
  over that digest, not this artifact (`:digest_mismatch`). The
  portability stage runs the direct scans under the authored channel
  re-derived from this import's negotiated critical extensions; the
  structure stage is the registry validation, kept disjoint so both
  guards are independently observable. Every clamp lands as
  `Evidence.clamps` and as a per-bound `:bounds` check carrying the
  `%ClampEvidence{}`. `AgentBlueprintProtocol.Compatibility.verify/2`:
  identity-exact matching of manifest `build_identities` against
  host-observed identities: ranges deny `:compatibility_identity_inexact`
  on both sides, duplicate candidates (including byte-identical
  observations) and duplicated manifest names deny
  `:compatibility_duplicate_entry`, unmatched entries deny
  `:compatibility_entry_missing`, extra observed identities are
  evidence-neutral; `exact?/1` is the public exact-version predicate.
  `AgentBlueprintProtocol.Evidence`, the non-authorizing verification
  record whose `not_verified` is non-empty BY CONSTRUCTION: `build/1`
  unions in the seven host-owned surfaces (tenancy, live_policy,
  authority, effect_ownership, execution, billing, evaluation_truth),
  never replacing them; callers may only add. The facade gains
  `verify_compatibility/2` and `reconcile/3`, and `Error.code` widens
  to carry the `{:ceiling, key}` family.

- Bounds-algebra hardening pass: classification comparison
  moves to the PRODUCT order the meet computes in (ordinal ≤ AND markers
  ⊇); a marker dropped at ANY ordinal is a widening (obligations are not
  tradeable against scope), `widens?` becomes `¬(a ⪯ b)` and so
  fail-closed on every incomparable pair (`{pci}` vs `{phi}` previously
  compared non-widening in both directions), and `narrower` requires both components. The rim is now
  deny-typed everywhere it previously raised on struct-bypass inputs:
  hostile map keys and unknown/extra names deny `:bound_unknown` with the
  CONTAINING surface as subject (never the attacker key; the echo
  channel closes), plain-map markers and marker maps with extra keys deny
  `:bound_value_invalid` at construction and again at `intersect`'s
  revalidation, malformed lifter sub-shapes read as absent (total,
  never-raising), off-lattice envelope strings deny with a constructible
  subject (the error builder itself was a crash site), a string on a
  numeric host bound denies `:invalid_type`, duplicate or extra members
  in hand-built `host_bounds`/`ceilings` objects deny `:invalid_type`
  (decode already enforced both), bound values above the parse profile's
  declared integer magnitude deny, `widens?`/`narrower` never raise on
  forged values (total predicates, fail-closed in the widening
  direction), and `Result.t`'s clamps type resolves its module.
- Bounds algebra: `AgentBlueprintProtocol.BoundsAlgebra`:
  the pointwise narrowest intersection of the Blueprint's declared
  bounds, the Deployment's `host_bounds`, and the host's live policy over
  the closed thirteen-bound vocabulary, with per-family direction
  (scope families narrow at the low end; authority/approval/effect
  narrow at the STRICT end; classification markers are
  retained regulatory obligations whose effective set is the UNION of
  the sources' sets; dropping one is a widening). Protected narrowings never happen silently: under the default
  `:deny` posture they deny `:protected_bound_clamp_denied` carrying
  the field/requested/effective triple; under `:acknowledge` they clamp
  with `acknowledged: true` evidence ALWAYS. Operational narrowings
  emit `ClampEvidence{field, class, unit, requested, effective, source,
  acknowledged}` with `:host` attribution on ties and composites (the
  live policy is the operative constraint), clamps ordered by the
  name-sorted vocabulary. `max_cost` compares within one currency only
  (`:bound_unit_mismatch`, order-free). All three sources must be total:
  an operational absence denies `:missing_ceiling`, a protected absence
  `:bound_source_missing`, under the pinned precedence (source order,
  then numerics → cost → protected, each name-sorted). `widens?/2` is
  fail-closed on incomparable pairs; `Bound.narrower/2` is
  direction-encoded per family and function-total (marker-bearing
  classification is a partial order; the lexicographic
  ordinal-then-marker superset relation). The lifters derive the
  Blueprint side totally (classification is the WIDEST across all five
  declaration sites; approval/authority/impact are the strictest claims
  across capabilities/effects with bottoms for empty arrays; disclosure
  is the identity element `:full`; the Blueprint declares no
  disclosure member) and lift the Deployment from `host_bounds` only
  (`model_policy` and `data_bindings` are not intersection inputs).
  The new `AgentBlueprintProtocol.Error{code, subject, detail}` record
  (typed shape, string subject paths, `detail` only for the
  protected deny) lands with the algebra surface; the facade gains
  `intersect/1`.

### Core surfaces

- Deployment Manifest + binding: the 19-member table
  (re-derived against the protocol's Deployment Manifest definition) on the
  SAME generic engine; `AgentBlueprintProtocol.Deployment` mirrors the
  Blueprint pipeline stage-for-stage (canonical verify → registry
  validation → portability scan → digest comparison) under the
  `:deployment_content` domain, with only the table, the scan's open
  regions (extension bodies, eligibility expressions), and the digest
  domain as deltas. The binding surface: `binds?/2` (digest equality and
  nothing else, against the paired Blueprint's recomputed digest,
  constant-time, total over malformed deployment input) and the six-stage
  `verify_binding/3` with a pinned order: release digest
  (`:deployment_digest_mismatch`), release identity and tool-binding
  completeness (`:binding_incomplete`), mutation/recovery
  (`:no_authoritative_recovery`, the stricter of both operation sources),
  attestation staleness (`:binding_attestation_stale`, future attestations
  deny), and observed rug-pull (`:binding_descriptor_mismatch`); stages
  carrying host observations skip exactly when their inputs are absent.
  Table semantics: `blueprint_release` with a REQUIRED digest;
  exact-only build identities (the range vocabulary, comparators,
  wildcards, `latest`, range spans, denies
  `:compatibility_identity_inexact`; prerelease/build suffixes are exact
  pins); the `as_of` total rule; lifecycle temporal rules
  (`:lifecycle_state_invalid`); `host_bounds` totality over the thirteen
  bound names (structure only; the algebra surface owns the rest); empty
  `allowed_model_roles` valid. Every `adapter_identity`/`profile_identity`
  and every string nested in tool/data/build members is strict-scanned
  (`:forbidden_portable_value` in deployment positions). A signature's
  `purpose` is asserted per artifact (`deployment` here, `blueprint` in
  `Blueprint`; the symmetric cross-surface gap this closes). The extension
  envelope judgment is extracted to `AgentBlueprintProtocol.Extension` so
  both tables carry one definition, and `Negotiation` resolves the
  artifact kind from the digest member so each
  artifact's `required_core_fields` check against its own vocabulary. The
  facade gains `decode_deployment/2`.
- Deployment hardening pass: `verify_binding/3` gains a
  stage-0 shape totality: a non-object root, DUPLICATE root members, or a
  malformed `tool_bindings` entry (shape, operands, digest) denies before
  any cross-artifact judgment, and validated entries thread every later
  stage (malformed bindings were silently discarded); negotiation restores revision-first
  order ahead of the new artifact-kind resolution, which now requires a
  well-formed string digest member (a malformed tag is machinery
  `:invalid_type`); the exact-version detector becomes one total charset
  rule (bare tilde, OR/comma/semicolon lists, and not-equal comparators
  join the denied range vocabulary); `max_attestation_age_ms` is
  shape-guarded (a non-integer bound silently failed to apply);
  scheme-relative network-path references (`//authority/path`) deny in
  every strict scan position; and the portability member-name denylist
  folds kebab/SCREAMING/camel spellings onto one normalized form (the
  normalization lesson swept across the guard family).
- Negotiation + compiled-in extension registry: the
  evolution gate (`AgentBlueprintProtocol.Negotiation`) with the pinned
  internal precedence (revision → required_core_fields → extensions) and
  registry-consistent reason rules for malformed machinery; explicit revision
  SET support (never ranges; a miss denies `:protocol_revision_unsupported`
  in both directions); the three fail-closed required-core-field checks;
  the positional extension state machine (unregistered critical denies,
  unregistered optional QUARANTINES byte-exactly with a notice fact,
  criticality conflict denies for live states before state handling,
  deprecated/retired/reserved cells all decided); critical-body validation
  only against digest-pinned host schemas (`:extension_schema_unavailable`
  / `:extension_schema_digest_mismatch`); and a reserved-semantics
  denylist (bound-shaped member names, camelCase twins included) over ALL
  extension bodies. The registry (`ExtensionRegistry`) is compiled-in
  data that requires no filesystem access,
  carrying the five first-release entries with `com.example/federation`'s schema
  authored in-repo under the new `:extension_schema` digest domain.
  `Blueprint.from_value/2`'s `:authored_extensions` option opens the
  encoded-content carriage channel: negotiation-validated critical bodies
  skip the portability value-shape heuristics (their controls are the
  schema pin and the denylist). The facade gains `negotiate/2`.
- Portability named-encoding closures: the raw-key floor
  drops to 24 decoded bytes (catches AES-128-class hex keys) with hyphenated
  UUIDs exempt by shape in every mode (the spec-pinned honest-limit
  calibration); padded standard base32 (up to six pad chars) joins the
  padded-base64 class; and a colon-chunked hex fingerprint class (the SSH
  fingerprint / EUI form, 24+ decoded bytes) denies while the chunk grammar
  spares tagged content addresses and MAC addresses.
- Blueprint artifact + generic registry engine: the ONE
  table-driven decode/validate engine (`AgentBlueprintProtocol.Registry`)
  parameterized by `AgentBlueprintProtocol.Blueprint.table/0`'s
  18-member field registry (the closed-world Blueprint core member
  table), with the pinned failure precedence
  (unknown member → missing required → type → constraint → cardinality →
  nested → cross-field hooks). `Blueprint.decode/2` runs the fail-closed
  pipeline in order: canonical verify (`:non_canonical_bytes` before any
  semantic read or digest work: the canonicality obligation, digests computed only
  over exact received bytes), registry validation (closed world;
  tag-strict integer typing so a float-tagged window value in an
  integer-typed core field denies `:invalid_type`; the window-float obligation,
  visible only at this layer), the portability scan, then the
  content-digest comparison (`:digest_mismatch`). Also ships
  `AgentBlueprintProtocol.Predicate` (the closed, order-independent
  predicate algebra: grammar validation against declared ports, the
  256-node ceiling, and error-dominant `evaluate/2`), and
  `AgentBlueprintProtocol.Portability` (the never-portable structural
  guard: the 34-name member denylist over the open regions and the
  value-shape denylist (PEM armour, compact JWS, network-authority URIs,
  ≥32-byte clean base64url with the identifier-style exemption) over every
  other string including signature `key_id`). The facade gains
  `decode_blueprint/2`.
- Public Elixir package starter with zero third-party/Hex production
  dependencies.
- Explicit non-authorizing product boundary and release-candidate posture.
- RFC 8785 JSON Canonicalization Scheme (`AgentBlueprintProtocol.Canonicalization`):
  UTF-16 code-unit member sorting, §3.2.2.2 string escaping, hand-written
  ECMA-262 §7.1.12.1 number serialization (byte-exact against every finite
  RFC 8785 Appendix B vector), and `verify/2` decode→re-encode→byte-compare
  interchange enforcement with fail-closed guards for duplicate names,
  invalid UTF-8/lone surrogates, and out-of-bound integers on the encode path.
- Strict unpadded base64url codec (`AgentBlueprintProtocol.Base64Url`):
  RFC 4648 §5 alphabet, RFC 7515 §2 padding-free wire form, and RFC 4648
  §3.3/§3.5 canonicality: padded input, non-alphabet characters, and
  non-canonical pad-bit spellings (which alias the same bytes) all reject
  with value-free reasons.
- Tagged content digests (`AgentBlueprintProtocol.Digest`):
  `"sha-256:<43-char unpadded base64url>"` wire strings over domain-separated
  preimages (`SHA-256(separator || <<0>> || canonical JCS bytes)` under the
  registered domain-separation separators), `from_tagged/1` fail-closed parsing
  (unknown algorithm tag vs malformed body, wrong-length bodies included),
  constant-time `equal?/2`, and `verify_content/3` (parse, then compare;
  divergence denies `:digest_mismatch`). SHA-256 conformance is pinned to the
  FIPS 180-4 known-answer vectors.
- Detached JWS signature envelope (`AgentBlueprintProtocol.Signature`):
  RFC 7515 compact serialization with the RFC 7797 `b64=false` unencoded
  detached payload: the signing input is
  `BASE64URL(JCS(protected_header)) || "." || JCS(signed_attributes)`,
  Ed25519 verified through `:crypto`, with no signing or private-key inputs.
  Host-supplied trusted
  keys match by `key_id` (`:signature_key_unsupported` when absent,
  `:signature_not_verified` on divergence; facts, never authorization).
  The exact four-member protected header (`alg/crit/b64/kid`) and the five
  signed attributes are closed-world with fail-closed, value-free denials;
  `kid` must equal the signed `key_id`, which is dot-free so the unencoded
  payload can never carry `.` (RFC 7797 §5.2). Compact rendering (`h..s`,
  empty payload segment per RFC 7515 Appendix F) supports standard-tooling
  cross-checks. RFC 8032 §7.1 TEST 1 is reproduced byte-exact. Attestations
  share the envelope with a registered `kind` and `statement_digest`; the
  kind registry is empty, so attestations deny `:attestation_malformed`
  today (fail-closed until kinds become data).

### Changed

- Integer window decode rule (the amendment): a pure-digit number lexeme
  above the I-JSON bound ±(2^53−1) now decodes as a float when it is exactly
  that double's canonical ECMAScript serialization (e.g. the RFC 8785
  Appendix B vectors `9007199254740992`, `295147905179352830000`), and
  denies with the new `:number_not_double_expressible` reason otherwise
  (retiring the interim `:integer_magnitude` decode reason). Canonical
  pure-digit float output in [2^53, 10^21) now round-trips `verify/2`; the
  encode/verify asymmetry previously documented here is closed.
- Bounded JSON Schema 2020-12 dialect + instance validator
  (`AgentBlueprintProtocol.Schema`): the closed 16-keyword subset
  (`type properties required items enum const minimum maximum minLength
  maxLength minItems maxItems additionalProperties oneOf $defs` plus
  document-local `$ref`) over the tagged algebra, with everything else
  (`pattern`/`format`/`patternProperties`/`if-then-else`/`allOf`/remote
  `$ref` and the rest of the 2020-12 keyword universe) denying
  `:schema_keyword_not_allowed`. 2020-12 semantics read first-hand and
  pinned: type-targeted assertions auto-pass other types, missing keywords
  never fail, `oneOf` is exactly-one, boolean schemas are the substrate,
  numbers compare by mathematical value across the integer/float tags
  (tag-blind `type:"integer"`; the tags do not survive the wire), object
  equality is order-blind, and string lengths count codepoints (not
  graphemes, not UTF-16 units). Resource posture: complexity metered as
  `nodes + keywords + Σ(branches) + depth × 4` against the 512 profile
  ceiling; evaluation memoized on (schema node, instance location),
  closing the acyclic-`$ref`-DAG exponential blowup for passing AND failing
  instances; document-local RFC 6901 pointers (split-then-unescape, `~1`
  before `~0`) resolve at parse, and application-reachable reference cycles
  deny while dead `$defs` self-references parse. Both `parse/2` and
  `validate_instance/3` are total; malformed tagged shapes deny, never
  raise. Multi-failure reasons follow a fixed canonical keyword order
  (mirrored for the TS verifier).

[Unreleased]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.1.2-rc.3...v1.1.2
[1.1.2-rc.3]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.1.2-rc.2...v1.1.2-rc.3
[1.1.2-rc.2]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.1.2-rc.1...v1.1.2-rc.2
[1.1.2-rc.1]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.1.1...v1.1.2-rc.1
[1.1.1]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.1.1-rc.1...v1.1.1
[1.1.1-rc.1]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.1.0...v1.1.1-rc.1
[1.1.0]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.1.0-rc.5...v1.1.0
[1.1.0-rc.5]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.1.0-rc.4...v1.1.0-rc.5
[1.1.0-rc.4]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.1.0-rc.3...v1.1.0-rc.4
[1.1.0-rc.3]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.1.0-rc.2...v1.1.0-rc.3
[1.1.0-rc.2]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.1.0-rc.1...v1.1.0-rc.2
[1.1.0-rc.1]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.0.1...v1.1.0-rc.1
[1.0.1]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.0.1-rc.1...v1.0.1
[1.0.1-rc.1]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.0.0...v1.0.1-rc.1
[1.0.0]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.0.0-rc.3...v1.0.0
[1.0.0-rc.3]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.0.0-rc.2...v1.0.0-rc.3
[1.0.0-rc.2]: https://github.com/baselabs/agent_blueprint_protocol/compare/v1.0.0-rc.1...v1.0.0-rc.2
[1.0.0-rc.1]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.8.4...v1.0.0-rc.1
[0.8.4]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.8.3...v0.8.4
[0.8.3]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.8.2...v0.8.3
[0.8.2]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/baselabs/agent_blueprint_protocol/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/baselabs/agent_blueprint_protocol/releases/tag/v0.1.0
