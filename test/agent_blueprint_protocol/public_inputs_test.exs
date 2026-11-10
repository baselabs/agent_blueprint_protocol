defmodule AgentBlueprintProtocol.PublicInputsTest do
  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{
    Blueprint,
    BlueprintFixture,
    Bounds,
    BoundsAlgebra,
    Canonicalization,
    Compatibility,
    Deployment,
    DeploymentFixture,
    Digest,
    Error,
    Extension,
    Federation,
    Negotiation,
    Reconcile,
    Schema,
    Signature
  }

  alias AgentBlueprintProtocol.Conformance.{Cli, Corpus, Report, Runner}
  alias AgentBlueprintProtocol.ConformanceTest.Builder

  @bad [
    nil,
    :x,
    1,
    [],
    %{},
    {:object, [:x]},
    {:object, nil},
    {:array, :x},
    {:string, nil},
    {:string, <<255>>},
    [nil | :x]
  ]

  test "public functions accept or deny malformed host shapes without raising" do
    for suffix <- [
          Base64Url,
          Bounds,
          Canonicalization,
          Digest,
          Blueprint,
          Deployment,
          Federation,
          Extension,
          ExtensionRegistry,
          Schema,
          Signature,
          Portability,
          Predicate,
          Negotiation,
          BoundsAlgebra,
          Compatibility,
          Evidence,
          Reconcile,
          Registry,
          Conformance.Corpus,
          Conformance.Report,
          Conformance.Runner
        ] do
      module =
        if String.starts_with?(Atom.to_string(suffix), "Elixir.AgentBlueprintProtocol."),
          do: suffix,
          else: Module.concat(AgentBlueprintProtocol, suffix)

      Code.ensure_loaded!(module)

      for {name, arity} <- module.__info__(:functions),
          arity > 0,
          name != :__struct__,
          bad <- @bad do
        apply(module, name, List.duplicate(bad, arity))
      end
    end
  end

  @tag :tmp_dir
  test "runner input readers deny malformed nested collections and structs", %{tmp_dir: dir} do
    for bad <- [MapSet.new([1]), Bounds.maximum(), %URI{}, [1 | :bad]] do
      assert {{:error, :invalid_type}, false} = Runner.execute(bad, %{}, %{})
      assert {:error, %Error{code: :invalid_type}} = BoundsAlgebra.BoundSet.new(bad)
    end

    for support <- [
          %{"revisions" => "x"},
          %{"revisions" => 1},
          %{"core_fields" => 1},
          %{"registry" => 1},
          %{"registry" => %{"example" => 1}},
          %{"schemas" => 1},
          %{"schemas" => MapSet.new()},
          %{"registry" => %URI{}}
        ] do
      row = %{
        "surface" => "negotiation.negotiate",
        "input" => %{"artifact" => %{}, "support" => support}
      }

      assert {{:error, :invalid_type}, false} = Runner.execute(row, %{}, %{})
    end

    for bad <- ["x", 1, [1 | :bad], MapSet.new()] do
      row = %{
        "surface" => "bounds_algebra.intersect",
        "input" => %{
          "blueprint" => %{"classification_ceiling" => %{"ordinal" => "public", "markers" => bad}}
        }
      }

      assert {{:error, _}, false} = Runner.execute(row, %{}, %{})
    end

    deep = Enum.reduce(1..65, %{}, fn _, acc -> %{"x" => acc} end)
    assert {{:error, :invalid_type}, false} = Runner.execute(%{"input" => deep}, %{}, %{})

    for binding <- [1, %{"blueprint" => BlueprintFixture.fixture_bytes(), "now" => 1}] do
      Runner.execute(
        %{
          "surface" => "deployment.decode",
          "input" => %{
            "text" => DeploymentFixture.fixture_bytes(),
            "binding" => binding
          }
        },
        %{},
        %{}
      )
    end

    assert {{:error, :invalid_type}, false} =
             Runner.execute(
               %{
                 "surface" => "schema.validate_instance",
                 "input" => %{"schema_file" => "example", "instance" => 1}
               },
               %{"example" => %URI{}},
               %{}
             )

    assert {{:error, :invalid_type}, false} =
             Runner.execute(
               %{
                 "surface" => "bounds_algebra.intersect",
                 "input" => %{
                   "blueprint" => %{"classification_ceiling" => %{"ordinal" => "public"}}
                 }
               },
               %{},
               %{}
             )

    for {surface, input} <- [
          {"negotiation.negotiate", %{"artifact" => %{}, "support" => %{"schemas" => 1}}},
          {"negotiation.negotiate", %{"artifact" => %{}, "support" => %{"registry" => 1}}},
          {"negotiation.negotiate",
           %{"artifact" => %{}, "support" => %{"registry" => %{"example" => 1}}}},
          {"negotiation.negotiate", %{"artifact" => %{}, "support" => "x"}},
          {"negotiation.negotiate", %{"artifact" => %{}, "support" => %{"revisions" => 1}}},
          {"negotiation.negotiate", %{"artifact" => %{}, "support" => %{"core_fields" => "x"}}},
          {"bounds_algebra.intersect",
           %{
             "blueprint" => %{
               "classification_ceiling" => %{"ordinal" => "public", "markers" => "x"}
             }
           }},
          {"bounds_algebra.intersect", %{"blueprint" => 1}}
        ] do
      rows = Builder.minimal_cases()
      [row | _] = rows
      row = %{row | "surface" => surface, "input" => input}
      # Keep the declared floor intact while adding one malformed case.
      map =
        Builder.build(rows ++ [%{row | "id" => "malformed-reader", "class" => "invalid_type"}])

      for {path, bytes} <- map do
        file = Path.join(dir, path)
        File.mkdir_p!(Path.dirname(file))
        File.write!(file, bytes)
      end

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          assert Cli.run(["--corpus", dir]) == 2
        end)

      assert stderr =~ "corpus integrity failure: :invalid_type"

      {output, status} =
        System.cmd("node", ["verifier/cli.ts", "--corpus", dir], stderr_to_stdout: true)

      assert status == 2
      assert output =~ "corpus integrity failure: :invalid_type"
    end

    assert {{:error, :invalid_type}, false} = Runner.execute(%{"input" => %URI{}}, %{}, %{})
    assert {{:error, :invalid_type}, false} = Runner.execute(%{}, %URI{}, %{})
    assert {{:error, :invalid_type}, false} = Runner.execute(%{}, %{}, %URI{})
  end

  test "artifact helpers deny malformed held values and malformed options" do
    checks = [%{surface: :signature, verified: true, subject: []} | :x]

    assert {:error, %Error{code: :invalid_type}} =
             AgentBlueprintProtocol.Evidence.build(%{checks: checks})

    for module <- [Blueprint, Deployment], bad <- @bad do
      artifact = struct(module, value: bad)
      assert {:error, _} = module.from_value(bad, [])
      assert {:error, _} = module.from_value(bad, %{authored_extensions: nil})
      assert {:error, _} = module.from_value(bad, %{authored_extensions: [nil]})
      result = module.content_digest(artifact)
      assert match?(%Digest{}, result) or match?({:error, _}, result)
      module.verify_content_digest(artifact)
      module.digest_input(artifact)
    end

    assert Schema.ceiling()

    assert :ok =
             Schema.validate_instance(
               {:object, [{"maximum", {:integer, 2}}]},
               {:float, 1.5},
               Schema.dialect()
             )

    entry = BlueprintFixture.signature_entry(attrs: BlueprintFixture.signature_attrs(key_id: ""))
    assert {:error, :signature_malformed} = Signature.signing_input(entry)

    assert {:error, :invalid_encoding} = Canonicalization.sort_key(<<255>>)
    assert {:error, :invalid_type} = Canonicalization.encode({:object, [{1, :null}]})
    assert {:error, :invalid_type} = Canonicalization.encode({:object, [{"x", :null} | :x]})
  end

  test "federation projections and checks deny malformed structs and carriers" do
    assert AgentBlueprintProtocol.federation_mapping() == Federation.mapping()
    assert length(Federation.envelope_members()) == 23

    for bad <- @bad do
      envelope = %Federation{value: bad}
      Federation.member_map(envelope)
      Federation.terminal_commitment(envelope)
      Federation.verify_commitment(envelope, %Federation.Context{})
      Federation.to_a2a_carrier(envelope)
      Federation.to_mcp_carrier(envelope)
      Federation.from_a2a_carrier(bad)
      Federation.from_mcp_carrier(bad)
    end

    assert {:error, %Error{code: :invalid_type}} =
             Federation.from_value({:object, [{"x", {:integer, nil}}]})
  end

  test "composed checks deny malformed artifacts and host inputs" do
    {:ok, blueprint} = Blueprint.from_value(BlueprintFixture.fixture_value())
    {:ok, deployment} = Deployment.from_value(DeploymentFixture.fixture_value())
    {:ok, set} = BoundsAlgebra.from_blueprint(blueprint)

    for observed <- [MapSet.new([1]), %URI{}] do
      assert {:error, :invalid_type} =
               Deployment.verify_binding(deployment, blueprint, %Deployment.Observations{
                 observed: observed
               })
    end

    args = %Reconcile.Inputs{
      host_bounds: set,
      support: %Negotiation.Support{},
      observations: %Deployment.Observations{},
      keys: [%Signature.PublicKey{algorithm: :ed25519, key_id: "example", key: <<>>} | :x],
      protected_clamp: :deny
    }

    assert {:error, %Error{code: :invalid_type}} =
             Reconcile.reconcile(blueprint, deployment, args)

    for bad <- @bad do
      assert {:error, _} = Negotiation.negotiate(bad, %Negotiation.Support{})

      assert {:error, _} =
               Compatibility.verify(%Deployment{value: bad}, %Compatibility.Observed{
                 identities: []
               })

      assert {:error, _} = BoundsAlgebra.from_blueprint(%Blueprint{value: bad})
      assert {:error, _} = BoundsAlgebra.from_deployment(%Deployment{value: bad})

      assert {:error, _} =
               Reconcile.reconcile(%Blueprint{value: bad}, deployment, %Reconcile.Inputs{})

      Deployment.verify_binding(deployment, %Blueprint{value: bad}, %Deployment.Observations{})
    end

    assert {:error, :invalid_type} =
             Deployment.verify_binding(deployment, blueprint, %Deployment.Observations{
               observed: nil
             })

    assert {:error, :invalid_type} = Signature.verify(BlueprintFixture.signature_entry(), [nil])

    assert {:error, :invalid_type} =
             Negotiation.negotiate(Blueprint.to_value(blueprint), %Negotiation.Support{
               revisions: nil
             })

    assert {:error, :invalid_type} = Extension.envelope_ok?({:object, [:x]})

    assert {:error, :invalid_type} =
             AgentBlueprintProtocol.Registry.validate([nil], {:object, []})

    assert {:error, :invalid_type} = Report.to_bytes(struct(Corpus), nil)
    assert {{:error, :invalid_type}, false} = Runner.execute(%{"input" => nil}, %{}, %{})

    assert {:error, :invalid_type} =
             Runner.run(struct(Corpus, cases: [nil], data: %{}, raws: %{}))
  end

  test "typed denials cover malformed result rows and reconstructed bounds" do
    corpus = struct(Corpus)
    assert {:error, :invalid_type} = Report.build(corpus, [nil])
    assert {:error, :invalid_type} = Report.build(corpus, [{"example", [nil]}])

    for rows <- [nil, [nil]] do
      assert {:error, :invalid_type} =
               Runner.run(struct(Corpus, cases: [{"example", rows}], data: %{}, raws: %{}))
    end

    {:ok, blueprint} = Blueprint.from_value(BlueprintFixture.fixture_value())
    {:ok, set} = BoundsAlgebra.from_blueprint(blueprint)
    malformed = %{set | bounds: Map.put(set.bounds, :max_attempts, nil)}
    assert BoundsAlgebra.widens?(malformed, set)
    assert {:error, %Error{code: :invalid_type}} = BoundsAlgebra.BoundSet.to_map(malformed)

    assert {:error, %Error{code: :invalid_type}} =
             BoundsAlgebra.intersect(%BoundsAlgebra.Sources{
               blueprint: malformed,
               deployment: set,
               host: set
             })

    {:ok, plain} = BoundsAlgebra.BoundSet.to_map(set)

    scoped = fn markers ->
      BoundsAlgebra.BoundSet.new(
        Map.put(plain, :classification_ceiling, %{
          ordinal: :internal,
          markers: MapSet.new(markers)
        })
      )
    end

    {:ok, bp_set} = scoped.([:pci])
    {:ok, dp_set} = scoped.([:phi])
    {:ok, host_set} = scoped.([])

    assert {:ok, _} =
             BoundsAlgebra.intersect(%BoundsAlgebra.Sources{
               blueprint: bp_set,
               deployment: dp_set,
               host: host_set,
               protected_clamp: :acknowledge
             })

    assert Digest.equal?(Digest.of([1, <<2>>]), Digest.of(<<1, 2>>))
    {:object, fields} = AgentBlueprintProtocol.FederationFixture.value(terminal: true)

    envelope = %Federation{
      value: {:object, List.keydelete(fields, "result_classification_ceiling", 0)}
    }

    assert {:error, %Error{code: :invalid_type}} = Federation.terminal_commitment(envelope)

    assert {:error, :invalid_type} =
             Negotiation.negotiate(
               {:object,
                [
                  {"protocol_revision", {:integer, 1}},
                  {"content_digest", {:string, "example"}},
                  {"required_core_fields", {:array, [:null]}}
                ]},
               %Negotiation.Support{revisions: MapSet.new([1])}
             )

    for assertion <- [:null, {:object, [{"kind", {:integer, 1}}]}] do
      value = BlueprintFixture.fixture_value(assertions: [assertion])

      assert {:error, :invalid_type} =
               AgentBlueprintProtocol.Registry.validate(Blueprint.table(), value)
    end

    for bad <- [{:object, [:x]}, {:object, [{"x", :x}]}] do
      assertion = BlueprintFixture.assertion(kind: "deterministic_predicate", predicate: bad)

      {:object, members} = BlueprintFixture.fixture_value()

      value =
        {:object,
         List.keyreplace(
           members,
           "evaluation_assertions",
           0,
           {"evaluation_assertions", {:array, [assertion]}}
         )}

      assert {:error, :invalid_type} =
               AgentBlueprintProtocol.Registry.validate(Blueprint.table(), value)
    end
  end

  test "compatibility denies improper observed identities with a valid deployment" do
    {:ok, deployment} = Deployment.from_value(DeploymentFixture.fixture_value())
    identity = %{kind: "tool", name: "example", version: "1.0.0", digest: "example"}

    for identities <- [[nil | :bad], [identity | :bad]] do
      observed = %Compatibility.Observed{identities: identities}
      assert {:error, %Error{code: :invalid_type}} = Compatibility.verify(deployment, observed)

      assert {:error, %Error{code: :invalid_type}} =
               AgentBlueprintProtocol.verify_compatibility(deployment, observed)
    end
  end

  test "registry input shapes deny before reading malformed descriptors or lists" do
    for kind <- [{:enum, nil}, {:array, nil}, {:object, %{members: nil}}, :example] do
      assert {:error, :invalid_type} =
               AgentBlueprintProtocol.Registry.validate(
                 [%{name: "example", required: false, kind: kind}],
                 {:object, []}
               )
    end

    table = [%{name: "example", required: false, kind: {:array, %{kind: :any}}}]

    assert {:error, :invalid_type} =
             AgentBlueprintProtocol.Registry.validate(
               table,
               {:object, [{"example", {:array, [:null | :x]}}]}
             )

    assert {:error, :invalid_type} =
             AgentBlueprintProtocol.Registry.validate(table, {:object, [{"example", :null} | :x]})

    for scan <- [:scan, :scan_authored, :scan_identifier, :scan_value] do
      assert {:error, :invalid_type} =
               apply(AgentBlueprintProtocol.Portability, scan, [{:object, [:x]}])
    end
  end
end
