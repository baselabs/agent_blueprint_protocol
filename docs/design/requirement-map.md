# Requirement map — every gate and its recorded red proof

A gate without a red proof is not a gate. This map records, for every
build-failing gate the package ships, the exact mutation that reddens it,
the command that observes the red, and the verbatim failing output. All
proofs on this page were re-derived live on **2026-08-23** against the
release-candidate tree, with the CI toolchain entry re-derived on
**2026-08-24** (plant → run → reverse-restore; the restored suite is green:
883 passed, 59 properties, 824 tests).

Structure contract (checked mechanically by `mix release.candidate`):

- one `### alias: <task>` entry per step of the live `quality` alias;
- one `### case: <test description>` entry per test case under
  `test/architecture/` (descriptions are extracted from the test files);
- one `### conformance: <name>` entry per conformance gate;
- every entry carries at least one fenced `red` block containing a command
  line (`$ ` or `mix `) and a failing-output line.

Scope boundary, stated: the property and fuzz lanes are suites, not
build-failing gates — they are covered by the alias `test` entry below and
by their own module suites; per-case red proofs are not owed for them.

## The quality alias lane

The alias as shipped (read live from `mix.exs`; the release-candidate
check re-derives this list, so a step added without a map entry reds):

`hex.audit → deps.unlock --check-unused → deps.audit →
format --check-formatted → compile --warnings-as-errors → credo --strict →
test --cover --seed 42 → conformance.verify → conformance.mutations →
verifier.agreement → dialyzer → docs --warnings-as-errors →
release.candidate`

> Reconciliation of record: the design spec listed the alias as gaining
> `architecture`, `identifiers`, and `package.check` steps. Shipped
> reality: the architecture and identifier gates are test files under
> `mix test` (the whole lane runs there), and the package check is
> `PackageBoundaryTest`'s two assertions plus the installed-corpus smoke
> (including the archive-side corpus verification inside
> `verifier.agreement`). The alias above is the truth; earlier draft
> step names were a pre-implementation sketch. `release.candidate` is a
> deliberate addition of this slice, noted here as such.

### alias: hex.audit

Proves: no dependency version is retired on Hex.

```red
$ python3 - <<'EOF'  # plant: {:plug_crypto, "1.1.1"} added to deps, mix deps.get
$ mix hex.audit
Retired:
  plug_crypto 1.1.1 - (invalid) Wrong default value is used for salt on encrypt
EXIT=1
```

### alias: deps.unlock --check-unused

Proves: the lockfile carries no dependency the project no longer declares
(a stale lock entry is un-attributable build input).

```red
$ # plant: plug_crypto removed from mix.exs deps, kept in mix.lock
$ mix deps.unlock --check-unused
** (Mix) Unused dependencies in mix.lock file:
  * :plug_crypto
EXIT=1
```

### alias: deps.audit

Proves: no dependency version falls in a published security advisory
(elixir-security-advisories DB).

```red
$ # plant: {:phoenix_html, "3.0.3"} added to deps, mix deps.get
$ mix deps.audit
Version: 3.0.3
URL: https://github.com/advisories/GHSA-j3gg-r6gp-95q2
Title: XSS in HEEx class attributes
Severity: moderate
EXIT=1
```

### alias: format --check-formatted

```red
$ # plant: lib/format_probe.ex with `def   spaced(a),do: a`
$ mix format --check-formatted
** (Mix) mix format failed due to --check-formatted.
The following files are not formatted:
... lib/format_probe.ex
EXIT=1
```

### alias: compile --warnings-as-errors

```red
$ # plant: lib/warn_probe.ex with an unused variable
$ MIX_ENV=test mix compile --warnings-as-errors
warning: variable "x" is unused
Compilation failed due to warnings while using the --warnings-as-errors option
EXIT=1
```

### alias: credo --strict

```red
$ # plant: IO.inspect(x) in a lib function body
$ mix credo --strict
┃ [W] ↗ There should be no calls to `IO.inspect/1`.
┃       lib/credo_probe.ex:5:5 #(CredoProbe.f)
EXIT=16
```

### alias: test --cover --seed 42

Proves: the suite passes at a 100% coverage threshold — an untested public
function is a build failure, not a metric dip.

```red
$ # plant: lib/cover_probe.ex — a public, spec'd, never-called function
$ mix test --cover --seed 42
|      0.00% | CoverProbe                                         |
Coverage test failed, threshold not met:
EXIT=3
```

This entry is also the map's anchor for the architecture lane: every
`test/architecture/*_test.exs` case below runs inside this step, and the
conformance-lane in-suite tests (corpus loader integrity, runner agreement,
report determinism, CLI exit codes) run here as well.

### alias: conformance.verify

Proves: the shipped corpus loads, integrity-verifies (per-file hashes,
exact file set both directions, counts, id-uniqueness, applicability
totality), executes, and agrees — 94/0 at the recorded digest.

```red
$ # plant: one byte of a corpus case JSON flipped (duplicate_member -> xuplicate_member)
$ mix conformance.verify
corpus integrity failure: :corpus_case_invalid
EXIT=1
```

### alias: conformance.mutations

