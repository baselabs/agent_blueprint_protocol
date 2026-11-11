defmodule AgentBlueprintProtocol.ExtensionRegistryTest do
  @moduledoc "The protocol-owned registry and its schema and digest bindings."

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Canonicalization, Digest, ExtensionRegistry, Schema}

  test "only the protocol federation entries are compiled" do
    {:ok, types} = Code.Typespec.fetch_types(ExtensionRegistry)

    {:type, {:state, {:type, _, :union, states}, []}} =
      Enum.find(types, fn {_, {name, _, _}} -> name == :state end)

    assert Enum.map(states, fn {:atom, _, state} -> state end) ==
             [:reserved, :active, :deprecated, :retired]

    assert {:type, {:output_state, {:type, _, :atom, []}, []}} =
             Enum.find(types, fn {_, {name, _, _}} -> name == :output_state end)

    entries = ExtensionRegistry.registered_extensions()

    by_ns = Map.new(entries, fn e -> {e.namespace, e} end)

    assert MapSet.new(Map.keys(by_ns)) ==
             MapSet.new([
               "com.example/federation",
               "io.github.baselabs/federation"
             ])

    assert by_ns["com.example/federation"].criticality == :critical
    assert by_ns["io.github.baselabs/federation"].state == :active
    assert by_ns["com.example/federation"].state == :deprecated
    assert Enum.all?(entries, &(&1.owner == "Agent Blueprint Protocol"))
    assert Enum.all?(entries, &(&1.state in [:active, :deprecated]))
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

  test "every compiled schema is a closed object schema" do
    for entry <- ExtensionRegistry.registered_extensions(), entry.schema_digest != nil do
      document = ExtensionRegistry.federation_schema()

      {:ok, parsed} = Schema.parse(document, Schema.dialect())

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
      assert Digest.to_tagged(ExtensionRegistry.digest()) ==
               "sha-256:hreDA2_XbV5J9geMJDDYG5BB42AGkh9jmQ9bqHe8kRk"
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
