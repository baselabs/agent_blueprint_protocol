defmodule AgentBlueprintProtocol.Fuzz.SchemaFuzzTest do
  @moduledoc """
  Raw-binary fuzz over the schema surface: arbitrary bytes either fail the
  bounded decoder (the expected deny for garbage) or parse and validate
  deny-or-ok — never a crash, never a hang. The complexity ceiling plus the
  decoder's own bounds make every accepted input bounded work.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Json, Schema}

  @dialect Schema.dialect()

  @blob_sources [
    "",
    "{}",
    ~s({"type":"object"}),
    ~s({"pattern":"^a+$"}),
    ~s({"$ref":"https://evil.example.com/s.json"}),
    ~s({"oneOf":[{"$ref":"#"}]}),
    ~s({"enum":),
    "\x00\x01\x02",
    String.duplicate(~s({"properties":{"p",), 200),
    "[]",
    "true",
    ~s({"type":["string","string"]}),
    ~s({"$defs":{"a":{"$ref":"#/$defs/b"}},"$ref":"#/$defs/a"})
  ]

  test "corpus of hostile blobs: deny-or-ok, never raise" do
    for blob <- @blob_sources do
      case Json.decode(blob) do
        {:ok, schema} ->
          assert deny_or_ok(Schema.parse(schema, @dialect))
          assert deny_or_ok(Schema.validate_instance(schema, {:integer, 1}, @dialect))

        {:error, _denied} ->
          :ok
      end
    end
  end

  test "byte-flip mutations of a valid schema stay deny-or-ok" do
    base = ~s({"type":"object","properties":{"a":{"type":"string"}}})

    for i <- 0..(byte_size(base) - 1) do
      <<head::binary-size(^i), _c, tail::binary>> = base
      mutant = head <> " " <> tail

      case Json.decode(mutant) do
        {:ok, schema} ->
          assert deny_or_ok(Schema.parse(schema, @dialect))
          assert deny_or_ok(Schema.validate_instance(schema, {:object, []}, @dialect))

        {:error, _denied} ->
          :ok
      end
    end
  end

  defp deny_or_ok(:ok), do: true
  defp deny_or_ok({:ok, _parsed}), do: true
  defp deny_or_ok({:error, reason}) when is_atom(reason), do: true
  defp deny_or_ok(_other), do: false
end