Self-proving by construction (`scripts/check_conformance_mutations.exs`):
for each of the seven named mutations the script isolates a scratch copy
of the repo, applies exactly one one-match source mutation, first proves
the UNMUTATED command green in a clean scratch (baseline non-vacuity),
then runs `mix conformance.verify` and raises `mutation survived` if the
corpus stays green. A corpus expectation flip (calibration entry) proves
the gate also observes corpus-side drift.

```red
$ mix conformance.mutations
mutation caught: intersect-min-to-max
mutation caught: duplicate-member-check-removal
mutation caught: utf16-sort-key-drop
mutation caught: padded-base64url-accept
mutation caught: revision-max-plus-one
mutation caught: obligation-meet-min
mutation caught: calibration-corpus-expectation-flip
conformance mutation gate: ok mutations=7
mutation survived: <name>   # the raise form — a mutation that leaves the corpus green
```

The `mutation survived: <name>` raise is the gate's red form — proven live
in the script header's calibration receipt (a command-inverted entry
raised on 2026-08-23; restored).

### alias: verifier.agreement

Self-proving by construction (`scripts/check_verifier_agreement.exs`):
byte-compares the escript and TypeScript verifier reports over the repo
corpus AND the built Hex archive's corpus, runs the TS self-check battery,
then runs three seeded reds — scratch-copy mutations of the verifier, each
directional and asserted to have caused the expected divergence; a seed
that fails to diverge raises (vacuous-seed guard, calibration-receipted
2026-08-23).

```red
$ mix verifier.agreement
agreement: repo corpus byte-identical
agreement: archive corpus byte-identical
self-checks ok (112)
seeded red fired: verdict-comparison-inverted
seeded red fired: calibration-report-format-drift
seeded red fired: window-check-deleted
verifier agreement gate: ok
report byte drift (repo corpus)   # the raise form — any byte divergence
seeded red did not diverge        # the vacuous-seed guard
```

Red forms: `report byte drift (repo corpus|built archive)` on any byte
divergence, and `seeded red did not diverge` on a vacuous seed.

### alias: dialyzer

```red
$ # plant: lib/dialyzer_probe.ex — @spec f(integer()) :: integer() whose body returns a string
$ mix dialyzer
Break ... DialyzerProbe.f/1
Success typing: (_) :: none()
done (warnings were emitted)
Halting VM with exit status 2
EXIT=2
```

### alias: docs --warnings-as-errors

```red
$ # plant: @doc "See [`f/1`](DocProbe.unknown_thing/9)." — a broken doc reference
$ mix docs --warnings-as-errors
warning: documentation references file "DocProbe.unknown_thing/9" but it does not exist
EXIT=1
```

### alias: release.candidate

