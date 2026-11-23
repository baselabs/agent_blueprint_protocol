# Roadmap

The current 1.x line maintains the language-neutral protocol, the Elixir and
TypeScript verifiers, and their shared conformance corpus under the
[stability policy](../documentation/stability.md). No additional protocol
features are currently committed for implementation.

Propose changes through the [contribution guidelines](../CONTRIBUTING.md), with
the affected contract and conformance cases. Accepted architectural changes
are recorded in numbered decision records under `docs/adr/`. Additive changes
preserve existing revisions, signed bytes, and consumer contracts; breaking
changes require a new major version. Product-specific semantics belong in
host-supplied extensions; a new core field requires two independently verified
consumers unless it is protocol machinery.
