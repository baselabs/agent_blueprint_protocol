defmodule AgentBlueprintProtocol.SchemaTest do
  @moduledoc """
  Unit matrix for the bounded schema dialect + instance validator.

  Every schema and instance enters through the REAL decoder (`Json.decode/1`)
  so the wire path is what's tested; hand-built tagged terms appear only
  where the decoder cannot produce the shape (malformed tagged values,
  duplicate members, non-finite floats, `/`-named `$defs` entries). Frozen
  semantics pin tests carry their spec section in a comment — they are
  contracts, not coverage.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Json, Schema}

  @dialect "https://json-schema.org/draft/2020-12/schema"

  test "equal?/2 is total on hand-built shapes (non-pair members are unequal, never a crash)" do
    refute Schema.equal?({:object, [1]}, {:object, [{"a", :null}]})
    refute Schema.equal?({:object, [{"a", :null}]}, {:object, [1]})
    refute Schema.equal?({:object, [{5, :null}]}, {:object, [{"a", :null}]})
    refute Schema.equal?({:object, [{"a", :null}]}, {:object, [{5, :null}]})
  end

  defp decode!(binary) do
    assert {:ok, value} = Json.decode(binary)
    value
  end

  defp schema!(binary), do: decode!(binary)

  defp validate(schema, instance) do
    schema = if is_binary(schema), do: decode!(schema), else: schema
    instance = if is_binary(instance), do: decode!(instance), else: instance
    Schema.validate_instance(schema, instance, @dialect)
  end

  # "e" + U+0301 combining acute: one grapheme, TWO codepoints, three bytes.
  @combining_json "\"" <> "e" <> <<0x0301::utf8>> <> "\""
  # U+1F600: one codepoint, one grapheme, TWO UTF-16 units in a TS peer.
  @astral_json "\"" <> <<0x1F600::utf8>> <> "\""
  @combining_value "e" <> <<0x0301::utf8>>
  @astral_value <<0x1F600::utf8>>

  describe "dialect parameter" do
    test "the exact 2020-12 dialect URI is accepted" do
      assert :ok = validate(~s({"type":"object"}), ~s({}))
    end

    test "any other dialect string denies :schema_dialect_unknown" do
      schema = schema!(~s({"type":"object"}))

      for bad <- [
            "https://json-schema.org/draft/2019-09/schema",
            "https://json-schema.org/draft/2020-12/vocab/validation",
            "https://example.com/v1",
            ""
          ] do
        assert {:error, :schema_dialect_unknown} =
                 Schema.validate_instance(schema, {:object, []}, bad),
               "expected #{inspect(bad)} to be unknown"
      end
    end

    test "parse enforces the same dialect gate" do
      assert {:error, :schema_dialect_unknown} =
               Schema.parse(schema!(~s({"type":"object"})), "other")

      assert {:ok, %Schema{}} = Schema.parse(schema!(~s({"type":"object"})), @dialect)
    end
  end

  describe "root shape" do
    test "a non-schema root denies :schema_invalid_shape" do
      assert {:error, :schema_invalid_shape} = Schema.parse({:string, "x"}, @dialect)
      assert {:error, :schema_invalid_shape} = Schema.parse({:integer, 5}, @dialect)
      assert {:error, :schema_invalid_shape} = Schema.parse(:null, @dialect)
      assert {:error, :schema_invalid_shape} = Schema.parse({:array, []}, @dialect)
    end

    test "boolean schemas are valid roots (core §4.3.2)" do
      assert {:ok, %Schema{}} = Schema.parse({:boolean, true}, @dialect)
      assert {:ok, %Schema{}} = Schema.parse({:boolean, false}, @dialect)
      assert :ok = validate({:boolean, true}, {:integer, 5})
      assert {:error, :invalid_type} = validate({:boolean, false}, {:integer, 5})
      assert {:error, :invalid_type} = validate({:boolean, false}, :null)
    end
  end

  describe "allowlist — every rejected keyword denies :schema_keyword_not_allowed" do
    # The full 2020-12 keyword universe outside the frozen 16 + document-local $ref.
    @rejected ~w(
      pattern format patternProperties if then else allOf anyOf not prefixItems
      contains minContains maxContains uniqueItems multipleOf exclusiveMinimum
      exclusiveMaximum minProperties maxProperties dependentRequired
      dependentSchemas propertyNames unevaluatedItems unevaluatedProperties
      $anchor $dynamicRef $dynamicAnchor $id $schema $vocabulary $comment
      title description default examples deprecated readOnly writeOnly
      contentEncoding contentMediaType contentSchema definitions
    )

    test "each rejected keyword denies, in schema position" do
      for keyword <- @rejected do
        schema = {:object, [{keyword, {:string, "x"}}]}

        assert {:error, :schema_keyword_not_allowed} = Schema.parse(schema, @dialect),
               "expected #{keyword} to be rejected"
      end
    end

    test "ticket acceptance trio: pattern, remote $ref, allOf" do
      assert {:error, :schema_keyword_not_allowed} =
               Schema.parse(schema!(~s({"pattern":"^a"})), @dialect)

      assert {:error, :schema_keyword_not_allowed} =
               Schema.parse(schema!(~s({"$ref":"https://example.com/schema.json"})), @dialect)

      assert {:error, :schema_keyword_not_allowed} =
               Schema.parse(schema!(~s({"allOf":[{"type":"string"}]})), @dialect)
    end

    test "rejected keywords deny at ANY schema depth, not just the root" do
      assert {:error, :schema_keyword_not_allowed} =
               Schema.parse(
                 schema!(~s({"properties":{"a":{"items":{"format":"uri"}}}})),
                 @dialect
               )
    end

    test "unknown arbitrary keywords deny too (closed world)" do
      assert {:error, :schema_keyword_not_allowed} =
               Schema.parse(schema!(~s({"zzz_custom":1})), @dialect)
    end
  end

  describe "positional keyword recognition (design decision 1)" do
    test "enum values carrying rejected-keyword members are DATA, not keywords" do
      schema = schema!(~s({"enum":[{"pattern":"x","allOf":true}]}))
      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)
      assert :ok = validate(schema, ~s({"pattern":"x","allOf":true}))
      assert {:error, :invalid_constraint} = validate(schema, ~s({"pattern":"y"}))
    end

    test "const values are DATA too" do
      schema = schema!(~s({"const":{"$id":"nope","if":1}}))
      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)
      assert :ok = validate(schema, ~s({"$id":"nope","if":1}))
    end

    test "properties member NAMES are data, never keywords (adversarial finding 13)" do
      schema = schema!(~s({"properties":{"pattern":{"type":"string"},"allOf":{"type":"number"}}}))
      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)
      assert :ok = validate(schema, ~s({"pattern":"s","allOf":1}))
    end

    test "$defs member names are data" do
      schema = schema!(~s({"$defs":{"format":{"type":"string"}},"$ref":"#/$defs/format"}))
      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)
      assert :ok = validate(schema, ~s("ok"))
    end

    test "a rejected keyword nested inside enum data at depth parses green" do
      schema = schema!(~s({"enum":[{"deep":[{"if":true}]}]}))
      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)
    end
  end

  describe "type (validation §6.1.1)" do
    test "each single type name matches its tag and nothing else" do
      matrix = [
        {"null", :null, :ok},
        {"null", {:boolean, true}, {:error, :invalid_type}},
        {"boolean", {:boolean, false}, :ok},
        {"boolean", {:integer, 1}, {:error, :invalid_type}},
        {"object", {:object, []}, :ok},
        {"object", {:array, []}, {:error, :invalid_type}},
        {"array", {:array, []}, :ok},
        {"array", {:object, []}, {:error, :invalid_type}},
        {"string", {:string, "s"}, :ok},
        {"string", {:integer, 1}, {:error, :invalid_type}},
        {"number", {:integer, 1}, :ok},
        {"number", {:float, 1.5}, :ok},
        {"number", {:string, "1"}, {:error, :invalid_type}}
      ]

      for {name, instance, expected} <- matrix do
        schema = schema!(~s({"type":"#{name}"}))
        assert ^expected = validate(schema, instance), "type #{name}"
      end
    end

    test "type arrays match any member" do
      schema = schema!(~s({"type":["string","null"]}))
      assert :ok = validate(schema, ~s("s"))
      assert :ok = validate(schema, ~s(null))
      assert {:error, :invalid_type} = validate(schema, ~s(5))
    end

    test "FROZEN: integer matches zero-fraction numbers tag-blind (validation §6.1.1; design decision 4)" do
      schema = schema!(~s({"type":"integer"}))
      assert :ok = validate(schema, ~s(1))
      assert :ok = validate(schema, ~s(1.0))
      assert :ok = validate(schema, ~s(1e2))
      assert {:error, :invalid_type} = validate(schema, ~s(1.5))
      # window-admitted doubles (integer-window decode) pass by spec;
      # the artifact layer owns the core-field deny.
      window_double = 9_007_199_254_740_992.0 * 10_000
      assert {:ok, {:float, ^window_double}} = Json.decode("90071992547409920000")
      assert :ok = validate(schema, ~s(90071992547409920000))
      # the pure-digit 2^53 lexeme itself is above the I-JSON window and
      # admits as the window double — also an "integer" by spec.
      assert {:ok, {:float, 9_007_199_254_740_992.0}} = Json.decode("9007199254740992")
      assert :ok = validate(schema, ~s(9007199254740992))
    end

    test "meta-schema floors: empty type array, duplicates, unknown names, non-strings deny" do
      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"type":[]})), @dialect)

      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"type":["string","string"]})), @dialect)

      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"type":"strang"})), @dialect)

      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"type":[1]})), @dialect)
    end
  end

  describe "enum / const (validation §6.1.2/6.1.3, core §4.2.2)" do
    test "enum membership by instance equality" do
      schema = schema!(~s({"enum":[1,"two",null,false,{"a":1},[1,2]]}))
      assert :ok = validate(schema, ~s(1))
      assert :ok = validate(schema, ~s("two"))
      assert :ok = validate(schema, ~s(null))
      assert :ok = validate(schema, ~s(false))
      assert :ok = validate(schema, ~s({"a":1}))
      assert :ok = validate(schema, ~s([1,2]))
      assert {:error, :invalid_constraint} = validate(schema, ~s(2))
      assert {:error, :invalid_constraint} = validate(schema, ~s([2,1]))
    end

    test "FROZEN: numbers compare by mathematical value across tags" do
      schema = schema!(~s({"const":1}))
      assert :ok = validate(schema, ~s(1))
      assert :ok = validate(schema, ~s(1.0))
      schema20 = schema!(~s({"const":1.0}))
      assert :ok = validate(schema20, ~s(1))
      assert {:error, :invalid_constraint} = validate(schema, ~s(1.5))
    end

    test "FROZEN: object equality is order-blind with equal member counts" do
      schema = schema!(~s({"const":{"a":1,"b":2}}))
      assert :ok = validate(schema, ~s({"b":2,"a":1}))
      assert {:error, :invalid_constraint} = validate(schema, ~s({"a":1}))
      assert {:error, :invalid_constraint} = validate(schema, ~s({"a":1,"b":2,"c":3}))
    end

    test "nested equality is recursive (arrays order-sensitive, core §4.2.2)" do
      schema = schema!(~s({"const":{"x":[1,{"y":null}]}}))
      assert :ok = validate(schema, ~s({"x":[1,{"y":null}]}))
      assert {:error, :invalid_constraint} = validate(schema, ~s({"x":[{"y":null},1]}))
    end

    test "empty enum parses and matches nothing (live meta-schema has no minItems)" do
      schema = schema!(~s({"enum":[]}))
      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)
      assert {:error, :invalid_constraint} = validate(schema, ~s(1))
      assert {:error, :invalid_constraint} = validate(schema, ~s(null))
    end

    test "enum applies to every instance type (no target-type auto-pass)" do
      schema = schema!(~s({"enum":["a"]}))
      assert {:error, :invalid_constraint} = validate(schema, ~s({"a":1}))
      assert {:error, :invalid_constraint} = validate(schema, ~s(null))
    end

    test "enum value syntax violations deny :schema_keyword_value_invalid" do
      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"enum":5})), @dialect)

      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"enum":"a"})), @dialect)
    end

    test "const accepts any single value including null" do
      schema = schema!(~s({"const":null}))
      assert :ok = validate(schema, ~s(null))
      assert {:error, :invalid_constraint} = validate(schema, ~s(1))
    end
  end

  describe "numeric bounds (validation §6.2)" do
    test "minimum and maximum are inclusive" do
      schema = schema!(~s({"minimum":2,"maximum":5}))
      assert {:error, :invalid_constraint} = validate(schema, ~s(1))
      assert :ok = validate(schema, ~s(2))
      assert :ok = validate(schema, ~s(5))
      assert {:error, :invalid_constraint} = validate(schema, ~s(6))
    end

    test "FROZEN: cross-tag comparisons are exact (probe-proven semantics)" do
      # Every decoder-reachable integer is ≤ 2^53−1 (exactly double-
      # representable), so wire forms alone cannot discriminate exact vs
      # lossy int/float comparison. The discriminator is a hand-built
      # above-window integer: 2^53+1 vs the 2^53 double — exact comparison
      # says greater (deny under this maximum); a lossy int→double
      # conversion would equate them (pass).
      schema = schema!(~s({"maximum":9007199254740992.0}))

      assert {:error, :invalid_constraint} =
               Schema.validate_instance(schema, {:integer, 9_007_199_254_740_993}, @dialect)

      assert :ok = Schema.validate_instance(schema, {:integer, 9_007_199_254_740_991}, @dialect)
      assert :ok = validate(schema, ~s(9007199254740991))

      schema_min = schema!(~s({"minimum":9007199254740992.0}))
      assert :ok = validate(schema_min, ~s(9007199254740992.0))

      assert {:error, :invalid_constraint} =
               Schema.validate_instance(schema_min, {:integer, 9_007_199_254_740_991}, @dialect)
    end

    test "bounds auto-pass non-number instances (core §7.6.1)" do
      schema = schema!(~s({"minimum":10}))
      assert :ok = validate(schema, ~s("5"))
      assert :ok = validate(schema, ~s([5]))
      assert :ok = validate(schema, ~s(null))
    end

    test "bound value syntax violations deny" do
      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"minimum":"2"})), @dialect)

      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"maximum":null})), @dialect)
    end
  end

  describe "string lengths (validation §6.3.1/6.3.2 — RFC 8259 characters = codepoints)" do
    test "FROZEN: lengths count codepoints, not graphemes, not UTF-16 units" do
      schema = schema!(~s({"maxLength":1}))

      # combining sequence: 2 codepoints (1 grapheme, 3 bytes) — over budget
      assert {:error, :invalid_constraint} =
               Schema.validate_instance(schema, decode!(@combining_json), @dialect)

      # astral plane: 1 codepoint (2 UTF-16 units in a TS peer) — within budget
      assert :ok = Schema.validate_instance(schema, decode!(@astral_json), @dialect)

      assert String.length(@combining_value) == 1 and
               length(String.codepoints(@combining_value)) == 2

      assert length(String.codepoints(@astral_value)) == 1
    end

    test "exact codepoint boundary is green, plus one is red" do
      schema = schema!(~s({"minLength":2,"maxLength":2}))
      assert :ok = Schema.validate_instance(schema, decode!(@combining_json), @dialect)
      assert {:error, :invalid_constraint} = validate(schema, ~s("a"))
      assert {:error, :invalid_constraint} = validate(schema, ~s("abc"))
    end

    test "lengths auto-pass non-string instances (the dialect's own example)" do
      # core §7.6.1: maxLength passes a null (and any non-string) instance.
      schema = schema!(~s({"type":["string","null"],"maxLength":1}))
      assert :ok = validate(schema, ~s(null))

      bare = schema!(~s({"maxLength":1}))
      assert :ok = validate(bare, ~s(100000))
    end

    test "negative or fractional lengths deny; zero-fraction floats admit (meta-schema integer typing)" do
      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"maxLength":-1})), @dialect)

      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"minLength":1.5})), @dialect)

      # 2.0 is an "integer" per validation §6.1.1 — the meta-schema types
      # these keywords "integer", so the zero-fraction float form admits.
      assert {:ok, %Schema{}} = Schema.parse(schema!(~s({"minLength":2.0})), @dialect)
    end
  end

  describe "array cardinality (validation §6.4)" do
    test "minItems/maxItems bounds with exact boundaries" do
      schema = schema!(~s({"minItems":2,"maxItems":3}))
      assert {:error, :invalid_cardinality} = validate(schema, ~s([1]))
      assert :ok = validate(schema, ~s([1,2]))
      assert :ok = validate(schema, ~s([1,2,3]))
      assert {:error, :invalid_cardinality} = validate(schema, ~s([1,2,3,4]))
    end

    test "cardinalities auto-pass non-array instances" do
      schema = schema!(~s({"minItems":5}))
      assert :ok = validate(schema, ~s({"a":1}))
      assert :ok = validate(schema, ~s("x"))
    end
  end

  describe "objects: required / properties / additionalProperties (validation §6.5, core §10.3.2)" do
    test "required: every name must be present; empty array is valid-and-vacuous" do
      schema = schema!(~s({"required":["a","b"]}))
      assert :ok = validate(schema, ~s({"a":1,"b":2,"c":3}))
      assert {:error, :invalid_cardinality} = validate(schema, ~s({"a":1}))

      empty = schema!(~s({"required":[]}))
      assert {:ok, %Schema{}} = Schema.parse(empty, @dialect)
      assert :ok = validate(empty, ~s({}))
    end

    test "required auto-passes non-object instances" do
      schema = schema!(~s({"required":["a"]}))
      assert :ok = validate(schema, ~s([1,2]))
      assert :ok = validate(schema, ~s("a"))
    end

    test "required value syntax: duplicates and non-strings deny" do
      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"required":["a","a"]})), @dialect)

      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"required":[1]})), @dialect)

      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"required":"a"})), @dialect)
    end

    test "properties validates only present members" do
      schema = schema!(~s({"properties":{"a":{"type":"string"}}}))
      assert :ok = validate(schema, ~s({}))
      assert :ok = validate(schema, ~s({"a":"s"}))
      assert {:error, :invalid_type} = validate(schema, ~s({"a":1}))
      assert :ok = validate(schema, ~s({"b":1}))
    end

    test "child reasons propagate unchanged (design decision 9)" do
      schema = schema!(~s({"properties":{"a":{"type":"string"},"b":{"minimum":4}}}))

      assert {:error, :invalid_type} = validate(schema, ~s({"a":1,"b":5}))
      assert {:error, :invalid_constraint} = validate(schema, ~s({"a":"s","b":1}))
    end

    test "additionalProperties: false closes the struct against adjacent properties only" do
      schema = schema!(~s({"properties":{"a":{}},"additionalProperties":false}))
      assert :ok = validate(schema, ~s({"a":1}))
      assert {:error, :invalid_cardinality} = validate(schema, ~s({"a":1,"z":2}))
    end

    test "FROZEN adjacency trap: oneOf-branch properties do NOT feed additionalProperties (core §10.3.2.3)" do
      schema =
        schema!(
          ~s({"oneOf":[{"properties":{"a":{"type":"string"}}}],"additionalProperties":false})
        )

      # The "a" member is matched only inside the oneOf branch; adjacent
      # properties is absent, so "a" IS additional and false denies it. The
      # EMPTY object carries no additional member and stays valid.
      assert {:error, :invalid_cardinality} = validate(schema, ~s({"a":"s"}))
      assert :ok = validate(schema, ~s({}))
    end

    test "additionalProperties as a schema validates the complement" do
      schema = schema!(~s({"properties":{"a":{}},"additionalProperties":{"type":"number"}}))
      assert :ok = validate(schema, ~s({"a":"s","z":1}))
      assert {:error, :invalid_type} = validate(schema, ~s({"a":"s","z":"x"}))
    end

    test "additionalProperties boolean true is the empty-schema pass" do
      schema = schema!(~s({"additionalProperties":true}))
      assert :ok = validate(schema, ~s({"anything":"goes"}))
    end
  end

  describe "items (core §10.3.1.2 — single-schema form, applies to all elements)" do
    test "items applies its subschema to every element" do
      schema = schema!(~s({"items":{"type":"string"}}))
      assert :ok = validate(schema, ~s([]))
      assert :ok = validate(schema, ~s(["a","b"]))
      assert {:error, :invalid_type} = validate(schema, ~s(["a",1]))
    end

    test "items auto-passes non-array instances; items:false propagates the child reason" do
      schema = schema!(~s({"items":false}))
      assert :ok = validate(schema, ~s({"a":[1]}))
      # child-descent failures propagate unchanged (design decision 9):
      # the false boolean schema is a type-family always-fail
      assert {:error, :invalid_type} = validate(schema, ~s([1]))
    end

    test "items value must be a schema (object or boolean)" do
      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"items":"string"})), @dialect)

      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"items":[]})), @dialect)
    end
  end

  describe "oneOf (core §10.2.1.3 — exactly one)" do
    test "exactly one branch passes" do
      schema = schema!(~s({"oneOf":[{"type":"string"},{"type":"number"}]}))
      assert :ok = validate(schema, ~s("s"))
      assert :ok = validate(schema, ~s(1))
      assert {:error, :invalid_cardinality} = validate(schema, ~s(null))
    end

    test "two branches passing denies (exactly-one, not at-least-one)" do
      schema = schema!(~s({"oneOf":[{"type":"string"},{"minLength":1}]}))
      assert {:error, :invalid_cardinality} = validate(schema, ~s("both"))
    end

    test "oneOf must be a non-empty array of schemas" do
      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"oneOf":[]})), @dialect)

      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"oneOf":{"type":"string"}})), @dialect)

      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"oneOf":[5]})), @dialect)
    end
  end

  describe "multi-failure reason precedence (design decision 9 — fixed canonical order)" do
    test "type outranks constraint when both fail" do
      schema = schema!(~s({"type":["string","number"],"minLength":5,"minimum":100}))
      assert {:error, :invalid_type} = validate(schema, ~s(null))
    end

    test "constraint and cardinality auto-pass rules compose (each class reachable)" do
      nested = schema!(~s({"properties":{"a":{"minimum":10,"minItems":5}}}))
      assert {:error, :invalid_constraint} = validate(nested, ~s({"a":1}))
      assert {:error, :invalid_cardinality} = validate(nested, ~s({"a":[1]}))
    end

    test "precedence is independent of schema member order" do
      forward = schema!(~s({"type":"string","minimum":10}))
      reversed = schema!(~s({"minimum":10,"type":"string"}))

      assert validate(forward, ~s(null)) == validate(reversed, ~s(null))
      assert {:error, :invalid_type} = validate(forward, ~s(null))
    end
  end

  describe "$ref (core §8.2.3.1, RFC 6901)" do
    test "document-local pointer into $defs applies the target" do
      schema =
        schema!(~s({
          "type":"array",
          "items":{"$ref":"#/$defs/positive"},
          "$defs":{"positive":{"type":"integer","minimum":1}}
        }))

      assert :ok = validate(schema, ~s([1,2]))
      assert {:error, :invalid_constraint} = validate(schema, ~s([1,0]))
    end

    test "siblings apply alongside $ref (2020-12, not draft-07)" do
      schema =
        {:object,
         [
           {"$defs", {:object, [{"num", {:object, [{"type", {:string, "number"}}]}}]}},
           {"$ref", {:string, "#/$defs/num"}},
           {"minimum", {:integer, 3}}
         ]}

      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)
      # $ref is first in canonical order: a non-number reports the ref'd type.
      assert {:error, :invalid_type} = validate(schema, ~s("s"))
      # the sibling still applies: 2 is a number below the sibling minimum.
      assert {:error, :invalid_constraint} = validate(schema, ~s(2))
      assert :ok = validate(schema, ~s(3))
    end

    test "root pointer # from a dead $defs entry parses GREEN (application-edge rule)" do
      schema = schema!(~s({"$defs":{"dead":{"$ref":"#"}},"type":"object"}))
      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)
      assert :ok = validate(schema, ~s({}))
    end

    test "self-referential root denies :schema_ref_cycle" do
      assert {:error, :schema_ref_cycle} = Schema.parse(schema!(~s({"$ref":"#"})), @dialect)
    end

    test "application-reachable mutual ref cycle denies" do
      schema =
        schema!(~s({
          "$defs":{"a":{"$ref":"#/$defs/b"},"b":{"$ref":"#/$defs/a"}},
          "$ref":"#/$defs/a"
        }))

      assert {:error, :schema_ref_cycle} = Schema.parse(schema, @dialect)
    end

    test "deep alternation chain over distinct acyclic terms parses" do
      # three levels of oneOf (duplicated branch terms materialize the
      # document exponentially — the meter charges the duplication; the
      # shared-subtree DAG case is the ref-DAG tripwire below)
      levels =
        Enum.reduce(1..3, {:object, [{"type", {:string, "integer"}}]}, fn _i, acc ->
          {:object, [{"oneOf", {:array, [acc, acc]}}]}
        end)

      schema =
        {:object, [{"$defs", {:object, [{"a1", levels}]}}, {"$ref", {:string, "#/$defs/a1"}}]}

      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)
    end

    test "RFC 6901 unescape: ~1 before ~0, split before unescape (adversarial finding 8)" do
      schema =
        {:object,
         [
           {"$defs", {:object, [{"a/b", {:object, [{"type", {:string, "string"}}]}}]}},
           {"$ref", {:string, "#/$defs/a~1b"}}
         ]}

      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)
      assert :ok = validate(schema, {:string, "s"})
    end

    test "the token ~01 decodes to the member named ~1" do
      schema =
        {:object,
         [
           {"$defs", {:object, [{"~1", {:object, [{"type", {:string, "string"}}]}}]}},
           {"$ref", {:string, "#/$defs/~01"}}
         ]}

      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)
    end

    test "empty pointer tokens address the empty-named member" do
      schema =
        {:object,
         [
           {"$defs", {:object, [{"", {:object, [{"type", {:string, "string"}}]}}]}},
           {"$ref", {:string, "#/$defs/"}}
         ]}

      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)
    end

    test "non-document-local ref string forms deny :schema_keyword_not_allowed" do
      for ref <- ["https://example.com/s.json", "other.json", "#anchor", "a/b", ""] do
        assert {:error, :schema_keyword_not_allowed} =
                 Schema.parse({:object, [{"$ref", {:string, ref}}]}, @dialect),
               "expected #{inspect(ref)} to be not-allowed"
      end
    end

    test "pointer tokens may carry spaces (RFC 6901 allows them)" do
      schema =
        {:object,
         [
           {"$defs", {:object, [{"a b", {:object, [{"type", {:string, "string"}}]}}]}},
           {"$ref", {:string, "#/$defs/a b"}}
         ]}

      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)
      assert :ok = validate(schema, {:string, "s"})
    end

    test "non-string $ref value denies :schema_keyword_value_invalid (adversarial finding 6)" do
      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse({:object, [{"$ref", {:integer, 5}}]}, @dialect)
    end

    test "dangling pointer denies :schema_ref_unresolvable" do
      assert {:error, :schema_ref_unresolvable} =
               Schema.parse(schema!(~s({"$ref":"#/$defs/missing"})), @dialect)

      assert {:error, :schema_ref_unresolvable} =
               Schema.parse(schema!(~s({"$ref":"#/nope"})), @dialect)
    end

    test "pointer landing on a non-schema value denies :schema_ref_unresolvable" do
      assert {:error, :schema_ref_unresolvable} =
               Schema.parse(schema!(~s({"type":"object","$ref":"#/type"})), @dialect)
    end

    test "pointer into enum DATA denies :schema_ref_unresolvable even when object-shaped (adversarial finding 7)" do
      schema = schema!(~s({"enum":[{"type":"object"}],"$ref":"#/enum/0"}))
      assert {:error, :schema_ref_unresolvable} = Schema.parse(schema, @dialect)
    end

    test "$defs entries are schema-validated even when unreferenced" do
      assert {:error, :schema_keyword_not_allowed} =
               Schema.parse(schema!(~s({"$defs":{"dead":{"pattern":"x"}}})), @dialect)
    end

    test "$defs value must be an object of schemas" do
      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"$defs":[]})), @dialect)

      assert {:error, :schema_keyword_value_invalid} =
               Schema.parse(schema!(~s({"$defs":{"a":5}})), @dialect)
    end
  end

  describe "missing keywords never fail (core §7.3)" do
    test "the empty schema passes everything" do
      schema = schema!(~s({}))
      assert :ok = validate(schema, ~s("anything"))
      assert :ok = validate(schema, ~s([1,{"a":null}]))
      assert :ok = validate(schema, ~s(null))
    end
  end

  describe "malformed tagged values never raise (design decision 9 — totality)" do
    @malformed [
      {:array, [5]},
      {:object, [{"k", "raw"}]},
      {:integer, 1.5},
      {:boolean, 5},
      {:float, :nan},
      {:string, :not_a_string},
      {:object, [{"k", {:object, [{"dup", 1}]}}]},
      :wrong_atom,
      {5, 5},
      {:array, [:head | "tail"]}
    ]

    test "as the INSTANCE: deny :invalid_type, never raise" do
      schema = schema!(~s({}))

      for value <- @malformed do
        assert {:error, :invalid_type} = Schema.validate_instance(schema, value, @dialect),
               "expected malformed #{inspect(value)} to deny, not raise"
      end
    end

    test "as the SCHEMA: deny, never raise" do
      for value <- @malformed do
        assert {:error, reason} = Schema.validate_instance(value, {:integer, 1}, @dialect)
        assert reason in [:schema_invalid_shape, :schema_keyword_value_invalid]
      end
    end

    test "duplicate members in a hand-built instance object deny :invalid_type" do
      schema = schema!(~s({"type":"object"}))
      dup = {:object, [{"a", {:integer, 1}}, {"a", {:integer, 2}}]}
      assert {:error, :invalid_type} = Schema.validate_instance(schema, dup, @dialect)
    end

    test "duplicate members in a hand-built schema object deny" do
      dup = {:object, [{"type", {:string, "object"}}, {"type", {:string, "array"}}]}
      assert {:error, :schema_keyword_value_invalid} = Schema.parse(dup, @dialect)
    end
  end

  describe "defensive surfaces + meter totality (coverage completion)" do
    test "complexity/1 meters scalar and malformed roots without validation" do
      assert Schema.complexity({:string, "x"}) == 5
      assert Schema.complexity({:integer, 5}) == 5
      # tagged-but-wrong-shape values in meter mode: nodes only, never a crash
      assert Schema.complexity({:object, [{"properties", {:object, [{"a", {:integer, 5}}]}}]}) > 0

      assert Schema.complexity({:object, [{"oneOf", {:array, [{:integer, 5}]}}]}) > 0

      assert Schema.complexity({:object, [{"items", {:string, "not-a-schema"}}]}) > 0
    end

    test "complexity/1 is total: malformed tagged shapes meter 0, never raise (security finding 1)" do
      for value <- [
            {:object, :notalist},
            {:object, [{"enum", {:array, :notalist}}]},
            {:object, [{"required", {:array, [1 | 2]}}]},
            {:array, :notalist},
            {:string, <<0xFF>>}
          ] do
        assert Schema.complexity(value) == 0, "expected #{inspect(value)} to meter 0"
      end
    end

    test "a forged Schema struct is re-parsed, never trusted (security finding 2)" do
      d = @dialect

      forged_ref =
        struct!(Schema,
          dialect: d,
          root: {:object, [{"$ref", {:string, "#/nope"}}]},
          pointers: %{},
          complexity: 1
        )

      assert {:error, :schema_ref_unresolvable} =
               Schema.validate_instance(forged_ref, {:integer, 1}, d)

      forged_null = struct!(Schema, dialect: d, root: :null, pointers: %{}, complexity: 1)

      assert {:error, :schema_invalid_shape} =
               Schema.validate_instance(forged_null, {:integer, 1}, d)
    end

    test "a '~' not followed by 0/1 is not an RFC 6901 escape: not-allowed" do
      assert {:error, :schema_keyword_not_allowed} =
               Schema.parse({:object, [{"$ref", {:string, "#/a~2b"}}]}, @dialect)
    end

    test "a $ref may target a boolean schema" do
      schema =
        {:object,
         [
           {"$defs", {:object, [{"flag", {:boolean, true}}]}},
           {"$ref", {:string, "#/$defs/flag"}}
         ]}

      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)
      assert :ok = validate(schema, ~s(1))

      false_schema =
        {:object,
         [
           {"$defs", {:object, [{"flag", {:boolean, false}}]}},
           {"$ref", {:string, "#/$defs/flag"}}
         ]}

      assert {:ok, %Schema{}} = Schema.parse(false_schema, @dialect)
      assert {:error, :invalid_type} = validate(false_schema, ~s(1))
    end

    test "a struct carrying a foreign dialect denies :schema_dialect_unknown" do
      foreign =
        struct!(Schema, dialect: "other", root: {:object, []}, pointers: %{}, complexity: 5)

      assert {:error, :schema_dialect_unknown} =
               Schema.validate_instance(foreign, {:object, []}, @dialect)
    end
  end

  describe "auto-pass catch-alls and equality corners (coverage completion)" do
    test "every type-targeted keyword auto-passes its non-target types, both bound directions" do
      schema =
        schema!(~s({
          "type":"object",
          "properties":{"n":{"type":"number"}},
          "required":["n"],
          "items":{"type":"string"},
          "additionalProperties":true
        }))

      # an object instance: maximum/maxLength/maxItems auto-pass
      maxed = schema!(~s({"maximum":10,"maxLength":3,"maxItems":2}))

      assert :ok =
               Schema.validate_instance(
                 maxed,
                 {:object, [{"a", {:integer, 999_999}}]},
                 @dialect
               )

      # a string instance: minItems/required/properties auto-pass (minimum too)
      mined =
        schema!(
          ~s({"minimum":10,"minItems":5,"required":["x"],"properties":{"x":{"type":"string"}}})
        )

      assert :ok = Schema.validate_instance(mined, {:string, "s"}, @dialect)

      # an array instance: minimum/maxLength/required/properties/additionalProperties auto-pass
      arr =
        schema!(
          ~s({"minimum":10,"maxLength":1,"required":["x"],"properties":{"x":{"type":"string"}},"additionalProperties":false})
        )

      assert :ok = Schema.validate_instance(arr, {:array, []}, @dialect)

      assert {:error, :invalid_cardinality} = validate(~s({"maxItems":1}), ~s([1,2]))

      # a number instance: minLength/maxItems/required/properties auto-pass
      num =
        schema!(
          ~s({"minLength":5,"maxItems":1,"required":["x"],"properties":{"x":{"type":"string"}}})
        )

      assert :ok = Schema.validate_instance(num, {:integer, 1}, @dialect)

      assert :ok = validate(schema, ~s({"n":1}))
    end

    test "an {:array, non-list} tagged shape reaches the improper-tail catch-all" do
      assert {:error, :invalid_type} =
               Schema.validate_instance(schema!(~s({"type":"array"})), {:array, 5}, @dialect)
    end

    test "float-valued bounds evaluate via the zero-fraction extraction" do
      schema = schema!(~s({"minLength":2.0,"maxItems":2.0}))
      assert :ok = Schema.validate_instance(schema, {:string, "abc"}, @dialect)

      assert {:error, :invalid_constraint} =
               Schema.validate_instance(schema, {:string, "a"}, @dialect)

      assert {:error, :invalid_cardinality} =
               Schema.validate_instance(
                 schema,
                 {:array, [{:integer, 1}, {:integer, 2}, {:integer, 3}]},
                 @dialect
               )
    end

    test "equality corners: float/float, array length mismatch, disjoint same-size objects" do
      assert :ok = validate(~s({"const":1.5}), ~s(1.5))
      assert {:error, :invalid_constraint} = validate(~s({"const":[1]}), ~s([1,2]))
      assert {:error, :invalid_constraint} = validate(~s({"const":{"a":1}}), ~s({"b":1}))
      assert {:error, :invalid_constraint} = validate(~s({"const":1.5}), ~s(2.5))
    end
  end

  describe "parsed-struct input (Bounds.coerce-style polymorphism)" do
    test "a parsed Schema struct validates identically to the raw path" do
      {:ok, parsed} = Schema.parse(schema!(~s({"type":"string"})), @dialect)
      assert :ok = Schema.validate_instance(parsed, {:string, "s"}, @dialect)
      assert {:error, :invalid_type} = Schema.validate_instance(parsed, {:integer, 1}, @dialect)
    end

    test "struct carries complexity and the dialect" do
      {:ok, parsed} = Schema.parse(schema!(~s({"type":"object"})), @dialect)
      assert parsed.dialect == @dialect
      assert is_integer(parsed.complexity) and parsed.complexity >= 1
    end
  end

  describe "complexity metering (design decision 8)" do
    # Metric: nodes + keywords + Σ(oneOf branch counts) + 4 × depth, over the
    # decoded schema document. Independent arithmetic for the padding shapes:
    #
    #   {}                          → nodes 1, keywords 0, depth 1      = 5
    #   + one  {"p":{"type":"str"}} → +2 nodes, +2 keywords, depth 3    = +4
    #   + one  {"const":[5]}        → +2 nodes, +1 keyword              = +3
    #
    # So with a p-members and c const-members (a ≥ 1 so depth is 3):
    #   total = (1 + 2a + 2c) + (2a + c) + 12 = 13 + 4a + 3c
    test "complexity/1 meters the documented shapes exactly" do
      assert Schema.complexity({:boolean, true}) == 5
      assert Schema.complexity({:object, []}) == 5

      assert Schema.complexity({:object, [{"type", {:string, "object"}}]}) == 11
    end

    test "enum data nodes meter as nodes, not keywords" do
      with_enum = {:object, [{"enum", {:array, [{:object, [{"pattern", {:string, "x"}}]}]}}]}
      # nodes: root + enum array + inner object + "x" string = 4
      # keywords: 1 (enum; "pattern" inside data is not a keyword)
      # depth 4 → 16. Total 4 + 1 + 16 = 21.
      assert Schema.complexity(with_enum) == 21
    end

    test "exact ceiling 512 parses green; plus one denies :schema_complexity_exceeded" do
      # Valid-keyword chain (only allowlisted members): a nested properties
      # chain of L levels (the root is one of them), m of which also carry
      # {"const":5}, innermost leaf {"type":"string"}. Empirically confirmed
      # metric: total = 11L + 2m + 11
      #   nodes    = 2L (level objs incl. root + name maps) + m + 2 (leaf obj, leaf string)
      #   keywords = L (properties) + m (const) + 1 (type)
      #   depth    = 2L + 2
      green = complexity_chain(45, 3)
      assert 11 * 45 + 2 * 3 + 11 == 512
      assert Schema.complexity(green) == 512
      assert {:ok, %Schema{complexity: 512}} = Schema.parse(green, @dialect)

      over = complexity_chain(44, 9)
      assert 11 * 44 + 2 * 9 + 11 == 513
      assert Schema.complexity(over) == 513
      assert {:error, :schema_complexity_exceeded} = Schema.parse(over, @dialect)
    end

    test "nested oneOf meters the materialized document (duplication costs)" do
      # Building oneOf[x, x] materializes x twice, so the document — and its
      # metric — grow with the duplication. Five levels stay under ceiling.
      leaf = {:object, [{"type", {:string, "integer"}}]}

      value =
        Enum.reduce(1..5, leaf, fn _i, acc ->
          {:object, [{"oneOf", {:array, [acc, acc]}}]}
        end)

      metric = Schema.complexity(value)
      assert metric < 512
      assert {:ok, %Schema{}} = Schema.parse(value, @dialect)
    end

    @tag timeout: 2_000
    test "ref-DAG blowup (design adversarial finding 1): tiny metric, exponential paths, memoized evaluation completes" do
      # 40 levels of a_i = oneOf[$ref a(i+1), $ref a(i+1)], a_40 = integer:
      # acyclic, ~468 complexity, 2^40 evaluation paths at one location —
      # without (node, location) memoization this cannot finish. The timeout
      # tag is the tripwire: removing the memo table must RED here.
      levels = 40

      defs =
        for i <- 1..(levels - 1), into: %{} do
          next = "#/$defs/a#{i + 1}"
          {"a#{i}", ~s({"oneOf":[{"$ref":"#{next}"},{"$ref":"#{next}"}]})}
        end

      defs = Map.put(defs, "a#{levels}", ~s({"type":"integer"}))

      def_members =
        defs
        |> Enum.sort_by(fn {name, _json} -> name end)
        |> Enum.map(fn {name, json} -> {name, decode!(json)} end)

      schema = {:object, [{"$defs", {:object, def_members}}, {"$ref", {:string, "#/$defs/a1"}}]}

      assert Schema.complexity(schema) < 512
      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)

      # both branches reference the same target, so an integer passes TWO
      # branches — exactly-one denies. The assertion that matters is that
      # both evaluations COMPLETE (memoized) inside the timeout budget.
      assert {:error, :invalid_cardinality} = validate(schema, ~s(7))
      assert {:error, :invalid_cardinality} = validate(schema, ~s("no"))
    end

    @tag timeout: 2_000
    test "distinct-branch ref-DAG: error-path memo must survive the unwind" do
      # Levels N_k = oneOf[{$ref:N(k+1),type:object}, {$ref:N(k+1),type:array}]
      # with a failing leaf — the two branches per level are STRUCTURALLY
      # DISTINCT, so per-term memoization collapses the fan-out only if the
      # memo gained while evaluating branch one's subtree SURVIVES branch
      # one's error return. The original implementation dropped it: 15s at
      # depth 22 / complexity 362, doubling per depth — depth 30 stays under
      # the ceiling while being un-runnable (2^30) without the memo. The
      # timeout tag is the tripwire.
      depth = 30

      levels =
        for k <- 0..(depth - 1) do
          next = "#/$defs/N#{k + 1}"

          branch = fn type ->
            {:object, [{"$ref", {:string, next}}, {"type", {:string, type}}]}
          end

          level = {:object, [{"oneOf", {:array, [branch.("object"), branch.("array")]}}]}
          {"N#{k}", level}
        end

      leaf = {"N#{depth}", {:object, [{"type", {:string, "string"}}]}}

      schema =
        {:object, [{"$defs", {:object, levels ++ [leaf]}}, {"$ref", {:string, "#/$defs/N0"}}]}

      assert Schema.complexity(schema) < 512
      assert {:ok, %Schema{}} = Schema.parse(schema, @dialect)
      assert {:error, :invalid_cardinality} = validate(schema, ~s(5))
    end

    # The first `m` levels carry an extra const member; the chain must be a
    # VALID schema (allowlisted members only) at both target metrics.
    defp complexity_chain(levels, const_count) do
      leaf = {:object, [{"type", {:string, "string"}}]}

      Enum.reduce(0..(levels - 1), leaf, fn i, inner ->
        members =
          if i < const_count do
            [{"const", {:integer, 5}}, {"properties", name_map(inner)}]
          else
            [{"properties", name_map(inner)}]
          end

        {:object, members}
      end)
    end

    defp name_map(schema), do: {:object, [{"p", schema}]}
  end
end