The release-candidate check (this map's mechanical backer). Red forms and
their proofs are recorded in `docs/adr/`-adjacent entries below; the two
acceptance reds of the slice:

```red
$ # plant M3: one architecture-case entry removed from this map
$ mix release.candidate
requirement-map: missing entry for case: "no shipped module/function/atom carries a version token"
EXIT=1
$ # plant M4: "spec/protocol.md" dropped from package.files
$ mix release.candidate
release candidate: spec/protocol.md missing from package.files
EXIT=1
reprove caught: publish-guard-toolpath-plant   # the M1-M4 acceptance plants
reprove caught: spec-coverage-undocumented-fn  # are replanted in scratch copies
reprove caught: map-entry-removal              # EVERY run — a plant that stays
reprove caught: protocol-doc-dropped-from-package
reprove survived: <name>   # the raise form — a vacuous plant (calibration-proven)
```

The release identity chain (priv/release-metadata.json) is asserted from
live state on every run — the specification digest over the working-tree
spec/ files, the package version, the corpus and registry digests, the
corpus index hash, the verifier runtime floor, and the
archive-authorization stance; the file is never trusted:

```red
$ # plant: one identity-chain link tampered (the format field)
$ mix release.candidate
release candidate: FAILED
identity chain: format is "tampered-release-metadata" — the live value is "agent-blueprint-protocol-release-metadata"EXIT=1
```

```red
$ # plant: a specification file edited without regenerating the metadata
$ mix release.candidate
release candidate: FAILED
identity chain: spec_digest is "sha-256:SystAAJPBzc8Uhbaoih3PT9-1cEwdyiW1V0Fu12aChY" — the live value is "sha-256:6xyHdg2qFDEJMRUVQnnw9UEWWHoHR_XG26O2Tq9Pgmk"EXIT=1
```

```red
$ # plant: a second copy of the normative document at docs/protocol.md
$ mix release.candidate
release candidate: FAILED
release candidate: docs/protocol.md exists — the normative document is spec/protocol.md; a second copy redsEXIT=1
```

### alias: spec.extraction

The specification-extraction check: spec/ + priv/conformance extract as a
standalone tree that renders with no dangling references. The local form
copies the working tree's two paths into a scratch; the CI workflow runs
the literal repository-filter extraction (`git filter-repo --path spec/
--path priv/conformance`) and re-runs the same script with `--tree` over
the result. Links resolve relative to their containing document INSIDE
the extracted tree; named section citations must name a pinned external
standard or an in-tree document; no `../` or `docs/` path literal may
appear in the specification's markdown.

```red
$ # plant: a repository-relative citation in spec/README.md
$ mix spec.extraction
spec extraction: FAILED
dangling reference: spec/README.md links ../docs/design/requirement-map.md, which is absent from the extracted treeEXIT=1
```

```red
$ # organic red during the founding: a path literal left in the moved document
$ mix spec.extraction
spec extraction: FAILED
self-containment: spec/protocol.md carries the path literal "docs/" — a repository-relative reference that dangles post-extractionEXIT=1
```

## The architecture lane

Every test case under `test/architecture/`, with its plant and failing
output. Plants marked *(dead-code note)* needed a reachable public probe:
the Elixir compiler eliminates never-called private functions, so
beam-census plants must be public (that elimination is itself load-bearing
for the census gates — a private dead function cannot smuggle a call).

### case: "the quality job selects an immutable supported Node runtime"

```red
$ # plant: remove the setup-node step from the quality job
$ mix test test/architecture/ci_node_toolchain_test.exs
the quality job must pin the setup action and the supported Node release
Result: 0/1 passed
$ # plant: replace Node 24.19.0 with the runner's ambient Node 22.23.2
$ mix test test/architecture/ci_node_toolchain_test.exs
the quality job must pin the setup action and the supported Node release
Result: 0/1 passed
$ # plant: add a second setup-node step for Node 25.9.0 before mix quality
$ mix test test/architecture/ci_node_toolchain_test.exs
the quality job must select Node exactly once
Result: 0/1 passed
```

The verifier floor is independently live: placing an executable that reports
`v22.23.2` first on `PATH` makes `mix verifier.agreement` fail with
`node 22 ... is below the >= 24 requirement`.

### case: "the byte loop is exactly tail-accumulate with a single final test"

```red
$ # plant: xor_zero?/3 recursive clause gains an early exit (a == b and ...)
$ mix test test/architecture/constant_time_compare_shape_test.exs
code:  assert {:xor_zero?, _, [...]} = recursive
Result: 1/2 passed
```

### case: "equal? reaches the digest bytes only through the accumulating loop"

```red
$ # plant: equal?/2 compares bytes directly (b1 == b2), bypassing xor_zero?
$ mix test test/architecture/constant_time_compare_shape_test.exs
code:  assert :xor_zero? in calls
Result: 1/2 passed
```

### case: "deployment.ex delegates validation to the generic engine"

```red
$ # plant: both `:ok <- Registry.validate(table(), value),` steps replaced with `:ok <- :ok,`
$ mix test test/architecture/deployment_engine_shape_test.exs
Deployment must validate through Registry.validate — no second pipeline
Result: 1/2 passed
```

### case: "deployment.ex defines none of the engine's stage functions locally"

```red
$ # plant: defp type_check(_v, _c), do: :ok added to deployment.ex
$ mix test test/architecture/deployment_engine_shape_test.exs
deployment.ex locally defines engine stage functions ["type_check"] — the engine's pinned precedence must not be forked
Result: 1/2 passed
```

### case: "every code position is built only from declared literals (per-site rule)"

```red
$ # plant: a public function returning %Error{code: :probe_undeclared_code}
$ mix test test/architecture/error_vocabulary_gate_test.exs
undeclared or dynamically-constructed code positions:
  lib/agent_blueprint_protocol/base64url.ex: undeclared [:probe_undeclared_code] family []
Result: 2/3 passed
```

### case: "every declared code is emitted somewhere (dead vocabulary reds)"

```red
$ # plant: :probe_dead_code added to the @codes list
$ mix test test/architecture/error_vocabulary_gate_test.exs
declared but unemitted: [:probe_dead_code] / family keys []
Result: 2/3 passed
```

### case: "the ceiling family's keys are exactly the decoder limit names (Bounds' field set)"

```red
$ # plant: :probe appended to @ceiling_keys
$ mix test test/architecture/error_vocabulary_gate_test.exs
code:  assert Enum.sort(Error.ceiling_keys()) == Enum.sort(bounds_fields)
Result: 1/3 passed
```

### case: "mapping rows and envelope members are bijective"

```red
$ # plant: mapping row 2's logical field renamed to duplicate row 1's
$ mix test test/architecture/federation_shape_test.exs
1) test mapping rows and envelope members are bijective
Result: 8/9 passed
```

### case: "verdict counts are the live-re-derived 3 native / 5 partial / 15 extension"

```red
$ # plant: row 1's verdict flipped :native -> :partial
$ mix test test/architecture/federation_shape_test.exs
code:  assert counts == %{native: 3, partial: 5, extension: 15}
left:  %{native: 2, extension: 15, partial: 6}
Result: 8/9 passed
```

### case: "every row carries both transport locations"

```red
$ # plant: row 1's a2a_location blanked
$ mix test test/architecture/federation_shape_test.exs
1) test every row carries both transport locations
Result: 8/9 passed
```

### case: "federation.ex delegates validation to the generic engine"

```red
$ # plant: both `:ok <- Registry.validate(table(), value),` steps replaced with `:ok <- :ok,`
$ mix test test/architecture/federation_shape_test.exs
Federation must validate through Registry.validate — no second pipeline
Result: 8/9 passed
```

### case: "federation.ex defines none of the engine's stage functions locally"

```red
$ # plant: defp type_check(_v, _c), do: :ok added to federation.ex
$ mix test test/architecture/federation_shape_test.exs
code: assert shadowed == [],
Result: 8/9 passed
```

### case: "delegates to Federation.decode with default bounds"

```red
$ # plant: facade's decode_federation_envelope/2 returns {:ok, bytes} directly
$ mix test test/architecture/federation_shape_test.exs
** (FunctionClauseError) no function clause matching in Federation.canonical_bytes/1
Result: 6/9 passed
```

### case: "tightened bounds delegate through"

```red
$ # plant (same full bypass as above): facade stops delegating
$ mix test test/architecture/federation_shape_test.exs
1) test tightened bounds delegate through / non-binary rims deny :invalid_type
Result: 6/9 passed
```

### case: "non-binary rims deny :invalid_type"

```red
$ # plant: non-binary inputs fall through a bypass clause returning {:ok, :bypassed}
$ mix test test/architecture/federation_shape_test.exs
right: {:ok, :bypassed}
Result: 8/9 passed
```

### case: "delegates to Federation.mapping"

```red
$ # plant: facade's federation_mapping/0 returns []
$ mix test test/architecture/federation_shape_test.exs
code:  assert AgentBlueprintProtocol.federation_mapping() == Federation.mapping()
Result: 8/9 passed
```

### case: "no shipped module/function/atom carries a version token"

```red
$ # plant: defp v2_probe(x), do: x in a shipped module
$ mix test test/architecture/identifier_naming_test.exs
code: assert offenders == [],
Result: 1/2 passed
```

### case: "no shipped path segment carries a version token"

```red
$ # plant: lib/v1_probe.ex created
$ mix test test/architecture/identifier_naming_test.exs
version tokens found in shipped paths (forbidden in shipped names): ["v1_probe"]
Result: 1/2 passed
```

### case: "the carve-out modules exist (a deleted CLI with a kept carve-out reds)"

```red
$ # plant: conformance/cli/main.ex moved away
$ mix test test/architecture/no_file_access_test.exs
expected Elixir.AgentBlueprintProtocol.Conformance.Cli.Main.beam to exist — the carve-out must track reality
Result: 2/3 passed
```

### case: "no shipped beam outside the CLI carve-out makes any File remote call"

*(dead-code note)*

```red
$ # plant: a public, spec'd File.read! probe in base64url.ex
$ mix test test/architecture/no_file_access_test.exs
1) test no shipped beam outside the CLI carve-out makes any File remote call
Result: 2/3 passed
```

### case: "the CLI carve-out contains no filesystem calls BEYOND read-side traversal"

```red
$ # plant: main/1 calls a File.write! helper before delegating
$ mix test test/architecture/no_file_access_test.exs
the CLI carve-out is read-only: [{"...Cli.Main.beam", File, :write!}]
Result: 2/3 passed
```

### case: "no shipped identifier carries authorization-decision vocabulary"

```red
$ # plant: def authorize_import(x), do: x in a shipped module
$ mix test test/architecture/non_authorizing_vocabulary_test.exs
code: assert offenders == [],
Result: 0/1 passed
```

### case: "package.files declares exactly the allowlisted entries"

```red
$ # plant: "docs/probe-drift.md" added to package.files
$ mix test test/architecture/package_boundary_test.exs
code:  assert Mix.Project.config()[:package][:files] == @declared_files
Result: 0/2 passed
```

### case: "the quality alias carries the minimum gate set"

The release-candidate check derives map obligations from the LIVE
alias — this freezes the floor so deleting a gate step cannot silently
delete its map requirement.

```red
$ # plant: "dialyzer" removed from the quality alias
$ mix test test/architecture/package_boundary_test.exs
quality alias lost gate steps (each step owes a requirement-map entry): ["dialyzer"]
Result: 2/3 passed
```

### case: "the built Hex archive ships exactly the allowlist, both directions"

```red
$ # plant: lib/rogue_probe.ex created (compiles, ships via the lib glob)
$ mix test test/architecture/package_boundary_test.exs
unexpected (contaminant leaked into the package): ["lib/rogue_probe.ex"]
Result: 1/2 passed
```

The same test performs the installed-package smoke (unpack the built
archive, feed every shipped corpus file to the loader, run the runner,
assert agreement) — red via any corpus-file corruption at build time,
exercised every run.

### case: "every declared package file exists"

```red
$ # plant: a declared entry with no file behind it
$ mix test test/architecture/publish_guard_test.exs
package.files declares entries that resolve to nothing: ["docs/no-such-probe.md"]
Result: 4/5 passed
```

### case: "no archived path is a symlink"

The built archive preserves symlinks as target-path strings the content
scan can never see — the guard reds on any symlinked path outright.

```red
$ # plant: lib/.symlink_probe -> /etc/hosts
$ mix test test/architecture/publish_guard_test.exs
publish-guard violation: a shipped path is a symlink (the archive would carry the target path itself):
Result: 3/4 passed
```

### case: "every archived file is tracked"

```red
$ # plant: create lib/archive_tracking_probe.ex after the source index is recorded
$ mix test test/architecture/publish_guard_test.exs
publish-guard violation: an untracked file would ship in the archive:
  lib/archive_tracking_probe.ex
Result: 7/8 passed
```

### case: "no archived file carries a private-path byte pattern"

Decided-red acceptance of this slice (M1):

```red
$ # plant: "See .kimosabe/handoffs for design history." appended to README.md
$ mix test test/architecture/publish_guard_test.exs
publish-guard violation: a shipped file carries a private path:
  README.md: .kimosabe
  README.md: kimosabe/
EXIT=2
```

### case: "no archived text file carries an internal reference"

Natural red at gate birth (the tree carried real internal references):

```red
$ # no plant: the 2026-08-23 tree as it stood before the scrub
$ mix test test/architecture/publish_guard_test.exs
publish-guard violation: a shipped text file references internal material:
  lib/agent_blueprint_protocol/reconcile.ex: /\b(ticket|issue)\s+00\d\d/ [["ticket 0011", "ticket"]]
  CHANGELOG.md: /(?<![+x])\b0\d{3}\b/ [["0017"], ["0005"], ["0013"]]
  lib/agent_blueprint_protocol/federation.ex: /\bbofn\b/ [["bofn"]]
  lib/agent_blueprint_protocol/signature.ex: /\bspec D\d/ [["spec D3"]]
EXIT=2
```

This map stays repository-side BY DESIGN and ships in no Hex archive:
its fenced `red` receipts are verbatim gate output quoting the very
tokens the publish guard bans (the catch is the evidence), so archiving
the map reds that guard outright — recorded here as the boundary's own
red proof:

```red
$ # no plant: docs/design/requirement-map.md added to package.files
$ mix test test/architecture/publish_guard_test.exs
publish-guard violation: a shipped text file references internal material:
  docs/design/requirement-map.md: /(?<![+x])\b0\d{3}\b/ [["0011"], ["0017"], ["0005"]]
  docs/design/requirement-map.md: /\b(ticket|issue)\s+0\d{3}/ [["ticket 0011", "ticket"]]
  docs/design/requirement-map.md: /\bkimosabe\b/ [["kimosabe"], ["kimosabe"], ["kimosabe"]]
Result: 7/8 passed
```

### case: "tracked files and reachable history contain no consumer-specific topology"

```red
$ # natural red: run before the current tree and seven reachable commits were scrubbed
$ mix test test/architecture/public_surface_privacy_test.exs
1) test tracked files and reachable history contain no consumer-specific topology
code: assert result == {0, false, false, false, false}
Result: 3/4 passed
```

### case: "candidate normalization is red-capable without publishing protected terms"

```red
$ # plant: corrupt the generic test-canary digest
$ mix test test/architecture/public_surface_privacy_test.exs
1) test candidate normalization is red-capable without publishing protected terms
code: assert forbidden?(@test_canary, test_hmacs, @test_key)
Result: 3/4 passed
```

### case: "invalid UTF-8 is handled deterministically"

```red
$ # plant: make invalid-byte normalization raise
$ mix test test/architecture/public_surface_privacy_test.exs
1) test invalid UTF-8 is handled deterministically
code: refute forbidden?(<<255, 254, 0, 1>>)
Result: 3/4 passed
```

### case: "Git plumbing detects tracked, historical, merge, ref-name, and tag violations"

```red
$ # plant: remove the raw-object override while replacement refs are active
$ mix test test/architecture/public_surface_privacy_test.exs
1) test Git plumbing detects tracked, historical, merge, ref-name, and tag violations
code: assert scan_repo(repo, test_hmacs, @test_key) == {1, false, true, false, false, false}
Result: 3/4 passed
```

### case: "README and SECURITY.md name the current released version"

Documentation-currency gate: the README install requirement pins the
exact current version (every hex requirement string in README is an
install pin and must name it), and SECURITY.md's supported-version
table opens with the current `major.minor` line marked supported (a
stale first row — wrong line, or the right line marked no — reds). The
version is read live from `mix.exs`, never frozen.

```red
$ # organic red: README pin left at the 0.1 line while the project is at 0.2.1
$ mix test test/architecture/documentation_currency_test.exs
1) test README and SECURITY.md name the current released version
README install requirement is stale: ["\"~> 0.1.0\""] — the current version is 0.2.1
code: assert Enum.uniq(pins) == ["~> " <> version],
Result: 2/3 passed
```

```red
$ # plant: bogus first data row inserted above the current line
$ mix test test/architecture/documentation_currency_test.exs
1) test README and SECURITY.md name the current released version
SECURITY.md supported table's first row must be the 0.2.x line marked yes (got {"0.0.x", "no"})
Result: 2/3 passed
```

### case: "the CHANGELOG entry for the current version carries the corpus identity"

The changelog's FIRST version heading must be the current release (a
stale top entry reds), and that entry must carry the live corpus digest
and the case total from `priv/conformance/index.json` — every release
names the conformance identity it ships.

