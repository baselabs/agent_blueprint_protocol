# 0021: Federation mapping identity

Status: Accepted

## Context

The federation mapping table describes how each TaskEnvelope member
crosses A2A and MCP. A receiver needs an exact identity for that table
when it verifies a signed terminal receipt.

## Decision

The mapping identity is the tagged SHA-256 of the RFC 8785 canonical JSON
array of mapping rows in ascending index order. The preimage includes the
field name, both transport locations, and the verdict of each indexed row.

A producer carries the digest as an identity in the existing signed
`compatibility_reference` list under a producer-selected name. The
receiver can require an exact identity match in that list. Verification
checks the pin after the signature, envelope binding, terminal commitment
and addressing checks, and before conflict and freshness checks.
An unmatched pin denies with `compatibility_entry_missing` on
`["compatibility_reference"]`.

## Consequences

A change to any row value changes the mapping identity. Receivers that pin
an identity can detect when a receipt carries a different one. Omitting
the pin preserves the existing verification behavior and the envelope
keeps its 23 members. The match establishes a signed content reference
and grants no authority.
