# Upgrading

This guide is for consumers comparing Agent Blueprint Protocol releases. You will distinguish version axes, choose package pins, and identify the fields used for compatibility comparisons. The [migration guide](migrating-to-1.0.md) lists source changes for 1.0.

## Version axes

The protocol uses separate version values for separate contracts:

- **Protocol revision** identifies the artifact vocabulary and wire rules.
- **Verification-semantics version** identifies computation over previously certified inputs.
- **Package version** identifies the supported APIs and distribution.
- **Corpus and registry digests** identify the exact conformance cases and extension vocabulary.

The Hex and npm packages carry the same complete version, including prerelease identifiers. The 1.0 release candidate uses this Hex requirement:

```elixir
{:agent_blueprint_protocol, "~> 1.0.0-rc.1"}
```

Install the npm package with its release-candidate tag:

```sh
npm install @agent-blueprint-protocol/verifier@rc
```

## Release identity

`priv/release-metadata.json` records the package version, verification-semantics version, and current specification, corpus, and registry identities. `priv/release-history.json` carries an append-only row for each manifest-era release. Published identities are immutable; corrections appear in a later release.

## Replay identity

For identity comparisons across releases, keep the protocol fields separate from release metadata:

| Identity | Fields | Comparison |
| --- | --- | --- |
| Replay identity | `manifest_version`, `verification_semantics_version`, `protocol_revision`, `registry_digest`, `blueprint_digest`, `deployment_digest`, `effective_bounds`, and consumer adapter, product-build, and authority identities | Compare for equality. |
| Provenance metadata | `package_version`, `corpus_digest`, and `spec_digest` | Record as release context; do not use as replay-identity equality fields. |

Releases with the same `verification_semantics_version` and unchanged registry census certify equivalent outcomes for the released cases. A semantics-version change marks changed computation. A registry digest change calls for a deliberate re-pin because the known extension vocabulary changed.

## Compatible consumers within 1.x

The error-code set and meanings stay closed: exhaustive `ErrorCode` switches
are safe. Notices, evidence surfaces and check kinds, detail variants, and
returned signature algorithm and purpose identifiers are open. Find the
names you know, retain a default branch, and never count an unknown entry
as proof. Select only the Elixir struct fields you use:

```elixir
case result do
  {:ok, %AgentBlueprintProtocol.Evidence{checks: checks}} ->
    Enum.filter(checks, fn
      %{surface: :digest, verified: true} -> true
      _ -> false
    end)
  {:error, %AgentBlueprintProtocol.Error{code: code}} -> {:error, code}
end
```

```ts
import { type Notice } from "@agent-blueprint-protocol/verifier";
function deprecated(notice: Notice): boolean {
  switch (notice) {
    case "extension_deprecated": return true;
    default: return false;
  }
}
```

Ignore unknown additive members in the release manifest, but reject unknown
values in `prior_census_verdicts`. An unknown nonzero harness exit is failure.
Earlier corpus claims remain valid for their exact corpus digest. New wire
revisions and execution versions are explicit choices, with earlier versions
supported throughout the major. The [stability policy](stability.md) lists
all additive paths and the runtime and compiler floors.

## Next steps

- [Migration guide](migrating-to-1.0.md)
- [Stability policy](stability.md)
- [Conformance guide](conformance.md)