```red
$ # plant: current entry's heading renamed — no entry names the live version
$ mix test test/architecture/documentation_currency_test.exs
1) test the CHANGELOG entry for the current version carries the corpus identity
CHANGELOG.md's first entry is "0.2.1-unreleased" — the current release entry (0.2.1) must open the changelog
code: assert first == version,
Result: 1/2 passed
```

```red
$ # plant: stale placeholder entry inserted above the current one
$ mix test test/architecture/documentation_currency_test.exs
1) test the CHANGELOG entry for the current version carries the corpus identity
CHANGELOG.md's first entry is "0.0.0" — the current release entry (0.2.1) must open the changelog
code: assert first == version,
Result: 1/2 passed
```

### case: "README count claims match the live test tree and corpus index"

Every numeric claim in README — test totals, property totals, corpus
case counts (`94-case` and `N cases` forms), and the coverage
percentage — must match the live census (test/property macros across
the test tree), the corpus index, and the configured coverage
threshold. A README that stops making a claim reds as stale.

```red
$ # organic red: README still states the previous release's suite total
$ mix test test/architecture/documentation_currency_test.exs
1) test README count claims match the live test tree and corpus index
README test count claims ["899"] — the live value is 845
code: assert_claim(readme, ~r/\b(\d+) tests\b/, live_test_count(), "test count")
Result: 1/2 passed
```

