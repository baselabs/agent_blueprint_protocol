defmodule AgentBlueprintProtocol.JsonPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentBlueprintProtocol.{Bounds, Json}

  @ijson_max 9_007_199_254_740_991

  property "decode of an encoded value is the identity over the closed algebra" do
    check all(value <- json_value()) do
      assert Json.decode(encode(value)) == {:ok, value}
    end
  end

  property "a widening bounds override is rejected; the exact maximum is accepted" do
    check all({field, max} <- member_of(Map.to_list(Map.from_struct(Bounds.maximum())))) do
      assert Bounds.new(%{field => max + 1}) == {:error, {:ceiling, field}}
      assert {:ok, _} = Bounds.new(%{field => max})
    end
  end

  # ---- generators + a minimal test-only encoder ------------------------------
  # The encoder exists only to feed the decoder valid bytes; the real RFC 8785
  # encoder is out of scope here. Keys/strings are lowercase letters (no escaping).

  defp json_value do
    StreamData.tree(leaf(), fn child ->
      one_of([
        map(list_of(child, max_length: 4), &{:array, &1}),
        object(child)
      ])
    end)
  end

  defp leaf do
    one_of([
      constant(:null),
      map(boolean(), &{:boolean, &1}),
      map(integer(-@ijson_max..@ijson_max), &{:integer, &1}),
      map(float(), &{:float, &1}),
      map(safe_string(), &{:string, &1})
    ])
  end

  defp object(child) do
    {safe_string(), child}
    |> tuple()
    |> list_of(max_length: 4)
    |> map(fn pairs -> {:object, Enum.uniq_by(pairs, &elem(&1, 0))} end)
  end

  defp safe_string, do: string(?a..?z, max_length: 6)

  defp encode(:null), do: "null"
  defp encode({:boolean, true}), do: "true"
  defp encode({:boolean, false}), do: "false"
  defp encode({:integer, i}), do: Integer.to_string(i)
  defp encode({:float, f}), do: Float.to_string(f)
  defp encode({:string, s}), do: <<?", s::binary, ?">>
  defp encode({:array, items}), do: "[" <> Enum.map_join(items, ",", &encode/1) <> "]"

  defp encode({:object, pairs}) do
    "{" <>
      Enum.map_join(pairs, ",", fn {k, v} -> <<?", k::binary, ?">> <> ":" <> encode(v) end) <> "}"
  end
end
