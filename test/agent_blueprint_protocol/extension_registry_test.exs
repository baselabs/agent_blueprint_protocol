defmodule AgentBlueprintProtocol.ExtensionRegistryTest do
  @moduledoc """
  The compiled-in extension registry: the six entries (five first-release rows plus
  the product-extension registration), the federation entry's REAL authored schema
  digest, the product entry's digest pin bound to the SHIPPED corpus schema
  document, compile-time sourcing, and the promotion-governance self-check.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Canonicalization, Digest, ExtensionRegistry, Json, Schema}

  @estate_contract_schema_path "priv/conformance/schemas/estate-contract.schema.json"

  defp estate_contract_schema_document do
    {:ok, raw} = File.read(@estate_contract_schema_path)
    {:ok, tagged} = Json.decode(raw)
    tagged
  end

  test "the six entries are registered with their owners and criticalities" do
    entries = ExtensionRegistry.registered_extensions()

    by_ns = Map.new(entries, fn e -> {e.namespace, e} end)

    assert MapSet.new(Map.keys(by_ns)) ==
             MapSet.new([
               "com.example.commerce/graph",
               "com.example.commerce/classification-labels",
               "com.example.commerce/rubric-assertion",
               "com.example.platform/estate",
               "com.example.platform/estate-contract",
               "com.example/federation"
             ])

    assert by_ns["com.example.commerce/graph"].criticality == :critical
    assert by_ns["com.example/federation"].criticality == :critical
    assert by_ns["com.example.commerce/classification-labels"].criticality == :optional
    assert Enum.all?(entries, &(&1.state in [:active, :deprecated]))
    assert Enum.all?(entries, fn e -> is_binary(e.a2a_uri) and e.a2a_uri != "" end)
  end

  test "the estate-contract product registration: born critical, active, unpromoted" do
    {:ok, entry} = ExtensionRegistry.entry("com.example.platform/estate-contract")

    assert entry.owner == "ExamplePlatform"
    assert entry.criticality == :critical
    assert entry.state == :active
    assert entry.promoted_at_revision == nil
    assert entry.a2a_uri == "https://example.com/extensions/platform-estate-contract"
    assert is_binary(entry.schema_digest)
  end

  test "the placeholder estate namespace is deprecated, not retired" do
    {:ok, entry} = ExtensionRegistry.entry("com.example.platform/estate")

    assert entry.criticality == :optional
    assert entry.state == :deprecated
  end

  test "entry/1 resolves a namespace and misses an unknown one" do
    assert {:ok, entry} = ExtensionRegistry.entry("com.example/federation")
    assert entry.owner == "Agent Blueprint Protocol"
    assert :error = ExtensionRegistry.entry("com.example.unregistered/playbook")
  end

  test "the federation entry ships a REAL digest over its authored schema" do
    {:ok, entry} = ExtensionRegistry.entry("com.example/federation")

    assert is_binary(entry.schema_digest)

    # The digest is over JCS of the PARSED document under the
    # extension-schema domain — the authoring contract.
    {:ok, jcs} = Canonicalization.encode(ExtensionRegistry.federation_schema())
    assert entry.schema_digest == Digest.to_tagged(Digest.hash(:extension_schema, jcs))
  end

  test "the authored federation schema lies inside the bounded dialect" do
    assert {:ok, _} =
             AgentBlueprintProtocol.Schema.parse(
               ExtensionRegistry.federation_schema(),
               AgentBlueprintProtocol.Schema.dialect()
             )
  end

  test "entries whose owner has not authored a schema carry nil digests" do
    {:ok, entry} = ExtensionRegistry.entry("com.example.commerce/graph")
    assert entry.schema_digest == nil
  end

  test "every authored registry schema is a CLOSED object schema (lens F7)" do
    for entry <- ExtensionRegistry.registered_extensions(), entry.schema_digest != nil do
      document =
        case entry.namespace do
          "com.example/federation" -> ExtensionRegistry.federation_schema()
          _other -> estate_contract_schema_document()
        end

      {:ok, parsed} = Schema.parse(document, Schema.dialect())

      root = parsed.root

      assert match?({:object, _}, root)

      assert List.keyfind(elem(root, 1), "additionalProperties", 0) ==
               {"additionalProperties", {:boolean, false}}

      _ = entry
    end
  end

  test "the estate-contract pin equals the digest of the SHIPPED corpus document" do
    # The two hash domains differ by construction (the corpus index hashes raw file
    # bytes; the registry pin hashes JCS of the PARSED document) — this test is the
    # binding between them. The federation pin test binds pin-to-lib-code above;
    # the product document lives in the corpus, so the pin binds to the fixture.
    {:ok, entry} = ExtensionRegistry.entry("com.example.platform/estate-contract")
    document = estate_contract_schema_document()

    assert {:ok, parsed} = Schema.parse(document, Schema.dialect())
    {:ok, jcs} = Canonicalization.encode(parsed.root)

    assert entry.schema_digest == Digest.to_tagged(Digest.hash(:extension_schema, jcs))
  end

  test "the shipped document meters inside the bounded complexity ceiling" do
    {:ok, parsed} = Schema.parse(estate_contract_schema_document(), Schema.dialect())
    assert parsed.complexity <= 512
  end

  describe "the estate-contract document's condition tiers (the portable depth bound)" do
    setup do
      {:ok, parsed} = Schema.parse(estate_contract_schema_document(), Schema.dialect())
      %{schema: parsed}
    end

    defp window, do: %{"definition" => %{"name" => "d", "version" => 1}, "window_days" => nil}

    defp body(condition),
      do: %{"asset_materialization_window" => window(), "objective_condition" => condition}

    defp leaf,
      do: %{"op" => "materialization_present", "definition" => %{"name" => "d", "version" => 1}}

    defp to_tagged(map) when is_map(map) do
      {:object, Enum.map(Enum.sort(map), fn {k, v} -> {k, to_tagged(v)} end)}
    end

    defp to_tagged(list) when is_list(list), do: {:array, Enum.map(list, &to_tagged/1)}
    defp to_tagged(nil), do: :null
    defp to_tagged(s) when is_binary(s), do: {:string, s}
    defp to_tagged(n) when is_integer(n), do: {:integer, n}

    defp validate(schema, value) do
      Schema.validate_instance(schema, to_tagged(value), Schema.dialect())
    end

    test "accepts the reference shapes: a bare leaf and uniform-depth tiers 1 through 3", %{
      schema: schema
    } do
      t1 = %{"op" => "and", "args" => [leaf(), leaf()]}
      t2 = %{"op" => "or", "args" => [t1, %{"op" => "not", "args" => [leaf()]}]}
      t3 = %{"op" => "and", "args" => [t2, t2]}

      assert :ok = validate(schema, body(leaf()))
      assert :ok = validate(schema, body(t1))
      assert :ok = validate(schema, body(t2))
      assert :ok = validate(schema, body(t3))
    end

    test "denies a depth-4 tree: the portable bound is three composite tiers", %{schema: schema} do
      t1 = %{"op" => "and", "args" => [leaf(), leaf()]}
      t2 = %{"op" => "and", "args" => [t1, t1]}
      t3 = %{"op" => "and", "args" => [t2, t2]}
      t4 = %{"op" => "and", "args" => [t3, t3]}

      assert {:error, :invalid_cardinality} = validate(schema, body(t4))
    end

    test "denies depth-skipping args (the renderer normalizes by identity padding)", %{
      schema: schema
    } do
      t1 = %{"op" => "and", "args" => [leaf(), leaf()]}
      skip = %{"op" => "and", "args" => [leaf(), t1]}

      assert {:error, :invalid_cardinality} = validate(schema, body(skip))
    end

    test "denies the grammar violations: not-arity, empty args, non-object op carrier", %{
      schema: schema
    } do
      assert {:error, :invalid_cardinality} =
               validate(schema, body(%{"op" => "not", "args" => [leaf(), leaf()]}))

      assert {:error, :invalid_cardinality} =
               validate(schema, body(%{"op" => "and", "args" => []}))

      assert {:error, :invalid_cardinality} = validate(schema, body("and"))
    end
  end

  test "promotion governance: no entry claims a promotion revision yet" do
    # The registry-authoring rule: optional -> critical moves only with a
    # protocol revision increment, recorded in promoted_at_revision. All
    # first-release entries are native, never promoted.
    for entry <- ExtensionRegistry.registered_extensions() do
      assert entry.promoted_at_revision == nil
    end
  end

  describe "digest/0 (the corpus-registry binding)" do
    test "is the pinned content digest — any registry edit consciously moves it" do
      # Pinned 2026-08-25 over the six entries (five first-release rows plus the
      # estate-contract product registration; the placeholder estate row deprecated).
      # A registry content change (new entry, criticality flip, schema authored,
      # state move) reds this pin; the developer updates it together with the corpus
      # index's registry_digest.
      assert Digest.to_tagged(ExtensionRegistry.digest()) ==
               "sha-256:6sKyVlqYeL7DfUOr0bfeNzneASJoih6yYfmA_C0Qadw"
    end

    test "is the domain-separated JCS digest over the projected entries" do
      # Pins the FORMULA: every registered entry, every declared field, JCS
      # member order, the :extension_registry separator.
      projected =
        {:object,
         Enum.map(ExtensionRegistry.registered_extensions(), fn entry ->
           {entry.namespace,
            {:object,
             [
               {"a2a_uri", {:string, entry.a2a_uri}},
               {"criticality", {:string, Atom.to_string(entry.criticality)}},
               {"owner", {:string, entry.owner}},
               {"promoted_at_revision",
                if(prom = entry.promoted_at_revision, do: {:integer, prom}, else: :null)},
               {"schema_digest", if(sd = entry.schema_digest, do: {:string, sd}, else: :null)},
               {"state", {:string, Atom.to_string(entry.state)}}
             ]}}
         end)}

      {:ok, jcs} = Canonicalization.encode(projected)

      assert ExtensionRegistry.digest() == Digest.hash(:extension_registry, jcs)
    end

    test "is stable across calls (no map-iteration order leakage)" do
      assert ExtensionRegistry.digest() == ExtensionRegistry.digest()
    end
  end
end