### case: "named section citations name a shipped document or a pinned standard"

Document-citation gate: across every markdown file the package ships,
a named section citation (`A2A §7.6.4`, `ECMA-262 §7.1.12.1`) must name
a pinned external standard or another document in the SHIPPED set — a
citation of a repo-only document (unshipped) or a nonexistent one reds
equally. Bare section numbers and requirement numbers after a
standard's designation inherit their target from surrounding prose and
stay unchecked.

```red
$ # organic red: two changelog entries cited an internal working document as "base §6" / "base-§8.2"
$ mix test test/architecture/document_citation_gate_test.exs
1) test named section citations name a shipped document or a pinned standard
a shipped document cites a document that exists nowhere:
  CHANGELOG.md: "base §…" names no shipped document or standard
code: assert offenders == [],
Result: 0/1 passed
```

```red
$ # plant: a shipped doc citing a repo-only (unshipped) document by name — requirement-map §3 in docs/protocol.md
$ mix test test/architecture/document_citation_gate_test.exs
1) test named section citations name a shipped document or a pinned standard
a shipped document cites a document that exists nowhere:
  docs/protocol.md: "requirement-map §…" names no shipped document or standard
Result: 0/1 passed
```

### case: "shipped markdown links resolve to real files"

Every markdown link target without a scheme must resolve, relative to
the directory of the document containing it (markdown link semantics),
to a file in the repository, as must every GitHub blob/tree URL into
this repository (those are root-relative); other URLs and pure anchors
are external and unchecked.

