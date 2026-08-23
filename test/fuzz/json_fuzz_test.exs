defmodule AgentBlueprintProtocol.JsonFuzzTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentBlueprintProtocol.Json

  property "arbitrary bytes never raise or hang; the result is always ok or a value-free error" do
    check all(bytes <- StreamData.binary(), max_runs: 2000) do
      case Json.decode(bytes) do
        {:ok, _value} -> :ok
        {:error, reason} -> assert valid_reason?(reason)
      end
    end
  end

  defp valid_reason?(reason)
       when reason in [
              :invalid_syntax,
              :invalid_encoding,
              :invalid_number,
              :number_not_double_expressible,
              :duplicate_member,
              :trailing_bytes
            ],
       do: true

  defp valid_reason?({:ceiling, name}),
    do: name in [:bytes, :depth, :members, :items, :nodes, :string, :key, :number_lexeme]

  defp valid_reason?(_reason), do: false
end
