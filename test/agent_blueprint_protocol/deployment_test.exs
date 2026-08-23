defmodule AgentBlueprintProtocol.DeploymentTest do
  @moduledoc """
  The Deployment artifact (base §7, re-derived 2026-08-22): the 19-member
  table through the SAME generic engine, the decode pipeline (canonical
  verify → registry validation → portability scan → digest comparison), and
  the binding surface — `binds?/2` (digest equality only) and the six-stage
  `verify_binding/3` with the decided-red deny set.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{
    Blueprint,
    Canonicalization,
    Deployment,
    DeploymentFixture,
    Digest,
    Negotiation
  }

  import DeploymentFixture,
    only: [
      base_members: 1,
      build_identity: 1,
      data_binding: 1,
      eligibility: 1,
      fixture_bytes: 1,
      fixture_value: 1,
      lifecycle: 1,
      paired_blueprint: 0,
      paired_blueprint: 1,
      release_digest: 1,
      signature_entry: 1,
      tagged: 1,
      tool_binding: 1,
      with_digest: 1,
      with_signatures: 1
    ]

  # ---- decode: green ------------------------------------------------------------

  test "a complete, honest artifact decodes green" do
    assert {:ok, %Deployment{}} = Deployment.decode(fixture_bytes([]))
  end

  test "an artifact carrying signatures and empty attestations decodes green" do
    value = with_signatures([])
    {:object, members} = value
    with_empty = {:object, (members ++ [{"attestations", {:array, []}}]) |> Enum.sort()}

    {:ok, bytes} = Canonicalization.encode(with_empty)
    assert {:ok, %Deployment{}} = Deployment.decode(bytes)
  end

  test "decode rejects non-canonical bytes before any semantic read" do
    assert {:error, :non_canonical_bytes} = Deployment.decode(~s( {"authority_requirement": 1} ))
  end

  # ---- the 16 required members ----------------------------------------------------

  test "every required member absent denies :missing_required_field" do
    for {name, _} <- base_members([]) do
      members = Enum.reject(base_members([]), fn {n, _} -> n == name end)
      {:ok, bytes} = Canonicalization.encode(with_digest(members))

      assert {:error, :missing_required_field} = Deployment.decode(bytes),
             "#{name} must be required"
    end
  end

  # ---- tripwire 1: blueprint_release digest REQUIRED (ticket) ----------------------

  test "blueprint_release without content_digest denies :missing_required_field" do
    release =
      {:object,
       [
         {"blueprint_id", {:string, "example.demo/echo"}},
         {"release_number", {:integer, 1}}
       ]}

    members = replace(base_members([]), "blueprint_release", release)
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :missing_required_field} = Deployment.decode(bytes)
  end

  test "blueprint_release with a malformed digest denies :digest_encoding_invalid" do
    release =
      release_member()
      |> element_replace("content_digest", {:string, "sha-256:not-base64!"})

    members = replace(base_members([]), "blueprint_release", release)
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :digest_encoding_invalid} = Deployment.decode(bytes)
  end

  # ---- tripwire 2: digest integrity, position pinned (corpus commitment) -----------

  test "a tampered byte inside blueprint_release denies :digest_mismatch" do
    # Mutate a covered byte AFTER the honest digest was declared, so the
    # recomputation diverges exactly at the release position.
    tampered =
      fixture_value([])
      |> element_replace_in("blueprint_release", "release_number", {:integer, 2})

    {:ok, bytes} = Canonicalization.encode(tampered)
    assert {:error, :digest_mismatch} = Deployment.decode(bytes)
  end

  test "a blueprint-domain digest transplanted into deployment_digest denies :digest_mismatch" do
    members = Enum.sort(base_members([]))
    {:ok, jcs} = Canonicalization.encode({:object, members})

    blueprint_tagged = Digest.to_tagged(Digest.hash(:blueprint_content, jcs))
    {:ok, bytes} = Canonicalization.encode(fixture_value(declared_digest: blueprint_tagged))
    assert {:error, :digest_mismatch} = Deployment.decode(bytes)
  end

  # ---- tripwire 3: build_identities exactness (ticket + admitted exacts) -----------

  test "range vocabulary in version denies :compatibility_identity_inexact" do
    for bad <-
          [
            "~> 1.2",
            ">=1.0.0",
            "1.x",
            "*",
            "latest",
            "1.0.0 - 2.0.0",
            "=1.2.3",
            "",
            "~1.2.3",
            "1.2.3||2.0.0",
            "1.2.3|2.0.0",
            "1.2.3,2.0.0",
            "1.2.3;2.0.0",
            "!=1.2.3",
            "!1.2.3"
          ] do
      members =
        replace(base_members([]), "build_identities", {:array, [build_identity(version: bad)]})

      {:ok, bytes} = Canonicalization.encode(with_digest(members))

      assert {:error, :compatibility_identity_inexact} = Deployment.decode(bytes),
             "version #{inspect(bad)} must deny as inexact"
    end
  end

  test "exact prerelease and build-suffix versions stay green (the false-positive guard)" do
    for exact <- ["2.0.0-x.1", "1.0.0-x", "1.2.3+build.5", "v1.2.3", "2026.8.22"] do
      members =
        replace(base_members([]), "build_identities", {:array, [build_identity(version: exact)]})

      {:ok, bytes} = Canonicalization.encode(with_digest(members))

      assert {:ok, %Deployment{}} = Deployment.decode(bytes),
             "version #{inspect(exact)} is an exact pin and must decode"
    end
  end

  test "an empty build_identities array denies :invalid_cardinality (min 1)" do
    members = replace(base_members([]), "build_identities", {:array, []})
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :invalid_cardinality} = Deployment.decode(bytes)
  end

  # ---- tripwire 15: as_of shapes, with codes ----------------------------------------

  test "as_of shape defects deny their typed reasons" do
    bad_modes = [
      {{:object, [{"mode", {:string, "sometimes"}}, {"max_age_ms", {:integer, 1000}}]},
       :invalid_constraint},
      {{:object, [{"mode", {:string, "required"}}, {"max_age_ms", {:integer, 0}}]},
       :invalid_constraint},
      {{:object, [{"mode", {:string, "required"}}, {"max_age_ms", {:string, "1000"}}]},
       :invalid_type},
      {{:object, [{"mode", {:string, "required"}}]}, :missing_required_field},
      {{:object, [{"mode", {:string, "required"}}, {"max_age_ms", :null}]}, :invalid_constraint},
      {{:object, [{"mode", {:string, "none"}}, {"max_age_ms", {:integer, 1000}}]},
       :invalid_constraint}
    ]

    for {bad, reason} <- bad_modes do
      members = replace(base_members([]), "data_bindings", {:array, [data_binding(as_of: bad)]})
      {:ok, bytes} = Canonicalization.encode(with_digest(members))
      assert {:error, ^reason} = Deployment.decode(bytes), "as_of #{inspect(bad)}"
    end
  end

  # ---- lifecycle temporal rules -----------------------------------------------------

  test "lifecycle temporal violations deny :lifecycle_state_invalid" do
    bad_states = [
      lifecycle(
        state: "retired",
        activated_at: {:string, "2026-08-20T00:00:00Z"},
        retired_at: nil
      ),
      lifecycle(state: "active", activated_at: nil),
      lifecycle(
        state: "retired",
        activated_at: {:string, "2026-08-21T00:00:00Z"},
        retired_at: {:string, "2026-08-20T00:00:00Z"}
      ),
      lifecycle(state: "draft", activated_at: {:string, "2026-08-20T00:00:00Z"})
    ]

    for bad <- bad_states do
      members = replace(base_members([]), "lifecycle", bad)
      {:ok, bytes} = Canonicalization.encode(with_digest(members))
      assert {:error, :lifecycle_state_invalid} = Deployment.decode(bytes)
    end
  end

  test "a well-formed retired lifecycle decodes green" do
    members =
      replace(
        base_members([]),
        "lifecycle",
        lifecycle(
          state: "retired",
          activated_at: {:string, "2026-08-20T00:00:00Z"},
          retired_at: {:string, "2026-08-21T00:00:00Z"}
        )
      )

    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:ok, %Deployment{}} = Deployment.decode(bytes)
  end

  # ---- tripwire 14: host_bounds totality ---------------------------------------------

  test "host_bounds missing a bound denies, bad lattice values deny" do
    {:object, bounds} = DeploymentFixture.host_bounds()

    missing = {:object, Enum.reject(bounds, fn {n, _} -> n == "disclosure_ceiling" end)}
    members = replace(base_members([]), "host_bounds", missing)
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :missing_required_field} = Deployment.decode(bytes)

    bad = {:object, replace(bounds, "disclosure_ceiling", {:string, "everything"})}
    members = replace(base_members([]), "host_bounds", bad)
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :invalid_constraint} = Deployment.decode(bytes)
  end

  # ---- tripwires 11 + 12: never-portable in deployment positions, closed world ------

  test "never-portable classes deny :forbidden_portable_value in deployment positions" do
    # eligibility member name (any depth)
    members =
      replace(
        base_members([]),
        "eligibility",
        eligibility(owner: {:object, [{"tenant_id", {:string, "org-7"}}]})
      )

    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :forbidden_portable_value} = Deployment.decode(bytes)

    # adapter_identity as a raw endpoint (scope_projection)
    members =
      replace(
        base_members([]),
        "scope_projection",
        {:object, [{"adapter_identity", {:string, "https://tools.internal.example.com/v1"}}]}
      )

    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :forbidden_portable_value} = Deployment.decode(bytes)

    # PEM armour inside an extension body
    pem = "-----" <> "BEGIN PRIVATE KEY-----"

    members =
      replace(
        base_members([]),
        "extensions",
        DeploymentFixture.extensions(
          optional: %{"example.demo/x" => {:object, [{"key", {:string, pem}}]}}
        )
      )

    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :forbidden_portable_value} = Deployment.decode(bytes)

    # JWS-shape string in profile_identity (final segment ≥ the detector's
    # 43-char signature floor)
    jws =
      "eyJhbGciOiJFZERTQSJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0." <>
        "cHJldHR5X2NvbXBhY3Rfc2lnbmF0dXJlX3NlZ21lbnRfMDA"

    members =
      replace(base_members([]), "authority_requirement", {
        :object,
        [
          {"adapter_identity", {:string, "example.adapters.authority"}},
          {"profile_identity", {:string, jws}}
        ]
      })

    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :forbidden_portable_value} = Deployment.decode(bytes)
  end

  test "unknown members deny :unknown_member at the root and in nested objects" do
    members = base_members([]) ++ [{"mystery", {:integer, 1}}]
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :unknown_member} = Deployment.decode(bytes)

    {:object, release} = release_member()
    bad_release = {:object, release ++ [{"surprise", {:integer, 1}}]}
    members = replace(base_members([]), "blueprint_release", bad_release)
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :unknown_member} = Deployment.decode(bytes)
  end

  # ---- tripwire 12 (design): signature purpose is the artifact's fact ----------------

  test "a blueprint-purpose signature riding a Deployment denies :invalid_constraint" do
    wrong =
      signature_entry(attrs: DeploymentFixture.signature_attrs(purpose: "blueprint"))

    value = with_signatures(signatures: [wrong])
    {:ok, bytes} = Canonicalization.encode(value)
    assert {:error, :invalid_constraint} = Deployment.decode(bytes)
  end

  # ---- eligibility expressions fail closed --------------------------------------------

  test "absent or empty eligibility expressions deny" do
    members = replace(base_members([]), "eligibility", eligibility(owner: {:object, []}))
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :invalid_constraint} = Deployment.decode(bytes)

    absent =
      {:object,
       [
         {"beneficiary", {:object, [{"kind", {:string, "b"}}]}},
         {"runtime_principal", {:object, [{"kind", {:string, "r"}}]}}
       ]}

    members = replace(base_members([]), "eligibility", absent)
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :missing_required_field} = Deployment.decode(bytes)
  end

  # ---- the authored-extensions channel mirrors Blueprint ------------------------------

  test "an encoded critical body denies strict, passes via the authored channel" do
    encoded = {:string, "QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVphYmNkZWZnaGk"}

    value =
      fixture_value(
        extensions:
          DeploymentFixture.extensions(
            critical: %{"example.demo/x" => {:object, [{"blob", encoded}]}}
          )
      )

    assert {:error, :forbidden_portable_value} = Deployment.from_value(value)

    assert {:ok, %Deployment{}} =
             Deployment.from_value(value, %{authored_extensions: ["example.demo/x"]})

    # The channel is tied to THIS artifact's critical region.
    assert {:error, :invalid_type} =
             Deployment.from_value(value, %{authored_extensions: ["example.other/y"]})
  end

  # ---- binds?/2: digest equality only ---------------------------------------------------

  test "binds? is true on the honest pair and false on digest divergence" do
    {:ok, deployment} = Deployment.decode(fixture_bytes([]))
    blueprint = paired_blueprint()
    assert Deployment.binds?(deployment, blueprint)

    other = paired_blueprint(ceilings: other_ceilings())
    refute Deployment.binds?(deployment, other)
  end

  test "binds? never raises and answers false on malformed input" do
    {:ok, deployment} = Deployment.decode(fixture_bytes([]))
    blueprint = paired_blueprint()

    garbage = %Deployment{value: {:object, []}}
    refute Deployment.binds?(garbage, blueprint)
    assert Deployment.binds?(deployment, blueprint)
  end

  # ---- verify_binding/3: the six-stage decided-red deny set ------------------------------

  test "stage 1: release digest divergence denies :deployment_digest_mismatch (the headline case)" do
    {:ok, deployment} = Deployment.decode(fixture_bytes([]))
    other = paired_blueprint(ceilings: other_ceilings())

    assert {:error, :deployment_digest_mismatch} =
             Deployment.verify_binding(deployment, other, %Deployment.Observations{})
  end

  test "stage pin: the earliest failing stage reports, with later defects present too" do
    value =
      fixture_value(
        tool_bindings: [tool_binding(operation: "no.such.operation")],
        effect_owner: DeploymentFixture.effect_owner(recovery: "none")
      )

    {:ok, deployment} = decode_value(value)
    other = paired_blueprint(ceilings: other_ceilings())

    assert {:error, :deployment_digest_mismatch} =
             Deployment.verify_binding(deployment, other, %Deployment.Observations{})
  end

  test "stage 2: declared identity divergence denies :binding_incomplete" do
    blueprint = paired_blueprint()

    value =
      fixture_value(blueprint: blueprint, blueprint_id: "example.demo/other", release_number: 7)

    {:ok, deployment} = decode_value(value)

    assert {:error, :binding_incomplete} =
             Deployment.verify_binding(deployment, blueprint, %Deployment.Observations{})
  end

  test "stage 3: an orphan logical_operation denies :binding_incomplete; effect-intent sources count" do
    value = fixture_value(tool_bindings: [tool_binding(operation: "no.such.operation")])
    {:ok, deployment} = decode_value(value)
    blueprint = paired_blueprint()

    assert {:error, :binding_incomplete} =
             Deployment.verify_binding(deployment, blueprint, %Deployment.Observations{})

    value = fixture_value(tool_bindings: [tool_binding(operation: "record_summary")])
    {:ok, deployment} = decode_value(value)

    assert :ok = Deployment.verify_binding(deployment, blueprint, %Deployment.Observations{})
  end

  test "stage 4: mutation with recovery none denies :no_authoritative_recovery; authoritative is green" do
    blueprint =
      paired_blueprint(
        capabilities: [
          AgentBlueprintProtocol.BlueprintFixture.capability(
            family: "example.demo.write_shape",
            kind: "mutation"
          )
        ]
      )

    value =
      fixture_value(
        blueprint: blueprint,
        tool_bindings: [tool_binding(operation: "example.demo.write_shape")],
        effect_owner: DeploymentFixture.effect_owner(recovery: "none")
      )

    {:ok, deployment} = decode_value(value)

    assert {:error, :no_authoritative_recovery} =
             Deployment.verify_binding(deployment, blueprint, %Deployment.Observations{})

    honest =
      fixture_value(
        blueprint: blueprint,
        tool_bindings: [tool_binding(operation: "example.demo.write_shape")],
        effect_owner: DeploymentFixture.effect_owner(recovery: "authoritative")
      )

    {:ok, deployment} = decode_value(honest)
    assert :ok = Deployment.verify_binding(deployment, blueprint, %Deployment.Observations{})
  end

  test "stage 4 totality: a name in both sources with disagreeing kinds takes the stricter reading" do
    blueprint =
      paired_blueprint(
        capabilities: [
          AgentBlueprintProtocol.BlueprintFixture.capability(
            family: "example.demo.split_shape",
            kind: "read"
          )
        ],
        effects: [
          AgentBlueprintProtocol.BlueprintFixture.effect_intent(
            operation: "example.demo.split_shape",
            kind: "mutation"
          )
        ]
      )

    value =
      fixture_value(
        blueprint: blueprint,
        tool_bindings: [tool_binding(operation: "example.demo.split_shape")],
        effect_owner: DeploymentFixture.effect_owner(recovery: "none")
      )

    {:ok, deployment} = decode_value(value)

    assert {:error, :no_authoritative_recovery} =
             Deployment.verify_binding(deployment, blueprint, %Deployment.Observations{})
  end

  test "stage 5: stale and future attestations deny :binding_attestation_stale; fresh is green" do
    blueprint = paired_blueprint()
    now = ~U[2026-08-22T00:00:00Z]

    value =
      fixture_value(
        blueprint: blueprint,
        tool_bindings: [
          tool_binding(operation: "example.demo.read_shape", attested_at: "2026-08-01T00:00:00Z")
        ]
      )

    {:ok, deployment} = decode_value(value)

    stale = %Deployment.Observations{now: now, max_attestation_age_ms: 86_400_000}

    assert {:error, :binding_attestation_stale} =
             Deployment.verify_binding(deployment, blueprint, stale)

    fresh = %Deployment.Observations{
      now: ~U[2026-08-01T06:00:00Z],
      max_attestation_age_ms: 86_400_000
    }

    assert :ok = Deployment.verify_binding(deployment, blueprint, fresh)

    future_value =
      fixture_value(
        blueprint: blueprint,
        tool_bindings: [
          tool_binding(operation: "example.demo.read_shape", attested_at: "2027-01-01T00:00:00Z")
        ]
      )

    {:ok, deployment} = decode_value(future_value)
    future = %Deployment.Observations{now: now, max_attestation_age_ms: 86_400_000}

    assert {:error, :binding_attestation_stale} =
             Deployment.verify_binding(deployment, blueprint, future)
  end

  test "stage 6: observed descriptor divergence denies :binding_descriptor_mismatch; matching is green" do
    blueprint = paired_blueprint()
    binding = tool_binding(operation: "example.demo.read_shape")
    value = fixture_value(blueprint: blueprint, tool_bindings: [binding])
    {:ok, deployment} = decode_value(value)

    {"descriptor_digest", {:string, descriptor}} =
      binding |> element_of() |> List.keyfind("descriptor_digest", 0)

    rug_pull = %Deployment.Observations{
      observed: %{"example.demo.read_shape" => tagged("mutated-descriptor")}
    }

    assert {:error, :binding_descriptor_mismatch} =
             Deployment.verify_binding(deployment, blueprint, rug_pull)

    honest = %Deployment.Observations{observed: %{"example.demo.read_shape" => descriptor}}
    assert :ok = Deployment.verify_binding(deployment, blueprint, honest)

    # Observations for unbound operations are ignored (the host observes its
    # whole tool surface).
    extra = %Deployment.Observations{observed: %{"unbound.op" => tagged("whatever")}}
    assert :ok = Deployment.verify_binding(deployment, blueprint, extra)
  end

  test "absent observations skip stages 5-6 and never skip decode-time integrity" do
    {:ok, deployment} = Deployment.decode(fixture_bytes([]))
    blueprint = paired_blueprint()

    assert :ok = Deployment.verify_binding(deployment, blueprint, %Deployment.Observations{})
  end

  # ---- binds? checks what it owns; the declared member lie ------------------------------

  test "binds? uses the recomputed Blueprint digest, not the declared member" do
    honest = AgentBlueprintProtocol.BlueprintFixture.fixture_value([])
    lying = replace(honest, "content_digest", {:string, tagged("lie")})
    {:ok, blueprint} = Blueprint.from_value(lying)

    assert {:error, :digest_mismatch} = Blueprint.verify_content_digest(blueprint)

    {:ok, deployment} = Deployment.decode(fixture_bytes([]))
    assert Deployment.binds?(deployment, blueprint)
  end

  # ---- negotiation: artifact-kind-aware machinery (design decision 4) -------------------

  test "a Deployment's required_core_fields resolve against the Deployment vocabulary" do
    support = deployment_support()

    assert {:ok, %Negotiation.Outcome{required_core_fields: ["tool_bindings"]}} =
             Negotiation.negotiate(
               fixture_value(required_core_fields: ["tool_bindings"]),
               support
             )

    assert {:error, :required_core_field_unsupported} =
             Negotiation.negotiate(fixture_value(required_core_fields: ["blueprint_id"]), support)
  end

  test "a raw value with no digest member denies :missing_required_field; with both, :invalid_type" do
    support = deployment_support()

    stripped =
      case fixture_value([]) do
        {:object, members} ->
          {:object, Enum.reject(members, fn {n, _} -> n == "deployment_digest" end)}
      end

    assert {:error, :missing_required_field} = Negotiation.negotiate(stripped, support)

    both =
      case fixture_value([]) do
        {:object, members} ->
          {:object, Enum.sort([{"content_digest", {:string, tagged("both")}} | members])}
      end

    assert {:error, :invalid_type} = Negotiation.negotiate(both, support)
  end

  test "a Deployment struct negotiates through its own vocabulary" do
    {:ok, deployment} = Deployment.decode(fixture_bytes([]))

    assert {:ok, %Negotiation.Outcome{protocol_revision: 1}} =
             Negotiation.negotiate(deployment, deployment_support())
  end

  # ---- bound_release + digest surface ---------------------------------------------------

  test "bound_release parses the one bound release; covered membership is exactly 16" do
    {:ok, deployment} = Deployment.decode(fixture_bytes([]))
    blueprint = paired_blueprint()

    assert {:ok,
            %{blueprint_id: "example.demo/echo", release_number: 1, content_digest: %Digest{}}} =
             Deployment.bound_release(deployment)

    %Digest{} = expected = Blueprint.content_digest(blueprint)
    {:ok, %{content_digest: declared}} = Deployment.bound_release(deployment)
    assert Digest.equal?(declared, expected)

    for member <-
          ~w(authority_requirement blueprint_release build_identities data_bindings effect_owner
             eligibility evaluation_binding extensions host_bounds lifecycle model_policy
             protocol_revision required_core_fields scope_projection signer_custody tool_bindings) do
      assert Deployment.digest_covered?(member)
    end

    refute Deployment.digest_covered?("deployment_digest")
    refute Deployment.digest_covered?("signatures")
    refute Deployment.digest_covered?("attestations")
  end

  # ---- totality: every hand-built malformed shape answers, never drifts ------------------

  test "canonical_bytes, content_digest, and digest_input expose the honest surface" do
    {:ok, deployment} = Deployment.decode(fixture_bytes([]))

    assert Deployment.canonical_bytes(deployment) == Canonicalization.encode(fixture_value([]))

    %Digest{} = digest = Deployment.content_digest(deployment)
    {:ok, jcs} = Canonicalization.encode(Deployment.digest_input(deployment))
    assert Digest.equal?(digest, Digest.hash(:deployment_content, jcs))
  end

  test "verify_content_digest denies a value without the digest member" do
    assert {:error, :invalid_type} =
             Deployment.verify_content_digest(%Deployment{value: {:object, []}})
  end

  test "bound_release is total over malformed input" do
    assert {:error, :invalid_type} = Deployment.bound_release(%Deployment{value: {:object, []}})

    bad_digest =
      hand_built(
        blueprint_release:
          {:object,
           [
             {"blueprint_id", {:string, "example.demo/echo"}},
             {"release_number", {:integer, 1}},
             {"content_digest", {:string, "not-a-digest"}}
           ]}
      )

    assert {:error, :digest_encoding_invalid} = Deployment.bound_release(bad_digest)

    bad_number =
      hand_built(
        blueprint_release:
          {:object,
           [
             {"blueprint_id", {:string, "example.demo/echo"}},
             {"release_number", {:string, "one"}},
             {"content_digest", {:string, tagged("release")}}
           ]}
      )

    assert {:error, :invalid_type} = Deployment.bound_release(bad_number)
  end

  test "verify_binding is total over hand-built garbage" do
    blueprint = paired_blueprint()
    none = %Deployment.Observations{}

    # effect_owner without idempotency → stage 4's own reason
    no_idempotency =
      hand_built(effect_owner: {:object, [{"adapter_identity", {:string, "example.a"}}]})

    assert {:error, :invalid_type} = Deployment.verify_binding(no_idempotency, blueprint, none)

    # idempotency with a malformed recovery tag
    bad_recovery =
      hand_built(
        effect_owner:
          {:object,
           [
             {"adapter_identity", {:string, "example.a"}},
             {"idempotency",
              {:object, [{"key_derivation", {:string, "host"}}, {"recovery", {:integer, 1}}]}}
           ]}
      )

    assert {:error, :invalid_type} = Deployment.verify_binding(bad_recovery, blueprint, none)

    # an EMPTY tool_bindings array binds zero operations — green, no raise
    no_tools = hand_built(tool_bindings: {:array, []})
    assert :ok = Deployment.verify_binding(no_tools, blueprint, none)

    # a non-array tool_bindings member DENIES (fail-closed, never absent)
    string_tools = hand_built(tool_bindings: {:string, "garbage"})
    assert {:error, :invalid_type} = Deployment.verify_binding(string_tools, blueprint, none)

    # a PRESENT-BUT-NULL tool_bindings member denies (only a truly absent
    # member or an empty array is the honest zero-binding case)
    null_tools = hand_built(tool_bindings: :null)
    assert {:error, :invalid_type} = Deployment.verify_binding(null_tools, blueprint, none)

    # a non-object effect_owner member
    bad_owner = hand_built(effect_owner: {:string, "x"})
    assert {:error, :invalid_type} = Deployment.verify_binding(bad_owner, blueprint, none)

    # a malformed attested_at with a supplied clock
    bad_time = hand_built(tool_bindings: {:array, [garbage_time_binding()]})
    now = %Deployment.Observations{now: ~U[2026-08-22T00:00:00Z]}
    assert {:error, :invalid_type} = Deployment.verify_binding(bad_time, blueprint, now)

    # an observed value that is not a tagged digest
    {:ok, deployment} = Deployment.decode(fixture_bytes([]))

    bad_observed = %Deployment.Observations{observed: %{"example.demo.read_shape" => "nope"}}

    assert {:error, :digest_encoding_invalid} =
             Deployment.verify_binding(deployment, blueprint, bad_observed)
  end

  test "a non-DateTime now denies :invalid_type" do
    {:ok, deployment} = Deployment.decode(fixture_bytes([]))
    blueprint = paired_blueprint()

    assert {:error, :invalid_type} =
             Deployment.verify_binding(deployment, blueprint, %Deployment.Observations{now: :nope})
  end

  test "an unparseable descriptor or faceless entry on the artifact side DENIES (fail-closed)" do
    blueprint = paired_blueprint()

    binding =
      {:object,
       [
         {"logical_operation", {:string, "example.demo.read_shape"}},
         {"adapter_identity", {:string, "example.adapters.tools"}},
         {"descriptor_digest", {:string, "garbage"}},
         {"schema_digest", {:string, tagged("schema")}},
         {"attested_at", {:string, "2026-08-20T00:00:00Z"}}
       ]}

    faceless = {:object, [{"adapter_identity", {:string, "example.adapters.tools"}}]}

    unparsable = hand_built(tool_bindings: {:array, [binding]})
    observed = %Deployment.Observations{observed: %{"example.demo.read_shape" => tagged("x")}}

    assert {:error, :digest_encoding_invalid} =
             Deployment.verify_binding(unparsable, blueprint, observed)

    # and even with NO observations: the malformed binding denies on its own
    assert {:error, :digest_encoding_invalid} =
             Deployment.verify_binding(unparsable, blueprint, %Deployment.Observations{})

    faceless_garbage = hand_built(tool_bindings: {:array, [faceless]})

    assert {:error, :invalid_type} =
             Deployment.verify_binding(faceless_garbage, blueprint, observed)

    # a non-object element denies at stage 0
    null_element = hand_built(tool_bindings: {:array, [:null]})

    assert {:error, :invalid_type} =
             Deployment.verify_binding(null_element, blueprint, observed)
  end

  # ---- remaining table shapes -------------------------------------------------------------

  test "a zero protocol_revision and an empty attestations member and unknown required fields deny" do
    members = replace(base_members([]), "protocol_revision", {:integer, 0})
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :invalid_constraint} = Deployment.decode(bytes)

    members =
      base_members([]) ++ [{"attestations", {:array, [{:object, [{"kind", {:string, "x"}}]}]}}]

    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :attestation_malformed} = Deployment.decode(bytes)

    members = replace(base_members([]), "required_core_fields", {:array, [{:string, "mystery"}]})
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :invalid_constraint} = Deployment.decode(bytes)

    members = replace(base_members([]), "required_core_fields", {:array, [{:integer, 1}]})
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :invalid_constraint} = Deployment.decode(bytes)
  end

  test "as_of mode none shapes: null green, absent missing, wrong tag typed" do
    # (none, null) is the valid second cell
    members =
      replace(
        base_members([]),
        "data_bindings",
        {:array,
         [
           data_binding(as_of: {:object, [{"mode", {:string, "none"}}, {"max_age_ms", :null}]})
         ]}
      )

    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:ok, %Deployment{}} = Deployment.decode(bytes)

    # (none, absent) defers to the required-member recursion
    members =
      replace(
        base_members([]),
        "data_bindings",
        {:array,
         [
           data_binding(as_of: {:object, [{"mode", {:string, "none"}}]})
         ]}
      )

    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :missing_required_field} = Deployment.decode(bytes)

    # (none, string) is a typed defect
    members =
      replace(
        base_members([]),
        "data_bindings",
        {:array,
         [
           data_binding(
             as_of: {:object, [{"mode", {:string, "none"}}, {"max_age_ms", {:string, "1"}}]}
           )
         ]}
      )

    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :invalid_type} = Deployment.decode(bytes)

    # a non-object as_of denies its own type
    members =
      replace(base_members([]), "data_bindings", {:array, [data_binding(as_of: {:string, "x"})]})

    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :invalid_type} = Deployment.decode(bytes)
  end

  test "an unknown lifecycle state defers to the enum; a malformed entry denies its own reason" do
    members = replace(base_members([]), "lifecycle", {:object, [{"state", {:string, "zombie"}}]})
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :invalid_constraint} = Deployment.decode(bytes)

    broken =
      signature_entry(
        attrs:
          {:object,
           [
             {"algorithm", {:string, "Ed25519"}},
             {"created_at", {:string, "2026-08-20T00:00:00Z"}}
           ]}
      )

    value = with_signatures(signatures: [broken])
    {:ok, bytes} = Canonicalization.encode(value)
    assert {:error, reason} = Deployment.decode(bytes)
    assert reason != :invalid_constraint
  end

  test "a secret-shaped evidence key_id denies in the deployment scan" do
    key = "QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVphYmNkZWZnaGk"

    entry =
      signature_entry(
        header: AgentBlueprintProtocol.BlueprintFixture.signature_header(key),
        attrs: DeploymentFixture.signature_attrs(key_id: key)
      )

    value = with_signatures(signatures: [entry])
    {:ok, bytes} = Canonicalization.encode(value)
    assert {:error, :forbidden_portable_value} = Deployment.decode(bytes)
  end

  test "an adapter_identity inside a tool_binding is strict-scanned (the nested position)" do
    members =
      replace(
        base_members([]),
        "tool_bindings",
        {:array,
         [
           tool_binding(adapter: "https://tools.internal.example.com/v1")
         ]}
      )

    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :forbidden_portable_value} = Deployment.decode(bytes)
  end

  test "the authored channel is total over values with no extensions member" do
    assert {:error, :invalid_type} =
             Deployment.from_value({:object, []}, %{authored_extensions: ["example.demo/x"]})

    assert {:error, :invalid_type} =
             Deployment.from_value({:array, []}, %{authored_extensions: ["example.demo/x"]})
  end

  # ---- hardened-rim pins --------------------------------------------------------------------

  test "scheme-relative network references deny in strict positions" do
    members =
      replace(
        base_members([]),
        "scope_projection",
        {:object, [{"adapter_identity", {:string, "//internal.svc/scope"}}]}
      )

    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :forbidden_portable_value} = Deployment.decode(bytes)
  end

  test "a non-integer max_attestation_age_ms denies when now is supplied" do
    {:ok, deployment} = Deployment.decode(fixture_bytes([]))
    blueprint = paired_blueprint()

    bad = %Deployment.Observations{
      now: ~U[2026-08-22T00:00:00Z],
      max_attestation_age_ms: "86400000"
    }

    assert {:error, :invalid_type} = Deployment.verify_binding(deployment, blueprint, bad)
  end

  test "non-object roots answer false/deny, never raise" do
    blueprint = paired_blueprint()
    garbage = %Deployment{value: :null}

    refute Deployment.binds?(garbage, blueprint)
    assert {:error, :invalid_type} = Deployment.bound_release(garbage)

    assert {:error, :invalid_type} =
             Deployment.verify_binding(garbage, blueprint, %Deployment.Observations{})
  end

  test "a non-binary observed digest denies :invalid_type" do
    {:ok, deployment} = Deployment.decode(fixture_bytes([]))
    blueprint = paired_blueprint()

    bad = %Deployment.Observations{observed: %{"example.demo.read_shape" => 5}}

    assert {:error, :invalid_type} = Deployment.verify_binding(deployment, blueprint, bad)
  end

  test "duplicate root members deny at the binding surface (first-wins reads must not decide)" do
    blueprint = paired_blueprint()
    {:object, members} = fixture_value([])

    duplicated =
      %Deployment{
        value:
          {:object,
           members ++
             [{"effect_owner", DeploymentFixture.effect_owner(recovery: "none")}] ++ members}
      }

    assert {:error, :invalid_type} =
             Deployment.verify_binding(duplicated, blueprint, %Deployment.Observations{})

    assert {:error, :invalid_type} = Deployment.bound_release(duplicated)
    refute Deployment.binds?(duplicated, blueprint)
  end

  test "a malformed-tag digest member denies :invalid_type at negotiation" do
    support = deployment_support()

    malformed =
      case fixture_value([]) do
        {:object, ms} ->
          {:object,
           Enum.map(ms, fn {n, v} -> if n == "deployment_digest", do: {n, :null}, else: {n, v} end)}
      end

    assert {:error, :invalid_type} = Negotiation.negotiate(malformed, support)
  end

  test "revision stays first: an unsupported revision reports before an undecidable kind" do
    support = %Negotiation.Support{revisions: MapSet.new([1]), core_fields: MapSet.new([])}
    value = AgentBlueprintProtocol.BlueprintFixture.fixture_value(protocol_revision: 99)

    stripped =
      case value do
        {:object, ms} -> {:object, Enum.reject(ms, fn {n, _} -> n == "content_digest" end)}
      end

    assert {:error, :protocol_revision_unsupported} = Negotiation.negotiate(stripped, support)
  end

  # ---- helpers ---------------------------------------------------------------------------

  defp deployment_support do
    %Negotiation.Support{
      revisions: MapSet.new([1]),
      core_fields:
        MapSet.new([
          "protocol_revision",
          "required_core_fields",
          "extensions",
          "tool_bindings",
          "host_bounds",
          "lifecycle",
          "blueprint_release",
          "deployment_digest"
        ])
    }
  end

  defp other_ceilings do
    {:object,
     [
       {"max_attempts", {:integer, 9}},
       {"max_concurrency", {:integer, 9}},
       {"max_cost", {:object, [{"amount", {:integer, 9}}, {"currency", {:string, "USD"}}]}},
       {"max_depth", {:integer, 9}},
       {"max_descendants", {:integer, 9}},
       {"max_elapsed_ms", {:integer, 9}},
       {"max_fan_out", {:integer, 9}},
       {"max_tokens", {:integer, 9}}
     ]}
  end

  defp release_member do
    {:object,
     [
       {"blueprint_id", {:string, "example.demo/echo"}},
       {"release_number", {:integer, 1}},
       {"content_digest", {:string, release_digest(paired_blueprint())}}
     ]}
  end

  defp element_replace({:object, members}, name, value),
    do: {:object, Enum.map(members, fn {n, v} -> if n == name, do: {n, value}, else: {n, v} end)}

  defp element_replace_in(value, member, name, new) do
    {:object, members} = value

    {:object,
     Enum.map(members, fn {n, v} ->
       if n == member, do: {n, element_replace(v, name, new)}, else: {n, v}
     end)}
  end

  defp element_of({:object, members}), do: members

  # A %Deployment{} hand-built from the fixture WITHOUT revalidation — the
  # verify_binding totality surface.
  defp hand_built(overrides) do
    {:object, members} = fixture_value([])

    replaced =
      Enum.reduce(overrides, members, fn {name, value}, acc ->
        replace(acc, Atom.to_string(name), value)
      end)

    %Deployment{value: {:object, replaced}}
  end

  defp garbage_time_binding do
    {:object,
     [
       {"logical_operation", {:string, "example.demo.read_shape"}},
       {"adapter_identity", {:string, "example.adapters.tools"}},
       {"descriptor_digest", {:string, tagged("descriptor")}},
       {"schema_digest", {:string, tagged("schema")}},
       {"attested_at", {:string, "yesterday"}}
     ]}
  end

  defp decode_value(value) do
    {:ok, bytes} = Canonicalization.encode(value)
    Deployment.decode(bytes)
  end

  defp replace({:object, members}, name, value),
    do: {:object, replace(members, name, value)}

  defp replace(members, name, value) when is_list(members),
    do: Enum.map(members, fn {n, v} -> if n == name, do: {n, value}, else: {n, v} end)

  describe "decode catch-all (the never-raising posture at the API type boundary)" do
    test "a non-binary input denies with a typed error, never raises" do
      assert Deployment.decode(:atom) == {:error, :invalid_type}
      assert Deployment.decode(123, %{}) == {:error, :invalid_type}
    end
  end
end
