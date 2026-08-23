defmodule AgentBlueprintProtocol.BoundsTest do
  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.Bounds

  test "maximum/0 exposes positive-integer ceilings" do
    max = Bounds.maximum()
    assert max.depth == 64

    assert max |> Map.from_struct() |> Map.values() |> Enum.all?(&(is_integer(&1) and &1 > 0))
  end

  test "new/1 accepts a tighter profile and keeps omitted fields at maximum" do
    {:ok, bounds} = Bounds.new(%{depth: 8, members: 10})
    assert bounds.depth == 8
    assert bounds.members == 10
    assert bounds.bytes == Bounds.maximum().bytes
  end

  test "new/1 accepts an override exactly at the maximum" do
    assert {:ok, %Bounds{depth: 64}} = Bounds.new(%{depth: 64})
  end

  test "new/1 rejects a widening override (tighten-only)" do
    assert Bounds.new(%{depth: 65}) == {:error, {:ceiling, :depth}}
  end

  test "new/1 rejects a non-positive or non-integer override" do
    assert Bounds.new(%{depth: 0}) == {:error, {:ceiling, :depth}}
    assert Bounds.new(%{depth: -1}) == {:error, {:ceiling, :depth}}
    assert Bounds.new(%{depth: 1.5}) == {:error, {:ceiling, :depth}}
  end

  test "new/1 rejects an unknown key" do
    assert Bounds.new(%{bogus: 1}) == {:error, :unknown_bound}
  end

  test "coerce/1 validates a struct and builds a profile from a map" do
    max = Bounds.maximum()
    assert Bounds.coerce(max) == {:ok, max}
    assert {:ok, %Bounds{depth: 4}} = Bounds.coerce(%{depth: 4})
  end

  test "coerce/1 rejects a directly-constructed struct that widens a ceiling" do
    widened = %{Bounds.maximum() | bytes: Bounds.maximum().bytes + 1}
    assert Bounds.coerce(widened) == {:error, {:ceiling, :bytes}}
  end
end
