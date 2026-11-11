# Read evidence

This guide is for consumers of reconciliation results. You will learn how to inspect checks, understand typed details, and keep unknown values from being treated as proof.

Reconciliation returns an Evidence struct. Its checks record a surface, subject path, verified flag, and typed detail. The not_verified list names surfaces the protocol did not establish; it is nonempty by design.

## Read known checks

The following excerpt assumes evidence is the result of AgentBlueprintProtocol.reconcile/3. It looks up known check names and keeps a default branch for future details.

```elixir
alias AgentBlueprintProtocol.Evidence

signature_check = Enum.find(evidence.checks, &(&1.surface == :signatures))

signature_summary =
  case signature_check do
    %{verified: true, detail: %Evidence.Signatures{key_ids: key_ids}} ->
      {:verified_by, key_ids}

    %{verified: false, detail: :no_signatures_present} ->
      :not_verified

    _unknown ->
      :unknown
  end

binding_check = Enum.find(evidence.checks, &(&1.surface == :bind))

binding_summary =
  case binding_check do
    %{detail: %Evidence.Binding{checked: checked, not_verified: skipped}} ->
      {checked, skipped}

    _unknown ->
      :unknown
  end
```

Evidence detail variants may grow. This code handles the known Signatures and Binding structs. The default branch leaves an unfamiliar shape unknown.

## Read not_verified

The not_verified names may also grow. Look up names you understand and retain a default branch:

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
