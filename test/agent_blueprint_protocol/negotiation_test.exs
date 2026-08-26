defmodule AgentBlueprintProtocol.NegotiationTest do
  @moduledoc """
  Negotiation: the revision SET, the three required-core-fields checks, the
  positional extension state machine, critical-body validation against
  digest-pinned host schemas, the reserved-semantics denylist, and the
  pinned internal precedence (revision → required_core_fields → extensions).
  """

  use ExUnit.Case, async: true

  import AgentBlueprintProtocol.BlueprintFixture, only: [base_members: 1, extensions: 1]

  alias AgentBlueprintProtocol.{
    Blueprint,
    Canonicalization,
    Digest,
    ExtensionRegistry,
    Negotiation
  }

  defp artifact_value(opts \\ []) do
    members =
      base_members([])
      |> replace("protocol_revision", {:integer, Keyword.get(opts, :revision, 1)})
      |> replace("extensions", Keyword.get(opts, :extensions, extensions([])))
      |> replace(
        "required_core_fields",
        {:array, Enum.map(Keyword.get(opts, :requires, []), &{:string, &1})}
      )
      |> maybe_unknown_member(Keyword.get(opts, :unknown_member, false))
      |> maybe_bad_enum(Keyword.get(opts, :bad_enum, false))

    AgentBlueprintProtocol.BlueprintFixture.with_digest(members)
  end

  defp replace(members, name, value) do
    Enum.map(members, fn
      {^name, _} -> {name, value}
      other -> other
    end)
  end

  defp maybe_unknown_member(members, true), do: members ++ [{"mystery", {:integer, 1}}]
  defp maybe_unknown_member(members, false), do: members

  defp maybe_bad_enum(members, true),
    do: replace(members, "classification_ceiling", {:string, "topsecret"})

  defp maybe_bad_enum(members, false), do: members

  defp support(opts \\ []) do
    %Negotiation.Support{
      revisions: Keyword.get(opts, :revisions, MapSet.new([1])),
      core_fields:
        Keyword.get(opts, :core_fields, MapSet.new(~w(blueprint_id producer triggers))),
      registry: Keyword.get(opts, :registry, %{}),
      schemas: Keyword.get(opts, :schemas, %{})
    }
  end

  # ---- revision ------------------------------------------------------------------

  test "an in-set revision negotiates green with the exact artifact revision" do
    assert {:ok, outcome} = Negotiation.negotiate(artifact_value(), support())
    assert outcome.protocol_revision == 1
    assert outcome.critical_extensions == []
    assert outcome.optional_retained == []
    assert outcome.quarantined_extensions == []
    assert outcome.notices == [] || outcome.notices == nil || Enum.empty?(outcome.notices)
  end

  test "a revision outside the set denies :protocol_revision_unsupported (above and below)" do
    assert {:error, :protocol_revision_unsupported} =
             Negotiation.negotiate(artifact_value(revision: 2), support())

    assert {:error, :protocol_revision_unsupported} =
             Negotiation.negotiate(
               artifact_value(revision: 1),
               support(revisions: MapSet.new([2]))
             )
  end

  test "the ordering pin: max+1 outranks every structural and extension failure" do
    value =
      artifact_value(
        revision: 2,
        unknown_member: true,
        bad_enum: true,
        extensions: extensions(critical: %{"com.example.unknown/x" => {:object, []}})
      )

    assert {:error, :protocol_revision_unsupported} = Negotiation.negotiate(value, support())
  end

  test "malformed machinery values reuse the decode reason rules" do
    no_rev =
      artifact_value()
      |> then(fn {:object, members} ->
        {:object, Enum.reject(members, fn {n, _} -> n == "protocol_revision" end)}
      end)

    assert {:error, :missing_required_field} = Negotiation.negotiate(no_rev, support())

    float_rev =
      artifact_value()
      |> then(fn {:object, m} -> {:object, replace(m, "protocol_revision", {:float, 1.0})} end)

    assert {:error, :invalid_type} = Negotiation.negotiate(float_rev, support())

    zero_rev =
      artifact_value()
      |> then(fn {:object, m} -> {:object, replace(m, "protocol_revision", {:integer, 0})} end)

    assert {:error, :invalid_constraint} = Negotiation.negotiate(zero_rev, support())
  end

  # ---- required_core_fields --------------------------------------------------------

  test "the three fail-closed checks with their pinned reasons and order" do
    unknown = artifact_value(requires: ["bogus"])
    assert {:error, :required_core_field_unsupported} = Negotiation.negotiate(unknown, support())

    evidence = artifact_value(requires: ["signatures"])

    assert {:error, :required_core_field_not_digest_covered} =
             Negotiation.negotiate(evidence, support())

    covered_unsupported =
      artifact_value(requires: ["ceilings"])

    assert {:error, :required_core_field_unsupported} =
             Negotiation.negotiate(covered_unsupported, support())

    # known-and-covered but evidence: not-covered fires before unsupported.
    evidence_unsupported = artifact_value(requires: ["attestations"])

    assert {:error, :required_core_field_not_digest_covered} =
             Negotiation.negotiate(evidence_unsupported, support())

    assert {:ok, outcome} =
             Negotiation.negotiate(artifact_value(requires: ["blueprint_id"]), support())

    assert outcome.required_core_fields == ["blueprint_id"]
  end

  test "required_core_fields precedes extensions in the pinned order" do
    value =
      artifact_value(
        requires: ["bogus"],
        extensions: extensions(critical: %{"com.example.unknown/x" => {:object, []}})
      )

    assert {:error, :required_core_field_unsupported} = Negotiation.negotiate(value, support())
  end

  # ---- the extension state machine ---------------------------------------------------

  defp entry(opts) do
    struct!(
      ExtensionRegistry.registered_extensions() |> hd(),
      Keyword.merge([state: :active, schema_digest: nil, promoted_at_revision: nil], opts)
    )
  end

  test "unregistered critical denies; unregistered optional QUARANTINES green" do
    unknown = %{"com.example.unknown/x" => {:object, [{"payload", {:integer, 1}}]}}

    assert {:error, :extension_unknown_critical} =
             Negotiation.negotiate(
               artifact_value(extensions: extensions(critical: unknown)),
               support()
             )

    assert {:ok, outcome} =
             Negotiation.negotiate(
               artifact_value(extensions: extensions(optional: unknown)),
               support()
             )

    assert outcome.quarantined_extensions == ["com.example.unknown/x"]
    assert outcome.notices == [:extension_unknown_optional_retained]
  end

  test "criticality conflict denies in BOTH directions, before state handling" do
    # registry says critical, artifact says optional (the real graph entry).
    assert {:error, :extension_criticality_conflict} =
             Negotiation.negotiate(
               artifact_value(
                 extensions:
                   extensions(optional: %{"com.example.commerce/graph" => {:object, []}})
               ),
               support()
             )

    # registry says optional, artifact says critical — via a host-pinned view.
    pinned = %{
      "example.test/flip" => entry(namespace: "example.test/flip", criticality: :optional)
    }

    assert {:error, :extension_criticality_conflict} =
             Negotiation.negotiate(
               artifact_value(
                 extensions: extensions(critical: %{"example.test/flip" => {:object, []}})
               ),
               support(registry: pinned)
             )
  end

  test "deprecated matching: supported/retained with a notice; conflict still denies first" do
    schema = ExtensionRegistry.federation_schema()

    pinned = %{
      "example.test/dep" =>
        entry(
          namespace: "example.test/dep",
          state: :deprecated,
          criticality: :critical,
          schema_digest: digest_of(schema)
        )
    }

    assert {:ok, outcome} =
             Negotiation.negotiate(
               artifact_value(extensions: extensions(critical: %{"example.test/dep" => body()})),
               support(registry: pinned, schemas: %{"example.test/dep" => schema})
             )

    assert outcome.critical_extensions == ["example.test/dep"]
    assert outcome.notices == [:extension_deprecated]

    # deprecated + position mismatch = conflict, not notice.
    assert {:error, :extension_criticality_conflict} =
             Negotiation.negotiate(
               artifact_value(
                 extensions: extensions(optional: %{"example.test/dep" => {:object, []}})
               ),
               support(registry: pinned)
             )
  end

  test "retired: critical denies, optional retains with a notice" do
    crit = %{
      "example.test/old" =>
        entry(namespace: "example.test/old", state: :retired, criticality: :critical)
    }

    assert {:error, :extension_retired} =
             Negotiation.negotiate(
               artifact_value(
                 extensions: extensions(critical: %{"example.test/old" => {:object, []}})
               ),
               support(registry: crit)
             )

    assert {:ok, outcome} =
             Negotiation.negotiate(
               artifact_value(
                 extensions: extensions(optional: %{"example.test/old" => {:object, []}})
               ),
               support(registry: crit)
             )

    assert outcome.optional_retained == ["example.test/old"]
    assert outcome.notices == [:extension_retired]
  end

  test "reserved state: critical denies unknown-critical, optional retains with a notice" do
    res = %{
      "example.test/res" =>
        entry(namespace: "example.test/res", state: :reserved, criticality: :optional)
    }

    assert {:error, :extension_unknown_critical} =
             Negotiation.negotiate(
               artifact_value(
                 extensions: extensions(critical: %{"example.test/res" => {:object, []}})
               ),
               support(registry: res)
             )

    assert {:ok, outcome} =
             Negotiation.negotiate(
               artifact_value(
                 extensions: extensions(optional: %{"example.test/res" => {:object, []}})
               ),
               support(registry: res)
             )

    assert outcome.optional_retained == ["example.test/res"]
  end

  test "a registered matching optional extension is retained, executable, unnotified" do
    assert {:ok, outcome} =
             Negotiation.negotiate(
               artifact_value(
                 extensions:
                   extensions(
                     optional: %{"com.example.commerce/classification-labels" => {:object, []}}
                   )
               ),
               support()
             )

    assert outcome.optional_retained == ["com.example.commerce/classification-labels"]
    assert outcome.quarantined_extensions == []
    assert outcome.notices == []
  end

  test "a deprecated optional namespace retains its body WITH a typed notice" do
    # The placeholder estate namespace, deprecated at the estate-contract
    # registration: retained (old artifacts stay verifiable) but never silently —
    # the notice is the honesty record.
    assert {:ok, outcome} =
             Negotiation.negotiate(
               artifact_value(
                 extensions:
                   extensions(optional: %{"com.example.platform/estate" => {:object, []}})
               ),
               support()
             )

    assert outcome.optional_retained == ["com.example.platform/estate"]
    assert outcome.notices == [:extension_deprecated]
  end

  # ---- critical body validation ---------------------------------------------------------

  test "a critical body without a host-supplied schema denies :extension_schema_unavailable" do
    assert {:error, :extension_schema_unavailable} =
             Negotiation.negotiate(
               artifact_value(
                 extensions: extensions(critical: %{"com.example/federation" => {:object, []}})
               ),
               support()
             )
  end

  test "a wrong-digest host schema denies :extension_schema_digest_mismatch" do
    wrong = {:object, [{"type", {:string, "object"}}]}

    assert {:error, :extension_schema_digest_mismatch} =
             Negotiation.negotiate(
               artifact_value(
                 extensions: extensions(critical: %{"com.example/federation" => body()})
               ),
               support(schemas: %{"com.example/federation" => wrong})
             )
  end

  test "a matching schema validates the body; instance failure passes the schema reason" do
    good_body = {:object, [{"issuer", {:string, "example.demo"}}]}
    schema = ExtensionRegistry.federation_schema()

    assert {:ok, outcome} =
             Negotiation.negotiate(
               artifact_value(
                 extensions: extensions(critical: %{"com.example/federation" => good_body})
               ),
               support(schemas: %{"com.example/federation" => schema})
             )

    assert outcome.critical_extensions == ["com.example/federation"]

    bad_body = {:object, [{"issuer", {:integer, 5}}]}

    assert {:error, :invalid_type} =
             Negotiation.negotiate(
               artifact_value(
                 extensions: extensions(critical: %{"com.example/federation" => bad_body})
               ),
               support(schemas: %{"com.example/federation" => schema})
             )
  end

  defp body, do: {:object, [{"issuer", {:string, "example.demo"}}]}

  # ---- reserved-semantics denylist ---------------------------------------------------------

  test "bound-shaped keys inside ANY extension body deny :extension_payload_forbidden" do
    for key <- [
          "max_depth",
          "maxDepth",
          "max-depth",
          "MAX_DEPTH",
          "CLASSIFICATION-CEILING",
          "classification_ceiling",
          "classificationCeiling",
          "authorityTrait",
          "disclosure_ceiling"
        ] do
      smuggle = %{"com.example.unknown/x" => {:object, [{key, {:integer, 8}}]}}

      assert {:error, :extension_payload_forbidden} =
               Negotiation.negotiate(
                 artifact_value(extensions: extensions(optional: smuggle)),
                 support()
               ),
             key
    end

    # at depth, and in critical bodies too.
    deep = %{
      "com.example.unknown/x" =>
        {:object, [{"outer", {:object, [{"max_fan_out", {:integer, 4}}]}}]}
    }

    assert {:error, :extension_payload_forbidden} =
             Negotiation.negotiate(
               artifact_value(extensions: extensions(optional: deep)),
               support()
             )

    crit = %{"com.example/federation" => {:object, [{"max_depth", {:integer, 8}}]}}

    assert {:error, :extension_payload_forbidden} =
             Negotiation.negotiate(
               artifact_value(extensions: extensions(critical: crit)),
               support(
                 schemas: %{"com.example/federation" => ExtensionRegistry.federation_schema()}
               )
             )
  end

  # ---- quarantine + the composed import ------------------------------------------------------

  test "quarantine round-trip is byte-exact through the composed import" do
    unknown = %{
      "com.example.unknown/x" => {:object, [{"note", {:string, "opaque_" <> "payload"}}]}
    }

    value = artifact_value(extensions: extensions(optional: unknown))
    {:ok, bytes} = Canonicalization.encode(value)

    with {:ok, verified} <- Canonicalization.verify(bytes),
         {:ok, outcome} <- Negotiation.negotiate(verified, support()),
         {:ok, bp} <- Blueprint.from_value(verified),
         :ok <- Blueprint.verify_content_digest(bp) do
      assert outcome.quarantined_extensions == ["com.example.unknown/x"]
      assert {:ok, ^bytes} = Blueprint.canonical_bytes(bp)

      # The fixed point: decode → to_value → encode → decode.
      assert {:ok, second} = Blueprint.from_value(Blueprint.to_value(bp))
      assert {:ok, ^bytes} = Blueprint.canonical_bytes(second)
      assert {:ok, second_outcome} = Negotiation.negotiate(Blueprint.to_value(second), support())
      assert second_outcome.quarantined_extensions == outcome.quarantined_extensions
    else
      other -> flunk("composed import failed: #{inspect(other)}")
    end
  end

  test "the composed import still catches a tamper after negotiation" do
    value = artifact_value()
    {:ok, bytes} = Canonicalization.encode(value)
    tampered = String.replace(bytes, ~s("release_number":1), ~s("release_number":2))

    assert {:ok, verified} = Canonicalization.verify(tampered)
    assert {:ok, _outcome} = Negotiation.negotiate(verified, support())
    assert {:ok, bp} = Blueprint.from_value(verified)
    assert {:error, :digest_mismatch} = Blueprint.verify_content_digest(bp)
  end

  test "region totality, override pins, denylist spellings" do
    # A non-object region and a junk region member deny
    # :invalid_type through the composed path (verify accepts these bytes).
    bad_region =
      artifact_value()
      |> then(fn {:object, m} ->
        {:object,
         replace(
           m,
           "extensions",
           {:object, [{"critical", {:array, []}}, {"optional", {:object, []}}]}
         )}
      end)

    assert {:error, :invalid_type} = Negotiation.negotiate(bad_region, support())

    junk_region =
      artifact_value()
      |> then(fn {:object, m} ->
        {:object,
         replace(
           m,
           "extensions",
           {:object,
            [{"critical", {:object, []}}, {"junk", {:integer, 1}}, {"optional", {:object, []}}]}
         )}
      end)

    assert {:error, :invalid_type} = Negotiation.negotiate(junk_region, support())

    # A host override cannot re-classify a compiled entry.
    {:ok, compiled} = ExtensionRegistry.entry("com.example.commerce/graph")
    flipped = %{"com.example.commerce/graph" => struct!(compiled, criticality: :optional)}

    assert {:error, :extension_criticality_conflict} =
             Negotiation.negotiate(
               artifact_value(
                 extensions:
                   extensions(optional: %{"com.example.commerce/graph" => {:object, []}})
               ),
               support(registry: flipped)
             )

    # lens-F4: a malformed override (bogus state atom, non-struct) falls
    # back to compiled behavior — never a raise.
    bogus = %{"com.example.platform/estate" => %{state: :bogus}}

    assert {:ok, outcome} =
             Negotiation.negotiate(
               artifact_value(
                 extensions:
                   extensions(optional: %{"com.example.platform/estate" => {:object, []}})
               ),
               support(registry: bogus)
             )

    assert outcome.optional_retained == ["com.example.platform/estate"]

    not_struct = %{"com.example.platform/estate" => :not_an_entry}

    assert {:ok, _} =
             Negotiation.negotiate(
               artifact_value(
                 extensions:
                   extensions(optional: %{"com.example.platform/estate" => {:object, []}})
               ),
               support(registry: not_struct)
             )
  end

  test "review finding: case-collapsed and kebab denylist spellings deny" do
    for key <- ["MaxDepth", "maxdepth", "max-depth", "MAX_DEPTH", "CLASSIFICATION-CEILING"] do
      smuggle = %{"com.example.unknown/x" => {:object, [{key, {:integer, 8}}]}}

      assert {:error, :extension_payload_forbidden} =
               Negotiation.negotiate(
                 artifact_value(extensions: extensions(optional: smuggle)),
                 support()
               ),
             key
    end
  end

  test "review finding: the authored channel is tied to this artifact's critical region" do
    blob = "cGFzdGhldGljYWxseV9sb25nX3NlY3JldF9rZXlfbWF0ZXJpYWwxMjM0"

    # An OPTIONAL namespace on the authored list denies — the channel is
    # for negotiation-validated CRITICAL bodies only.
    smuggle = %{"com.example.unknown/x" => {:object, [{"engine_id", {:string, blob}}]}}
    value = artifact_value(extensions: extensions(optional: smuggle))

    assert {:error, :invalid_type} =
             Blueprint.from_value(value, %{authored_extensions: ["com.example.unknown/x"]})

    # A critical namespace that IS in this value threads green; the same
    # list against a DIFFERENT artifact (cross-artifact replay) denies.
    schema =
      {:object,
       [
         {"type", {:string, "object"}},
         {"properties", {:object, [{"handle", {:object, [{"type", {:string, "string"}}]}}]}},
         {"additionalProperties", {:boolean, false}}
       ]}

    pinned = %{
      "example.test/blob" =>
        entry(
          namespace: "example.test/blob",
          criticality: :critical,
          schema_digest: digest_of(schema)
        )
    }

    carrier =
      artifact_value(
        extensions:
          extensions(critical: %{"example.test/blob" => {:object, [{"handle", {:string, blob}}]}})
      )

    assert {:ok, outcome} =
             Negotiation.negotiate(
               carrier,
               support(registry: pinned, schemas: %{"example.test/blob" => schema})
             )

    assert {:ok, %Blueprint{}} =
             Blueprint.from_value(carrier, %{authored_extensions: outcome.critical_extensions})

    # Replay the SAME list against the optional-smuggle artifact: denies.
    assert {:error, :invalid_type} =
             Blueprint.from_value(value, %{authored_extensions: outcome.critical_extensions})

    # A non-object value with a non-empty authored list hits the fallback.
    assert {:error, :invalid_type} =
             Blueprint.from_value({:array, []}, %{authored_extensions: ["example.test/blob"]})
  end

  test "branch sweep: malformed machinery and region shapes deny with reasons" do
    # malformed required_core_fields element
    bad =
      artifact_value()
      |> then(fn {:object, m} -> {:object, replace(m, "required_core_fields", {:array, [5]})} end)

    assert {:error, :invalid_type} = Negotiation.negotiate(bad, support())

    # absent required_core_fields
    no_fields =
      artifact_value()
      |> then(fn {:object, m} ->
        {:object, Enum.reject(m, fn {n, _} -> n == "required_core_fields" end)}
      end)

    assert {:error, :missing_required_field} = Negotiation.negotiate(no_fields, support())

    # non-array required_core_fields
    bad_shape =
      artifact_value()
      |> then(fn {:object, m} ->
        {:object, replace(m, "required_core_fields", {:string, "x"})}
      end)

    assert {:error, :invalid_type} = Negotiation.negotiate(bad_shape, support())

    # absent and malformed extensions envelope
    no_ext =
      artifact_value()
      |> then(fn {:object, m} ->
        {:object, Enum.reject(m, fn {n, _} -> n == "extensions" end)}
      end)

    assert {:error, :missing_required_field} = Negotiation.negotiate(no_ext, support())

    bad_ext =
      artifact_value()
      |> then(fn {:object, m} -> {:object, replace(m, "extensions", {:string, "x"})} end)

    assert {:error, :invalid_type} = Negotiation.negotiate(bad_ext, support())

    # a deprecated OPTIONAL extension with matching criticality retains with notice
    pinned = %{
      "example.test/depopt" =>
        entry(namespace: "example.test/depopt", state: :deprecated, criticality: :optional)
    }

    assert {:ok, outcome} =
             Negotiation.negotiate(
               artifact_value(
                 extensions: extensions(optional: %{"example.test/depopt" => {:object, []}})
               ),
               support(registry: pinned)
             )

    assert outcome.optional_retained == ["example.test/depopt"]
    assert outcome.notices == [:extension_deprecated]

    # malformed revision member shape (non-integer tag, e.g. a string)
    str_rev =
      artifact_value()
      |> then(fn {:object, m} -> {:object, replace(m, "protocol_revision", {:string, "one"})} end)

    assert {:error, :invalid_type} = Negotiation.negotiate(str_rev, support())

    # absent revision
    no_rev2 =
      artifact_value()
      |> then(fn {:object, m} ->
        {:object, Enum.reject(m, fn {n, _} -> n == "protocol_revision" end)}
      end)

    assert {:error, :missing_required_field} = Negotiation.negotiate(no_rev2, support())
  end

  test "sweep: denylist inside arrays; negotiate on a non-object denies" do
    in_array = %{
      "com.example.unknown/x" => {:array, [{:object, [{"max_depth", {:integer, 8}}]}]}
    }

    assert {:error, :extension_payload_forbidden} =
             Negotiation.negotiate(
               artifact_value(extensions: extensions(optional: in_array)),
               support()
             )

    # A non-object value reaches member_of's fallback: the first machinery
    # read (revision) is absent.
    assert {:error, :missing_required_field} = Negotiation.negotiate({:array, []}, support())
    assert {:error, :missing_required_field} = Negotiation.negotiate(:null, support())
  end

  test "runtime-smoke finding: a partially-built Support works (struct defaults)" do
    # A host building Support with only revisions + core_fields must not
    # crash on nil registry/schemas (found by the runtime smoke: Map.fetch
    # on nil BadMapError'd).
    minimal = %Negotiation.Support{
      revisions: MapSet.new([1]),
      core_fields: MapSet.new(~w(blueprint_id))
    }

    assert {:ok, %Negotiation.Outcome{}} = Negotiation.negotiate(artifact_value(), minimal)
  end

  test "negotiate/2 accepts a %Blueprint{} (machinery reads only)" do
    {:ok, bp} = Blueprint.from_value(artifact_value())
    assert {:ok, %Negotiation.Outcome{}} = Negotiation.negotiate(bp, support())
  end

  test "the authored-extensions channel: validated critical bodies scan as authored" do
    # A 43+ char encoded blob inside a QUARANTINED body denies (strict scan).
    blob = "cGFzdGhldGljYWxseV9sb25nX3NlY3JldF9rZXlfbWF0ZXJpYWwxMjM0"
    smuggle = %{"com.example.unknown/x" => {:object, [{"correlation", {:string, blob}}]}}

    assert {:error, :forbidden_portable_value} =
             Blueprint.from_value(artifact_value(extensions: extensions(optional: smuggle)))

    # The same blob shape inside a schema-declared, digest-pinned critical
    # body scans as authored when the caller threads the validated list.
    schema =
      {:object,
       [
         {"type", {:string, "object"}},
         {"properties", {:object, [{"handle", {:object, [{"type", {:string, "string"}}]}}]}},
         {"additionalProperties", {:boolean, false}}
       ]}

    pinned = %{
      "example.test/blob" =>
        entry(
          namespace: "example.test/blob",
          criticality: :critical,
          schema_digest: digest_of(schema)
        )
    }

    body = {:object, [{"handle", {:string, blob}}]}

    value = artifact_value(extensions: extensions(critical: %{"example.test/blob" => body}))

    assert {:ok, outcome} =
             Negotiation.negotiate(
               value,
               support(registry: pinned, schemas: %{"example.test/blob" => schema})
             )

    assert outcome.critical_extensions == ["example.test/blob"]

    assert {:ok, %Blueprint{}} =
             Blueprint.from_value(value, %{authored_extensions: outcome.critical_extensions})
  end

  defp digest_of(schema) do
    {:ok, jcs} = Canonicalization.encode(schema)
    Digest.to_tagged(Digest.hash(:extension_schema, jcs))
  end
end
