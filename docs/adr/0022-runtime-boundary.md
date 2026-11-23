# 0022: runtime boundary

Status: Accepted

## Context

Hosts embed this package inside their own trust, scheduling and storage
decisions. A protocol library that starts processes, reads files, holds keys
or pulls runtime dependencies would carry its own policy into every host and
widen the surface each host has to audit.

## Decision

The package is an inert verification library:

- It registers no application callback and no supervision tree. The only
  extra OTP application is `:crypto`.
- It has no production dependency. Every declared dependency is limited to
  development and test and is not loaded at runtime. Canonicalization,
  digests, JSON decoding and signature verification are implemented in the
  package over `:crypto`.
- No library module touches the filesystem. The conformance command line
  (the escript and its main module) is the one exception: it reads the corpus
  directory a user names.
- It verifies and never signs. No function accepts private key material and
  no structure holds it.
- The caller owns every input the decision depends on: the bytes, the
  registrations, the trust anchors and the observation time. The package
  reads no clock and no environment to decide an outcome.

The purity, file-access and verify-only architecture gates enforce these
rules over the compiled code, so an aliased or indirect call cannot hide.

## Consequences

- A host can call any public function from any process without starting the
  package or granting it file or network access.
- Producing and signing artifacts is host work, described in the
  [producer surface](0008-producer-surface.md) record.