```red
$ # plant: "See [the internals note](docs/internals-note.md) and internals §12" appended to README
$ mix test test/architecture/document_citation_gate_test.exs
1) test shipped markdown links resolve to real files
a shipped document links to a file that does not exist:
  README.md: docs/internals-note.md resolves to no file in this repository
code: assert offenders == [],
2) test named section citations name a shipped document or a pinned standard
a shipped document cites a document that exists nowhere:
  README.md: "internals §…" names no shipped document or standard
Result: 0/2 passed
```

```red
$ # plant: a file-relative dangling link inside a nested doc (docs/protocol.md → adr/nonexistent-doc.md);
$ # # the VALID file-relative link adr/producer-surface.md on the same line stays green (containing-dir resolution)
$ mix test test/architecture/document_citation_gate_test.exs
1) test shipped markdown links resolve to real files
a shipped document links to a file that does not exist:
  docs/protocol.md: adr/nonexistent-doc.md resolves to no file in this repository
Result: 0/1 passed
```

### case: "no code file carries an internal tracker citation"

Repo-side citation gate (lib/ + test/ + scripts/ + the TypeScript
verifier tree): the working tree's code files stay free of tracker
numerals, internal planning shorthand, internal design-note question
identifiers, and internal review-process vocabulary so a public
transition of the repository inherits no remediation debt. The publish guard covers the shipped archive; this covers the
tree. The guard's and this gate's own pattern blocks are exempt by
name (they name what they ban).

```red
$ # plant: "# see 0016 for the original red" appended to test/property/evidence_property_test.exs
$ mix test test/architecture/internal_citation_gate_test.exs
internal citation found in a code file (the repo must stay citation-free so a public transition needs no scrub):
  test/property/evidence_property_test.exs: /(?<![+x.{])\b0\d{3}\b/ [["0016"]]
Result: 0/1 passed
```

```red
$ # widened-arm red (planning prose "slice" at six real sites, captured before the scrub)
$ mix test test/architecture/internal_citation_gate_test.exs
internal citation found in a code file (the repo must stay citation-free so a public transition needs no scrub):
  scripts/generate_conformance_corpus.exs: slice-pattern [["this slice's"]]
  test/agent_blueprint_protocol_test.exs: slice-pattern [["owning slice"]]
Result: 0/1 passed
```

```red
$ # TS-root red: planted conformance/verifier/planted_probe.ts carrying review vocabulary
$ mix test test/architecture/internal_citation_gate_test.exs
internal citation found in a code file (the repo must stay citation-free so a public transition needs no scrub):
  conformance/verifier/planted_probe.ts: review-vocabulary-pattern [["cross-vendor"]]
Result: 0/1 passed
```

### case: "every public function has a matching @spec"

Natural red at gate birth (one real gap) plus decided-red acceptance (M2):

```red
$ # no plant: the 2026-08-23 tree as it stood
$ mix test test/architecture/spec_coverage_test.exs
spec-coverage violation: public functions without a matching @spec:
  lib/agent_blueprint_protocol/extension_registry.ex: ... def federation_schema/0
$ # plant M2: def undoced_helper(x), do: x added to base64url.ex
$ mix test test/architecture/spec_coverage_test.exs
spec-coverage violation: public functions without a matching @spec:
  lib/agent_blueprint_protocol/base64url.ex: ... def undoced_helper/1
EXIT=2
```

### case: "no use or unquote-generated public surface hides from the static walk"

