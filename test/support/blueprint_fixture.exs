defmodule AgentBlueprintProtocol.BlueprintFixture do
  @moduledoc """
  Shared builder for a complete, valid Blueprint artifact (the 15 required
  members plus optional evidence), used by the unit, conformance, property,
  and fuzz lanes. The digest is computed the way an honest producer would:
  over the canonical bytes of the covered members exactly.
  """

  alias AgentBlueprintProtocol.{Canonicalization, Digest}

  def schema_value do
    {:object, [{"type", {:string, "object"}}]}
  end

  def port(name, opts \\ []) do
    {:object,
     [
       {"name", {:string, name}},
       {"schema", Keyword.get(opts, :schema, schema_value())},
       {"classification_ceiling", {:string, Keyword.get(opts, :classification, "internal")}},
       {"required", {:boolean, Keyword.get(opts, :required, true)}}
     ]}
  end

  def capability(opts \\ []) do
    {:object,
     [
       {"operation_family", {:string, Keyword.get(opts, :family, "example.demo.read_shape")}},
       {"argument_schema", Keyword.get(opts, :argument_schema, schema_value())},
       {"result_schema", Keyword.get(opts, :result_schema, schema_value())},
       {"operation_kind", {:string, Keyword.get(opts, :kind, "read")}},
       {"impact_class", {:string, Keyword.get(opts, :impact, "ordinary")}},
       {"classification_ceiling", {:string, Keyword.get(opts, :classification, "internal")}},
       {"approval_trait", {:string, Keyword.get(opts, :approval, "none")}},
       {"authority_trait", {:string, Keyword.get(opts, :authority, "none")}}
     ]}
  end

  def effect_intent(opts \\ []) do
    {:object,
     [
       {"logical_operation", {:string, Keyword.get(opts, :operation, "record_summary")}},
       {"operation_kind", {:string, Keyword.get(opts, :kind, "mutation")}},
       {"impact_class", {:string, Keyword.get(opts, :impact, "ordinary")}}
     ]}
  end

  def ceilings do
    {:object,
     [
       {"max_attempts", {:integer, 3}},
       {"max_concurrency", {:integer, 2}},
       {"max_cost", {:object, [{"amount", {:integer, 1000}}, {"currency", {:string, "USD"}}]}},
       {"max_depth", {:integer, 8}},
       {"max_descendants", {:integer, 64}},
       {"max_elapsed_ms", {:integer, 60_000}},
       {"max_fan_out", {:integer, 4}},
       {"max_tokens", {:integer, 100_000}}
     ]}
  end

  def assertion(opts \\ []) do
    kind = Keyword.get(opts, :kind, "output_schema")
    {:object, [{"kind", {:string, kind}} | assertion_members(kind, opts)]}
  end

  defp assertion_members("output_schema", opts),
    do: [
      {"port", {:string, Keyword.get(opts, :port, "result")}},
      {"schema", Keyword.get(opts, :schema, schema_value())}
    ]

  defp assertion_members("deterministic_predicate", opts),
    do: [
      {"predicate",
       Keyword.get(
         opts,
         :predicate,
         {:object,
          [{"op", {:string, "eq"}}, {"path", path(["request"])}, {"value", {:string, "x"}}]}
       )}
    ]

  defp assertion_members("required_capability_use", opts),
    do: [{"operation_family", {:string, Keyword.get(opts, :family, "example.demo.read_shape")}}]

  defp assertion_members("forbidden_capability_use", opts),
    do: [{"operation_family", {:string, Keyword.get(opts, :family, "example.demo.erase_db")}}]

  defp assertion_members("grounding_presence", opts),
    do: [{"dataset", {:string, Keyword.get(opts, :dataset, "shape_orders")}}]

  defp assertion_members("policy_denial_expected", opts),
    do: [{"operation_family", {:string, Keyword.get(opts, :family, "example.demo.erase_db")}}]

  defp assertion_members("approval_expected", opts),
    do: [
      {"operation_family", {:string, Keyword.get(opts, :family, "example.demo.read_shape")}},
      {"approval_trait", {:string, Keyword.get(opts, :approval, "human_required")}}
    ]

  defp assertion_members("parameter_bound", opts),
    do: [
      {"parameter", {:string, Keyword.get(opts, :parameter, "level")}},
      {"maximum", {:integer, Keyword.get(opts, :maximum, 10)}}
    ]

  defp assertion_members("provenance_tie_out", opts),
    do: [{"member", {:string, Keyword.get(opts, :member, "blueprint_id")}}]

  defp assertion_members("ceiling", opts),
    do: [
      {"ceiling", {:string, Keyword.get(opts, :ceiling, "max_depth")}},
      {"at_most", {:integer, Keyword.get(opts, :at_most, 32)}}
    ]

  def path(segments), do: {:array, Enum.map(segments, &{:string, &1})}

  def extensions(opts \\ []) do
    critical = Keyword.get(opts, :critical, %{})
    optional = Keyword.get(opts, :optional, %{})

    to_object = fn map ->
      {:object, Enum.map(Enum.sort(map), fn {ns, body} -> {ns, body} end)}
    end

    {:object, [{"critical", to_object.(critical)}, {"optional", to_object.(optional)}]}
  end

  def signature_header(kid \\ "example-demo-signing-key") do
    {:object,
     [
       {"alg", {:string, "EdDSA"}},
       {"b64", {:boolean, false}},
       {"crit", {:array, [{:string, "b64"}]}},
       {"kid", {:string, kid}}
     ]}
  end

  def signature_attrs(opts \\ []) do
    {:object,
     [
       {"algorithm", {:string, "Ed25519"}},
       {"content_digest", {:string, Keyword.get(opts, :digest, honest_tagged_digest())}},
       {"created_at", {:string, "2026-08-20T00:00:00Z"}},
       {"key_id", {:string, Keyword.get(opts, :key_id, "example-demo-signing-key")}},
       {"purpose", {:string, Keyword.get(opts, :purpose, "blueprint")}}
     ]}
  end

  defp honest_tagged_digest,
    do: Digest.to_tagged(Digest.hash(:blueprint_content, ~s({"a":1})))

  def signature_entry(opts \\ []) do
    header = Keyword.get(opts, :header, signature_header())
    attrs = Keyword.get(opts, :attrs, signature_attrs())

    sig =
      Keyword.get_lazy(opts, :signature, fn ->
        with {:ok, h} <- Canonicalization.encode(header),
             {:ok, a} <- Canonicalization.encode(attrs) do
          signing_input = AgentBlueprintProtocol.Base64Url.encode(h) <> "." <> a
          {_pub, priv} = signing_keypair()

          {:string,
           AgentBlueprintProtocol.Base64Url.encode(
             :crypto.sign(:eddsa, :none, signing_input, [priv, :ed25519])
           )}
        end
      end)

    {:object, [{"protected", header}, {"signed_attributes", attrs}, {"signature", sig}]}
  end

  def signing_keypair do
    :crypto.generate_key(:eddsa, :ed25519, :crypto.strong_rand_bytes(32))
  end

  # The 15 required members (content_digest computed by with_digest/1).
  def base_members(opts \\ []) do
    [
      {"blueprint_id", {:string, Keyword.get(opts, :blueprint_id, "example.demo/echo")}},
      {"capability_requirements", {:array, Keyword.get(opts, :capabilities, [capability()])}},
      {"ceilings", Keyword.get(opts, :ceilings, ceilings())},
      {"classification_ceiling", {:string, Keyword.get(opts, :classification, "internal")}},
      {"effect_intents", {:array, Keyword.get(opts, :effects, [effect_intent()])}},
      {"evaluation_assertions", {:array, Keyword.get(opts, :assertions, [assertion()])}},
      {"extensions", Keyword.get(opts, :extensions, extensions())},
      {"input_ports", {:array, Keyword.get(opts, :input_ports, [port("request")])}},
      {"output_contract",
       {:object,
        [
          {"port", {:string, Keyword.get(opts, :output_port, "result")}},
          {"classification_ceiling", {:string, "internal"}}
        ]}},
      {"output_ports", {:array, Keyword.get(opts, :output_ports, [port("result")])}},
      {"producer",
       {:object,
        [
          {"created_at", {:string, "2026-08-20T00:00:00Z"}},
          {"identity", {:string, "example.demo"}},
          {"toolchain", {:string, Keyword.get(opts, :toolchain, "example.demo.toolchain")}}
        ]}},
      {"protocol_revision", {:integer, Keyword.get(opts, :protocol_revision, 1)}},
      {"release_number", {:integer, Keyword.get(opts, :release_number, 1)}},
      {"required_core_fields",
       {:array, Enum.map(Keyword.get(opts, :required_core_fields, []), &{:string, &1})}},
      {"triggers", {:array, Enum.map(Keyword.get(opts, :triggers, ["manual"]), &{:string, &1})}}
    ]
  end

  @evidence_members ~w(content_digest signatures attestations)

  def with_digest(members, opts \\ []) do
    sorted = Enum.sort(members)

    covered = Enum.reject(sorted, fn {name, _} -> name in @evidence_members end)
    tagged = Digest.to_tagged(compute_digest(covered))

    digest_member =
      {"content_digest", {:string, Keyword.get(opts, :declared_digest, tagged)}}

    kept = Enum.reject(sorted, fn {name, _} -> name == "content_digest" end)
    {:object, Enum.sort([digest_member | kept])}
  end

  def compute_digest(members) do
    {:ok, jcs} = Canonicalization.encode({:object, members})
    Digest.hash(:blueprint_content, jcs)
  end

  def fixture_value(opts \\ []) do
    extra = Keyword.get(opts, :extra_members, [])

    (base_members(opts) ++ extra)
    |> with_digest(Keyword.take(opts, [:declared_digest]))
  end

  def fixture_bytes(opts \\ []) do
    {:ok, bytes} = Canonicalization.encode(fixture_value(opts))
    bytes
  end

  def with_signatures(opts \\ []) do
    entries = Keyword.get(opts, :signatures, [signature_entry(opts)])

    fixture_value(opts ++ [extra_members: [{"signatures", {:array, entries}}]])
  end
end
