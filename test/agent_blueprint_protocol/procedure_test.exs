Code.require_file("../../scripts/procedure_cases.exs", __DIR__)

defmodule AgentBlueprintProtocol.ProcedureTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentBlueprintProtocol.Conformance.Runner

  alias AgentBlueprintProtocol.{
    Canonicalization,
    Deployment,
    DeploymentFixture,
    Digest,
    Error,
    Json,
    Procedure
  }

  @namespace "io.github.baselabs/procedure"

  def tag(value) do
    {:ok, value} = value |> Jason.encode!() |> Json.decode()
    value
  end

  def hash(value) do
    {:ok, bytes} = value |> tag() |> Canonicalization.encode()
    Digest.of(bytes) |> Digest.to_tagged()
  end

  def body do
    %{
      "profile" => %{
        "profile_id" => "example.profiles/one",
        "roles" => [
          %{
            "role" => "example.roles/one",
            "forms" => ["artifact"],
            "bases" => ["host_computed", "holder_asserted"],
            "min" => 1,
            "max" => 2,
            "evidence" => "optional",
            "principal" => "optional",
            "validity" => "optional"
          }
        ]
      },
      "instances" => [
        %{
          "id" => "example.instances/one",
          "role" => "example.roles/one",
          "identity" => %{"form" => "artifact", "digest" => hash("artifact")},
          "provenance" => %{"basis" => "host_computed"}
        }
      ]
    }
  end

  def deployment(body) do
    value =
      DeploymentFixture.fixture_value(
        extensions: DeploymentFixture.extensions(critical: %{@namespace => tag(body)})
      )

    {:ok, deployment} = Deployment.from_value(value, %{authored_extensions: [@namespace]})
    deployment
  end

  def inputs(deployment, body) do
    builds = [
      %{
        kind: "package",
        name: "agent_blueprint_protocol",
        version: "0.1.0",
        digest: DeploymentFixture.tagged("identity")
      }
    ]

    struct(Procedure.Inputs,
      children: [],
      documents: %{},
      accepted_profiles: [hash(body["profile"])],
      attempt: hash("attempt"),
      execution_boundary: hash("boundary"),
      phase: :before_send,
      inventory: %{
        "builds" => builds,
        "instances" => body["instances"],
        "manifest_digest" => Digest.to_tagged(Deployment.content_digest(deployment)),
        "attempt" => hash("attempt")
      }
    )
  end

  def verify(body, change \\ fn x -> x end) do
    deployment = deployment(body)
    Procedure.verify(deployment, change.(inputs(deployment, body)))
  end

  for row <- AgentBlueprintProtocol.ProcedureCases.constraint_cases() do
    @row row
    test "procedure constraint: #{@row["id"]}" do
      assert {_actual, true} = Runner.execute(@row, %{}, %{})
    end
  end

  for row <-
        AgentBlueprintProtocol.ProcedureCases.carrier_cases(
          "priv/conformance/cases/procedure-reconcile.json"
          |> File.read!()
          |> Jason.decode!()
          |> Map.fetch!("cases")
          |> Enum.find(&(&1["id"] == "reconcile-procedure-valid"))
        ) do
    @row row
    test "Deployment-only carrier: #{@row["id"]}" do
      assert {_actual, true} = Runner.execute(@row, %{}, %{})
      assert Runner.project(@row, %{}, %{}) == @row["expected"]
    end
  end

  test "struct observations deny a typed input error without raising" do
    assert {:error, %Error{code: :invalid_type, subject: ["inputs"]}} =
             verify(body(), &put_in(&1.inventory["instances"], [%URI{}]))
  end

  test "native procedure imports deny non-map and struct inventories" do
    b = body()
    dep = deployment(b)
    opts = inputs(dep, b)

    for inventory <- [nil, false, [], %URI{}] do
      assert {:error, %Error{code: :invalid_type, subject: ["inputs"]}} =
               Procedure.verify(dep, %{opts | inventory: inventory})
    end
  end

  test "honest artifact observations produce measured, attempt-bound evidence" do
    assert {:ok, evidence} = verify(body())
    assert [%{surface: :procedure, verified: true, detail: detail} | _] = evidence.checks
    assert detail.phase == :before_send
    assert detail.attempt == hash("attempt")
    assert :identity_validity in evidence.not_verified
    assert :observer_trust in evidence.not_verified
    assert Enum.any?(evidence.checks, &(Map.get(&1.detail, :assurance) == :measured))
  end

  test "all procedure mismatches are binding checks, never build compatibility codes" do
    for mutate <- [
          fn i -> put_in(i.inventory["attempt"], hash("another")) end,
          fn i -> put_in(i.inventory["manifest_digest"], hash("another")) end,
          fn i -> put_in(i.inventory["instances"], []) end,
          fn i -> update_in(i.inventory["instances"], &(&1 ++ &1)) end,
          fn i ->
            update_in(
              i.inventory["instances"],
              &(&1 ++ [put_in(hd(&1)["id"], "example.instances/extra")])
            )
          end,
          fn i ->
            put_in(i.inventory["instances"], [
              put_in(hd(body()["instances"])["identity"]["digest"], hash("changed"))
            ])
          end
        ] do
      assert {:error, %Error{code: :binding_incomplete}} = verify(body(), mutate)
    end
  end

  test "a profile changed under its id is rejected" do
    changed = put_in(body()["profile"]["roles"], [])
    assert {:error, %Error{code: :invalid_cardinality}} = verify(changed)

    assert {:error, %Error{code: :invalid_constraint}} =
             verify(body(), &%{&1 | accepted_profiles: [hash("other")]})
  end

  test "holder assertions and validity remain explicit host-owned facts" do
    b =
      put_in(body()["instances"], [
        put_in(
          hd(body()["instances"])["provenance"],
          %{"basis" => "holder_asserted", "validity" => %{"not_before" => "2099-01-01T00:00:00Z"}}
        )
      ])

    assert {:ok, evidence} = verify(b)
    assert Enum.any?(evidence.checks, &(Map.get(&1.detail, :assurance) == :asserted))
    assert :holder_assertion_truth in evidence.not_verified
    assert :identity_validity in evidence.not_verified
  end

  test "decode precedence pins unknown, missing, type, constraint, cardinality and nested failures" do
    for {b, code} <- [
          {Map.put(%{}, "unknown", true), :unknown_member},
          {%{}, :missing_required_field},
          {%{"profile" => false, "instances" => []}, :invalid_type},
          {put_in(body()["instances"], []), :invalid_cardinality},
          {put_in(body()["instances"], [%{"unknown" => true}]), :unknown_member},
          {put_in(body()["instances"], [
             put_in(hd(body()["instances"])["identity"]["form"], "unknown")
           ]), :invalid_constraint}
        ] do
      assert {:error, %Error{code: ^code}} = Procedure.decode(tag(b))
    end
  end

  test "authored critical procedure bodies keep the strict portability scan" do
    b = put_in(body()["profile"]["profile_id"], "https://example.invalid/config")

    value =
      DeploymentFixture.fixture_value(
        extensions: DeploymentFixture.extensions(critical: %{@namespace => tag(b)})
      )

    assert {:error, %Error{code: :forbidden_portable_value}} =
             Deployment.from_value(value, %{authored_extensions: [@namespace]})
  end

  test "the procedure portability rule applies to every artifact carrier" do
    b = put_in(body()["profile"]["profile_id"], "https://example.invalid/config")

    value =
      AgentBlueprintProtocol.BlueprintFixture.fixture_value(
        extensions: DeploymentFixture.extensions(critical: %{@namespace => tag(b)})
      )

    assert {:error, %Error{code: :forbidden_portable_value}} =
             AgentBlueprintProtocol.Blueprint.from_value(value, %{
               authored_extensions: [@namespace]
             })
  end

  test "configuration documents require typed salted commitments and schema exactness" do
    doc = %{
      "type" => "agent-blueprint-protocol/procedure-configuration",
      "nonce" => String.duplicate("0", 64),
      "version" => "1.2.3"
    }

    rule =
      Map.merge(hd(body()["profile"]["roles"]), %{
        "forms" => ["configuration"],
        "schema" => %{
          "type" => "object",
          "properties" => %{
            "type" => %{"type" => "string"},
            "nonce" => %{"type" => "string"},
            "version" => %{"type" => "string"}
          },
          "required" => ["type", "nonce", "version"],
          "additionalProperties" => false
        },
        "exact" => ["version"]
      })

    instance =
      put_in(hd(body()["instances"])["identity"], %{
        "form" => "configuration",
        "digest" => hash(doc)
      })

    b = body() |> put_in(["profile", "roles"], [rule]) |> put_in(["instances"], [instance])
    assert {:ok, commitment} = Procedure.document_commitment(tag(doc))
    assert commitment == hash(doc)
    assert {:error, %Error{code: :binding_incomplete}} = verify(b)
    assert {:ok, _} = verify(b, &%{&1 | documents: %{hash(doc) => tag(doc)}})
    bad = Map.put(doc, "version", "latest")
    b = put_in(b["instances"], [put_in(instance["identity"]["digest"], hash(bad))])

    assert {:error, %Error{code: :invalid_constraint, subject: subject}} =
             verify(b, &%{&1 | documents: %{hash(bad) => tag(bad)}})

    assert "version" in subject

    assert {:error, %Error{code: :invalid_constraint}} =
             Procedure.document_commitment(tag(Map.delete(doc, "nonce")))
  end

  test "configuration schema roots resolve array pointers and reject self-reference" do
    doc = %{
      "type" => "agent-blueprint-protocol/procedure-configuration",
      "nonce" => String.duplicate("0", 64),
      "revision" => 1
    }

    closed = %{
      "type" => "object",
      "properties" => %{
        "type" => %{"type" => "string"},
        "nonce" => %{"type" => "string"},
        "revision" => %{"type" => "integer"}
      },
      "required" => ["type", "nonce", "revision"],
      "additionalProperties" => false
    }

    schema = %{"$ref" => "#/oneOf/0", "oneOf" => [closed]}

    role =
      hd(body()["profile"]["roles"])
      |> Map.put("forms", ["configuration"])
      |> Map.put("schema", schema)

    instance =
      put_in(hd(body()["instances"])["identity"], %{
        "form" => "configuration",
        "digest" => hash(doc)
      })

    b = body() |> put_in(["profile", "roles"], [role]) |> put_in(["instances"], [instance])

    assert {:ok, _} = verify(b, &%{&1 | documents: %{hash(doc) => tag(doc)}})

    cyclic = put_in(b["profile"]["roles"], [Map.put(role, "schema", %{"$ref" => "#"})])
    assert {:error, %Error{code: :schema_ref_cycle}} = verify(cyclic)
  end

  test "reconcile denies an incomplete procedure import and includes successful procedure evidence" do
    b = body()
    dep = deployment(b)
    bp = DeploymentFixture.paired_blueprint()
    {:ok, bounds} = AgentBlueprintProtocol.BoundsAlgebra.from_deployment(dep)

    support = %AgentBlueprintProtocol.Negotiation.Support{
      revisions: MapSet.new([1]),
      schemas: %{@namespace => Procedure.schema()}
    }

    options = %AgentBlueprintProtocol.Reconcile.Inputs{
      host_bounds: bounds,
      support: support,
      keys: [],
      protected_clamp: :acknowledge,
      observations: %Deployment.Observations{}
    }

    assert {:error, %Error{code: :binding_incomplete}} =
             AgentBlueprintProtocol.Reconcile.reconcile(bp, dep, options)

    assert {:ok, evidence} =
             AgentBlueprintProtocol.Reconcile.reconcile(
               bp,
               dep,
               Map.put(options, :procedure, inputs(dep, b))
             )

    assert Enum.any?(evidence.checks, &(&1.surface == :procedure))
    assert :identity_validity in evidence.not_verified
    refute :procedure_identity in evidence.not_verified

    bad = put_in(inputs(dep, b).inventory["attempt"], hash("other-attempt"))

    assert {:error, %Error{code: :binding_incomplete}} =
             AgentBlueprintProtocol.Reconcile.reconcile(bp, dep, %{options | procedure: bad})
  end

  test "composition accepts decoded children and denies duplicate or malformed child inputs" do
    b = AgentBlueprintProtocol.ProcedureCases.body()
    {bytes, digest} = AgentBlueprintProtocol.ProcedureCases.manifest(b)
    {root, _, _} = AgentBlueprintProtocol.ProcedureCases.parent(b, [{b, bytes, digest}])
    dep = deployment(root)
    opts = inputs(dep, root)
    {:ok, child} = Deployment.decode(bytes)
    assert {:ok, _} = Procedure.verify(dep, %{opts | children: [child]})

    assert {:error, %Error{code: :invalid_constraint}} =
             Procedure.verify(dep, %{opts | children: [child, bytes]})

    assert {:error, %Error{code: :binding_incomplete}} =
             Procedure.verify(dep, %{opts | children: [false]})
  end

  test "procedure runner denies malformed nested host inputs without raising" do
    base =
      AgentBlueprintProtocol.ProcedureCases.input(AgentBlueprintProtocol.ProcedureCases.body())

    for input <- [
          Map.put(base, "inputs", false),
          put_in(base["inputs"]["inventory"], false),
          put_in(base["inputs"]["inventory"]["builds"], false),
          put_in(base["inputs"]["inventory"]["builds"], [false]),
          put_in(base["inputs"]["inventory"]["builds"], [%{}]),
          put_in(base["inputs"]["documents"], false),
          put_in(base["inputs"]["phase"], "unknown")
        ] do
      row = %{
        "surface" => "procedure.verify",
        "input" => input,
        "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
      }

      assert {{:error, %Error{code: :invalid_type}}, true} =
               Runner.execute(row, %{}, %{})
    end
  end

  test "role schemas preserve numeric keyword values" do
    role = Map.put(hd(body()["profile"]["roles"]), "schema", %{"minimum" => 0.5})
    assert {:ok, _} = verify(put_in(body()["profile"]["roles"], [role]))
  end

  test "missing namespace and non-object document inputs deny" do
    {:ok, dep} = Deployment.from_value(DeploymentFixture.fixture_value())

    assert {:error, %Error{code: :missing_required_field}} =
             Procedure.verify(dep, inputs(dep, body()))

    assert {:error, %Error{code: :invalid_type}} =
             Procedure.document_commitment({:boolean, false})

    assert {:error, %Error{code: :invalid_type}} =
             Procedure.decode(
               tag(
                 put_in(body()["instances"], [put_in(hd(body()["instances"])["identity"], false)])
               )
             )
  end

  test "durable validity still requires a valid timestamp spelling" do
    for timestamp <- ["tomorrow", "2026-02-30T00:00:00Z"] do
      instance =
        put_in(hd(body()["instances"])["provenance"]["validity"], %{"not_before" => timestamp})

      assert {:error, %Error{code: :invalid_constraint}} =
               Procedure.decode(tag(put_in(body()["instances"], [instance])))
    end
  end

  test "a declared form or provenance basis must be allowed by its role" do
    for instance <- [
          put_in(hd(body()["instances"])["identity"], %{
            "form" => "build",
            "name" => "agent_blueprint_protocol"
          }),
          put_in(hd(body()["instances"])["provenance"]["basis"], "host_configured")
        ] do
      assert {:error, %Error{code: :invalid_constraint}} =
               verify(put_in(body()["instances"], [instance]))
    end
  end

  test "shared descendants are checked once per declared composition edge" do
    b = AgentBlueprintProtocol.ProcedureCases.body()
    {bytes, digest} = AgentBlueprintProtocol.ProcedureCases.manifest(b)
    leaf = {b, bytes, digest}
    mid = AgentBlueprintProtocol.ProcedureCases.parent(b, [leaf, leaf])
    root = AgentBlueprintProtocol.ProcedureCases.parent(b, [mid, mid])
    root_body = elem(root, 0)
    dep = deployment(root_body)
    opts = inputs(dep, root_body)
    assert {:ok, evidence} = Procedure.verify(dep, %{opts | children: [bytes, elem(mid, 1)]})
    members = Enum.filter(evidence.checks, &match?(["composition" | _], &1.subject))
    assert length(members) == 4
  end

  test "procedure schema is the shipped derived grammar inside the complexity ceiling" do
    {:ok, derived} = File.read!("spec/grammar/derived/procedure.schema.json") |> Json.decode()
    assert Procedure.schema() == derived

    assert {:ok, schema} =
             AgentBlueprintProtocol.Schema.parse(derived, AgentBlueprintProtocol.Schema.dialect())

    assert schema.complexity <= 512
  end

  test "principal choices preserve unknown, missing and type precedence" do
    for {principal, code} <- [
          {%{"extra" => hash("key")}, :unknown_member},
          {%{}, :missing_required_field},
          {%{"key" => 7}, :invalid_type},
          {%{"key" => "sha-256:bad"}, :digest_encoding_invalid},
          {%{"key" => hash("key"), "enrollment" => hash("enrollment")}, :invalid_constraint},
          {false, :invalid_type}
        ] do
      b =
        put_in(body()["instances"], [
          put_in(hd(body()["instances"])["provenance"]["principal"], principal)
        ])

      assert {:error, %Error{code: ^code}} = Procedure.decode(tag(b))
    end
  end

  test "decoder options enforce a tightened byte ceiling" do
    {:ok, bytes} = body() |> tag() |> Canonicalization.encode()
    assert {:ok, _} = Procedure.decode(bytes)

    assert {:error, %Error{code: {:ceiling, :bytes}}} =
             Procedure.decode(bytes, %{bytes: byte_size(bytes) - 1})
  end

  test "improper input lists deny a typed input error" do
    b = body()
    dep = deployment(b)
    i = inputs(dep, b)

    for bad <- [
          %{i | children: [false | false]},
          %{i | accepted_profiles: [hash("profile") | false]},
          put_in(i.inventory["instances"], [hd(b["instances"]) | false])
        ] do
      assert {:error, %Error{code: :invalid_type}} = Procedure.verify(dep, bad)
    end
  end

  test "malformed Deployment roots deny a typed input error" do
    b = body()
    opts = inputs(deployment(b), b)

    for value <- [nil, {:array, []}, {:object, [:invalid]}, {:object, nil}] do
      assert {:error, %Error{code: :invalid_type}} =
               Procedure.verify(%Deployment{value: value}, opts)
    end
  end

  test "malformed build arrays deny before declaration reference checks" do
    role = Map.put(hd(body()["profile"]["roles"]), "forms", ["build"])

    instance =
      put_in(hd(body()["instances"])["identity"], %{
        "form" => "build",
        "name" => "agent_blueprint_protocol"
      })

    b = body() |> put_in(["profile", "roles"], [role]) |> Map.put("instances", [instance])
    dep = deployment(b)
    {:object, pairs} = dep.value

    value =
      {:object,
       List.keyreplace(pairs, "build_identities", 0, {"build_identities", {:boolean, false}})}

    invalid = %{dep | value: value}
    digest = Digest.to_tagged(Deployment.content_digest(invalid))
    {:object, invalid_pairs} = value

    pairs =
      List.keyreplace(
        invalid_pairs,
        "deployment_digest",
        0,
        {"deployment_digest", {:string, digest}}
      )

    assert {:error, %Error{code: :invalid_type}} =
             Procedure.verify(%{invalid | value: {:object, pairs}}, inputs(dep, b))
  end

  test "standalone binding checks that the declared Deployment digest covers its bytes" do
    b = body()
    dep = deployment(b)
    {:object, pairs} = dep.value

    value =
      {:object,
       List.keyreplace(
         pairs,
         "deployment_digest",
         0,
         {"deployment_digest", {:string, hash("other")}}
       )}

    assert {:error, %Error{code: :digest_mismatch}} =
             Procedure.verify(%{dep | value: value}, inputs(dep, b))
  end

  test "object schemas stay closed when expressed through unions or object keywords" do
    for schema <- [
          %{"type" => ["object", "null"]},
          %{"additionalProperties" => true},
          %{"required" => ["revision"]}
        ] do
      role = Map.put(hd(body()["profile"]["roles"]), "schema", schema)
      b = put_in(body()["profile"]["roles"], [role])
      assert {:error, %Error{code: :invalid_constraint}} = verify(b)
    end
  end

  property "host commitments use canonical object order" do
    check all(n <- integer(0..1_000)) do
      doc =
        tag(%{"type" => "example.document", "nonce" => String.duplicate("0", 64), "value" => n})

      {:object, pairs} = doc

      assert Procedure.document_commitment(doc) ==
               Procedure.document_commitment({:object, Enum.reverse(pairs)})
    end
  end

  property "procedure bodies round-trip through canonical bytes" do
    check all(n <- integer(0..1_000)) do
      value =
        put_in(body()["instances"], [
          put_in(hd(body()["instances"])["identity"]["digest"], hash(n))
        ])
        |> tag()

      assert {:ok, decoded} = Procedure.decode(value)
      assert {:ok, bytes} = Canonicalization.encode(decoded.value)
      assert {:ok, ^decoded} = Procedure.decode(bytes)
    end
  end
end
