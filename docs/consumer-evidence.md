# Consumer evidence lane

A repository-level record of consumer rehearsal evidence — UNVERIFIED
third-party claims, linked, never shipped in the package and never part
of the conformance corpus. Implementer conformance (the specification's
Conformance clause) and consumer evidence are different claims; nothing
here extends or dilutes conformance.

## What a lane entry states

Each entry links a consumer's published rehearsal manifest, which must
state:

- the exact pin (package version, `manifest_version`,
  `verification_semantics_version`, corpus and registry digests at the
  pin);
- the census the rehearsal ran against;
- the outcomes: a byte-identical replay of a previously accepted import,
  a fresh import, a changed-body conflict, and restart recovery;
- the evidence digests by which each outcome can be independently
  checked by anyone the consumer shared the evidence with.

An entry names its own verification posture explicitly: the
maintainers have NOT verified the consumer's evidence; the link records
that the consumer published it.

## Entries

_None yet._ The first entry is reserved for the bounded_authority
rehearsal (a populated pre-upgrade database; old accepted replay / new
import / changed-body conflict / restart recovery), to be linked when
the consumer can publish it.
