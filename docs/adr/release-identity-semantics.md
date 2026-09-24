# ADR: the release-identity semantics/census split

Status: accepted (2026-09-24).

## Context

Exact-pinned consumers (bounded_authority first: an exact pin one
census generation back, identity verified against the installed
`priv/release-metadata.json` before decode and database access, exact
equality of persisted identity fields on replay) broke on identity
movement that carries no verification-semantics change: one release
grew the certified corpus and moved the corpus digest; the
specification digest has moved on its own cadence all along (the
release history shows every move, including two the changelog prose of
those releases never stated). A byte-identical historical re-import
under a newer pin conflicts on those digests despite unchanged
verdicts for previously-certified inputs. The consumer will not relax
equality, relabel evidence, or skip re-verification — upgradability
belongs protocol-side.

A replay probe (2026-09-23) certified the mechanism's premise: the one
prior manifest-era census (`sha-256:sg6Fo7…`) replays case-perfect
under the then-current package. The same probe exposed that the census
change of that release also rotated the golden vectors' fixture
signature on unchanged covered bytes — the changelog narrative
under-recorded it — which is itself the argument for machine-checked
compatibility claims.

## Decision

Two independent identities per release (the specification's Evolution
clause is the normative text): the CENSUS digests (corpus, registry —
what the release certifies; growth is verdict-neutral for
previously-certified inputs) and a `verification_semantics_version`
integer (the release's computational meaning for
previously-certified inputs: canonicalization, digests, decode
verdicts, bounds computation, negotiation outcomes, signature
verification). The manifest declares the split
(`verification_semantics_version`, `digest_identity`,
`protocol_revisions_supported`, `prior_census_verdicts`); the release
history (`priv/release-history.json`, append-only, manifest era only)
is the retroactive mapping — semantics version 1 spans the entire
manifest era through this release, replay-evidenced (the exact
per-release span lives in the history file, not in prose).

Rejected rivals: a semantics DIGEST (the derivation needs an
equivalence-baseline rule that is itself an authored claim; equivalent
semantics under different baselines would show different digests,
recreating the conflict one level up); a sibling `compatibility.json`
(a second derivation source and gate for no benefit — the manifest is
already additive-tolerant to the known consumer); riding
`protocol_revision` (wrong axis — the wire revision governs artifact
bytes).

## Enforcement — and its honest boundary

`mix compatibility.replay` certifies the claims per release: every
manifest-era tag's census, deduped by digest, loads through
`Corpus.load_prior_census` (the census's OWN index integrity; the two
current-state couplings — the compiled registry digest and the compiled
applicability floor — suspended, because a released census was
certified against the registry and floor of ITS release) and runs under
the current Runner. An `equivalent` claim with any disagreement reds;
`diverged_by_registry_census` demands registry-diff-explained
divergences; an unclaimed census, a stale claim, or a tampered history
row reds; the TS verifier replays each prior census byte-identically
(the current census's TS agreement is the verifier-agreement gate's
own duty). The load-bearing design correction: the replay must
NOT route through the ordinary corpus loader — the loader's
current-state bindings are correct for conformance runs and would kill
the gate at the first extension registration or floor expansion.

The one direction no gate can prove: a `not_equivalent` claim is
authored intent (a semantics change that moves no prior-census case is
still a legitimate bump), never inverse-checked. Certification is over
the released censuses, never the input space at large — the boundary is
stated in the specification, the manifest vocabulary, and the upgrading
guide.