`use` injects public surface the unexpanded AST never sees; an
`unquote` head is a generated name the walk cannot enumerate. Neither
may exist under lib/.

```red
$ # plant: `use Bitwise` in a shipped module
$ mix test test/architecture/spec_coverage_test.exs
spec-coverage violation: generated public surface in lib/ is invisible to the static walk (no macros, no use, no unquote heads):
  lib/agent_blueprint_protocol/base64url.ex: use
Result: 2/3 passed
```

### case: "every shipped module has a real moduledoc stating the boundary"

Natural red at gate birth — 39 shipped modules (nested submodules
included) carried no stance-assertive sentence; each gained an honest
boundary line in this slice.

```red
$ # no plant: the 2026-08-23 tree as it stood
$ mix test test/architecture/spec_coverage_test.exs
spec-coverage violation: modules whose moduledoc is missing, false, or states no non-authorizing boundary:
  lib/agent_blueprint_protocol/base64url.ex: AgentBlueprintProtocol.Base64Url
  ... (39 modules)
EXIT=2
```

### case: "no OTP application callback / supervision tree is registered"

```red
$ # plant: mod: {NonexistentSupervisor, []} added to application/0
$ mix test test/architecture/purity_test.exs
application/0 must not register a :mod callback — the package has no supervision tree
Result: 2/3 passed
```

### case: "extra_applications lists only the vetted OTP applications"

```red
$ # plant: :ssl added to extra_applications
$ mix test test/architecture/purity_test.exs
Result: 2/3 passed
```

### case: "every dependency is dev/test-only and non-runtime (zero third-party prod deps)"

```red
$ # plant: stream_data's only/runtime flags dropped
$ mix test test/architecture/purity_test.exs
Result: 2/3 passed
```

### case: "registry.ex's beam never references a domain module"

*(dead-code note)*

```red
$ # plant: a public, spec'd probe calling AgentBlueprintProtocol.Blueprint.table()
$ mix test test/architecture/registry_engine_shape_test.exs
Result: 0/1 passed
```

### case: "schema.ex's beam calls exactly the frozen module set — nothing else is reachable"

*(dead-code note)*

```red
$ # plant: a public, spec'd Regex.run probe added to schema.ex
$ mix test test/architecture/schema_shape_test.exs
schema module-set drift.
unexpected: [Regex, :re]
missing: []
Result: 2/3 passed
```

### case: "no banned reach-mechanism (apply / atom construction / spawn) exists in the beam"

```red
$ # plant: apply(String, :to_atom, [p]) probe in schema.ex
$ mix test test/architecture/schema_shape_test.exs
banned dynamic-dispatch or atom-construction call in the schema beam
Result: 2/3 passed
```

### case: "red-capability: the census catches every evasion form a name scan cannot"

Self-proving by construction: the test itself compiles a planted module
with renamed aliases, variable-indirected calls, and full dynamic apply,
then asserts each surfaces in the census (`{:crypto, :sign}`, `{Regex,
:run}`, `{:erlang, :apply}`, `{:erlang, :binary_to_atom}`).

```red
$ mix test test/architecture/schema_shape_test.exs
assert {:crypto, :sign} in census, "renamed-alias or variable-indirected :crypto.sign not seen"
Result: 3 passed
```

### case: "no function in lib/ takes a private_key/seed/secret parameter"

```red
$ # plant: public key_probe(private_key) in base64url.ex
$ mix test test/architecture/verify_only_test.exs
verify-only violation: a shipped function accepts key material:
Result: 2/4 passed
```

### case: "no :crypto.sign invocation exists anywhere in lib/"

```red
$ # plant (same probe): a :crypto.sign call site
$ mix test test/architecture/verify_only_test.exs
verify-only violation: the package never signs, but a :crypto.sign call exists:
Result: 2/4 passed
```

### case: "no struct field or module attribute in lib/ is named like key material"

```red
$ # plant (same probe): @secret module attribute
$ mix test test/architecture/verify_only_test.exs
verify-only violation: shipped source declares key-material shape:
Result: 2/4 passed
```

### case: "no lib beam can call :crypto.sign under ANY spelling (beam census)"

*(dead-code note — the probe is public so the beam carries the call)*

```red
$ # plant (same probe): the sign call compiled into the shipped beam
$ mix test test/architecture/verify_only_test.exs
Result: 0/4 passed
```

### case: "every conventional version-token form is flagged"

```red
$ # plant: ArchitectureScan.version_token?/1's leading-bound regex weakened to two digits
$ mix test test/architecture/version_token_test.exs
expected V2 to be flagged
Result: 1/2 passed
```

```red
$ # probe: acronym spellings under the [A-Z][a-z]+\d+ pattern
$ elixir -e '... for s <- ["HTTP2Stream", "TLS12Socket", "Base2Protocol"], do: IO.inspect({s, S.v(s)})'
{"HTTP2Stream", false}
{"TLS12Socket", false}
{"Base2Protocol", false}
```

### case: "protocol names and clean identifiers are not flagged"

```red
$ # plant: version_token?/1 gains an over-matching [a-z] clause
$ mix test test/architecture/version_token_test.exs
did not expect AgentBlueprintProtocol to be flagged
Result: 1/2 passed
```

### case: "only the enumerated package contract identity may carry a version token"

