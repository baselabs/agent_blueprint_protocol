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
deny crossing into MCP, the logical `:submitted` state has no MCP
status (`Federation.to_mcp_state(:submitted)`), and `UNSPECIFIED` has no
logical state; each denies `:federation_state_unmappable`. Two terminal
receipts for one task identity diverging in ANY commitment component
deny `:federation_terminal_conflict`.

```elixir
{:ok, rejected} = AgentBlueprintProtocol.Federation.from_a2a_state("TASK_STATE_REJECTED")
elem(AgentBlueprintProtocol.Federation.to_mcp_state(rejected), 1).code # => :federation_state_unmappable
elem(AgentBlueprintProtocol.Federation.to_mcp_state(:submitted), 1).code # => :federation_state_unmappable
elem(AgentBlueprintProtocol.Federation.from_a2a_state("TASK_STATE_UNSPECIFIED"), 1).code # => :federation_state_unmappable
AgentBlueprintProtocol.Federation.to_mcp_state(:completed) # => {:ok, "completed"}
```

## Receiver posture

`AgentBlueprintProtocol.Federation.verify_commitment/2` is purpose-pinned:
a signature whose signed `purpose` is `blueprint` or `deployment` never
verifies a receipt; it denies `:invalid_constraint` with subject
`["evidence_receipt", "signature"]`. Keys are labels, not issuers — per-issuer
attribution uses the host's key sets; replay is receiver policy with
signed-staleness windows. Correlation grants nothing.
