defmodule AgentBlueprintProtocol.FederationCommitmentTest do
  @moduledoc """
  The terminal-commitment contract (the commitment law, federation design note): the
  seven-component commitment digest, the JWS binding step (fold F1 — an
  honestly-signed statement naming a different digest is evidence over
  THAT digest, not this envelope), the parametrized context comparison
  (fold F5 — all three members, nil-pin semantics both directions), and
  the equivocation/conflict denials.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{
    Base64Url,
    Canonicalization,
    Digest,
    Federation,
    FederationFixture,
    Signature
  }

  # RFC 8032 §7.1 TEST 1 (the signature_test seed).
  @seed Base.decode16!("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
          case: :lower
        )

  defp pub, do: elem(:crypto.generate_key(:eddsa, :ed25519, @seed), 0)
  defp priv, do: elem(:crypto.generate_key(:eddsa, :ed25519, @seed), 1)

  defp keys, do: [%Signature.PublicKey{key_id: "remote-key", algorithm: :ed25519, key: pub()}]

  # A receipt honestly signed over the CORRECT covered digest but with the
  # WRONG purpose label — the cross-surface lifting the purpose member
  # exists to prevent.
  defp wrong_purpose_envelope(purpose) do
    shell = FederationFixture.value(terminal: true)
    with_commitment = put_receipt_member(shell, "terminal_commitment", commitment_of(shell))
    {:ok, jcs} = Canonicalization.encode(with_commitment)
    {:ok, env} = Federation.decode(jcs)
    # re-sign the same covered bytes under the wrong purpose
    {:ok, expected} = Federation.terminal_commitment(env)
    _ = expected

    covered = covered_body(with_commitment)
    {:ok, cj} = Canonicalization.encode(covered)
    digest = Digest.hash(:federation_envelope, cj)

    attrs =
      {:object,
       [
         {"algorithm", {:string, "Ed25519"}},
         {"content_digest", {:string, Digest.to_tagged(digest)}},
         {"created_at", {:string, "2026-08-22T00:00:00Z"}},
         {"key_id", {:string, "remote-key"}},
         {"purpose", {:string, purpose}}
       ]}

    sig = :crypto.sign(:eddsa, :none, signing_input(header(), attrs), [priv(), :ed25519])

    entry =
      {:object,
       [
         {"protected", header()},
         {"signed_attributes", attrs},
         {"signature", {:string, Base64Url.encode(sig)}}
       ]}

    signed = put_receipt_member(with_commitment, "signature", entry)
    {:ok, jcs2} = Canonicalization.encode(signed)
    Federation.decode(jcs2)
  end

  # ---- honest receipt minting (the verify-only package never signs) --------------

  defp header do
    {:object,
     [
       {"alg", {:string, "EdDSA"}},
       {"b64", {:boolean, false}},
       {"crit", {:array, [{:string, "b64"}]}},
       {"kid", {:string, "remote-key"}}
     ]}
  end

  defp signing_input(hdr, attrs) do
    {:ok, h} = Canonicalization.encode(hdr)
    {:ok, a} = Canonicalization.encode(attrs)
    Base64Url.encode(h) <> "." <> a
  end

  # The envelope with the receipt's signature dropped — the JWS content
  # digest covers exactly this.
  defp covered_body(envelope_value) do
    {:object, members} = envelope_value

    {:object,
     Enum.map(members, fn
       {"evidence_receipt", {:object, receipt}} ->
         {"evidence_receipt", {:object, Enum.reject(receipt, fn {n, _} -> n == "signature" end)}}

       other ->
         other
     end)}
  end

  defp content_digest(envelope_value) do
    {:ok, jcs} = Canonicalization.encode(covered_body(envelope_value))
    Digest.hash(:federation_envelope, jcs)
  end

  defp attrs_for(envelope_value, digest) do
    {:object,
     [
       {"algorithm", {:string, "Ed25519"}},
       {"content_digest", {:string, Digest.to_tagged(digest)}},
       {"created_at", {:string, "2026-08-22T00:00:00Z"}},
       {"key_id", {:string, "remote-key"}},
       {"purpose", {:string, "federation-envelope"}}
     ]}
  end

  defp sign_into(envelope_value, digest) do
    attrs = attrs_for(envelope_value, digest)
    sig = :crypto.sign(:eddsa, :none, signing_input(header(), attrs), [priv(), :ed25519])

    entry =
      {:object,
       [
         {"protected", header()},
         {"signed_attributes", attrs},
         {"signature", {:string, Base64Url.encode(sig)}}
       ]}

    {:object, members} = envelope_value

    {:object,
     Enum.map(members, fn
       {"evidence_receipt", {:object, receipt}} ->
         inner =
           Enum.map(receipt, fn {n, v} -> {n, if(n == "signature", do: entry, else: v)} end)

         {"evidence_receipt", {:object, inner}}

       other ->
         other
     end)}
  end

  # The full honest terminal envelope: fixture shell + commitment over the
  # seven components + signature bound to the covered body's digest.
  defp honest_envelope(opts \\ []) do
    shell =
      FederationFixture.value(
        terminal: true,
        task_identity: Keyword.get(opts, :task_identity, "task-7f3a2c"),
        terminal_state: Keyword.get(opts, :terminal_state, "completed"),
        result_material: Keyword.get(opts, :result_material, "result-bytes"),
        audience: Keyword.get(opts, :audience, "audience-gamma"),
        issuer: Keyword.get(opts, :issuer, "issuer-alpha"),
        subject: Keyword.get(opts, :subject, "subject-beta")
      )

    with_commitment =
      put_receipt_member(shell, "terminal_commitment", commitment_of(shell))

    signed = sign_into(with_commitment, content_digest(with_commitment))

    {:ok, jcs} = Canonicalization.encode(signed)
    {:ok, env} = Federation.decode(jcs)
    env
  end

  defp commitment_of(envelope_value) do
    {:ok, digest} = Federation.terminal_commitment(%Federation{value: envelope_value})
    {:string, Digest.to_tagged(digest)}
  end

  # Replaces a member INSIDE the receipt's JWS entry (e.g. the raw
  # signature string), leaving the entry's own shape intact.
  defp put_receipt_inner(envelope_value, name, value) do
    {:object, members} = envelope_value

    {:object,
     Enum.map(members, fn
       {"evidence_receipt", {:object, receipt}} ->
         inner =
           Enum.map(receipt, fn
             {"signature", {:object, entry}} ->
               {"signature",
                {:object,
                 Enum.map(entry, fn {n, v} ->
                   {n, if(n == name, do: {:string, value}, else: v)}
                 end)}}

             other ->
               other
           end)

         {"evidence_receipt", {:object, inner}}

       other ->
         other
     end)}
  end

  defp drop_receipt_member({:object, members}, name) do
    {:object,
     Enum.map(members, fn
       {"evidence_receipt", {:object, receipt}} ->
         {"evidence_receipt", {:object, Enum.reject(receipt, fn {n, _} -> n == name end)}}

       other ->
         other
     end)}
  end

  defp drop_member(%Federation{value: {:object, members}}, name),
    do: %Federation{value: {:object, Enum.reject(members, fn {n, _} -> n == name end)}}

  # A forged struct with valid identity members plus the given overrides —
  # each rim test targets one member's denial.
  defp forged_with(overrides) do
    base = [
      {"task_identity", {:string, "t"}},
      {"terminal_state", {:string, "completed"}},
      {"evidence_receipt", {:object, []}}
    ]

    pairs = Enum.map(overrides, fn {k, v} -> {to_string(k), v} end)

    merged =
      Enum.reject(base, fn {n, _} -> Enum.any?(pairs, fn {on, _} -> on == n end) end) ++ pairs

    %Federation{value: {:object, merged}}
  end

  defp put_receipt_member(envelope_value, name, value) do
    {:object, members} = envelope_value

    {:object,
     Enum.map(members, fn
       {"evidence_receipt", {:object, receipt}} ->
         inner = Enum.map(receipt, fn {n, v} -> {n, if(n == name, do: value, else: v)} end)
         {"evidence_receipt", {:object, inner}}

       other ->
         other
     end)}
  end

  defp context(opts \\ []) do
    struct!(
      Federation.Context,
      Keyword.merge([keys: keys()], opts)
    )
  end

  defp prior_facts(env) do
    assert {:ok, facts} = Federation.verify_commitment(env, context())
    facts
  end

  # ---- the decided reds ------------------------------------------------------------

  describe "verify_commitment/2" do
    test "an honestly-signed receipt for the receiving context verifies" do
      env = honest_envelope()

      assert {:ok, %{task_identity: "task-7f3a2c", terminal_commitment: %Digest{}}} =
               Federation.verify_commitment(env, context())
    end

    test "context divergence denies :audience_mismatch parametrized over all three members" do
      for {member, pinned} <- [
            {"audience", "audience-other"},
            {"issuer", "issuer-other"},
            {"subject", "subject-other"}
          ] do
        env = honest_envelope()

        assert {:error,
                %AgentBlueprintProtocol.Error{code: :audience_mismatch, subject: [^member]}} =
                 Federation.verify_commitment(env, context([{String.to_atom(member), pinned}]))
      end
    end

    test "nil pins skip a matching member; matching pins pass" do
      env = honest_envelope()

      assert match?(
               {:ok, %{task_identity: "task-7f3a2c"}},
               Federation.verify_commitment(
                 env,
                 context(issuer: nil, subject: nil, audience: nil)
               )
             )

      assert match?(
               {:ok, _},
               Federation.verify_commitment(
                 env,
                 context(
                   issuer: "issuer-alpha",
                   subject: "subject-beta",
                   audience: "audience-gamma"
                 )
               )
             )
    end

    test "an honestly-signed statement naming a DIFFERENT digest denies :digest_mismatch (F1 binding)" do
      shell = FederationFixture.value(terminal: true)
      with_commitment = put_receipt_member(shell, "terminal_commitment", commitment_of(shell))

      wrong_digest = Digest.hash(:federation_envelope, "some-other-envelope")
      forged = sign_into(with_commitment, wrong_digest)
      {:ok, jcs} = Canonicalization.encode(forged)
      {:ok, env} = Federation.decode(jcs)

      assert {:error, %AgentBlueprintProtocol.Error{code: :digest_mismatch}} =
               Federation.verify_commitment(env, context())
    end

    test "a tampered covered member (audience rewritten post-signing) denies :digest_mismatch" do
      env = honest_envelope()
      {:object, members} = env.value

      tampered =
        {:object,
         Enum.map(members, fn
           {"audience", _} -> {"audience", {:string, "audience-other"}}
           other -> other
         end)}

      assert {:error, %AgentBlueprintProtocol.Error{code: :digest_mismatch}} =
               Federation.verify_commitment(%Federation{value: tampered}, context())
    end

    test "a tampered signature denies :signature_not_verified" do
      env = honest_envelope()
      # A meaningful first byte flipped inside the JWS entry; the trailing
      # "AA" pair keeps the unpadded length canonical so the tamper reaches
      # crypto, not parsing.
      smashed = put_receipt_inner(env.value, "signature", "C" <> String.duplicate("A", 85))

      assert {:error, %AgentBlueprintProtocol.Error{code: :signature_not_verified}} =
               Federation.verify_commitment(%Federation{value: smashed}, context())
    end

    test "a tampered terminal commitment denies :digest_mismatch" do
      env = honest_envelope()

      other =
        put_receipt_member(
          env.value,
          "result_digest",
          FederationFixture.tagged_digest(:federation_envelope, "other-result")
        )

      assert {:error, %AgentBlueprintProtocol.Error{code: :digest_mismatch}} =
               Federation.verify_commitment(%Federation{value: other}, context())
    end

    test "same-state divergent result digests deny :federation_terminal_conflict (equivocation)" do
      first = honest_envelope()
      second = honest_envelope(result_material: "divergent-result-bytes")

      prior = prior_facts(first)

      assert {:error, %AgentBlueprintProtocol.Error{code: :federation_terminal_conflict}} =
               Federation.verify_commitment(second, context(prior_receipts: [prior]))
    end

    test "divergent terminal states for one task identity deny :federation_terminal_conflict" do
      first = honest_envelope(terminal_state: "completed")
      second = honest_envelope(terminal_state: "failed")

      prior = prior_facts(first)

      assert {:error, %AgentBlueprintProtocol.Error{code: :federation_terminal_conflict}} =
               Federation.verify_commitment(second, context(prior_receipts: [prior]))
    end

    test "a matching prior receipt stays green (no false conflict)" do
      env = honest_envelope()
      prior = prior_facts(env)

      assert {:ok, _} = Federation.verify_commitment(env, context(prior_receipts: [prior]))
    end

    test "a non-terminal envelope denies :missing_required_field" do
      {:ok, env} = Federation.decode(FederationFixture.bytes(checkpoint: true))

      assert {:error, %AgentBlueprintProtocol.Error{code: :missing_required_field}} =
               Federation.verify_commitment(env, context())
    end

    test "a non-object evidence_receipt member denies :invalid_type (forged struct)" do
      forged = forged_with([{"evidence_receipt", {:string, "nope"}}])

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               Federation.verify_commitment(forged, context())
    end

    test "a wrong-purpose signature denies :invalid_constraint (no cross-surface lifting)" do
      for purpose <- ["blueprint", "deployment"] do
        {:ok, env} = wrong_purpose_envelope(purpose)

        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
                 Federation.verify_commitment(env, context())
      end
    end

    test "a forged struct with a signature-less receipt denies, never raises" do
      forged = %Federation{value: {:object, [{"evidence_receipt", {:object, []}}]}}

      assert {:error, %AgentBlueprintProtocol.Error{code: :missing_required_field}} =
               Federation.verify_commitment(forged, context())
    end

    test "a forged struct with non-string identity members denies :invalid_type" do
      for member <- ["task_identity", "terminal_state"] do
        forged = forged_with([{member, {:integer, 3}}])

        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: [^member]}} =
                 Federation.verify_commitment(forged, context())
      end
    end

    test "forged receipt rims: malformed terminal_commitment and absent receipts deny typed" do
      # An honestly-signed receipt whose declared commitment member is a
      # non-string (decode would deny it; the forged-struct path must deny
      # typed too, after signature and binding pass).
      shell = FederationFixture.value(terminal: true)
      mangled = put_receipt_member(shell, "terminal_commitment", {:integer, 5})
      signed = sign_into(mangled, content_digest(mangled))

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               Federation.verify_commitment(%Federation{value: signed}, context())

      # Absent commitment member and an unparseable commitment string —
      # both honestly signed (signature and binding pass first).
      absent =
        FederationFixture.value(terminal: true)
        |> drop_receipt_member("terminal_commitment")
        |> then(fn v -> sign_into(v, content_digest(v)) end)

      assert {:error, %AgentBlueprintProtocol.Error{code: :missing_required_field}} =
               Federation.verify_commitment(%Federation{value: absent}, context())

      unparseable =
        FederationFixture.value(terminal: true)
        |> put_receipt_member("terminal_commitment", {:string, "not-a-digest"})
        |> then(fn v -> sign_into(v, content_digest(v)) end)

      assert {:error, %AgentBlueprintProtocol.Error{code: :digest_encoding_invalid}} =
               Federation.verify_commitment(%Federation{value: unparseable}, context())

      no_receipt = forged_with([]) |> drop_member("evidence_receipt")

      assert {:error, %AgentBlueprintProtocol.Error{code: :missing_required_field}} =
               Federation.verify_commitment(no_receipt, context())
    end

    test "rims: malformed arguments deny :invalid_type, never raise" do
      env = honest_envelope()

      for bad <- [nil, 42, %{}] do
        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 Federation.verify_commitment(bad, context())

        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 Federation.verify_commitment(env, bad)
      end
    end
  end

  describe "issuer_key_sets (per-issuer key attribution)" do
    @org_b_seed Base.decode16!(
                  "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8c66086ae20945",
                  case: :lower
                )

    defp org_b_pub,
      do: elem(:crypto.generate_key(:eddsa, :ed25519, @org_b_seed), 0)

    defp org_b_priv,
      do: elem(:crypto.generate_key(:eddsa, :ed25519, @org_b_seed), 1)

    # A receipt claiming issuer-b, honestly signed by the org-b key.
    defp org_b_receipt do
      shell = FederationFixture.value(terminal: true, issuer: "issuer-b")

      with_commitment = put_receipt_member(shell, "terminal_commitment", commitment_of(shell))
      {:ok, jcs} = Canonicalization.encode(with_commitment)
      {:ok, env} = Federation.decode(jcs)
      covered = covered_body(with_commitment)
      {:ok, cj} = Canonicalization.encode(covered)
      digest = Digest.hash(:federation_envelope, cj)

      attrs =
        {:object,
         [
           {"algorithm", {:string, "Ed25519"}},
           {"content_digest", {:string, Digest.to_tagged(digest)}},
           {"created_at", {:string, "2026-08-22T00:00:00Z"}},
           {"key_id", {:string, "org-b-key"}},
           {"purpose", {:string, "federation-envelope"}}
         ]}

      org_b_header =
        {:object,
         [
           {"alg", {:string, "EdDSA"}},
           {"b64", {:boolean, false}},
           {"crit", {:array, [{:string, "b64"}]}},
           {"kid", {:string, "org-b-key"}}
         ]}

      sig =
        :crypto.sign(:eddsa, :none, signing_input(org_b_header, attrs), [org_b_priv(), :ed25519])

      entry =
        {:object,
         [
           {"protected", org_b_header},
           {"signed_attributes", attrs},
           {"signature", {:string, Base64Url.encode(sig)}}
         ]}

      signed = put_receipt_member(with_commitment, "signature", entry)
      {:ok, jcs2} = Canonicalization.encode(signed)
      Federation.decode(jcs2)
    end

    test "a receipt claiming org-a but signed by org-b's key denies when the set maps only org-a" do
      # org-b's key rides the FLAT pool; issuer_key_sets maps only org-a.
      # Precedence: sets non-nil => flat ignored => cross-attribution denies.
      {:ok, env} = org_b_receipt()

      assert {:error, %AgentBlueprintProtocol.Error{code: :signature_key_unsupported}} =
               Federation.verify_commitment(env, %Federation.Context{
                 keys: [
                   %Signature.PublicKey{
                     key_id: "org-b-key",
                     algorithm: :ed25519,
                     key: org_b_pub()
                   }
                 ],
                 issuer_key_sets: %{
                   "issuer-a" => [
                     %Signature.PublicKey{key_id: "remote-key", algorithm: :ed25519, key: pub()}
                   ]
                 }
               })
    end

    test "the correct issuer's set verifies" do
      {:ok, env} = org_b_receipt()

      assert {:ok, %{task_identity: _}} =
               Federation.verify_commitment(env, %Federation.Context{
                 keys: [],
                 issuer_key_sets: %{
                   "issuer-b" => [
                     %Signature.PublicKey{
                       key_id: "org-b-key",
                       algorithm: :ed25519,
                       key: org_b_pub()
                     }
                   ]
                 }
               })
    end

    test "an issuer absent from the map denies with the attribution subject (names the issuer, not the signature)" do
      {:ok, env} = org_b_receipt()

      assert {:error, %AgentBlueprintProtocol.Error{code: :signature_key_unsupported}} =
               Federation.verify_commitment(env, %Federation.Context{
                 keys: [],
                 issuer_key_sets: %{
                   "issuer-a" => [
                     %Signature.PublicKey{key_id: "remote-key", algorithm: :ed25519, key: pub()}
                   ]
                 }
               })
    end

    test "an empty map trusts no issuer (deny-all, not fallback)" do
      env = honest_envelope()

      assert {:error, %AgentBlueprintProtocol.Error{code: :signature_key_unsupported}} =
               Federation.verify_commitment(env, %Federation.Context{
                 keys: keys(),
                 issuer_key_sets: %{}
               })
    end

    test "the flat pool still verifies when issuer_key_sets is nil (back-compat)" do
      env = honest_envelope()
      assert {:ok, _} = Federation.verify_commitment(env, context())
    end

    test "nil pools deny :invalid_type typed, never raise (the live crash fixed)" do
      env = honest_envelope()

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               Federation.verify_commitment(env, %Federation.Context{})
    end

    test "malformed pools deny typed with STATIC subjects: a non-map set, a non-list member anywhere in the map" do
      env = honest_envelope()

      assert {:error,
              %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["issuer_key_sets"]}} =
               Federation.verify_commitment(env, %Federation.Context{
                 keys: [],
                 issuer_key_sets: [:not_a_map]
               })

      # A malformed pool under a DIFFERENT issuer's key still denies — the
      # whole map validates, not just the claimed entry. The subject is
      # static: the claimed issuer value never rides an error.
      assert {:error,
              %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["issuer_key_sets"]}} =
               Federation.verify_commitment(env, %Federation.Context{
                 keys: [],
                 issuer_key_sets: %{"issuer-other" => :not_a_list}
               })

      assert {:error,
              %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["issuer_key_sets"]}} =
               Federation.verify_commitment(env, %Federation.Context{
                 keys: [],
                 issuer_key_sets: %{99 => keys()}
               })

      assert {:error,
              %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["created_after"]}} =
               Federation.verify_commitment(env, context(created_after: 42))
    end

    test "envelope failures under an empty ATTRIBUTED pool keep the signature subject (only the key-miss relabels)" do
      # A MALFORMED entry fails at parse, before candidate selection — that
      # failure must keep the signature subject even under attribution.
      env = honest_envelope()
      mangled = put_receipt_inner(env.value, "signature", "not-base64url!!")

      assert {:error,
              %AgentBlueprintProtocol.Error{
                code: :signature_malformed,
                subject: ["evidence_receipt", "signature"]
              }} =
               Federation.verify_commitment(%Federation{value: mangled}, %Federation.Context{
                 keys: [],
                 issuer_key_sets: %{}
               })
    end

    test "an empty FLAT pool keeps the signature subject (no attribution in use)" do
      env = honest_envelope()

      assert {:error,
              %AgentBlueprintProtocol.Error{
                code: :signature_key_unsupported,
                subject: ["evidence_receipt", "signature"]
              }} =
               Federation.verify_commitment(env, %Federation.Context{keys: []})
    end

    test "a forged absent issuer never selects a keyed set (the empty pool is literal)" do
      env = honest_envelope()

      forged =
        Map.update!(env, :value, fn {:object, members} ->
          {:object, Enum.reject(members, fn {n, _} -> n == "issuer" end)}
        end)

      assert {:error,
              %AgentBlueprintProtocol.Error{code: :signature_key_unsupported, subject: ["issuer"]}} =
               Federation.verify_commitment(forged, %Federation.Context{
                 keys: [],
                 issuer_key_sets: %{"" => keys()}
               })
    end

    test "malformed prior_receipts deny typed, never raise" do
      env = honest_envelope()
      prior = prior_facts(env)

      assert {:error,
              %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["prior_receipts"]}} =
               Federation.verify_commitment(env, context(prior_receipts: nil))

      assert {:error,
              %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["prior_receipts"]}} =
               Federation.verify_commitment(env, context(prior_receipts: [prior, :garbage]))

      assert {:error,
              %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["prior_receipts"]}} =
               Federation.verify_commitment(env, context(prior_receipts: [%{task_identity: "x"}]))
    end

    test "a forged non-string issuer selects the empty pool and denies naturally" do
      env = honest_envelope()

      forged =
        Map.update!(env, :value, fn {:object, members} ->
          {:object,
           Enum.map(members, fn
             {"issuer", _} -> {"issuer", {:integer, 9}}
             other -> other
           end)}
        end)

      assert {:error, %AgentBlueprintProtocol.Error{code: :signature_key_unsupported}} =
               Federation.verify_commitment(forged, %Federation.Context{
                 keys: [],
                 issuer_key_sets: %{"issuer-alpha" => keys()}
               })
    end
  end

  describe "freshness pins (signed created_at window)" do
    test "a receipt created before created_after denies :invalid_constraint with the created_at subject" do
      env = honest_envelope()

      assert {:error,
              %AgentBlueprintProtocol.Error{
                code: :invalid_constraint,
                subject: ["evidence_receipt", "signature", "created_at"]
              }} =
               Federation.verify_commitment(env, context(created_after: "2026-08-23T00:00:00Z"))
    end

    test "a receipt created after created_before denies" do
      env = honest_envelope()

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               Federation.verify_commitment(env, context(created_before: "2026-08-21T00:00:00Z"))
    end

    test "both bounds are INCLUSIVE (the receipt's exact created_at passes at each edge)" do
      env = honest_envelope()

      assert match?(
               {:ok, _},
               Federation.verify_commitment(env, context(created_after: "2026-08-22T00:00:00Z"))
             )

      assert match?(
               {:ok, _},
               Federation.verify_commitment(env, context(created_before: "2026-08-22T00:00:00Z"))
             )
    end

    test "a window containing the receipt passes" do
      env = honest_envelope()

      assert match?(
               {:ok, _},
               Federation.verify_commitment(
                 env,
                 context(
                   created_after: "2026-08-21T00:00:00Z",
                   created_before: "2026-08-23T00:00:00Z"
                 )
               )
             )
    end

    test "offset-bearing and garbage pins deny :invalid_type (the double gate)" do
      env = honest_envelope()

      for bad <- ["2026-08-22T00:00:00+02:00", "not-a-time", ""] do
        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 Federation.verify_commitment(env, context(created_after: bad))

        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 Federation.verify_commitment(env, context(created_before: bad))
      end
    end

    test "a stale AND equivocating receipt still reports the conflict (integrity outranks policy)" do
      first = honest_envelope()
      second = honest_envelope(result_material: "divergent-result-bytes")
      prior = prior_facts(first)

      assert {:error, %AgentBlueprintProtocol.Error{code: :federation_terminal_conflict}} =
               Federation.verify_commitment(
                 second,
                 context(prior_receipts: [prior], created_before: "2026-08-21T00:00:00Z")
               )
    end
  end

  describe "value-free structural guard" do
    test "every federation denial's subject is schema-shaped and detail is nil" do
      env = honest_envelope()
      wrong_audience = context(audience: "audience-other")
      stale = context(created_before: "2026-08-21T00:00:00Z")

      for {{:error, error}, _label} <- [
            {Federation.verify_commitment(env, wrong_audience), "audience"},
            {Federation.verify_commitment(env, stale), "freshness"},
            {Federation.verify_commitment(env, %Federation.Context{}), "nil-pools"}
          ] do
        assert error.detail == nil
        assert Enum.all?(error.subject, &(&1 == nil or is_binary(&1) or is_integer(&1)))
      end
    end
  end

  describe "terminal_commitment/1" do
    test "the commitment covers the seven components — mutating any covered member changes it" do
      base = honest_envelope().value

      {:ok, base_commitment} = Federation.terminal_commitment(%Federation{value: base})

      mutations = [
        fn members ->
          Enum.map(members, &put_if(&1, "task_identity", {:string, "task-other"}))
        end,
        fn members -> Enum.map(members, &put_if(&1, "terminal_state", {:string, "failed"})) end,
        fn members ->
          Enum.map(
            members,
            &put_if(
              &1,
              "result_classification_ceiling",
              {:object, [{"level", {:string, "restricted"}}, {"markers", {:array, []}}]}
            )
          )
        end,
        fn members ->
          Enum.map(
            members,
            &put_if(
              &1,
              "compatibility_reference",
              {:array,
               [{:object, [{"name", {:string, "other"}}, {"identity", {:string, "9.9.9"}}]}]}
            )
          )
        end,
        fn members ->
          Enum.map(members, &put_if(&1, "authority_proof_references", {:array, []}))
        end
      ]

      for mutate <- mutations do
        {:object, members} = base

        {:ok, mutated} =
          Federation.terminal_commitment(%Federation{value: {:object, mutate.(members)}})

        refute Digest.equal?(base_commitment, mutated),
               "commitment must change with covered content"
      end
    end

    test "the receipt's own covered members — result digest and history — change it" do
      base = honest_envelope().value
      {:ok, base_commitment} = Federation.terminal_commitment(%Federation{value: base})

      other_result =
        put_receipt_member(
          base,
          "result_digest",
          FederationFixture.tagged_digest(:federation_envelope, "r2")
        )

      {:ok, c1} = Federation.terminal_commitment(%Federation{value: other_result})
      refute Digest.equal?(base_commitment, c1)

      other_history =
        put_receipt_member(
          base,
          "checkpoint_history_commitment",
          FederationFixture.tagged_digest(:federation_envelope, "h2")
        )

      {:ok, c2} = Federation.terminal_commitment(%Federation{value: other_history})
      refute Digest.equal?(base_commitment, c2)
    end

    test "rims: malformed values deny :invalid_type" do
      for bad <- [nil, 42, %Federation{value: {:array, []}}] do
        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 Federation.terminal_commitment(bad)
      end
    end

    test "a forged non-object receipt denies :invalid_type, and missing receipt members deny typed" do
      non_object = forged_with([{"evidence_receipt", {:string, "x"}}])

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               Federation.terminal_commitment(non_object)

      missing_members = forged_with([{"evidence_receipt", {:object, []}}])

      assert {:error, %AgentBlueprintProtocol.Error{code: :missing_required_field}} =
               Federation.terminal_commitment(missing_members)

      non_string_identity = forged_with([{"task_identity", {:integer, 1}}])

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               Federation.terminal_commitment(non_string_identity)
    end
  end

  defp put_if({name, _} = pair, name, value), do: {name, value}
  defp put_if(pair, _other, _value), do: pair
end
