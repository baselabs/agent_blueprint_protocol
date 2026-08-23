defmodule AgentBlueprintProtocol.FederationTest do
  @moduledoc """
  Unit contract for the federation profile's envelope surface: the 23-member closed world, the decode pipeline
  (canonical-before-semantics), the cross-field rules, the portability
  pass with its mode map (:nonportable_content), the lossy-aware
  state codecs, and the carrier placement laws for both transports.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Canonicalization, Federation, FederationFixture, Json}

  @required ~w(task_identity idempotency_identity blueprint_digest deployment_digest
               input_commitment result_schema result_classification_ceiling time_policy
               resource_policy recovery_handle issuer subject audience
               identity_mapping_evidence compatibility_reference
               authority_proof_references)

  # ---- decode: the happy shapes -------------------------------------------------

  describe "decode/1" do
    test "a valid root envelope decodes and round-trips its exact bytes" do
      bytes = FederationFixture.bytes()

      assert {:ok, env} = Federation.decode(bytes)
      assert {:ok, ^bytes} = Federation.canonical_bytes(env)
    end

    test "the child variant carries parent + initiating subject" do
      assert {:ok, env} = Federation.decode(FederationFixture.bytes(parent: true))

      members = Federation.member_map(env)
      assert Map.has_key?(members, "parent_execution_reference")
      assert Map.has_key?(members, "initiating_subject")
    end

    test "the checkpoint variant decodes" do
      assert {:ok, env} = Federation.decode(FederationFixture.bytes(checkpoint: true))
      assert Map.has_key?(Federation.member_map(env), "checkpoint_status")
    end

    test "the terminal variant decodes with an opaque receipt" do
      assert {:ok, env} = Federation.decode(FederationFixture.bytes(terminal: true))
      assert Map.has_key?(Federation.member_map(env), "evidence_receipt")
    end
  end

  # ---- decode: the deny ladder (canonical first) ---------------------------------

  describe "decode/1 canonical-before-semantics" do
    test "non-canonical bytes deny :non_canonical_bytes before any semantic read" do
      # Same members, hand-serialized in non-sorted member order: the value
      # is semantically fine, the bytes are not canonical.
      value = FederationFixture.value()
      raw = hand_serialize(value)

      assert {:error, %AgentBlueprintProtocol.Error{code: :non_canonical_bytes}} =
               Federation.decode(raw)
    end
  end

  describe "decode/1 closed world" do
    test "an unknown member denies :unknown_member" do
      bad = put_json_member(FederationFixture.value(), "urgent", {:boolean, true})

      assert {:error, %AgentBlueprintProtocol.Error{code: :unknown_member}} =
               Federation.decode(bytes_of(bad))
    end

    test "dropping each required member denies :missing_required_field" do
      for member <- @required do
        bad = drop_json_member(FederationFixture.value(), member)

        assert {:error, %AgentBlueprintProtocol.Error{code: :missing_required_field}} =
                 Federation.decode(bytes_of(bad)),
               "dropping #{member} must deny"
      end
    end

    test "a wrong-typed member denies :invalid_type" do
      bad = put_json_member(FederationFixture.value(), "task_identity", {:integer, 7})

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               Federation.decode(bytes_of(bad))
    end

    test "a malformed tagged digest denies :invalid_constraint" do
      bad = put_json_member(FederationFixture.value(), "blueprint_digest", {:string, "md5:abc"})

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               Federation.decode(bytes_of(bad))
    end

    test "a non-positive policy integer denies :invalid_constraint" do
      bad =
        put_json_member(
          FederationFixture.value(),
          "time_policy",
          {:object, [{"elapsed_ms", {:integer, 0}}]}
        )

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               Federation.decode(bytes_of(bad))
    end
  end

  # ---- cross-field rules R1-R3 + terminal-supersedes ------------------------------

  describe "cross-field rules" do
    test "R1: parent without initiating subject denies" do
      bad =
        FederationFixture.value(parent: true)
        |> drop_json_member("initiating_subject")

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               Federation.decode(bytes_of(bad))
    end

    test "R2: checkpoint status without commitment denies, and vice versa" do
      no_commitment =
        FederationFixture.value(checkpoint: true)
        |> drop_json_member("checkpoint_commitment")

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               Federation.decode(bytes_of(no_commitment))

      no_status =
        FederationFixture.value(checkpoint: true)
        |> drop_json_member("checkpoint_status")

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               Federation.decode(bytes_of(no_status))
    end

    test "R3: terminal state without receipt denies, and vice versa" do
      no_receipt =
        FederationFixture.value(terminal: true)
        |> drop_json_member("evidence_receipt")

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               Federation.decode(bytes_of(no_receipt))

      no_state =
        FederationFixture.value(terminal: true)
        |> drop_json_member("terminal_state")

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               Federation.decode(bytes_of(no_state))
    end

    test "terminal supersedes: terminal + checkpoint members together deny" do
      bad =
        put_json_member(
          FederationFixture.value(terminal: true),
          "checkpoint_status",
          {:string, "working"}
        )

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               Federation.decode(bytes_of(bad))
    end
  end

  # ---- the portability pass --------------------------------------------------------

  describe "portability pass" do
    test "R4: an authority claim denies :nonportable_content with the claim's path" do
      bad = FederationFixture.value(claim_kind: "authority")

      assert {:error,
              %AgentBlueprintProtocol.Error{
                code: :nonportable_content,
                subject: ["identity_mapping_evidence", "claims", 0]
              }} = Federation.decode(bytes_of(bad))
    end

    test "a secret-shaped receipt key id denies :forbidden_portable_value" do
      secret = String.duplicate("ab", 24)

      bad =
        FederationFixture.value(terminal: true)
        |> put_json_member("evidence_receipt", fn receipt ->
          put_json_member(receipt, "signature", fn entry ->
            entry
            |> put_json_member("protected", fn p ->
              put_json_member(p, "kid", {:string, secret})
            end)
            |> put_json_member("signed_attributes", fn a ->
              put_json_member(a, "key_id", {:string, secret})
            end)
          end)
        end)

      assert {:error, %AgentBlueprintProtocol.Error{code: :forbidden_portable_value}} =
               Federation.decode(bytes_of(bad))
    end

    test "duplicate regulated markers deny :invalid_cardinality" do
      bad =
        put_json_member(
          FederationFixture.value(),
          "result_classification_ceiling",
          {:object,
           [
             {"level", {:string, "internal"}},
             {"markers", {:array, [{:string, "pci"}, {:string, "pci"}]}}
           ]}
        )

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_cardinality}} =
               Federation.decode(bytes_of(bad))
    end

    test "non-UTF-8 string bytes deny typed through the carrier path, never crash" do
      # A hand-built carrier whose body carries invalid UTF-8: the decode
      # lane's JSON gate would refuse it; the codec-reconstruction lane
      # must deny equally instead of crashing later digest encodes.
      {:ok, env} = Federation.decode(FederationFixture.bytes(checkpoint: true))
      {:ok, carrier} = Federation.to_a2a_carrier(env)

      poisoned =
        put_json_member(carrier, "metadata", fn meta ->
          put_json_member(meta, Federation.a2a_carrier_key(), fn body ->
            put_json_member(body, "issuer", {:string, <<0xFF, 0xFE>>})
          end)
        end)

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_encoding}} =
               Federation.from_a2a_carrier(poisoned)
    end

    test "an oversized carrier body denies the decoder's ceiling, not unbounded work" do
      oversized =
        put_json_member(FederationFixture.value(), "authority_proof_references", fn _ ->
          {:array,
           Enum.map(1..11_000, fn i ->
             FederationFixture.tagged_digest(:federation_envelope, "p#{i}")
           end)}
        end)

      assert {:error, %AgentBlueprintProtocol.Error{code: {:ceiling, :items}}} =
               Federation.from_value(oversized)
    end

    test "a secret-shaped claim value denies :forbidden_portable_value" do
      # 24 bytes of hex-fitting entropy: passes the segment grammar, trips
      # the value heuristics.
      bad = FederationFixture.value(claim_value: String.duplicate("ab", 24))

      assert {:error, %AgentBlueprintProtocol.Error{code: :forbidden_portable_value}} =
               Federation.decode(bytes_of(bad))
    end

    test "a URI-shaped issuer denies :invalid_constraint at the table (identifier grammar)" do
      bad = FederationFixture.value(issuer: "https://remote.example/svc")

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               Federation.decode(bytes_of(bad))
    end
  end

  # ---- state codecs: lossy-aware by construction ------------------------------------

  describe "state codecs" do
    test "the 8 mappable A2A states decode; UNSPECIFIED denies :federation_state_unmappable" do
      for spelling <- [
            "TASK_STATE_SUBMITTED",
            "TASK_STATE_WORKING",
            "TASK_STATE_COMPLETED",
            "TASK_STATE_FAILED",
            "TASK_STATE_CANCELED",
            "TASK_STATE_INPUT_REQUIRED",
            "TASK_STATE_REJECTED",
            "TASK_STATE_AUTH_REQUIRED"
          ] do
        assert {:ok, logical} = Federation.from_a2a_state(spelling)
        assert {:ok, ^spelling} = Federation.to_a2a_state(logical)
      end

      assert {:error, %AgentBlueprintProtocol.Error{code: :federation_state_unmappable}} =
               Federation.from_a2a_state("TASK_STATE_UNSPECIFIED")
    end

    test "the 5 MCP states map upward with the cancelled spelling fold" do
      for {spelling, logical} <- [
            {"working", :working},
            {"input_required", :input_required},
            {"completed", :completed},
            {"failed", :failed},
            {"cancelled", :canceled}
          ] do
        assert Federation.from_mcp_state(spelling) == {:ok, logical}
        assert Federation.to_mcp_state(logical) == {:ok, spelling}
      end
    end

    test "to_mcp_state denies the states with no MCP counterpart" do
      for logical <- [:rejected, :submitted, :auth_required] do
        assert {:error, %AgentBlueprintProtocol.Error{code: :federation_state_unmappable}} =
                 Federation.to_mcp_state(logical)
      end
    end

    test "unknown spellings deny :invalid_constraint, never raise" do
      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               Federation.from_a2a_state("TASK_STATE_WAT")

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               Federation.from_mcp_state("paused")

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               Federation.to_a2a_state("completed")

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               Federation.from_a2a_state(42)
    end
  end

  # ---- carriers: placement laws + round-trips -----------------------------------------

  describe "A2A carrier" do
    test "placement: native homes populated, body carries exactly the 19 non-native members" do
      {:ok, env} = Federation.decode(FederationFixture.bytes(parent: true, checkpoint: true))
      {:ok, carrier} = Federation.to_a2a_carrier(env)

      assert carrier_key_set(carrier, "metadata") ==
               MapSet.new([Federation.a2a_carrier_key()])

      assert carrier_member(carrier, "id") == {:string, "task-7f3a2c"}

      assert match?(
               {:object, [{"state", {:string, "TASK_STATE_" <> _}}]},
               carrier_member(carrier, "status")
             )

      body = carrier_body(carrier, Federation.a2a_carrier_key())

      # Base fixture: 16 present required members, 2 of them native
      # (task_identity, recovery_handle) → 14 body members; the parent
      # variant adds 2 (parent_execution_reference, initiating_subject),
      # the checkpoint variant adds 2 body members (checkpoint_request,
      # checkpoint_commitment — checkpoint_status is native).
      assert MapSet.size(body_key_set(body)) == 18
      assert not MapSet.member?(body_key_set(body), "task_identity")
      assert not MapSet.member?(body_key_set(body), "recovery_handle")
      assert not MapSet.member?(body_key_set(body), "checkpoint_status")
    end

    test "a divergent recovery handle denies :federation_mapping_conflict" do
      {:ok, env} = Federation.decode(FederationFixture.bytes(recovery_handle: "task-other"))

      assert {:error, %AgentBlueprintProtocol.Error{code: :federation_mapping_conflict}} =
               Federation.to_a2a_carrier(env)
    end

    test "round-trip is byte-stable" do
      bytes = FederationFixture.bytes(parent: true, checkpoint: true)
      {:ok, env} = Federation.decode(bytes)
      {:ok, carrier} = Federation.to_a2a_carrier(env)
      {:ok, back} = Federation.from_a2a_carrier(carrier)

      assert Federation.canonical_bytes(back) == {:ok, bytes}
    end

    test "a state-less envelope has no Task image and denies the carrier" do
      # A2A Tasks REQUIRE status; an envelope with no observed state is a
      # message-context payload (rows 3/7 homes), never a Task carrier.
      {:ok, env} = Federation.decode(FederationFixture.bytes(parent: true))

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               Federation.to_a2a_carrier(env)
    end

    test "a native member double-placed in the body denies :federation_mapping_conflict" do
      {:ok, env} = Federation.decode(FederationFixture.bytes(checkpoint: true))
      {:ok, carrier} = Federation.to_a2a_carrier(env)

      tampered =
        put_json_member(carrier, "metadata", fn meta ->
          put_json_member(meta, Federation.a2a_carrier_key(), fn body ->
            put_json_member(body, "task_identity", {:string, "task-forge"})
          end)
        end)

      assert {:error, %AgentBlueprintProtocol.Error{code: :federation_mapping_conflict}} =
               Federation.from_a2a_carrier(tampered)
    end

    test "an UNSPECIFIED status on the carrier denies at intake" do
      {:ok, env} = Federation.decode(FederationFixture.bytes(checkpoint: true))
      {:ok, carrier} = Federation.to_a2a_carrier(env)

      unspecified =
        put_json_member(
          carrier,
          "status",
          {:object, [{"state", {:string, "TASK_STATE_UNSPECIFIED"}}]}
        )

      assert {:error, %AgentBlueprintProtocol.Error{code: :federation_state_unmappable}} =
               Federation.from_a2a_carrier(unspecified)
    end

    test "a terminal envelope rides its terminal state natively" do
      {:ok, env} = Federation.decode(FederationFixture.bytes(terminal: true))
      {:ok, carrier} = Federation.to_a2a_carrier(env)

      assert carrier_member(carrier, "status") ==
               {:object, [{"state", {:string, "TASK_STATE_COMPLETED"}}]}

      assert not MapSet.member?(
               body_key_set(carrier_body(carrier, Federation.a2a_carrier_key())),
               "terminal_state"
             )
    end
  end

  describe "MCP carrier" do
    test "placement: taskId + status + _meta under the namespace key" do
      {:ok, env} = Federation.decode(FederationFixture.bytes(checkpoint: true))
      {:ok, carrier} = Federation.to_mcp_carrier(env)

      assert carrier_member(carrier, "taskId") == {:string, "task-7f3a2c"}
      assert carrier_member(carrier, "status") == {:string, "working"}
      assert carrier_key_set(carrier, "_meta") == MapSet.new([Federation.mcp_carrier_key()])

      assert not MapSet.member?(
               body_key_set(carrier_body(carrier, Federation.mcp_carrier_key())),
               "checkpoint_status"
             )
    end

    test "to_mcp denies the lossy states before placement" do
      {:ok, rejected} =
        Federation.decode(FederationFixture.bytes(terminal: true, terminal_state: "rejected"))

      assert {:error, %AgentBlueprintProtocol.Error{code: :federation_state_unmappable}} =
               Federation.to_mcp_carrier(rejected)

      {:ok, submitted} =
        Federation.decode(
          FederationFixture.bytes(checkpoint: true, checkpoint_status: "submitted")
        )

      assert {:error, %AgentBlueprintProtocol.Error{code: :federation_state_unmappable}} =
               Federation.to_mcp_carrier(submitted)

      {:ok, auth_required} =
        Federation.decode(
          FederationFixture.bytes(checkpoint: true, checkpoint_status: "auth_required")
        )

      assert {:error, %AgentBlueprintProtocol.Error{code: :federation_state_unmappable}} =
               Federation.to_mcp_carrier(auth_required)
    end

    test "round-trip is byte-stable including the cancelled spelling fold" do
      bytes = FederationFixture.bytes(terminal: true, terminal_state: "canceled")
      {:ok, env} = Federation.decode(bytes)
      {:ok, carrier} = Federation.to_mcp_carrier(env)
      assert carrier_member(carrier, "status") == {:string, "cancelled"}

      {:ok, back} = Federation.from_mcp_carrier(carrier)
      assert Federation.canonical_bytes(back) == {:ok, bytes}
    end
  end

  # ---- rim probes (the design-note §6 law: every catch-all gets a test) ---------

  describe "rim denials (never-raising)" do
    test "a non-string digest member denies :invalid_type (custom kind reaches the check)" do
      bad = put_json_member(FederationFixture.value(), "blueprint_digest", {:integer, 5})

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               Federation.decode(bytes_of(bad))
    end

    test "an unparseable receipt signature denies :invalid_constraint" do
      bad =
        FederationFixture.value(terminal: true)
        |> put_json_member("evidence_receipt", fn receipt ->
          put_json_member(receipt, "signature", {:string, "not-base64url!!"})
        end)

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               Federation.decode(bytes_of(bad))
    end

    test "from_value denies a value the engine rejects (else-clause path)" do
      bad = put_json_member(FederationFixture.value(), "urgent", {:boolean, true})

      assert {:error, %AgentBlueprintProtocol.Error{code: :unknown_member}} =
               Federation.from_value(bad)
    end

    test "from_value denies a portability failure without re-wrapping the error" do
      bad = FederationFixture.value(claim_kind: "authority")

      assert {:error,
              %AgentBlueprintProtocol.Error{
                code: :nonportable_content,
                subject: ["identity_mapping_evidence", "claims", 0]
              }} = Federation.from_value(bad)
    end

    test "a forbidden compatibility identity denies :forbidden_portable_value" do
      bad =
        put_json_member(FederationFixture.value(), "compatibility_reference", fn _ ->
          {:array,
           [
             {:object,
              [
                {"name", {:string, "abp"}},
                {"identity", {:string, String.duplicate("cd", 24)}}
              ]}
           ]}
        end)

      assert {:error, %AgentBlueprintProtocol.Error{code: :forbidden_portable_value}} =
               Federation.decode(bytes_of(bad))
    end

    test "a secret-shaped identifier member denies :forbidden_portable_value" do
      bad = FederationFixture.value(issuer: String.duplicate("ab", 24))

      assert {:error, %AgentBlueprintProtocol.Error{code: :forbidden_portable_value}} =
               Federation.decode(bytes_of(bad))
    end

    test "an unknown logical atom denies to_a2a_state :invalid_type" do
      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               Federation.to_a2a_state(:banana)
    end

    test "a metadata map missing the carrier key denies :missing_required_field" do
      {:ok, env} = Federation.decode(FederationFixture.bytes(checkpoint: true))
      {:ok, carrier} = Federation.to_a2a_carrier(env)

      bare =
        put_json_member(carrier, "metadata", {:object, [{"other-extension", {:object, []}}]})

      assert {:error, %AgentBlueprintProtocol.Error{code: :missing_required_field}} =
               Federation.from_a2a_carrier(bare)
    end

    test "decode rejects non-binary input" do
      for bad <- [nil, 42, ~c"bytes", {:object, []}] do
        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 Federation.decode(bad)
      end
    end

    test "an empty claim value or compatibility identity denies typed, never raises" do
      # the second-language mirror's parity finding: check_nonempty/1 had no
      # fallback clause, so a claim (or compatibility identity) carrying ""
      # CRASHED decode with FunctionClauseError (probed live 2026-08-23)
      # instead of denying. The fallback restores the never-raising posture.
      {:ok, base} = Federation.decode(FederationFixture.bytes())
      {:ok, bytes} = Federation.canonical_bytes(base)
      {:ok, root} = Json.decode(bytes)

      empty_claim_value = fn {:object, ims} ->
        {:object,
         Enum.map(ims, fn
           {"claims", {:array, claims}} ->
             {"claims",
              {:array,
               Enum.map(claims, fn {:object, claim} ->
                 {:object,
                  Enum.map(claim, fn
                    {"value", {:string, _}} -> {"value", {:string, ""}}
                    other -> other
                  end)}
               end)}}

           other ->
             other
         end)}
      end

      {:ok, emptied} =
        Canonicalization.encode(
          put_json_member(root, "identity_mapping_evidence", empty_claim_value)
        )

      with_emptied_claim = Federation.decode(emptied)

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               with_emptied_claim

      empty_identity = fn {:array, refs} ->
        {:array,
         Enum.map(refs, fn {:object, ref} ->
           {:object,
            Enum.map(ref, fn
              {"identity", {:string, _}} -> {"identity", {:string, ""}}
              other -> other
            end)}
         end)}
      end

      {:ok, emptied_ref} =
        Canonicalization.encode(put_json_member(root, "compatibility_reference", empty_identity))

      with_empty_identity = Federation.decode(emptied_ref)

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               with_empty_identity
    end

    test "from_value rejects non-object input" do
      for bad <- ["{}", {:array, []}, {:string, "x"}, nil] do
        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 Federation.from_value(bad)
      end
    end

    test "state codec rims: non-binary spellings and non-atom logicals deny :invalid_type" do
      for bad <- [nil, 42, :completed] do
        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 Federation.from_a2a_state(bad)

        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 Federation.from_mcp_state(bad)
      end

      # nil IS an atom in Elixir, so it rides the atom clause of to_mcp/1
      # into the unmappable branch — the documented behavior, not a rim miss.
      for bad <- ["completed", 42] do
        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 Federation.to_a2a_state(bad)

        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 Federation.to_mcp_state(bad)
      end

      assert {:error, %AgentBlueprintProtocol.Error{code: :federation_state_unmappable}} =
               Federation.to_mcp_state(nil)
    end

    test "carrier rims: malformed carriers deny typed, never raise" do
      for bad <- ["{}", {:array, []}, nil, 42] do
        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 Federation.from_a2a_carrier(bad)

        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 Federation.from_mcp_carrier(bad)
      end

      for bad <- [nil, 42, %{}] do
        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 Federation.to_a2a_carrier(bad)

        assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
                 Federation.to_mcp_carrier(bad)
      end
    end

    test "an A2A carrier missing its native homes denies per-member" do
      {:ok, env} = Federation.decode(FederationFixture.bytes(checkpoint: true))
      {:ok, carrier} = Federation.to_a2a_carrier(env)

      for dropped <- ["id", "status", "metadata"] do
        assert {:error, %AgentBlueprintProtocol.Error{code: :missing_required_field}} =
                 Federation.from_a2a_carrier(drop_json_member(carrier, dropped))
      end

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               Federation.from_a2a_carrier(put_json_member(carrier, "id", {:integer, 7}))

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               Federation.from_a2a_carrier(put_json_member(carrier, "status", {:string, "x"}))

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               Federation.from_a2a_carrier(put_json_member(carrier, "metadata", {:array, []}))
    end

    test "an MCP carrier missing its native homes denies per-member" do
      {:ok, env} = Federation.decode(FederationFixture.bytes(checkpoint: true))
      {:ok, carrier} = Federation.to_mcp_carrier(carrier_env(env))

      for dropped <- ["taskId", "status", "_meta"] do
        assert {:error, %AgentBlueprintProtocol.Error{code: :missing_required_field}} =
                 Federation.from_mcp_carrier(drop_json_member(carrier, dropped))
      end
    end

    test "a carrier body key that is not an object denies :invalid_type" do
      {:ok, env} = Federation.decode(FederationFixture.bytes(checkpoint: true))
      {:ok, carrier} = Federation.to_a2a_carrier(env)

      smashed =
        put_json_member(carrier, "metadata", fn meta ->
          put_json_member(meta, Federation.a2a_carrier_key(), {:string, "opaque"})
        end)

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               Federation.from_a2a_carrier(smashed)
    end

    test "a forged struct's unknown state spelling denies instead of crashing" do
      forged = forged_state_struct("checkpoint_status", {:string, "banana"})

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}} =
               Federation.to_a2a_carrier(forged)

      forged_nonstring = forged_state_struct("terminal_state", {:integer, 3})

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               Federation.to_mcp_carrier(forged_nonstring)
    end
  end

  defp carrier_env(env), do: env

  # A forged struct whose identity members agree (the recovery gate passes)
  # but whose state member is garbage — the wire_to_logical rim.
  defp forged_state_struct(member, value) do
    %Federation{
      value:
        {:object,
         [
           {"task_identity", {:string, "t"}},
           {"recovery_handle", {:string, "t"}},
           {member, value}
         ]}
    }
  end

  # ---- helpers ---------------------------------------------------------------------

  defp bytes_of({:object, _} = value) do
    {:ok, jcs} = Canonicalization.encode(value)
    jcs
  end

  defp hand_serialize({:object, members}) do
    # Deliberately non-sorted member order, whitespace included: the same
    # VALUE, non-canonical BYTES.
    inner =
      Enum.map_join(members, ",", fn {name, value} -> ~s("#{name}":#{hand_serialize(value)}) end)

    "{" <> inner <> "}"
  end

  defp hand_serialize({:string, s}), do: ~s("#{s}")
  defp hand_serialize({:integer, n}), do: Integer.to_string(n)
  defp hand_serialize({:boolean, b}), do: to_string(b)

  defp hand_serialize({:array, items}),
    do: "[" <> Enum.map_join(items, ",", &hand_serialize/1) <> "]"

  defp put_json_member({:object, members}, name, value) when is_function(value, 1) do
    {:object, Enum.map(members, fn {n, v} -> {n, if(n == name, do: value.(v), else: v)} end)}
  end

  defp put_json_member({:object, members}, name, value) do
    if List.keymember?(members, name, 0) do
      {:object, Enum.map(members, fn {n, v} -> {n, if(n == name, do: value, else: v)} end)}
    else
      {:object, members ++ [{name, value}]}
    end
  end

  defp drop_json_member({:object, members}, name),
    do: {:object, Enum.reject(members, fn {n, _} -> n == name end)}

  defp carrier_member({:object, members}, name) do
    {_, value} = Enum.find(members, fn {n, _} -> n == name end)
    value
  end

  defp carrier_key_set({:object, members}, name) do
    {_, {:object, inner}} = Enum.find(members, fn {n, _} -> n == name end)
    MapSet.new(Enum.map(inner, &elem(&1, 0)))
  end

  defp carrier_body({:object, members}, key) do
    {_, {:object, inner}} = Enum.find(members, fn {n, _} -> n == "metadata" || n == "_meta" end)
    {_, body} = Enum.find(inner, fn {n, _} -> n == key end)
    body
  end

  defp body_key_set({:object, members}), do: MapSet.new(Enum.map(members, &elem(&1, 0)))
end
