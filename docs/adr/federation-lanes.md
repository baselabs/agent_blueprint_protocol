# ADR: federation lanes: A2A primary, MCP draft-tracking

## Context

Task-federation interop has two candidate wire lanes (an A2A task
protocol and an MCP tasks extension). The 23 logical fields a task
evidence envelope needs map onto them unevenly, and neither lane is
required to carry the protocol's evidence semantics natively.

## Decision

Field-by-field mapping (23 rows) with an honest verdict per row: 3
native, 5 partial, 15 carried via the registered
`io.github.baselabs/federation` extension in A2A `Task.metadata` / MCP
`_meta`. Zero native wire fields; no native transport. A2A is the
primary lane. The upstream MCP Tasks contract is draft-tracking. ABP's shipped MCP mapping and documented codec contracts remain subject to the 1.x stability policy. If an upstream change requires incompatible federation semantics, a new registered critical namespace is introduced beside the existing profile; the existing profile remains supported throughout 1.x. The extension has released tags; v0.2.3 carries the dated
2026-07-28 contract. A2A v1.0.1 is the released baseline.

The protocol's federation surface enforces the lossy boundaries:
`REJECTED`/`AUTH_REQUIRED` deny crossing into MCP, `UNSPECIFIED` is
unmapped, cancellation is a request never a terminal receipt. Terminal
Commitments digest the full terminal tuple, and ANY divergence between
receipts for one task identity denies (`:federation_terminal_conflict`).
Commitment verification compares issuer/subject/audience against the
receiving context (`:audience_mismatch`). AgentCard signing carries a
protobuf field-presence pre-normalization on top of JCS, documented so
adapters do not inherit silent verification failure. Correlation grants
nothing.

## Consequences

Host adapters own the wire; the protocol owns the evidence semantics
and the state codecs. Live federation acceptance depends on the remote
task/receipt surfaces of the consuming hosts (owner-side work). The
untyped metadata channel is safe only because the extension body is
itself registry-validated; that is why the federation namespace is a
critical registration.

The deprecated `com.example/federation` spelling remains supported throughout 1.x.
