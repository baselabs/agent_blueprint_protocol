# The federation guide — A2A and MCP Tasks carriage

The 23-member task envelope rides INSIDE each transport's untyped
extension channel — A2A `Task.metadata` (URI-keyed) and MCP `_meta`
(reverse-DNS key) — under the registered `com.example/federation`
namespace: the same JCS-canonical object, the same detached-Ed25519
signature envelope on both.

## The mapping is data

`AgentBlueprintProtocol.federation_mapping/0` returns the 23-row
A2A/MCP field mapping: 3 native, 5 partial, 15 with no safe native
home. Zero native wire fields were invented; the full table ships as
the federation mapping document.

## Lossy-aware state codecs

Crossings deny rather than degrade: A2A `REJECTED`/`AUTH_REQUIRED`
deny crossing into MCP, `UNSPECIFIED` is unmappable, and two terminal
receipts for one task identity diverging in ANY commitment component
deny `:federation_terminal_conflict`.

## Receiver posture

`verify_commitment/2` is purpose-pinned (a blueprint signature never
verifies a receipt); keys are labels, not issuers — per-issuer
attribution uses the host's key sets; replay is receiver policy with
signed-staleness windows. Correlation grants nothing.
