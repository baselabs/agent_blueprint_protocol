# 0018: artifacts carry requirements, hosts resolve them

Status: Accepted

## Context

An agent blueprint moves between hosts. Every host has its own endpoints,
credentials, tenants, network rules and backend engines. If an artifact
carries any of them, it stops being portable and starts carrying one host's
operational state and policy to every other host.

## Decision

- Artifacts state logical requirements. Concrete endpoints, credentials,
  tenant and account identifiers, provider engine identifiers and network or
  egress policy are resolved and enforced by the host and are not
  representable in a portable artifact. The normative rule is the
  portability and privacy sections of the
  [specification](../../spec/protocol.md).
- Network and egress policy was considered both as a core member and as a
  registered extension and rejected in both forms for this protocol
  revision: it is host policy, not artifact content.
- `AgentBlueprintProtocol.Portability` enforces the rule structurally over
  open regions at any depth: a normalized member name denylist and value
  shape checks for PEM blocks, compact JWS, network URIs, raw key material,
  padded base64 and colon separated hex fingerprints, with UUID shaped values
  exempt.
  Every class has a red case in the corpus.
- The guard is necessary, not sufficient. It is structural, not semantic;
  quarantined extension bodies are reported as unscanned; and a pass is
  never presented as a privacy guarantee.

## Consequences

- A host that needs network policy keeps it in its own configuration, keyed
  by the logical requirement the artifact names.
- Proposals to carry addresses, credentials or network policy in artifacts
  are answered by this record unless a later protocol revision supersedes it.
