defmodule AgentBlueprintProtocol.ExtensionRegistryTest do
  @moduledoc """
  The compiled-in extension registry: the five first-release entries, the federation
  entry's REAL authored schema digest, compile-time sourcing, and the
  promotion-governance self-check.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Canonicalization, Digest, ExtensionRegistry}

  test "the five first-release entries are registered with their owners and criticalities" do
    entries = ExtensionRegistry.registered_extensions()

    by_ns = Map.new(entries, fn e -> {e.namespace, e} end)

    assert MapSet.new(Map.keys(by_ns)) ==
             MapSet.new([
               "com.example.commerce/graph",
               "com.example.commerce/classification-labels",
               "com.example.commerce/rubric-assertion",
               "com.example.platform/estate",
               "com.example/federation"
             ])

    assert by_ns["com.example.commerce/graph"].criticality == :critical
    assert by_ns["com.example/federation"].criticality == :critical
    assert by_ns["com.example.commerce/classification-labels"].criticality == :optional
    assert Enum.all?(entries, &(&1.state == :active))
    assert Enum.all?(entries, fn e -> is_binary(e.a2a_uri) and e.a2a_uri != "" end)
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
      {:ok, parsed} =
        AgentBlueprintProtocol.Schema.parse(
          ExtensionRegistry.federation_schema(),
          AgentBlueprintProtocol.Schema.dialect()
        )

      root = parsed.root

      assert match?({:object, _}, root)

      assert List.keyfind(elem(root, 1), "additionalProperties", 0) ==
               {"additionalProperties", {:boolean, false}}

      _ = entry
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
      # Pinned 2026-08-23 over the five first-release entries. A registry content change
      # (new entry, criticality flip, schema authored) reds this pin; the
      # developer updates it together with the corpus index's registry_digest.
      assert Digest.to_tagged(ExtensionRegistry.digest()) ==
               "sha-256:N4ov7ha5HubUBUVZSsJCuofuaYdHps3FDVBXW2Rv890"
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
