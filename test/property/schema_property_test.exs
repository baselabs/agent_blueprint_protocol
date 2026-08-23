defmodule AgentBlueprintProtocol.SchemaPropertyTest do
  @moduledoc """
  Properties for the bounded schema dialect validator.

  - verdict-class invariance under object-member permutation (schema AND
    instance — the tagged algebra preserves wire order; the VERDICT class
    must not depend on it, though the reported reason legitimately may);
  - the mathematical-value equality law (core §4.2.2) over generated
    in-window numbers;
  - parse idempotence: parsing a schema yields a struct whose validation
    verdicts equal the raw path's;
  - totality: no input — including generated MALFORMED tagged shapes —
    ever raises; everything is deny-or-ok.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentBlueprintProtocol.{Json, Schema}

  @dialect Schema.dialect()

  defp decode!(binary) do
    assert {:ok, value} = Json.decode(binary)
    value
  end

  # Writable bounded JSON: values the decoder can always produce.
  defp json_value do
    one_of([
      constant(:null),
      boolean(),
      integer(-9_007_199_254_740_991..9_007_199_254_740_991//1),
      map(float(), &round_to_window/1),
      string(:alphanumeric, max_length: 12)
    ])
  end

  defp round_to_window(f), do: Float.round(f, 6)

  property "mathematical-value equality: in-window integers equal their float spelling" do
    check all(n <- integer(0..9_007_199_254_740_991//1), max_runs: 200) do
      schema = {:object, [{"const", {:integer, n}}]}

      assert Schema.validate_instance(schema, {:integer, n}, @dialect) == :ok
      # the float spelling of an in-window integer is exact — == holds
      assert Schema.validate_instance(schema, {:float, n * 1.0}, @dialect) == :ok
    end
  end

  property "verdict class is invariant under instance object-member permutation" do
    base =
      map(
        list_of({string(:alphanumeric, max_length: 4), json_value()},
          max_length: 5,
          uniq_fun: fn {k, _v} -> k end
        ),
        &{:object, &1}
      )

    schema =
      constant(decode!(~s({
          "type":"object",
          "properties":{"a":{"type":"string"},"b":{"type":"integer"}},
          "required":["a"],
          "additionalProperties":false
        })))

    check all(instance <- base, schema_v <- schema, max_runs: 200) do
      shuffled = {:object, Enum.shuffle(elem(instance, 1))}

      assert verdict_class(Schema.validate_instance(schema_v, instance, @dialect)) ==
               verdict_class(Schema.validate_instance(schema_v, shuffled, @dialect))
    end
  end

  property "verdict class is invariant under schema object-member permutation" do
    raw = ~s({"type":"string","minLength":2,"maxLength":6})
    permuted = ~s({"maxLength":6,"type":"string","minLength":2})

    check all(
            s <- member_of([decode!(raw), decode!(permuted)]),
            v <- one_of([string(:alphanumeric, max_length: 10), integer(0..100//1)]),
            max_runs: 200
          ) do
      instance = if is_binary(v), do: {:string, v}, else: {:integer, v}

      assert verdict_class(Schema.validate_instance(decode!(raw), instance, @dialect)) ==
               verdict_class(Schema.validate_instance(s, instance, @dialect))
    end
  end

  property "parse idempotence: struct path equals raw path" do
    schema_json =
      map(
        list_of(
          {string(:alphanumeric, max_length: 5),
           one_of([
             constant({:string, "object"}),
             constant({:string, "string"}),
             constant({:array, []}),
             constant({:integer, 3})
           ])},
          max_length: 3,
          uniq_fun: fn {k, _v} -> k end
        ),
        &{:object, &1}
      )

    check all(schema <- schema_json, max_runs: 200) do
      case Schema.parse(schema, @dialect) do
        {:ok, parsed} ->
          assert {:ok, ^parsed} = Schema.parse(schema, @dialect)

          assert Schema.validate_instance(schema, {:object, []}, @dialect) ==
                   Schema.validate_instance(parsed, {:object, []}, @dialect)

        {:error, reason} ->
          assert {:error, ^reason} = Schema.validate_instance(schema, {:object, []}, @dialect)
      end
    end
  end

  property "totality: malformed tagged shapes never raise, on either side" do
    check all(term <- malformed_term(), max_runs: 300) do
      result = Schema.validate_instance(term, {:integer, 1}, @dialect)
      assert result == :ok or match?({:error, reason} when is_atom(reason), result)

      result_instance = Schema.validate_instance(decode!(~s({"type":"object"})), term, @dialect)

      assert result_instance == :ok or
               match?({:error, reason} when is_atom(reason), result_instance)
    end
  end

  property "totality: arbitrary decoded documents deny-or-ok, never raise" do
    check all(blob <- string(:printable, max_length: 64), max_runs: 200) do
      case Json.decode(blob) do
        {:ok, schema} ->
          assert match_?(schema, {:integer, 1})

        {:error, _denied} ->
          :ok
      end
    end
  end

  defp match_?(schema, instance) do
    result = Schema.validate_instance(schema, instance, @dialect)
    result == :ok or match?({:error, reason} when is_atom(reason), result)
  end

  defp verdict_class(:ok), do: :ok
  defp verdict_class({:error, reason}) when is_atom(reason), do: {:error, reason}

  # The malformed-tagged catalog (adversarial finding 5): generator over
  # shapes the decoder can never emit — wrong payloads, wrong tag types,
  # non-tuples, improper lists, nested breakage.
  def malformed_term do
    leaf =
      one_of([
        constant(5),
        constant("raw"),
        constant(:nan),
        constant(:wrong_atom),
        constant({5, 5}),
        constant({:integer, 1.5}),
        constant({:boolean, 5}),
        constant({:float, :nan}),
        constant({:string, :not_a_string}),
        constant({:array, [:head | "tail"]}),
        constant({:object, [{"k", "raw"}]}),
        constant({:object, [{"dup", {:integer, 1}}, {"dup", {:integer, 2}}]}),
        constant({:object, [5]}),
        json_value()
      ])

    grow(3, leaf)
  end

  defp grow(0, leaf), do: leaf

  defp grow(size, leaf) do
    one_of([
      leaf,
      map(grow(size - 1, leaf), &{:array, [&1]}),
      map({string(:alphanumeric, max_length: 3), grow(size - 1, leaf)}, fn {k, v} ->
        {:object, [{k, v}]}
      end)
    ])
  end
end
