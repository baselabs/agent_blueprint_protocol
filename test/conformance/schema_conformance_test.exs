defmodule AgentBlueprintProtocol.Conformance.SchemaConformanceTest do
  @moduledoc """
  Conformance corpus row `schema.validate_instance` (spec applicability
  floor): valid · invalid_type · invalid_constraint · maximum_plus_one
  (complexity) · invalid_cardinality — each red on its mutation, pinning
  the class-to-reason mapping the corpus vectors tag. Plus spec-derived
  KATs transcribed from the 2020-12 documents read first-hand here
  (local copies /tmp/js2020-12-{core,validation}.txt): every vector's
  provenance is cited in its test.

  Instance validation is schema-local — signature, digest, and federation
  classes cannot reach this surface.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Json, Schema}

  @dialect Schema.dialect()

  defp decode!(binary) do
    assert {:ok, value} = Json.decode(binary)
    value
  end

  defp validate(schema, instance) do
    Schema.validate_instance(
      (is_binary(schema) && decode!(schema)) || schema,
      (is_binary(instance) && decode!(instance)) || instance,
      @dialect
    )
  end

  # The corpus fixture: a closed port-payload shape exercising every
  # instance-side reason class in one schema.
  @corpus_schema ~s({
    "type":"object",
    "required":["name","revisions"],
    "properties":{
      "name":{"type":"string","minLength":1,"maxLength":64},
      "revisions":{"type":"integer","minimum":0,"maximum":100},
      "labels":{"type":"array","items":{"type":"string"},"minItems":1,"maxItems":8}
    },
    "additionalProperties":false
  })

  describe "class: valid" do
    test "the full corpus shape validates" do
      assert :ok =
               validate(
                 @corpus_schema,
                 ~s({"name":"deploy","revisions":3,"labels":["a","b"]})
               )
    end

    test "mutation red: breaking any keyword flips the verdict (corpus floor)" do
      assert {:error, :invalid_cardinality} =
               validate(@corpus_schema, ~s({"revisions":3,"labels":["a"]}))

      assert {:error, :invalid_type} =
               validate(@corpus_schema, ~s({"name":5,"revisions":3}))

      assert {:error, :invalid_constraint} =
               validate(@corpus_schema, ~s({"name":"x","revisions":101}))

      assert {:error, :invalid_cardinality} =
               validate(@corpus_schema, ~s({"name":"x","revisions":3,"labels":[]}))

      assert {:error, :invalid_cardinality} =
               validate(@corpus_schema, ~s({"name":"x","revisions":3,"extra":1}))
    end
  end

  describe "class: invalid_type" do
    test "type mismatch denies; the reason is the type class" do
      assert {:error, :invalid_type} = validate(~s({"type":"string"}), ~s(5))
      assert {:error, :invalid_type} = validate(@corpus_schema, ~s([1,2]))
    end
  end

  describe "class: invalid_constraint" do
    test "value bounds (enum/const/minimum/maximum/minLength/maxLength)" do
      assert {:error, :invalid_constraint} = validate(~s({"enum":[1,2]}), ~s(3))
      assert {:error, :invalid_constraint} = validate(~s({"const":null}), ~s(1))
      assert {:error, :invalid_constraint} = validate(~s({"minimum":2}), ~s(1))
      assert {:error, :invalid_constraint} = validate(~s({"maxLength":1}), ~s("ab"))
    end
  end

  describe "class: invalid_cardinality" do
    test "member/item set shape (required/minItems/maxItems/oneOf/additionalProperties)" do
      assert {:error, :invalid_cardinality} = validate(~s({"required":["a"]}), ~s({}))
      assert {:error, :invalid_cardinality} = validate(~s({"minItems":2}), ~s([1]))

      assert {:error, :invalid_cardinality} =
               validate(~s({"oneOf":[{"type":"string"}]}), ~s(null))
    end
  end

  describe "class: maximum_plus_one (complexity)" do
    test "a schema under the profile ceiling parses; over denies the complexity reason" do
      # nested properties chain, metric 11L + 11 (no consts — the exact
      # 512 boundary is pinned in the unit suite; here the CLASS is the
      # point: above-ceiling denies :schema_complexity_exceeded).
      under = chain(45)
      assert Schema.complexity(under) == 11 * 45 + 11
      assert {:ok, %Schema{}} = Schema.parse(under, @dialect)

      over = chain(46)
      assert Schema.complexity(over) == 11 * 46 + 11
      assert Schema.complexity(over) > Schema.ceiling()
      assert {:error, :schema_complexity_exceeded} = Schema.parse(over, @dialect)
    end
  end

  describe "spec-derived KATs (2020-12, read first-hand)" do
    test "core §7.6.1: null passes maxLength under type [string,null]" do
      # A reference example schema — a function returning a bounded
      # string or null.
      schema = ~s({"type":["string","null"],"maxLength":255})
      assert :ok = validate(schema, ~s(null))
      assert :ok = validate(schema, ~s("short"))

      assert {:error, :invalid_constraint} =
               validate(schema, {:string, String.duplicate("a", 256)})
    end

    test "core §8.2.4 (adapted): $defs positiveInteger via document-local $ref" do
      # An array-of-positive-integers example, with the dialect's
      # minimum replacing the out-of-subset exclusiveMinimum.
      schema = ~s({
        "type":"array",
        "items":{"$ref":"#/$defs/positiveInteger"},
        "$defs":{"positiveInteger":{"type":"integer","minimum":1}}
      })

      assert :ok = validate(schema, ~s([1,2,3]))
      assert {:error, :invalid_constraint} = validate(schema, ~s([1,0]))
      assert {:error, :invalid_constraint} = validate(schema, ~s([1,-5]))
    end

    test "core §12.4 (adapted): the polygon schema — three error positions, three classes" do
      # A polygon example minus $id/$schema. The dialect's three
      # errors (missing y, disallowed z, two-of-three) map: required →
      # cardinality, additionalProperties → cardinality, minItems →
      # cardinality; adapted instances trip type and constraint classes so
      # ALL THREE reason classes are exercised on this schema.
      schema = ~s({
        "$defs":{
          "point":{
            "type":"object",
            "properties":{"x":{"type":"number"},"y":{"type":"number"}},
            "additionalProperties":false,
            "required":["x","y"]
          }
        },
        "type":"array",
        "items":{"$ref":"#/$defs/point"},
        "minItems":3
      })

      assert :ok =
               validate(schema, ~s([{"x":2.5,"y":1.3},{"x":1,"y":2},{"x":3,"y":4}]))

      # spec error 1: second point missing "y" — cardinality
      assert {:error, :invalid_cardinality} =
               validate(schema, ~s([{"x":2.5,"y":1.3},{"x":1,"z":6.7},{"x":3,"y":4}]))

      # spec error 2 (folded into the same vector by the spec): disallowed
      # "z" — cardinality (closure)
      # spec error 3: only two points — cardinality
      assert {:error, :invalid_cardinality} =
               validate(schema, ~s([{"x":1,"y":2},{"x":3,"y":4}]))

      # adapted: type class — a point that is not an object
      assert {:error, :invalid_type} = validate(schema, ~s([1,2,3]))

      # adapted: constraint class — a coordinate out of a bound added to
      # the adapted schema's point coordinates
      bounded = ~s({
        "$defs":{"point":{
          "type":"object",
          "properties":{"x":{"type":"number","maximum":10},"y":{"type":"number"}},
          "additionalProperties":false,
          "required":["x","y"]}},
        "type":"array",
        "items":{"$ref":"#/$defs/point"},
        "minItems":3
      })

      assert {:error, :invalid_constraint} =
               validate(bounded, ~s([{"x":11,"y":1},{"x":1,"y":2},{"x":3,"y":4}]))
    end

    test "validation §6.1.1: 1.0 is an integer; 1.5 is not" do
      schema = ~s({"type":"integer"})
      assert :ok = validate(schema, ~s(1.0))
      assert {:error, :invalid_type} = validate(schema, ~s(1.5))
    end

    test "validation §6.2.2: maximum is inclusive" do
      assert :ok = validate(~s({"maximum":5}), ~s(5))
      assert {:error, :invalid_constraint} = validate(~s({"maximum":5}), ~s(5.0001))
    end

    test "validation §6.5.3: required demands every named member" do
      assert {:error, :invalid_cardinality} = validate(~s({"required":["a","b"]}), ~s({"a":1}))
      assert :ok = validate(~s({"required":["a","b"]}), ~s({"a":1,"b":2}))
    end
  end

  defp chain(levels) do
    leaf = {:object, [{"type", {:string, "string"}}]}

    Enum.reduce(0..(levels - 1), leaf, fn _i, inner ->
      {:object, [{"properties", {:object, [{"p", inner}]}}]}
    end)
  end
end
