defmodule AgentBlueprintProtocol.DeploymentFixture do
  @moduledoc """
  Shared builder for a complete, valid Deployment Manifest artifact (the 16
  required members plus optional evidence), used by the unit, property, and
  fuzz lanes. The deployment digest is computed the way an honest producer
  would: over the canonical bytes of the covered members exactly, under the
  deployment-content domain.

  The default fixture binds the default `BlueprintFixture` artifact: the
  release digest is the paired Blueprint's honest content digest and every
  `tool_bindings.logical_operation` resolves against that Blueprint's
  capability families or effect intents — so `binds?/2` and `verify_binding/3`
  are green on the defaults and each deny has a one-option override.
  """

  alias AgentBlueprintProtocol.{
    Blueprint,
    BlueprintFixture,
    Canonicalization,
    Digest
  }

  def tagged(bytes), do: Digest.to_tagged(Digest.hash(:deployment_content, bytes))

  def paired_blueprint(opts \\ []) do
    {:ok, blueprint} = Blueprint.from_value(BlueprintFixture.fixture_value(opts))
    blueprint
  end

  def release_digest(%Blueprint{} = blueprint) do
    # content_digest returns the digest directly on success; anything else
    # fails loud here (a fixture's honest-producer assumption).
    blueprint |> Blueprint.content_digest() |> Digest.to_tagged()
  end

  def blueprint_release(opts \\ []) do
    blueprint = Keyword.get_lazy(opts, :blueprint, fn -> paired_blueprint() end)

    {:object,
     [
       {"blueprint_id", {:string, Keyword.get(opts, :blueprint_id, "example.demo/echo")}},
       {"release_number", {:integer, Keyword.get(opts, :release_number, 1)}},
       {"content_digest", {:string, Keyword.get(opts, :digest, release_digest(blueprint))}}
     ]}
  end

  def tool_binding(opts \\ []) do
    {:object,
     [
       {"logical_operation", {:string, Keyword.get(opts, :operation, "example.demo.read_shape")}},
       {"adapter_identity", {:string, Keyword.get(opts, :adapter, "example.adapters.tools")}},
       {"descriptor_digest", {:string, Keyword.get(opts, :descriptor, tagged("descriptor"))}},
       {"schema_digest", {:string, Keyword.get(opts, :schema, tagged("schema"))}},
       {"attested_at", {:string, Keyword.get(opts, :attested_at, "2026-08-20T00:00:00Z")}}
     ]}
  end

  def expression(kind) do
    {:object,
     [
       {"kind", {:string, kind}},
       {"policy", {:string, "example.policies/principal-bands"}},
       {"band", {:string, "operator"}}
     ]}
  end

  def eligibility(opts \\ []) do
    {:object,
     [
       {"owner", Keyword.get(opts, :owner, expression("owner_band"))},
       {"beneficiary", Keyword.get(opts, :beneficiary, expression("beneficiary_band"))},
       {"runtime_principal", Keyword.get(opts, :runtime_principal, expression("runtime_band"))}
     ]}
  end

  def data_binding(opts \\ []) do
    {:object,
     [
       {"logical_dataset", {:string, Keyword.get(opts, :dataset, "shape_orders")}},
       {"classification_ceiling", {:string, Keyword.get(opts, :classification, "internal")}},
       {"as_of",
        Keyword.get(
          opts,
          :as_of,
          {:object, [{"mode", {:string, "required"}}, {"max_age_ms", {:integer, 86_400_000}}]}
        )}
     ]}
  end

  def authority_requirement do
    {:object,
     [
       {"adapter_identity", {:string, "example.adapters.authority"}},
       {"profile_identity", {:string, "example.profiles.read-only"}}
     ]}
  end

  def effect_owner(opts \\ []) do
    {:object,
     [
       {"adapter_identity", {:string, Keyword.get(opts, :adapter, "example.adapters.effects")}},
       {"idempotency",
        {:object,
         [
           {"key_derivation", {:string, "host"}},
           {"recovery", {:string, Keyword.get(opts, :recovery, "authoritative")}}
         ]}}
     ]}
  end

  def evaluation_binding do
    {:object,
     [
       {"adapter_identity", {:string, "example.adapters.evaluations"}},
       {"corpus",
        {:object,
         [
           {"name", {:string, "example.corpora/echo"}},
           {"digest", {:string, tagged("corpus")}}
         ]}}
     ]}
  end

  def build_identity(opts \\ []) do
    {:object,
     [
       {"kind", {:string, Keyword.get(opts, :kind, "package")}},
       {"name", {:string, Keyword.get(opts, :name, "agent_blueprint_protocol")}},
       {"version", {:string, Keyword.get(opts, :version, "0.1.0")}},
       {"digest", {:string, Keyword.get(opts, :digest, tagged("identity"))}}
     ]}
  end

  def host_bounds do
    {:object,
     [
       {"approval_trait", {:string, "none"}},
       {"authority_trait", {:string, "none"}},
       {"classification_ceiling", {:string, "internal"}},
       {"disclosure_ceiling", {:string, "summary"}},
       {"effect_impact_ceiling", {:string, "ordinary"}},
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

  def lifecycle(opts \\ []) do
    state = Keyword.get(opts, :state, "active")

    {:object,
     [
       {"state", {:string, state}},
       {"activated_at", Keyword.get(opts, :activated_at, activated_default(state))},
       {"retired_at", Keyword.get(opts, :retired_at, nil)}
     ]
     |> Enum.reject(fn {_name, value} -> value == nil end)}
  end

  defp activated_default("draft"), do: nil
  defp activated_default(_active_or_retired), do: {:string, "2026-08-20T00:00:00Z"}

  def model_policy(opts \\ []) do
    {:object,
     [
       {"allowed_model_roles",
        {:array, Enum.map(Keyword.get(opts, :roles, ["reasoner"]), &{:string, &1})}},
       {"max_tokens", {:integer, Keyword.get(opts, :max_tokens, 50_000)}},
       {"max_cost", {:object, [{"amount", {:integer, 500}}, {"currency", {:string, "USD"}}]}}
     ]}
  end

  def extensions(opts \\ []) do
    critical = Keyword.get(opts, :critical, %{})
    optional = Keyword.get(opts, :optional, %{})

    to_object = fn map ->
      {:object, Enum.map(Enum.sort(map), fn {ns, body} -> {ns, body} end)}
    end

    {:object, [{"critical", to_object.(critical)}, {"optional", to_object.(optional)}]}
  end

  def signature_attrs(opts \\ []) do
    {:object,
     [
       {"algorithm", {:string, "Ed25519"}},
       {"content_digest", {:string, Keyword.get(opts, :digest, tagged("signed"))}},
       {"created_at", {:string, "2026-08-20T00:00:00Z"}},
       {"key_id", {:string, Keyword.get(opts, :key_id, "example-demo-deploy-key")}},
       {"purpose", {:string, Keyword.get(opts, :purpose, "deployment")}}
     ]}
  end

  def signature_entry(opts \\ []) do
    header =
      Keyword.get(opts, :header, BlueprintFixture.signature_header("example-demo-deploy-key"))

    attrs = Keyword.get(opts, :attrs, signature_attrs())

    sig =
      with {:ok, h} <- Canonicalization.encode(header),
           {:ok, a} <- Canonicalization.encode(attrs) do
        signing_input = AgentBlueprintProtocol.Base64Url.encode(h) <> "." <> a
        {_pub, priv} = BlueprintFixture.signing_keypair()

        {:string,
         AgentBlueprintProtocol.Base64Url.encode(
           :crypto.sign(:eddsa, :none, signing_input, [priv, :ed25519])
         )}
      end

    {:object, [{"protected", header}, {"signed_attributes", attrs}, {"signature", sig}]}
  end

  # The 16 required members (deployment_digest computed by with_digest/1).
  def base_members(opts \\ []) do
    [
      {"authority_requirement",
       Keyword.get(opts, :authority_requirement, authority_requirement())},
      {"blueprint_release",
       Keyword.get(
         opts,
         :blueprint_release,
         blueprint_release(
           Keyword.take(opts, [:blueprint, :blueprint_id, :release_number, :digest])
         )
       )},
      {"build_identities", {:array, Keyword.get(opts, :build_identities, [build_identity()])}},
      {"data_bindings", {:array, Keyword.get(opts, :data_bindings, [data_binding()])}},
      {"effect_owner", Keyword.get(opts, :effect_owner, effect_owner())},
      {"eligibility", Keyword.get(opts, :eligibility, eligibility())},
      {"evaluation_binding", Keyword.get(opts, :evaluation_binding, evaluation_binding())},
      {"extensions", Keyword.get(opts, :extensions, extensions())},
      {"host_bounds", Keyword.get(opts, :host_bounds, host_bounds())},
      {"lifecycle",
       Keyword.get(
         opts,
         :lifecycle,
         lifecycle(Keyword.take(opts, [:state, :activated_at, :retired_at]))
       )},
      {"model_policy", Keyword.get(opts, :model_policy, model_policy())},
      {"protocol_revision", {:integer, Keyword.get(opts, :protocol_revision, 1)}},
      {"required_core_fields",
       {:array, Enum.map(Keyword.get(opts, :required_core_fields, []), &{:string, &1})}},
      {"scope_projection",
       {:object, [{"adapter_identity", {:string, "example.adapters.scope"}}]}},
      {"signer_custody", {:string, Keyword.get(opts, :signer_custody, "host_managed")}},
      {"tool_bindings",
       {:array,
        Keyword.get(opts, :tool_bindings, [
          tool_binding(operation: "example.demo.read_shape"),
          tool_binding(operation: "record_summary", adapter: "example.adapters.effects.tools")
        ])}}
    ]
  end

  @evidence_members ~w(deployment_digest signatures attestations)

  def with_digest(members, opts \\ []) do
    sorted = Enum.sort(members)

    covered = Enum.reject(sorted, fn {name, _} -> name in @evidence_members end)
    tagged = Digest.to_tagged(compute_digest(covered))

    digest_member =
      {"deployment_digest", {:string, Keyword.get(opts, :declared_digest, tagged)}}

    kept = Enum.reject(sorted, fn {name, _} -> name == "deployment_digest" end)
    {:object, Enum.sort([digest_member | kept])}
  end

  def compute_digest(members) do
    {:ok, jcs} = Canonicalization.encode({:object, members})
    Digest.hash(:deployment_content, jcs)
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
    entries = Keyword.get(opts, :signatures, [signature_entry()])

    fixture_value(opts ++ [extra_members: [{"signatures", {:array, entries}}]])
  end
end