```red
$ # before the exact path/kind/value allowlist existed
$ mix test test/architecture/version_token_test.exs
** (UndefinedFunctionError) function AgentBlueprintProtocol.ArchitectureScan.check_durable_identifier/1 is undefined or private
Result: 2/3 passed
```

### case: "the package source identity is observed from the real package metadata"

```red
$ # mutate the actual mix.exs package source_ref from v#{@version} to v2
$ mix test test/architecture/identifier_naming_test.exs
left: [%{name: "source_ref: \"v2\"", path: "mix.exs", kind: :package_source_ref}]
right: [%{name: "source_ref: \"v#{@version}\"", path: "mix.exs", kind: :package_source_ref}]
Result: 2/3 passed
```

```red
$ # probe: canonical spellings under the stem set ["Base","Ed","Ipv"]
$ elixir -e '... probe of version_token? for IPv4 IPv6 Utf8 Sha256 Rfc8785'
IPv4 -> true    # stem resolves to "Pv" — the standard capitalization false-flags
Utf8 -> true
Rfc8785 -> true
```

### case: "live registry data matches no guard pattern (exemption pin)"

The exemption record (registry owner/namespace/a2a_uri data is
published-by-design; no pattern targets it) made mechanical: a future
pattern that accidentally covers exempted data reds here, naming the
exemption decision, instead of spurious-redning the main scans.

```red
$ # plant: ~r/\bExampleCommerce\b/ added to @text_patterns
$ mix test test/architecture/publish_guard_test.exs
publish-guard pattern covers exempted registry data (update the exemption decision, not the data):
  pattern "\\bExampleCommerce\\b" covers ExampleCommerce
Result: 2/8 passed
```

### case: "the exemption pin can fire (calibration)"

```red
$ # plant: calibration's planted pattern swapped for a non-matching ~r/Zz9NoFixtureEver/
$ mix test test/architecture/publish_guard_test.exs
exemption-pin calibration is vacuous: a pattern that targets owner data found no fixture — registry_fixtures/ is empty or broken
Result: 7/8 passed
```

### case: "corpus json members are byte-scanned but text-exempt (exemption pin)"

```red
$ # plant: the corpus filter selects .md (text-scanned) members instead of .json
$ mix test test/architecture/publish_guard_test.exs
corpus .json members must stay text-exempt (byte patterns still apply): ["docs/protocol.md", "docs/federation-mapping.md", "README.md", "CHANGELOG.md", "SECURITY.md", "usage-rules.md"]
Result: 7/8 passed
```

### case: "cli main is exactly one pure halt delegation (shape pin)"

Cli.Main is the coverage-census exemption; this pin makes its
"pure delegation" constraint mechanical (a recorded design
constraint, closed).

```red
$ # plant: defp planted_extra(x), do: x + 1 added to main.ex
$ mix test test/architecture/cli_main_shape_test.exs
Cli.Main must define only main/1 (the coverage-exempt halt shim carries no logic): found [defp: :planted_extra, def: :main]
Result: 0/1 passed
```

```red
$ # plant: main/1 body spread to a multi-statement block (code = Cli.run(argv); System.halt(code))
$ mix test test/architecture/cli_main_shape_test.exs
match (=) failed
code:  assert {{:., _, [{:__aliases__, _, [:System]}, :halt]}, _,
Result: 0/1 passed
```

```red
$ # probe: main({argv, _extra}) passed the name-only assertion, then red
$ # under the arity+plain-variable assertion
$ mix test test/architecture/cli_main_shape_test.exs
match (=) failed
code:  assert [{:def, :main, [{arg_name, _, nil}]}] = defs
Result: 0/1 passed
```

## The conformance lane (in-suite)

### conformance: corpus loader integrity

`Conformance.Corpus.load/1`'s two-directional checks (per-file SHA-256,
exact file-set equality, counts, case-id uniqueness, applicability
totality with falsifiable n/a reasons, tamper-case verbatim bytes, hash-
bound `.raw` sidecars) run as in-suite tests under the alias `test` entry.
The loader's integrity contract reddens at the gate level the moment any
shipped corpus byte drifts — the same plant as the `conformance.verify`
entry, observed there:

```red
$ # plant: one byte of a corpus case JSON flipped
$ mix conformance.verify
corpus integrity failure: :corpus_case_invalid
EXIT=1
```

### conformance: runner agreement + report determinism

`Runner`/`Report` determinism and the exit-status contract run as
in-suite tests under the alias `test` entry; the report refuses a
vacuous green (`total > 0` AND zero disagreements). The
cross-implementation form of the same contract is
`verifier.agreement`, whose seeded reds are asserted to fire every run:

```red
$ mix verifier.agreement
seeded red fired: verdict-comparison-inverted
seeded red fired: calibration-report-format-drift
seeded red fired: window-check-deleted
report byte drift (repo corpus)   # the raise form — any byte divergence
seeded red did not diverge        # the vacuous-seed guard
```

## Archive-content decision of record

The design spec's package-boundary line once read "package.files GAINS
`priv/conformance`, `priv/registry`, and the normative protocol doc". The
registry half is superseded: the extension registry is compiled-in data
(`extension_registry.ex`), no `priv/registry` directory exists, and none
ships — see `docs/adr/compiled-registry.md`. The archive gains
`docs/protocol.md` (the normative protocol doc) and nothing else beyond
the previously frozen set.
