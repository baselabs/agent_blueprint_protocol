Code.require_file("../scripts/check_grammar_derivation.exs", __DIR__)

defmodule AgentBlueprintProtocol.GrammarDerivationTest do
  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{GrammarDerivation, Json, Schema}

  @dialect "https://json-schema.org/draft/2020-12/schema"

  test "map choices derive oneOf with literal and null members" do
    source = """
    policy =
      { mode: "none", max_age_ms: null } /
      { mode: "required", max_age_ms: positive-integer }
    positive-integer = integer .gt 0
    """

    assert {:ok, schema} = GrammarDerivation.derive(source, "policy")
    assert %{"oneOf" => [none, required]} = schema["$defs"]["policy"]
    assert none["properties"]["mode"] == %{"const" => "none"}
    assert none["properties"]["max_age_ms"] == %{"type" => "null"}
    assert required["properties"]["mode"] == %{"const" => "required"}
    assert none["additionalProperties"] == false
    assert required["additionalProperties"] == false
  end

  test "unsupported choices and malformed maps fail closed" do
    for expression <- [
          ~s({ mode: "none" } / tstr),
          ~s({ mode: "none" } /),
          ~s({ mode: "none" } trailing),
          ~s({ mode: "none"),
          ~s({ mode: "none" } // { mode: "required" })
        ] do
      assert {:error, _} = GrammarDerivation.derive("policy = " <> expression, "policy")
    end
  end

  test "deployment grammar accepts exactly the supported as_of policies within the schema ceiling" do
    assert {:ok, schema} =
             GrammarDerivation.derive(File.read!("spec/grammar/deployment.cddl"), "deployment")

    {:ok, tagged_schema} = schema |> Jason.encode!() |> Json.decode()
    assert {:ok, parsed} = Schema.parse(tagged_schema, @dialect)
    assert parsed.complexity <= Schema.ceiling()

    golden = File.read!("priv/conformance/vectors/deployment-golden.json") |> Jason.decode!()

    for {policy, accepted?} <- [
          {%{"mode" => "none", "max_age_ms" => nil}, true},
          {%{"mode" => "required", "max_age_ms" => 1}, true},
          {%{"mode" => "none", "max_age_ms" => 1}, false},
          {%{"mode" => "required", "max_age_ms" => nil}, false},
          {%{"mode" => "required", "max_age_ms" => 0}, false},
          {%{"mode" => "none"}, false},
          {%{"mode" => "required"}, false}
        ] do
      [binding | rest] = golden["data_bindings"]
      value = Map.put(golden, "data_bindings", [Map.put(binding, "as_of", policy) | rest])
      {:ok, tagged} = value |> Jason.encode!() |> Json.decode()
      result = Schema.validate_instance(tagged_schema, tagged, @dialect)
      assert result == :ok == accepted?, "as_of grammar disagrees for #{inspect(policy)}"
    end
  end
end
