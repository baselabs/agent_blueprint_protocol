# Read evidence

This guide is for consumers of reconciliation results. You will learn how to inspect checks, understand typed details, and keep unknown values from being treated as proof.

Reconciliation returns an `Evidence` struct. Its checks record a surface, subject path, verified flag, and typed detail. The `not_verified` list names surfaces the protocol did not establish; it is nonempty by design.

## Read known checks

The following excerpt assumes `evidence` is the result of `AgentBlueprintProtocol.reconcile/3`. It looks up known check names and keeps a default branch for future details.

```elixir
alias AgentBlueprintProtocol.Evidence

signature_summaries =
  Enum.map(["blueprint", "deployment"], fn artifact ->
    check = Enum.find(evidence.checks, fn check ->
      check.surface == :signatures and check.subject == [artifact]
    end)

    summary =
      case check do
        %{verified: true, detail: %Evidence.Signatures{key_ids: key_ids}} ->
          {:verified_by, key_ids}

        %{verified: false, detail: :no_signatures_present} ->
          :not_verified

        _unknown ->
          :unknown
      end

    {artifact, summary}
  end)

binding_check = Enum.find(evidence.checks, &(&1.surface == :bind and &1.subject == ["deployment"]))

binding_summary =
  case binding_check do
    %{detail: %Evidence.Binding{checked: checked, not_verified: skipped}} ->
      {checked, skipped}

    _unknown ->
      :unknown
  end
```

The signature summaries preserve the subject. A signed Blueprint and unsigned Deployment produce a verified Blueprint entry and an unverified Deployment entry. The global `:signatures` entry in `not_verified` indicates at least one relevant signature surface remains unverified. Use the same subject-aware lookup for digest, canonical, structure, and negotiation checks.

For example, the mixed result is:

```elixir
[{"blueprint", {:verified_by, ["example-producer-key"]}}, {"deployment", :not_verified}]
```

For the same pair, `:signatures in evidence.not_verified` is `true`. A single verified subject cannot establish the other subject's signature status.

Evidence detail variants may grow. This code handles the known Signatures and Binding structs. The default branch leaves an unfamiliar shape unknown.

## Read `not_verified`

The `not_verified` names may also grow. Look up names you understand and retain a default branch:

```elixir
not_verified_summary =
  Enum.map(evidence.not_verified, fn
    :tenancy -> {:known_unverified, :tenancy}
    :live_policy -> {:known_unverified, :live_policy}
    unknown -> {:unknown, unknown}
  end)
```

An unknown name stays unknown. It does not show that a check passed. A result with checks still does not grant permission to act.

## Next steps

- [Integrate reconciliation](host-integration.md)
- [Handle typed errors](handling-errors.md)
- [Read protocol section 13](../spec/protocol.md#13-evidence-and-reconcile)
