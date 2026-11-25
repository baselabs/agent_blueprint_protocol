# 0023: Package contents identity

Status: Accepted (2026-11-25)

## Context

Installed consumers have package files. Registry checksums identify complete
archives, whose headers and compression are absent after installation.
The Hex package and npm kit share protocol release metadata, while their
payloads differ.

## Decision

Publish a release manifest with one checksum per distribution. Derive
each from the actual package archive so that file selection belongs to
the packaging tool and compiled kit files participate. The manifest
retains the release metadata shared by both packages.

Reuse the specification digest's file frame and add a domain prefix
that binds the distribution. Omit the embedded release records from
the file set and define the Hex installer records outside it. A verifier
receives an explicit installation root and a checksum authenticated by
the caller. The package contents entry point can traverse and read that
root. Artifact verification still consumes caller-supplied bytes, and
the registry is embedded at build time.

## Consequences

Changing, adding or removing a covered file changes the checksum.
Release-candidate promotion recomputes the published checksums from
the promoted archives. Historical replay remains a check of verifier
semantics across censuses.
