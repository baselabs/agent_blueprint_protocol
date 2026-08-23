defmodule AgentBlueprintProtocol.FederationFixture do
  @moduledoc """
  Shared builder for a complete, valid Federation.TaskEnvelope value (the
  23 logical members), used by the unit, property, and fuzz lanes. Variants:
  `parent:` (parent_execution_reference + initiating_subject), `checkpoint:`
  (the three checkpoint members), `terminal:` (terminal_state +
  evidence_receipt with opaque digests — the honest commitment computation
  and signature minting live with verify_commitment's tests, not here).
  """

  alias AgentBlueprintProtocol.{Canonicalization, Digest}

  def tagged_digest(domain, material),
    do: {:string, Digest.to_tagged(Digest.hash(domain, material))}

  def value(opts \\ []) do
    task_id = Keyword.get(opts, :task_identity, "task-7f3a2c")

    [
      {"task_identity", {:string, task_id}},
      {"idempotency_identity",
       {:string, Keyword.get(opts, :idempotency_identity, "idem-9c2d41")}},
      {"blueprint_digest", tagged_digest(:blueprint_content, "blueprint-bytes")},
      {"deployment_digest", tagged_digest(:deployment_content, "deployment-bytes")},
      {"input_commitment", tagged_digest(:federation_envelope, "input-bytes")},
      {"result_schema", tagged_digest(:federation_envelope, "schema-bytes")},
      {"result_classification_ceiling",
       {:object, [{"level", {:string, "internal"}}, {"markers", {:array, []}}]}},
      {"time_policy", {:object, [{"elapsed_ms", {:integer, 60_000}}]}},
      {"resource_policy",
       {:object,
        [
          {"attempts", {:integer, 3}},
          {"concurrency", {:integer, 2}},
          {"tokens", {:integer, 1_000}},
          {"cost", {:integer, 500}}
        ]}},
      {"recovery_handle", {:string, Keyword.get(opts, :recovery_handle, task_id)}},
      {"issuer", {:string, Keyword.get(opts, :issuer, "issuer-alpha")}},
      {"subject", {:string, Keyword.get(opts, :subject, "subject-beta")}},
      {"audience", {:string, Keyword.get(opts, :audience, "audience-gamma")}},
      {"identity_mapping_evidence",
       {:object,
        [
          {"claims",
           {:array,
            [
              {:object,
               [
                 {"kind", {:string, Keyword.get(opts, :claim_kind, "correlation")}},
                 {"value", {:string, Keyword.get(opts, :claim_value, "local-subject-42")}}
               ]}
            ]}}
        ]}},
      {"compatibility_reference",
       {:array,
        [
          {:object,
           [
             {"name", {:string, "abp"}},
             {"identity", {:string, "0.1.0-dev.abc"}}
           ]}
        ]}},
      {"authority_proof_references",
       {:array, [tagged_digest(:federation_envelope, "proof-ref-1")]}}
    ]
    |> maybe_parent(opts)
    |> maybe_checkpoint(opts)
    |> maybe_terminal(opts)
    |> then(&{:object, &1})
  end

  def bytes(opts \\ []) do
    {:ok, jcs} = Canonicalization.encode(value(opts))
    jcs
  end

  defp maybe_parent(members, opts) do
    if Keyword.get(opts, :parent, false) do
      members ++
        [
          {"parent_execution_reference", {:string, "task-parent-11"}},
          {"initiating_subject", {:string, "subject-root"}}
        ]
    else
      members
    end
  end

  defp maybe_checkpoint(members, opts) do
    if Keyword.get(opts, :checkpoint, false) do
      members ++
        [
          {"checkpoint_request",
           {:object,
            [
              {"kind", {:string, "input_required"}},
              {"request_digest", tagged_digest(:federation_envelope, "request-bytes")}
            ]}},
          {"checkpoint_status", {:string, Keyword.get(opts, :checkpoint_status, "working")}},
          {"checkpoint_commitment", tagged_digest(:federation_envelope, "decision-bytes")}
        ]
    else
      members
    end
  end

  defp maybe_terminal(members, opts) do
    if Keyword.get(opts, :terminal, false) do
      members ++
        [
          {"terminal_state", {:string, Keyword.get(opts, :terminal_state, "completed")}},
          {"evidence_receipt",
           {:object,
            [
              {"result_digest",
               tagged_digest(
                 :federation_envelope,
                 Keyword.get(opts, :result_material, "result-bytes")
               )},
              {"checkpoint_history_commitment",
               tagged_digest(:federation_envelope, "history-bytes")},
              {"terminal_commitment", tagged_digest(:federation_envelope, "commitment-bytes")},
              {"signature", Keyword.get(opts, :signature, opaque_signature())}
            ]}}
        ]
    else
      members
    end
  end

  # A well-shaped but cryptographically arbitrary signature entry: decode
  # checks envelope shape only; verify_commitment (its own test file) mints
  # honestly-signed receipts with :crypto.sign the signature_test way.
  defp opaque_signature do
    {:object,
     [
       {"protected",
        {:object,
         [
           {"alg", {:string, "EdDSA"}},
           {"b64", {:boolean, false}},
           {"crit", {:array, [{:string, "b64"}]}},
           {"kid", {:string, "remote-key"}}
         ]}},
       {"signed_attributes",
        {:object,
         [
           {"algorithm", {:string, "Ed25519"}},
           {"content_digest", tagged_digest(:federation_envelope, "covered-bytes")},
           {"created_at", {:string, "2026-08-22T00:00:00Z"}},
           {"key_id", {:string, "remote-key"}},
           {"purpose", {:string, "federation-envelope"}}
         ]}},
       {"signature", {:string, String.duplicate("A", 86)}}
     ]}
  end
end
