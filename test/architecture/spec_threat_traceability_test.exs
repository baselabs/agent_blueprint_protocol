defmodule AgentBlueprintProtocol.Architecture.SpecThreatTraceabilityTest do
  @moduledoc """
  Threat-traceability gate: every corpus class cited by the
  specification's Security/Privacy threat model must be a class the
  conformance corpus actually exercises — a threat row citing a class
  the corpus does not carry reds (an untraceable security claim).
  """

  use ExUnit.Case, async: true

  @spec_path "spec/protocol.md"

  test "every threat-model corpus citation resolves to a live corpus class" do
    spec = File.read!(@spec_path)

    section =
      spec
      |> String.split(~r/^## /m)
      |> Enum.find("", &String.starts_with?(&1, "17. Security considerations"))

    assert section != "", "the Security considerations section is missing"

    cited =
      section
      |> String.split("\n")
      |> Enum.flat_map(fn
        "| " <> _ = row ->
          case String.split(row, "|") do
            parts when length(parts) >= 5 ->
              parts |> Enum.at(3) |> cited_classes()

            _ ->
              []
          end

        _ ->
          []
      end)

    assert cited != [], "the threat model cites no corpus classes (vacuous)"

    untraceable = cited -- corpus_classes()

    assert untraceable == [],
           "the threat model cites corpus classes that do not exist " <>
             "(untraceable security claims): #{inspect(Enum.uniq(untraceable))}"
  end

  defp cited_classes(cell) do
    ~r/`([^`]+)`/
    |> Regex.scan(cell || "")
    |> Enum.map(fn [_, name] -> name end)
  end

  defp corpus_classes do
    "priv/conformance/index.json"
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("applicability")
    |> Enum.flat_map(fn {_surface, classes} -> Map.keys(classes) end)
    |> Enum.uniq()
  end
end
