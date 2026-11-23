# 0011: the release-identity semantics/census split

Status: Accepted

## Decision

Two independent identities per release (the specification's Evolution
clause is the normative text): the CENSUS digests (corpus, registry;
what the release certifies; growth is verdict-neutral for
previously-certified inputs) and a `verification_semantics_version`
integer (the release's computational meaning for
previously-certified inputs: canonicalization, digests, decode
verdicts, bounds computation, negotiation outcomes, signature
verification). The manifest declares the split
(`verification_semantics_version`, `digest_identity`,
`protocol_revisions_supported`, `prior_census_verdicts`); the release
history (`priv/release-history.json`, append-only, manifest era only)
is the retroactive mapping between release versions and these identities.

## Compatibility certification

`mix compatibility.replay` loads each released census with its own index
integrity, without imposing the current registry or applicability floor.
An `equivalent` claim requires agreement on every case;
`diverged_by_registry_census` requires registry-explained disagreements.
The TypeScript and Elixir reports agree byte for byte.
A `not_equivalent` claim is authored intent, never inverse-checked.
Certification covers released censuses, not the entire input space.
The manifest and upgrading guide state this boundary.

## Candidate promotion

A final tree differs from its candidate only in package versions, the
manifest's bound package and kit versions, an appended history row, a new
dated CHANGELOG entry added directly above the candidate's unchanged entry,
install pins, the security table's candidate row and the site. The promotion check
rejects every other byte change, including library and verifier sources,
public API census, specification, corpus, registry and semantics version.
Final publication compares against the highest candidate tag for that exact
final version; an absent candidate refuses publication. A source correction
requires another candidate.
