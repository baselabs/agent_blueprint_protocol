defmodule AgentBlueprintProtocol.Conformance.GoldensCoverageTest do
  @moduledoc """
  Track-A's mechanical coverage assertion (the corpus acceptance line): the
  golden vectors exercise EVERY registry member — Blueprint's 16-member
  table and Deployment's 17-member table — asserted against the tables
  themselves, not by prose. Red proof: drop one member from a golden (via
  the generator) and this test reds.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Blueprint, Deployment}

  test "the golden blueprint covers every registry table member" do
    golden = read_golden("vectors/blueprint-golden.json")
    golden_members = golden |> Map.keys() |> MapSet.new()

    table_members =
      Blueprint.table()
      |> Enum.map(& &1.name)
      |> MapSet.new()

    missing = MapSet.difference(table_members, golden_members)

    assert MapSet.size(missing) == 0,
           "golden blueprint does not exercise: #{inspect(MapSet.to_list(missing))}"

    assert MapSet.size(golden_members) == MapSet.size(table_members)
  end

  test "the golden deployment covers every registry table member" do
    golden = read_golden("vectors/deployment-golden.json")
    golden_members = golden |> Map.keys() |> MapSet.new()

    table_members =
      Deployment.table()
      |> Enum.map(& &1.name)
      |> MapSet.new()

    missing = MapSet.difference(table_members, golden_members)

    assert MapSet.size(missing) == 0,
           "golden deployment does not exercise: #{inspect(MapSet.to_list(missing))}"

    assert MapSet.size(golden_members) == MapSet.size(table_members)
  end

  # The golden vectors ship as canonical JSON; decode with the package's
  # own decoder (no :jason — zero-dep discipline).
  defp read_golden(path) do
    bytes = File.read!(Path.join("priv/conformance", path))

    {:ok, {:object, members}} = AgentBlueprintProtocol.Json.decode(bytes)

    Map.new(members, fn {k, v} -> {k, plain(v)} end)
  end

  defp plain({:object, ms}), do: ms |> Enum.map(fn {k, v} -> {k, plain(v)} end) |> Map.new()
  defp plain({:array, items}), do: Enum.map(items, &plain/1)
  defp plain({:string, s}), do: s
  defp plain({:integer, n}), do: n
  defp plain({:float, n}), do: n
  defp plain({:boolean, b}), do: b
  defp plain(:null), do: nil
end
