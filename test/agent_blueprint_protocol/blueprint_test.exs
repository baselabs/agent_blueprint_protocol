defmodule AgentBlueprintProtocol.BlueprintTest do
  @moduledoc """
  The Blueprint artifact: the 18-member table through the generic engine,
  the decode pipeline (canonical verify → registry validation → portability
  scan → digest comparison), and the two carried obligations — the
  canonicality ordering and the window-float deny.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{
    Blueprint,
    Canonicalization,
    Digest,
    Registry
  }

  import AgentBlueprintProtocol.BlueprintFixture,
    only: [
      assertion: 1,
      base_members: 1,
      extensions: 1,
      fixture_bytes: 1,
      fixture_value: 1,
      port: 1,
      signature_entry: 1,
      with_signatures: 1
    ]

  @window_float {:float, 9.007_199_254_740_992e15}

  # ---- decode: green ------------------------------------------------------------

  test "a complete, honest artifact decodes green" do
    assert {:ok, %Blueprint{}} = Blueprint.decode(fixture_bytes([]))
  end

  test "an artifact carrying signatures and empty attestations decodes green" do
    value =
      with_signatures(extra_members: [{"attestations", {:array, []}}])

    {:ok, bytes} = Canonicalization.encode(value)
    assert {:ok, %Blueprint{}} = Blueprint.decode(bytes)
  end

  test "a deployment-purpose signature riding a Blueprint denies :invalid_constraint" do
    wrong =
      AgentBlueprintProtocol.BlueprintFixture.signature_entry(
        attrs: AgentBlueprintProtocol.BlueprintFixture.signature_attrs(purpose: "deployment")
      )

    value = with_signatures(signatures: [wrong])
    {:ok, bytes} = Canonicalization.encode(value)
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)
  end

  # ---- the 15 required members ---------------------------------------------------

  test "every required member absent denies :missing_required_field" do
    for name <- Enum.map(base_members([]), fn {n, _} -> n end) do
      members = Enum.reject(base_members([]), fn {n, _} -> n == name end)
      {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))

      assert {:error, :missing_required_field} = Blueprint.decode(bytes),
             "#{name} must be required"
    end
  end

  defp with_digest_fake(members) do
    # The digest value is irrelevant at this stage; keep a well-formed tag.
    {:object, [{"content_digest", {:string, tagged_zero()}} | Enum.sort(members)]}
  end

  defp tagged_zero,
    do: Digest.to_tagged(Digest.hash(:blueprint_content, "x"))

  # ---- closed world ----------------------------------------------------------------

  test "unknown members deny :unknown_member at the root and in nested objects" do
    root = base_members([]) ++ [{"mystery", {:integer, 1}}]
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(root))
    assert {:error, :unknown_member} = Blueprint.decode(bytes)

    bad_port = {:object, [{"name", {:string, "request"}}, {"surprise", {:integer, 1}}]}
    nested = base_members([]) |> replace("input_ports", {:array, [bad_port]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(nested))
    assert {:error, :unknown_member} = Blueprint.decode(bytes)

    bad_ceiling =
      {:object, [{"max_depth", {:integer, 8}}, {"extra", {:integer, 1}}]}

    nested = base_members([]) |> replace("ceilings", bad_ceiling)
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(nested))
    assert {:error, :unknown_member} = Blueprint.decode(bytes)
  end

  # ---- the window-float obligation ----------------------------------------------

  test "a float-tagged window value in an integer-typed core field denies :invalid_type" do
    for swap <- [
          {"protocol_revision", @window_float},
          {"release_number", @window_float}
        ] do
      members = base_members([]) |> replace_elem(swap)
      {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
      assert {:error, :invalid_type} = Blueprint.decode(bytes), inspect(elem(swap, 0))
    end

    bad_ceiling =
      base_members([])
      |> replace("ceilings", replace_ceiling("max_attempts", @window_float))

    {:ok, bytes} = Canonicalization.encode(with_digest_fake(bad_ceiling))
    assert {:error, :invalid_type} = Blueprint.decode(bytes)

    bad_cost =
      base_members([])
      |> replace("ceilings", replace_cost_amount(@window_float))

    {:ok, bytes} = Canonicalization.encode(with_digest_fake(bad_cost))
    assert {:error, :invalid_type} = Blueprint.decode(bytes)
  end

  test "the integer forms of the same fields stay green at the boundary" do
    members =
      base_members([])
      |> replace("protocol_revision", {:integer, 9_007_199_254_740_991})

    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:ok, %Blueprint{}} = Blueprint.decode(bytes)
  end

  # ---- enums ---------------------------------------------------------------------------

  test "enum boundaries deny :invalid_constraint" do
    for swap <- [
          {"classification_ceiling", {:string, "topsecret"}},
          {"triggers", {:array, [{:string, "cron"}]}}
        ] do
      members = base_members([]) |> replace_elem(swap)
      {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
      assert {:error, :invalid_constraint} = Blueprint.decode(bytes), inspect(elem(swap, 0))
    end

    bad_port =
      AgentBlueprintProtocol.BlueprintFixture.port("request", classification: "topsecret")

    members = base_members([]) |> replace("input_ports", {:array, [bad_port]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)
  end

  defp with_digest(members) do
    AgentBlueprintProtocol.BlueprintFixture.with_digest(members)
  end

  # ---- cardinality -----------------------------------------------------------------------

  test "cardinality plus-one and empty-set boundaries deny :invalid_cardinality" do
    oversized = Enum.map(1..65, &port("p#{&1}"))
    members = base_members([]) |> replace("input_ports", {:array, oversized})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_cardinality} = Blueprint.decode(bytes)

    members = base_members([]) |> replace("triggers", {:array, []})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_cardinality} = Blueprint.decode(bytes)

    dup_triggers = {:array, [{:string, "manual"}, {:string, "manual"}]}
    members = base_members([]) |> replace("triggers", dup_triggers)
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_cardinality} = Blueprint.decode(bytes)
  end

  test "duplicate identity members deny :invalid_cardinality" do
    dup_ports = {:array, [port("same"), port("same")]}
    members = base_members([]) |> replace("input_ports", dup_ports)
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_cardinality} = Blueprint.decode(bytes)
  end

  # ---- canonicality (the carried obligation) ---------------------------------------------------

  test "non-canonical spellings deny :non_canonical_bytes before any digest work" do
    # Member reordering: honest digest over the canonical form, serialized
    # by hand with reversed member order — the re-encode-then-digest trap
    # artifact. A pipeline that skips canonical verify and digests
    # normalized re-encoded bytes would PASS the digest on this input.
    {:object, members} = fixture_value([])
    bytes = raw_object(Enum.reverse(members))
    assert {:error, :non_canonical_bytes} = Blueprint.decode(bytes)

    # Non-canonical number spelling: 1.0 where JCS emits 1.
    patched =
      String.replace(fixture_bytes([]), ~s("release_number":1,), ~s("release_number":1.0,))

    assert patched != fixture_bytes([])
    assert {:error, :non_canonical_bytes} = Blueprint.decode(patched)

    # Escaped unicode where JCS emits the literal character.
    patched =
      String.replace(
        fixture_bytes([]),
        "example.demo.toolchain",
        "\\u0062aselabs.demo.toolchain"
      )

    assert patched != fixture_bytes([])
    assert {:error, :non_canonical_bytes} = Blueprint.decode(patched)

    # Whitespace between tokens.
    spaced = String.replace(fixture_bytes([]), ~s({"blueprint_id"), ~s({ "blueprint_id"))
    assert {:error, :non_canonical_bytes} = Blueprint.decode(spaced)
  end

  # A hand-rolled object serializer that does NOT sort members — the only
  # honest way to produce non-canonical bytes for the trap artifact.
  defp raw_object(members) do
    inner =
      Enum.map_join(members, ",", fn {name, value} ->
        {:ok, key} = Canonicalization.encode({:string, name})
        {:ok, encoded} = Canonicalization.encode(value)
        key <> ":" <> encoded
      end)

    "{" <> inner <> "}"
  end

  # ---- digest -------------------------------------------------------------------------------

  test "a tampered covered member denies :digest_mismatch" do
    tampered =
      base_members([])
      |> replace("release_number", {:integer, 2})
      |> then(
        &AgentBlueprintProtocol.BlueprintFixture.with_digest(&1,
          declared_digest:
            Digest.to_tagged(
              AgentBlueprintProtocol.BlueprintFixture.compute_digest(
                Enum.reject(base_members([]), fn {n, _} -> n == "content_digest" end)
              )
            )
        )
      )

    {:ok, bytes} = Canonicalization.encode(tampered)
    assert {:error, :digest_mismatch} = Blueprint.decode(bytes)
  end

  test "a tampered digest member (still well-formed) denies :digest_mismatch" do
    honest =
      AgentBlueprintProtocol.BlueprintFixture.compute_digest(
        Enum.reject(base_members([]), fn {n, _} -> n == "content_digest" end)
      )

    # Swap two base64url characters inside the tag: still parses, wrong bytes.
    tagged = Digest.to_tagged(honest)

    swapped =
      String.slice(tagged, 0, 9) <>
        String.slice(tagged, 10, 1) <>
        String.slice(tagged, 9, 1) <> String.slice(tagged, 11..-1//1)

    members =
      base_members([])
      |> AgentBlueprintProtocol.BlueprintFixture.with_digest(declared_digest: swapped)

    {:ok, bytes} = Canonicalization.encode(members)
    assert {:error, :digest_mismatch} = Blueprint.decode(bytes)
  end

  test "mutating the signatures member leaves the digest comparison green" do
    value = with_signatures([])
    # Retamper the signature bytes: evidence members are digest-uncovered.
    {:object, members} = value

    tampered =
      Enum.map(members, fn
        {"signatures", {:array, [entry]}} ->
          {:object, entry_members} = entry

          tampered_entry =
            Enum.map(entry_members, fn
              {"signature", {:string, sig}} ->
                # Tamper the FIRST character: a significant 6-bit position at
                # every base64url length, never the canonicality-constrained
                # final group. (Replacing the first "A" anywhere could land on
                # the LAST character — the one position whose value is
                # constrained — and produce a correctly-rejected non-canonical
                # string on ~7% of random signatures; the known seed-sensitivity flake,
                # root-caused 2026-08-22.)
                first = String.first(sig)
                replacement = if first == "Z", do: "Y", else: "Z"
                {"signature", {:string, replacement <> String.slice(sig, 1..-1//1)}}

              other ->
                other
            end)

          {"signatures", {:array, [{:object, tampered_entry}]}}

        other ->
          other
      end)

    {:ok, bytes} = Canonicalization.encode({:object, tampered})
    assert {:ok, %Blueprint{}} = Blueprint.decode(bytes)
  end

  # ---- evidence members ------------------------------------------------------------------------

  test "any non-empty attestations array denies :attestation_malformed (kind registry empty)" do
    members = base_members([]) ++ [{"attestations", {:array, [{:object, []}]}}]
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :attestation_malformed} = Blueprint.decode(bytes)
  end

  test "a malformed signature entry denies :signature_malformed" do
    # Remove a member from the protected header: the closed envelope denies.
    entry = signature_entry([])
    {:object, entry_members} = entry
    {"protected", {:object, header_members}} = List.keyfind(entry_members, "protected", 0)

    broken_header = Enum.reject(header_members, fn {n, _} -> n == "crit" end)

    broken =
      List.keyreplace(entry_members, "protected", 0, {"protected", {:object, broken_header}})

    members = base_members([]) ++ [{"signatures", {:array, [{:object, broken}]}}]
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :signature_malformed} = Blueprint.decode(bytes)
  end

  # ---- assertion kinds ----------------------------------------------------------------------------

  test "each assertion kind's closed operand set is enforced" do
    bad = {:object, [{"kind", {:string, "output_schema"}}, {"port", {:string, "result"}}]}
    members = base_members([]) |> replace("evaluation_assertions", {:array, [bad]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :missing_required_field} = Blueprint.decode(bytes)

    unknown_kind = {:object, [{"kind", {:string, "rubric"}}]}
    members = base_members([]) |> replace("evaluation_assertions", {:array, [unknown_kind]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)

    no_bound = {:object, [{"kind", {:string, "parameter_bound"}}, {"parameter", {:string, "x"}}]}
    members = base_members([]) |> replace("evaluation_assertions", {:array, [no_bound]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)
  end

  test "cross-field assertion references are enforced" do
    tie_out_bad = assertion(kind: "provenance_tie_out", member: "signatures")
    members = base_members([]) |> replace("evaluation_assertions", {:array, [tie_out_bad]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)

    use_bad = assertion(kind: "required_capability_use", family: "no.such.family")
    members = base_members([]) |> replace("evaluation_assertions", {:array, [use_bad]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)

    pred_bad =
      assertion(
        kind: "deterministic_predicate",
        predicate:
          {:object,
           [
             {"op", {:string, "eq"}},
             {"path", AgentBlueprintProtocol.BlueprintFixture.path(["nowhere"])},
             {"value", {:string, "x"}}
           ]}
      )

    members = base_members([]) |> replace("evaluation_assertions", {:array, [pred_bad]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :predicate_path_unresolved} = Blueprint.decode(bytes)
  end

  test "output_contract.port must name an output port" do
    members =
      base_members(output_port: "elsewhere")
      |> replace("output_ports", {:array, []})

    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)
  end

  # ---- required_core_fields -------------------------------------------------------------------------

  test "required_core_fields entries must be known covered members, unique" do
    for value <- ["bogus", "signatures", "attestations", "content_digest"] do
      members = base_members(required_core_fields: [value])
      {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
      assert {:error, :invalid_constraint} = Blueprint.decode(bytes), value
    end

    members = base_members(required_core_fields: ["blueprint_id", "blueprint_id"])
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_cardinality} = Blueprint.decode(bytes)
  end

  # ---- extensions --------------------------------------------------------------------------------------

  test "the positional extensions envelope is enforced" do
    missing_optional = {:object, [{"critical", {:object, []}}]}
    members = base_members([]) |> replace("extensions", missing_optional)
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :missing_required_field} = Blueprint.decode(bytes)

    extra = {:object, [{"critical", {:object, []}}, {"optional", {:object, []}}, {"x", :null}]}
    members = base_members([]) |> replace("extensions", extra)
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :unknown_member} = Blueprint.decode(bytes)

    dup =
      extensions(
        critical: %{"example.demo/x" => {:object, []}},
        optional: %{"example.demo/x" => {:object, []}}
      )

    members = base_members([]) |> replace("extensions", dup)
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :extension_duplicate} = Blueprint.decode(bytes)

    for bad_ns <- ["example.demo/a/b", "Example.Demo/x", "example.demo"] do
      bad = extensions(critical: %{bad_ns => {:object, []}})
      members = base_members([]) |> replace("extensions", bad)
      {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
      assert {:error, :extension_namespace_invalid} = Blueprint.decode(bytes), bad_ns
    end

    many = Map.new(1..33, &{"example.demo/ns#{&1}", {:object, []}})
    members = base_members([]) |> replace("extensions", extensions(optional: many))
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_cardinality} = Blueprint.decode(bytes)
  end

  # ---- portability ----------------------------------------------------------------------------------------

  test "never-portable values deny :forbidden_portable_value in core and evidence positions" do
    pem = "-----" <> "BEGIN PRIVATE KEY-----\nMIIEvQ\n-----" <> "END PRIVATE KEY-----"
    members = base_members(toolchain: pem)
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :forbidden_portable_value} = Blueprint.decode(bytes)

    # Tripwire: a PEM inside a signature entry's free key_id string.
    entry =
      signature_entry(
        header: AgentBlueprintProtocol.BlueprintFixture.signature_header(pem),
        attrs: AgentBlueprintProtocol.BlueprintFixture.signature_attrs(key_id: pem)
      )

    value = fixture_value(extra_members: [{"signatures", {:array, [entry]}}])
    {:ok, bytes} = Canonicalization.encode(value)
    assert {:error, :forbidden_portable_value} = Blueprint.decode(bytes)
  end

  test "never-portable member names deny :forbidden_portable_value in the open regions" do
    for name <- ["tenant_id", "engine_id", "billing_account", "primary_key"] do
      bad = extensions(optional: %{"example.demo/x" => {:object, [{name, {:integer, 1}}]}})
      members = base_members([]) |> replace("extensions", bad)
      {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
      assert {:error, :forbidden_portable_value} = Blueprint.decode(bytes), name
    end

    schema_with_bad_name =
      {:object,
       [
         {"type", {:string, "object"}},
         {"properties", {:object, [{"engine_id", {:object, [{"type", {:string, "string"}}]}}]}}
       ]}

    bad_port =
      AgentBlueprintProtocol.BlueprintFixture.port("request", schema: schema_with_bad_name)

    members = base_members([]) |> replace("input_ports", {:array, [bad_port]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :forbidden_portable_value} = Blueprint.decode(bytes)
  end

  test "an endpoint value inside an extension body denies" do
    bad =
      extensions(
        optional: %{
          "example.demo/x" => {:object, [{"relay", {:string, "https://ingest.internal/x"}}]}
        }
      )

    members = base_members([]) |> replace("extensions", bad)
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :forbidden_portable_value} = Blueprint.decode(bytes)
  end

  test "the honest-limit calibration: UUID green, identifier convention position-scoped" do
    # UUID (27 decoded bytes) stays green in an extension body.
    ok =
      extensions(
        optional: %{
          "example.demo/x" =>
            {:object, [{"correlation", {:string, "550e8400-e29b-41d4-a716-446655440000"}}]}
        }
      )

    members = base_members([]) |> replace("extensions", ok)
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:ok, %Blueprint{}} = Blueprint.decode(bytes)

    # A long identifier-style string in an extension body now DENIES: host
    # content earns no identifier tolerance.
    smug =
      extensions(
        optional: %{
          "example.demo/x" =>
            {:object, [{"slug", {:string, "fetch_grounding_dataset_with_citations_and_sources"}}]}
        }
      )

    members = base_members([]) |> replace("extensions", smug)
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :forbidden_portable_value} = Blueprint.decode(bytes)

    # The same string as a logical operation name (an identifier position)
    # stays green.
    long_op =
      {:object,
       [
         {"logical_operation", {:string, "fetch_grounding_dataset_with_citations_and_sources"}},
         {"operation_kind", {:string, "read"}},
         {"impact_class", {:string, "ordinary"}}
       ]}

    members = base_members([]) |> replace("effect_intents", {:array, [long_op]})
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:ok, %Blueprint{}} = Blueprint.decode(bytes)
  end

  # ---- precedence ---------------------------------------------------------------------------------------------

  test "canonicality outranks every semantic failure" do
    members = base_members([]) ++ [{"mystery", {:integer, 1}}]
    {:object, sorted} = with_digest_fake(members)
    bytes = raw_object(Enum.reverse(sorted))
    assert {:error, :non_canonical_bytes} = Blueprint.decode(bytes)
  end

  test "structural failures outrank the portability scan" do
    pem = "-----" <> "BEGIN PRIVATE KEY-----\nMIIEvQ\n-----" <> "END PRIVATE KEY-----"

    members =
      base_members(toolchain: pem) |> replace("classification_ceiling", {:string, "topsecret"})

    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)
  end

  # ---- from_value + the artifact API ---------------------------------------------------------------------------

  test "from_value validates structure without canonicality and is order-blind" do
    {:object, members} = fixture_value([])
    assert {:ok, %Blueprint{}} = Blueprint.from_value({:object, Enum.reverse(members)})

    bad = base_members([]) |> replace("classification_ceiling", {:string, "topsecret"})
    assert {:error, :invalid_constraint} = Blueprint.from_value(with_digest_fake(bad))
  end

  test "to_value is the decoded value; digest_input drops exactly the three evidence members" do
    value = with_signatures([])
    assert {:ok, %Blueprint{value: ^value}} = Blueprint.from_value(value)
    {:ok, bp} = Blueprint.from_value(value)
    assert Blueprint.to_value(bp) == value

    {:object, dropped} = Blueprint.digest_input(bp)
    refute List.keyfind(dropped, "content_digest", 0)
    refute List.keyfind(dropped, "signatures", 0)
    refute List.keyfind(dropped, "attestations", 0)
    assert length(dropped) == length(members_of(value)) - 2

    assert Blueprint.digest_covered?("blueprint_id")
    refute Blueprint.digest_covered?("content_digest")
    refute Blueprint.digest_covered?("signatures")
    refute Blueprint.digest_covered?("attestations")
  end

  defp members_of({:object, members}), do: members

  test "canonical_bytes, content_digest, and verify_content_digest agree with the fixture" do
    bytes = fixture_bytes([])
    {:ok, bp} = Blueprint.decode(bytes)
    assert {:ok, ^bytes} = Blueprint.canonical_bytes(bp)

    honest =
      AgentBlueprintProtocol.BlueprintFixture.compute_digest(
        Enum.reject(base_members([]), fn {n, _} -> n == "content_digest" end)
      )

    assert Blueprint.content_digest(bp) == honest
    assert :ok = Blueprint.verify_content_digest(bp)
  end

  # ---- totality ---------------------------------------------------------------------------------------------------

  test "decode is total: arbitrary bytes deny, never raise" do
    for input <- [
          <<>>,
          "not json",
          ~s({"a":1}),
          String.duplicate("x", 100),
          <<0xFF, 0xFE>>,
          ~s([1,2,3])
        ] do
      assert {:error, _reason} = Blueprint.decode(input)
    end
  end

  # ---- the engine seam ----------------------------------------------------------------------------------------------

  test "the table drives the shared engine (the reuse invariant)" do
    table = Blueprint.table()
    assert length(table) == 18
    # The engine is importable and accepts the table without domain knowledge.
    assert :ok = Registry.validate(table, fixture_value([]))
  end

  # ---- hardened rims (each reproduced, then fixed) ------------------------------

  test "malformed shapes deny with reasons, never raise" do
    # F2: a non-object extensions value.
    members =
      [{:extensions_placeholder_nil, nil} | []]
      |> tl()
      |> then(fn _ -> base_members([]) end)
      |> replace("extensions", {:string, "x"})

    value = digested(members)
    assert {:error, :invalid_type} = Blueprint.from_value(value)

    # F3: a non-string required_core_fields element (constraint stage runs
    # before element recursion).
    members = base_members([]) |> replace("required_core_fields", {:array, [{:integer, 1}]})
    assert {:error, :invalid_constraint} = Blueprint.from_value(digested(members))
  end

  test "review F5: impossible calendar timestamps deny" do
    bad_producer =
      {:object,
       [
         {"created_at", {:string, "2026-99-99T99:99:99Z"}},
         {"identity", {:string, "example.demo"}},
         {"toolchain", {:string, "t"}}
       ]}

    members = base_members([]) |> replace("producer", bad_producer)
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)
  end

  test "review F6: predicate operand member names are denylist-scanned" do
    smuggle =
      {:object,
       [
         {"kind", {:string, "deterministic_predicate"}},
         {"predicate",
          {:object,
           [
             {"op", {:string, "eq"}},
             {"path", AgentBlueprintProtocol.BlueprintFixture.path(["request"])},
             {"value", {:object, [{"tenant_id", {:string, "t-123"}}]}}
           ]}}
       ]}

    members = base_members([]) |> replace("evaluation_assertions", {:array, [smuggle]})
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :forbidden_portable_value} = Blueprint.decode(bytes)
  end

  test "review F7: output_schema assertions must name a declared port" do
    bad =
      {:object,
       [
         {"kind", {:string, "output_schema"}},
         {"port", {:string, "nowhere"}},
         {"schema", AgentBlueprintProtocol.BlueprintFixture.schema_value()}
       ]}

    members = base_members([]) |> replace("evaluation_assertions", {:array, [bad]})
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)
  end

  test "a PEM as a port name denies (identifier position, exemption bypassed by the marker)" do
    pem = "-----" <> "BEGIN PRIVATE KEY-----\nMIIEvQ\n-----" <> "END PRIVATE KEY-----"

    bad_port =
      AgentBlueprintProtocol.BlueprintFixture.port("clean-name",
        schema: AgentBlueprintProtocol.BlueprintFixture.schema_value()
      )

    bad_port = put_member(bad_port, "name", {:string, pem})

    members = base_members([]) |> replace("input_ports", {:array, [bad_port]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :forbidden_portable_value} = Blueprint.decode(bytes)
  end

  defp put_member({:object, members}, name, value),
    do:
      {:object,
       Enum.map(members, fn
         {^name, _} -> {name, value}
         other -> other
       end)}

  test "review F9: input and output ports may not collide on a name" do
    members =
      base_members([])
      |> replace("output_ports", {:array, [port("request"), port("result")]})

    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:error, :invalid_cardinality} = Blueprint.decode(bytes)
  end

  defp digested(members), do: AgentBlueprintProtocol.BlueprintFixture.with_digest(members)

  # ---- helpers ---

  defp replace_ceiling(name, value) do
    {:object, ceiling_members} = AgentBlueprintProtocol.BlueprintFixture.ceilings()

    {:object,
     Enum.map(ceiling_members, fn
       {^name, _} -> {name, value}
       other -> other
     end)}
  end

  defp replace_cost_amount(value) do
    {:object, ceiling_members} = AgentBlueprintProtocol.BlueprintFixture.ceilings()

    {:object,
     Enum.map(ceiling_members, fn
       {"max_cost", {:object, members}} ->
         {"max_cost",
          {:object,
           Enum.map(members, fn
             {"amount", _} -> {"amount", value}
             other -> other
           end)}}

       other ->
         other
     end)}
  end

  defp replace(members, name, value) do
    Enum.map(members, fn
      {^name, _} -> {name, value}
      other -> other
    end)
  end

  defp replace_elem(members, {name, value}), do: replace(members, name, value)
  # ---- branch sweep: live fallback clauses through the public API -------------------

  test "sweep: field-check fallbacks reachable through decode" do
    # release_number 0: the positive floor.
    members = base_members([]) |> replace("release_number", {:integer, 0})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)

    # malformed digest tag: from_tagged's reason passes through.
    members = base_members([]) ++ [{"content_digest", {:string, "sha-256:short"}}]
    {:ok, bytes} = Canonicalization.encode({:object, Enum.sort(members)})
    assert {:error, :digest_encoding_invalid} = Blueprint.decode(bytes)

    # malformed port schema: Schema's reason passes through.
    bad_port =
      AgentBlueprintProtocol.BlueprintFixture.port("request",
        schema: {:object, [{"type", {:string, "nope"}}]}
      )

    members = base_members([]) |> replace("input_ports", {:array, [bad_port]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :schema_keyword_value_invalid} = Blueprint.decode(bytes)

    # assertion element that is not an object (not encodable — from_value).
    members = base_members([]) |> replace("evaluation_assertions", {:array, [5]})
    assert {:error, :invalid_type} = Blueprint.from_value(with_digest_fake(members))

    # assertion kind member with a malformed-tagged value (from_value).
    bad_kind = {:object, [{"kind", 5}]}
    members = base_members([]) |> replace("evaluation_assertions", {:array, [bad_kind]})
    assert {:error, :invalid_type} = Blueprint.from_value(with_digest_fake(members))

    # extensions region that is not an object denies :invalid_type (the
    # total-walk fallback; the envelope member names themselves are fine).
    bad_ext = {:object, [{"critical", {:array, []}}, {"optional", {:object, []}}]}
    members = base_members([]) |> replace("extensions", bad_ext)
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_type} = Blueprint.decode(bytes)
  end

  test "sweep: assertion operand type fallbacks" do
    # empty dataset string.
    bad = assertion(kind: "grounding_presence", dataset: "")
    members = base_members([]) |> replace("evaluation_assertions", {:array, [bad]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_type} = Blueprint.decode(bytes)

    # parameter_bound with float bounds, integer bounds, and rich values.
    good =
      {:object,
       [
         {"kind", {:string, "parameter_bound"}},
         {"parameter", {:string, "x"}},
         {"minimum", {:float, 0.5}},
         {"maximum", {:float, 9.5}}
       ]}

    members = base_members([]) |> replace("evaluation_assertions", {:array, [good]})
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:ok, %Blueprint{}} = Blueprint.decode(bytes)

    good_int =
      {:object,
       [
         {"kind", {:string, "parameter_bound"}},
         {"parameter", {:string, "x"}},
         {"minimum", {:integer, 1}}
       ]}

    members = base_members([]) |> replace("evaluation_assertions", {:array, [good_int]})
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:ok, %Blueprint{}} = Blueprint.decode(bytes)

    rich =
      {:object,
       [
         {"kind", {:string, "deterministic_predicate"}},
         {"predicate",
          {:object,
           [
             {"op", {:string, "eq"}},
             {"path", AgentBlueprintProtocol.BlueprintFixture.path(["request"])},
             {"value", {:array, [{:object, [{"deep", :null}]}, {:boolean, false}]}}
           ]}}
       ]}

    members = base_members([]) |> replace("evaluation_assertions", {:array, [rich]})
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:ok, %Blueprint{}} = Blueprint.decode(bytes)

    # ceiling with a float at_most.
    good =
      {:object,
       [
         {"kind", {:string, "ceiling"}},
         {"ceiling", {:string, "max_tokens"}},
         {"at_most", {:float, 100.5}}
       ]}

    members = base_members([]) |> replace("evaluation_assertions", {:array, [good]})
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:ok, %Blueprint{}} = Blueprint.decode(bytes)

    # approval_expected with a bad family (family_in fallback) and bad trait.
    bad = assertion(kind: "approval_expected", family: "no.such.family")
    members = base_members([]) |> replace("evaluation_assertions", {:array, [bad]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)

    bad_trait =
      {:object,
       [
         {"kind", {:string, "approval_expected"}},
         {"operation_family", {:string, "example.demo.read_shape"}},
         {"approval_trait", {:string, "auto"}}
       ]}

    members = base_members([]) |> replace("evaluation_assertions", {:array, [bad_trait]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)

    # forbidden_capability_use with a malformed-tagged family operand
    # (not encodable — validate through from_value).
    bad = {:object, [{"kind", {:string, "forbidden_capability_use"}}, {"operation_family", 5}]}
    members = base_members([]) |> replace("evaluation_assertions", {:array, [bad]})
    assert {:error, :invalid_type} = Blueprint.from_value(with_digest_fake(members))

    # ceiling assertion naming max_cost (excluded from the seven-name enum).
    bad = assertion(kind: "ceiling", ceiling: "max_cost")
    members = base_members([]) |> replace("evaluation_assertions", {:array, [bad]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)
  end

  test "sweep: producer/currency/namespace constraint fallbacks" do
    # currency lowercase.
    bad_cost = replace_cost_amount({:integer, 1000}) |> then(fn _ -> nil end)

    ceilings =
      Enum.map(
        AgentBlueprintProtocol.BlueprintFixture.ceilings() |> then(fn o -> elem(o, 1) end),
        fn
          {"max_cost", {:object, ms}} ->
            {"max_cost",
             {:object,
              Enum.map(ms, fn
                {"currency", _} -> {"currency", {:string, "usd"}}
                o -> o
              end)}}

          o ->
            o
        end
      )

    {:object, _} = AgentBlueprintProtocol.BlueprintFixture.ceilings()
    members = base_members([]) |> replace("ceilings", {:object, ceilings})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)
    _ = bad_cost

    # created_at not in Z whole-second form.
    bad_producer =
      {:object,
       [
         {"created_at", {:string, "2026-08-20T00:00:00+00:00"}},
         {"identity", {:string, "example.demo"}},
         {"toolchain", {:string, "t"}}
       ]}

    members = base_members([]) |> replace("producer", bad_producer)
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)

    # blueprint_id with a bad segment form.
    members =
      base_members(blueprint_id: "Example.Demo/echo")
      |> replace("blueprint_id", {:string, "Example.Demo/echo"})

    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)

    # producer identity with a slash (not the dotted form).
    bad_producer =
      {:object,
       [
         {"created_at", {:string, "2026-08-20T00:00:00Z"}},
         {"identity", {:string, "example.demo/x"}},
         {"toolchain", {:string, "t"}}
       ]}

    members = base_members([]) |> replace("producer", bad_producer)
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :invalid_constraint} = Blueprint.decode(bytes)
  end

  test "sweep: assertion shape fallbacks and verify_content_digest totality" do
    # assertion with no kind member at all.
    members = base_members([]) |> replace("evaluation_assertions", {:array, [{:object, []}]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :missing_required_field} = Blueprint.decode(bytes)

    # assertion with an unknown extra member.
    extra =
      {:object,
       [
         {"kind", {:string, "output_schema"}},
         {"port", {:string, "result"}},
         {"schema", AgentBlueprintProtocol.BlueprintFixture.schema_value()},
         {"extra", :null}
       ]}

    members = base_members([]) |> replace("evaluation_assertions", {:array, [extra]})
    {:ok, bytes} = Canonicalization.encode(with_digest_fake(members))
    assert {:error, :unknown_member} = Blueprint.decode(bytes)

    # verify_content_digest on a struct whose value lacks the member: the
    # public function's own totality branch.
    assert {:error, :invalid_type} =
             Blueprint.verify_content_digest(%Blueprint{value: {:object, []}})

    # rich :any operand values exercising well_formed?'s numeric positives.
    rich =
      {:object,
       [
         {"kind", {:string, "deterministic_predicate"}},
         {"predicate",
          {:object,
           [
             {"op", {:string, "eq"}},
             {"path", AgentBlueprintProtocol.BlueprintFixture.path(["request"])},
             {"value", {:array, [{:integer, 2}, {:float, 1.5}]}}
           ]}}
       ]}

    members = base_members([]) |> replace("evaluation_assertions", {:array, [rich]})
    {:ok, bytes} = Canonicalization.encode(with_digest(members))
    assert {:ok, %Blueprint{}} = Blueprint.decode(bytes)

    # malformed :any operand values deny via well_formed?'s fallbacks
    # (not encodable — through from_value).
    for bad_value <- [{:object, [{5, :null}]}, 5] do
      bad =
        {:object,
         [
           {"kind", {:string, "deterministic_predicate"}},
           {"predicate",
            {:object,
             [
               {"op", {:string, "eq"}},
               {"path", AgentBlueprintProtocol.BlueprintFixture.path(["request"])},
               {"value", bad_value}
             ]}}
         ]}

      members = base_members([]) |> replace("evaluation_assertions", {:array, [bad]})
      assert {:error, :invalid_type} = Blueprint.from_value(with_digest_fake(members))
    end
  end

  describe "decode catch-all (the never-raising posture at the API type boundary)" do
    test "a non-binary input denies with a typed error, never raises" do
      assert Blueprint.decode(:atom) == {:error, :invalid_type}
      assert Blueprint.decode(123, %{}) == {:error, :invalid_type}
    end
  end
end
