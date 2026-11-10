defmodule AgentBlueprintProtocol.InputLimitsTest do
  use ExUnit.Case, async: false

  alias AgentBlueprintProtocol.{
    Blueprint,
    BlueprintFixture,
    Bounds,
    Canonicalization,
    Deployment,
    Digest,
    Federation,
    Json,
    Schema,
    Signature
  }

  test "host argument shapes deny through the existing result channel" do
    value = BlueprintFixture.fixture_value()

    for call <- [
          fn -> Json.decode("1", nil) end,
          fn -> AgentBlueprintProtocol.decode_blueprint("{}", bytes: 10) end,
          fn -> Canonicalization.verify(:x) end,
          fn -> Canonicalization.encode({:object, [:x]}) end,
          fn -> Signature.verify(BlueprintFixture.signature_entry(), nil) end,
          fn -> Digest.from_tagged(1) end,
          fn -> Blueprint.from_value(value, []) end,
          fn -> Deployment.from_value(:x) end,
          fn -> Bounds.new(nil) end
        ] do
      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} = call.()
    end
  end

  test "predicate content is scanned through boolean arguments and path segments" do
    leaf =
      {:object,
       [
         {"op", {:string, "eq"}},
         {"path", BlueprintFixture.path(["request"])},
         {"value", {:string, "https://example.com/token"}}
       ]}

    for predicate <- [
          {:object, [{"op", {:string, "and"}}, {"args", {:array, [leaf]}}]},
          {:object, [{"op", {:string, "or"}}, {"args", {:array, [leaf]}}]},
          {:object, [{"op", {:string, "not"}}, {"args", {:array, [leaf]}}]},
          {:object,
           [
             {"op", {:string, "eq"}},
             {"path", BlueprintFixture.path(["request", "https://example.com/token"])},
             {"value", :null}
           ]}
        ] do
      assertion =
        BlueprintFixture.assertion(kind: "deterministic_predicate", predicate: predicate)

      assert {:error, %AgentBlueprintProtocol.Error{code: :forbidden_portable_value}} =
               Blueprint.decode(BlueprintFixture.fixture_bytes(assertions: [assertion]))
    end
  end

  test "schema memoization work excludes repeated hashing of enum payloads" do
    values = [{:string, "match"} | for(i <- 1..200, do: {:string, "example_#{i}"})]
    schema = {:object, [{"items", {:object, [{"enum", {:array, values}}]}}]}
    instance = {:array, List.duplicate({:string, "match"}, 16)}
    parent = self()
    tracer = spawn(fn -> memo_work(parent, 0) end)
    Code.ensure_loaded!(Schema)

    assert 1 =
             :erlang.trace_pattern({Schema, :evaluate, 5}, [{:_, [], [{:return_trace}]}], [:local])

    :erlang.trace(self(), true, [:call, {:tracer, tracer}])

    try do
      {:reductions, before} = Process.info(self(), :reductions)
      assert :ok = Schema.validate_instance(schema, instance, Schema.dialect())
      {:reductions, after_count} = Process.info(self(), :reductions)
      assert after_count - before < 100_000
      ref = :erlang.trace_delivered(self())
      assert_receive {:trace_delivered, _, ^ref}, 1_000
      send(tracer, :finish)
      assert_receive {:memo_work, bytes}, 1_000
      assert bytes > 0 and bytes < 4_096
    after
      :erlang.trace(self(), false, [:call])
      :erlang.trace_pattern({Schema, :evaluate, 5}, false, [:local])
      send(tracer, :finish)
    end
  end

  defp memo_work(parent, largest) do
    receive do
      {:trace, _, :return_from, {Schema, :evaluate, 5}, {:ok, memo}} ->
        bytes = memo |> Map.keys() |> Enum.map(&:erlang.external_size/1) |> Enum.sum()
        memo_work(parent, max(largest, bytes))

      :finish ->
        send(parent, {:memo_work, largest})

      _ ->
        memo_work(parent, largest)
    end
  end

  test "federation reconstruction bounds total nodes across sibling subtrees" do
    subtree = {:array, List.duplicate(:null, 1_000)}
    value = {:object, [{"example", {:array, List.duplicate(subtree, 201)}}]}

    assert {:error, %AgentBlueprintProtocol.Error{code: {:ceiling, :nodes}}} =
             Federation.from_value(value)
  end

  test "direct portability scans bound recursion before walking deeply nested values" do
    value = Enum.reduce(1..20_000, :null, fn _, acc -> {:array, [acc]} end)

    for scan <- [:scan, :scan_authored, :scan_identifier, :scan_value] do
      assert {:error, %AgentBlueprintProtocol.Error{code: {:ceiling, :depth}}} =
               apply(AgentBlueprintProtocol.Portability, scan, [value])

      assert {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}} =
               apply(AgentBlueprintProtocol.Portability, scan, [{:array, [:null | :x]}])
    end
  end
end
