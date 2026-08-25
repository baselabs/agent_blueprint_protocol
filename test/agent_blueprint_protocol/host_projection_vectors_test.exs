defmodule AgentBlueprintProtocol.HostProjectionVectorsTest do
  @moduledoc """
  Host example vectors: one Blueprint Core + one estate Deployment Manifest
  projected from reference definition shapes. They validate the protocol
  against a self-contained fixture with two governed proposers, one estate
  read, and one objective-driven mutation.

  Two portability-name findings are pinned as reds, not hidden:

  - the host's effect-once identity names its tenant members `org_id` /
    `account_id` — portability-denylisted member names, so the projection
    spells them `organization` / `account` (no tenant identifiers in
    portable artifacts; the fixture names are red-tested here);
  - a foreign critical extension (the `com.example.commerce/graph`
    namespace) fails closed at a host-pinned registry view that holds it
    `:reserved` — the two-host fail-closed half of this acceptance.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{
    Blueprint,
    BlueprintFixture,
    Deployment,
    DeploymentFixture,
    Evidence,
    ExtensionRegistry,
    Negotiation,
    Reconcile
  }

  alias AgentBlueprintProtocol.BoundsAlgebra
  alias AgentBlueprintProtocol.Deployment.Observations
  alias AgentBlueprintProtocol.Negotiation.Support

  # The reference pair used by this projection: AssetDefinition
  # (name "daily_position_summary", definition_version 7) + an
  # ObjectiveDefinition whose condition requires a present, non-stale
  # materialization under that definition (stale beyond max_age_days 7).
  @definition_name "daily_position_summary"
  @definition_version 7
  @max_age_days 7

  # The reference action surface, one operation family per modeled action (the
  # falsifier table): an estate read, the objective-driven mutation, and the
  # two governed proposers. The mutation family uses the fixture's operation
  # identifier.
  @reference_action_families %{
    "example.estate.investigate" => {"read", "none", "none"},
    "example.estate.act_under_objective" => {"mutation", "none", "external_authority_required"},
    "example.estate.propose_asset_definition" => {"mutation", "human_required", "none"},
    "example.estate.propose_objective" => {"mutation", "human_required", "none"}
  }

  # ---- the reference-shaped condition AST (carried verbatim in the estate body) ----------

  defp condition_ast do
    {:object,
     [
       {"op", {:string, "and"}},
       {"args",
        {:array,
         [
           {:object,
            [
              {"op", {:string, "materialization_present"}},
              {"definition",
               {:object,
                [
                  {"name", {:string, @definition_name}},
                  {"version", {:integer, @definition_version}}
                ]}}
            ]},
           {:object,
            [
              {"op", {:string, "materialization_stale"}},
              {"definition",
               {:object,
                [
                  {"name", {:string, @definition_name}},
                  {"version", {:integer, @definition_version}}
                ]}},
              {"max_age_days", {:integer, @max_age_days}}
            ]}
         ]}}
     ]}
  end

  # ---- schema documents ---------------------------------------------------------------

  defp object_schema(properties, required) do
    {:object,
     [
       {"type", {:string, "object"}},
       {"properties", {:object, Enum.map(Enum.sort(properties), & &1)}},
       {"required", {:array, Enum.map(Enum.sort(required), &{:string, &1})}}
     ]}
  end

  defp string_schema, do: {:object, [{"type", {:string, "string"}}]}
  defp integer_schema, do: {:object, [{"type", {:string, "integer"}}]}
  defp free_object_schema, do: {:object, [{"type", {:string, "object"}}]}

  # The objective-gate input: the arguments the host's condition evaluator
  # reads (the objective, the account, the evaluation instant, and the
  # definition reference the condition's leaves resolve against).
  defp gate_schema do
    object_schema(
      [
        {"objective", string_schema()},
        {"account", string_schema()},
        {"as_of", string_schema()},
        {"definition",
         object_schema([{"name", string_schema()}, {"version", integer_schema()}], [
           "name",
           "version"
         ])}
      ],
      ["objective", "account", "as_of", "definition"]
    )
  end

  # The effect-once identity echo: the host's idempotency identity
  # (org, account, asset definition, definition version, as_of) with the two
  # tenant-identifier members under their projected names — the original
  # member names are portability-denylisted and red-tested below.
  defp echo_schema do
    object_schema(
      [
        {"organization", string_schema()},
        {"account", string_schema()},
        {"asset_definition", string_schema()},
        {"definition_version", integer_schema()},
        {"as_of", string_schema()}
      ],
      ["organization", "account", "asset_definition", "definition_version", "as_of"]
    )
  end

  # ---- the projected Blueprint -------------------------------------------------------

  # Hand-enumerated literals, deliberately NOT derived from
  # @reference_action_families: the falsifier pin below compares the projected
  # vector against the reference-action table as two independent sources — a
  # vector generated from the table could never redden the pin.
  defp capabilities do
    [
      {:object,
       [
         {"operation_family", {:string, "example.estate.investigate"}},
         {"argument_schema", object_schema([{"account", string_schema()}], ["account"])},
         {"result_schema", free_object_schema()},
         {"operation_kind", {:string, "read"}},
         {"impact_class", {:string, "ordinary"}},
         {"classification_ceiling", {:string, "internal"}},
         {"approval_trait", {:string, "none"}},
         {"authority_trait", {:string, "none"}}
       ]},
      {:object,
       [
         {"operation_family", {:string, "example.estate.act_under_objective"}},
         {"argument_schema",
          object_schema(
            [
              {"objective", string_schema()},
              {"account", string_schema()},
              {"as_of", string_schema()}
            ],
            ["objective", "account", "as_of"]
          )},
         {"result_schema", free_object_schema()},
         {"operation_kind", {:string, "mutation"}},
         {"impact_class", {:string, "ordinary"}},
         {"classification_ceiling", {:string, "internal"}},
         {"approval_trait", {:string, "none"}},
         {"authority_trait", {:string, "external_authority_required"}}
       ]},
      {:object,
       [
         {"operation_family", {:string, "example.estate.propose_asset_definition"}},
         {"argument_schema",
          object_schema(
            [
              {"name", string_schema()},
              {"definition_version", integer_schema()},
              {"window_days", integer_schema()}
            ],
            ["name", "definition_version"]
          )},
         {"result_schema", free_object_schema()},
         {"operation_kind", {:string, "mutation"}},
         {"impact_class", {:string, "ordinary"}},
         {"classification_ceiling", {:string, "internal"}},
         {"approval_trait", {:string, "human_required"}},
         {"authority_trait", {:string, "none"}}
       ]},
      {:object,
       [
         {"operation_family", {:string, "example.estate.propose_objective"}},
         {"argument_schema",
          object_schema(
            [
              {"name", string_schema()},
              {"version", integer_schema()},
              {"condition", free_object_schema()},
              {"definition", string_schema()}
            ],
            ["name", "version", "condition", "definition"]
          )},
         {"result_schema", free_object_schema()},
         {"operation_kind", {:string, "mutation"}},
         {"impact_class", {:string, "ordinary"}},
         {"classification_ceiling", {:string, "internal"}},
         {"approval_trait", {:string, "human_required"}},
         {"authority_trait", {:string, "none"}}
       ]}
    ]
  end

  defp blueprint_members(opts) do
    echo =
      Keyword.get(
        opts,
        :echo_schema,
        echo_schema()
      )

    [
      {"blueprint_id", {:string, "example.estate/objective-projection"}},
      {"capability_requirements", {:array, capabilities()}},
      {"ceilings", BlueprintFixture.ceilings()},
      {"classification_ceiling", {:string, "internal"}},
      {"effect_intents",
       {:array,
        [
          {:object,
           [
             {"logical_operation", {:string, "record_materialization"}},
             {"operation_kind", {:string, "mutation"}},
             {"impact_class", {:string, "ordinary"}}
           ]}
        ]}},
      {"evaluation_assertions",
       {:array,
        [
          # The core-expressible half of the condition contract: the gate's
          # definition reference must resolve to THIS release's version.
          {:object,
           [
             {"kind", {:string, "deterministic_predicate"}},
             {"predicate",
              {:object,
               [
                 {"op", {:string, "eq"}},
                 {"path",
                  {:array,
                   [{:string, "objective_gate"}, {:string, "definition"}, {:string, "version"}]}},
                 {"value", {:integer, Keyword.get(opts, :gate_version, @definition_version)}}
               ]}}
           ]},
          # The objective-driven operation must run through the reference mutation
          # family, never a bespoke one.
          {:object,
           [
             {"kind", {:string, "required_capability_use"}},
             {"operation_family", {:string, "example.estate.act_under_objective"}}
           ]},
          # The condition grounds on the mirrored estate dataset the host binds.
          {:object,
           [
             {"kind", {:string, "grounding_presence"}},
             {"dataset", {:string, "mirrored_estate_transactions"}}
           ]}
        ]}},
      {"extensions",
       BlueprintFixture.extensions(
         optional: %{"com.example.platform/estate" => condition_ast()},
         critical: Keyword.get(opts, :critical_extensions, %{})
       )},
      {"input_ports",
       {:array,
        [
          # window_days is nullable at the host (nil = all-time); the port
          # carries that as required: false.
          BlueprintFixture.port("window_days",
            schema: integer_schema(),
            required: false
          ),
          BlueprintFixture.port("objective_gate", schema: gate_schema())
        ]}},
      {"output_contract",
       {:object,
        [
          {"port", {:string, "materialization_identity"}},
          {"classification_ceiling", {:string, "internal"}}
        ]}},
      {"output_ports",
       {:array,
        [
          BlueprintFixture.port("materialization_identity", schema: echo)
        ]}},
      {"producer",
       {:object,
        [
          {"created_at", {:string, "2026-08-23T00:00:00Z"}},
          {"identity", {:string, "example.estate"}},
          {"toolchain", {:string, "example.estate.projection"}}
        ]}},
      {"protocol_revision", {:integer, 1}},
      {"release_number", {:integer, Keyword.get(opts, :release_number, @definition_version)}},
      {"required_core_fields", {:array, []}},
      {"triggers", {:array, [{:string, "manual"}]}}
    ]
  end

  defp blueprint_value(opts \\ []) do
    BlueprintFixture.with_digest(blueprint_members(opts), Keyword.take(opts, [:declared_digest]))
  end

  defp blueprint(opts \\ []) do
    {:ok, blueprint} = Blueprint.from_value(blueprint_value(opts))
    blueprint
  end

  # ---- the projected Deployment Manifest ---------------------------------------------

  # The host posture the meet needs: approval and authority at the levels
  # the projected capabilities oblige (the governed proposers are
  # human-approved; the mutation runs under external authority), disclosure
  # full (the Blueprint declares no disclosure member — the identity).
  defp host_bounds do
    {:object, members} = DeploymentFixture.host_bounds()

    overrides = %{
      "approval_trait" => "human_required",
      "authority_trait" => "external_authority_required",
      "disclosure_ceiling" => "full"
    }

    {:object,
     Enum.map(members, fn
       {name, {:string, _}} = entry ->
         case Map.fetch(overrides, name) do
           {:ok, value} -> {name, {:string, value}}
           :error -> entry
         end

       entry ->
         entry
     end)}
  end

  defp deployment_members(%Blueprint{} = bound) do
    max_age_ms = @max_age_days * 24 * 60 * 60 * 1000

    [
      {"authority_requirement",
       {:object,
        [
          {"adapter_identity", {:string, "example.estate.authority"}},
          {"profile_identity", {:string, "example.profiles.revocation-sensitive"}}
        ]}},
      {"blueprint_release",
       {:object,
        [
          {"blueprint_id", {:string, "example.estate/objective-projection"}},
          {"release_number", {:integer, @definition_version}},
          {"content_digest", {:string, DeploymentFixture.release_digest(bound)}}
        ]}},
      {"build_identities",
       {:array,
        [
          {:object,
           [
             {"kind", {:string, "package"}},
             {"name", {:string, "example_pipeline"}},
             {"version", {:string, "0.9.1"}},
             {"digest", {:string, DeploymentFixture.tagged("example-build")}}
           ]}
        ]}},
      {"data_bindings",
       {:array,
        [
          # The mirrored estate the condition reads, gated at the freshness
          # the condition's own max_age_days demands.
          DeploymentFixture.data_binding(
            dataset: "mirrored_estate_transactions",
            as_of:
              {:object, [{"mode", {:string, "required"}}, {"max_age_ms", {:integer, max_age_ms}}]}
          ),
          # The append-only spine: evidence reads carry no as_of requirement.
          DeploymentFixture.data_binding(
            dataset: "spine_events",
            classification: "internal",
            as_of: {:object, [{"mode", {:string, "none"}}, {"max_age_ms", :null}]}
          )
        ]}},
      {"effect_owner",
       {:object,
        [
          {"adapter_identity", {:string, "example.estate.materializations.record"}},
          {"idempotency",
           {:object,
            [
              {"key_derivation", {:string, "host"}},
              {"recovery", {:string, "authoritative"}}
            ]}}
        ]}},
      {"eligibility", DeploymentFixture.eligibility()},
      {"evaluation_binding", DeploymentFixture.evaluation_binding()},
      {"extensions", DeploymentFixture.extensions()},
      {"host_bounds", host_bounds()},
      {"lifecycle", DeploymentFixture.lifecycle()},
      {"model_policy", DeploymentFixture.model_policy()},
      {"protocol_revision", {:integer, 1}},
      {"required_core_fields", {:array, []}},
      {"scope_projection", {:object, [{"adapter_identity", {:string, "example.estate.scope"}}]}},
      {"signer_custody", {:string, "host_managed"}},
      {"tool_bindings",
       {:array,
        [
          DeploymentFixture.tool_binding(
            operation: "example.estate.investigate",
            adapter: "example.estate.tools"
          ),
          DeploymentFixture.tool_binding(
            operation: "example.estate.act_under_objective",
            adapter: "example.estate.tools"
          ),
          DeploymentFixture.tool_binding(
            operation: "record_materialization",
            adapter: "example.estate.effects"
          )
        ]}}
    ]
  end

  defp deployment_value(%Blueprint{} = bound) do
    DeploymentFixture.with_digest(deployment_members(bound))
  end

  defp inputs(opts \\ []) do
    deployment = Keyword.get_lazy(opts, :deployment, fn -> deployment(blueprint()) end)

    {:ok, bounds} = BoundsAlgebra.from_deployment(deployment)

    %Reconcile.Inputs{
      host_bounds: bounds,
      support: Keyword.get(opts, :support, %Support{revisions: MapSet.new([1])}),
      keys: [],
      protected_clamp: :deny,
      observations: %Observations{
        now: ~U[2026-08-21T00:00:00Z],
        max_attestation_age_ms: 86_400_000,
        observed: %{}
      }
    }
  end

  defp deployment(%Blueprint{} = bound) do
    {:ok, deployment} = deployment_value(bound) |> Deployment.from_value()
    deployment
  end

  # ---- green end-to-end ---------------------------------------------------------------

  test "the projected pair reconciles green with the estate extension retained" do
    blueprint = blueprint()
    deployment = deployment(blueprint)

    assert {:ok, %Evidence{clamps: [], optional_extensions_retained: retained} = evidence} =
             Reconcile.reconcile(blueprint, deployment, inputs(deployment: deployment))

    assert "com.example.platform/estate" in retained
    assert Enum.all?(evidence.checks, & &1.verified)

    assert Enum.take(evidence.not_verified, 7) ==
             ~w(tenancy live_policy authority effect_ownership execution billing evaluation_truth)a

    # Mapping pins: release ← definition_version (the gate predicate and the
    # deployment's bound release agree with it), window_days ← a nullable
    # input port, and the estate binding's max_age_ms is the condition's
    # max_age_days rendered in milliseconds.
    {:object, blueprint_members} = Blueprint.to_value(blueprint)
    blueprint_members_map = Map.new(blueprint_members)

    assert Map.fetch!(blueprint_members_map, "release_number") == {:integer, @definition_version}

    # The gate predicate's definition version IS the release (the condition's
    # leaves resolve against this release's definition row).
    {:array, assertions} = Map.fetch!(blueprint_members_map, "evaluation_assertions")

    assert {:object, gate_members} =
             Enum.find(assertions, fn {:object, assertion} ->
               List.keyfind(assertion, "kind", 0) ==
                 {"kind", {:string, "deterministic_predicate"}}
             end)

    {"predicate", {:object, predicate_members}} = List.keyfind(gate_members, "predicate", 0)
    {"value", {:integer, gate_version}} = List.keyfind(predicate_members, "value", 0)
    assert gate_version == @definition_version

    {:array, ports} = Map.fetch!(blueprint_members_map, "input_ports")

    assert {:object, window_members} =
             Enum.find(ports, fn {:object, port} ->
               List.keyfind(port, "name", 0) == {"name", {:string, "window_days"}}
             end)

    assert List.keyfind(window_members, "required", 0) == {"required", {:boolean, false}}

    {:object, deployment_members_now} = Deployment.to_value(deployment)

    assert deployment_members_now
           |> Map.new()
           |> Map.fetch!("data_bindings")
           |> estate_binding_max_age_ms() == @max_age_days * 24 * 60 * 60 * 1000
  end

  # ---- the falsifier pin ----------------------------------------------------------------

  test "every projected operation family is a reference action family" do
    {:object, members} = blueprint_value()
    {:array, projected} = Map.new(members) |> Map.fetch!("capability_requirements")

    projected_families =
      Map.new(projected, fn {:object, capability} ->
        map = Map.new(capability)

        {Map.fetch!(map, "operation_family") |> tagged_string(),
         {Map.fetch!(map, "operation_kind") |> tagged_string(),
          Map.fetch!(map, "approval_trait") |> tagged_string(),
          Map.fetch!(map, "authority_trait") |> tagged_string()}}
      end)

    assert projected_families == @reference_action_families
  end

  # ---- reds on reference-shaped data ---------------------------------------------------------

  test "a digest lie on the reference-derived Blueprint denies :digest_mismatch" do
    honest = blueprint()
    lying_value = blueprint_value(declared_digest: "sha-256:#{String.duplicate("A", 43)}")
    lying = Blueprint.from_value(lying_value) |> elem(1)

    assert {:error, %{code: :digest_mismatch}} =
             Reconcile.reconcile(lying, deployment(honest), inputs())
  end

  test "the effect-once echo under its denylisted member names denies :forbidden_portable_value" do
    # Each tenant-identifier name is tested ALONE: a schema carrying both
    # would stay green if the denylist ever dropped just one of the two
    # (the single-name allow regression).
    for denied_name <- ["org_id", "account_id"] do
      denied_named_echo =
        object_schema(
          [
            {denied_name, string_schema()},
            {"asset_definition", string_schema()},
            {"definition_version", integer_schema()},
            {"as_of", string_schema()}
          ],
          [denied_name, "asset_definition", "definition_version", "as_of"]
        )

      assert {:error, :forbidden_portable_value} =
               Blueprint.from_value(blueprint_value(echo_schema: denied_named_echo))
    end

    # The projected names on the same shape stay green.
    assert match?({:ok, _}, Blueprint.from_value(blueprint_value()))
  end

  test "a foreign critical extension fails closed at a host-pinned registry view" do
    commerce_blueprint =
      blueprint(
        critical_extensions: %{
          "com.example.commerce/graph" => {:object, [{"root", {:string, "account"}}]}
        }
      )

    # The host-pinned registry view: the foreign namespace is held reserved
    # at this host's import surface — a critical attachment is unknown here.
    host_view = %Support{
      revisions: MapSet.new([1]),
      registry: %{
        "com.example.commerce/graph" => %ExtensionRegistry{
          namespace: "com.example.commerce/graph",
          owner: "ExampleCommerce",
          criticality: :critical,
          state: :reserved
        }
      }
    }

    assert {:error, :extension_unknown_critical} =
             Negotiation.negotiate(Blueprint.to_value(commerce_blueprint), host_view)

    assert {:error, %{code: :extension_unknown_critical}} =
             Reconcile.reconcile(
               commerce_blueprint,
               deployment(commerce_blueprint),
               inputs(support: host_view, deployment: deployment(commerce_blueprint))
             )

    # Contrast at the compiled registry (no view pin): the same attachment
    # denies for the missing critical schema, not unknownness — the two-host
    # half needs the view pin to reach the unknown-critical verdict.
    assert {:error, :extension_schema_unavailable} =
             Negotiation.negotiate(
               Blueprint.to_value(commerce_blueprint),
               %Support{revisions: MapSet.new([1])}
             )
  end

  # ---- helpers ---------------------------------------------------------------------------

  defp tagged_string({:string, s}), do: s

  defp estate_binding_max_age_ms({:array, bindings}) do
    {:object, estate} =
      Enum.find(bindings, fn {:object, binding} ->
        List.keyfind(binding, "logical_dataset", 0) ==
          {"logical_dataset", {:string, "mirrored_estate_transactions"}}
      end)

    {"as_of", {:object, as_of}} = List.keyfind(estate, "as_of", 0)
    {"max_age_ms", {:integer, ms}} = List.keyfind(as_of, "max_age_ms", 0)
    ms
  end
end
