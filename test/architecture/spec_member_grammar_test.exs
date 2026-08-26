defmodule AgentBlueprintProtocol.Architecture.SpecMemberGrammarTest do
  @moduledoc """
  Grammar-coupling gates: the specification's member-grammar tables and
  error-semantics table cross-read against the compiled truth in both
  directions. The prose grammar cannot drift from the shipped tables (a
  member renamed or dropped on either side reds), and the error table
  covers exactly the closed error vocabulary (a missing or invented code
  reds).
  """

  use ExUnit.Case, async: true

  @spec_path "spec/protocol.md"

  test "the grammar tables match the compiled member tables in both directions" do
    spec = File.read!(@spec_path)

    expectations = [
      {"Blueprint Core", AgentBlueprintProtocol.Blueprint.table() |> Enum.map(& &1.name)},
      {"Deployment Manifest", AgentBlueprintProtocol.Deployment.table() |> Enum.map(& &1.name)},
      {"Federation TaskEnvelope", AgentBlueprintProtocol.Federation.envelope_members()}
    ]

    offenders =
      for {title, compiled} <- expectations,
          drift <- table_drift(spec, title, compiled) do
        {title, drift}
      end

    assert offenders == [],
           "a grammar table disagrees with the compiled registry:\n" <>
             Enum.map_join(offenders, "\n", fn {title, drift} ->
               "  #{title}: #{drift}"
             end)
  end

  test "the error semantics table covers exactly the closed error vocabulary" do
    spec = File.read!(@spec_path)
    table = table_members(spec, "## 12. Error vocabulary")
    compiled = AgentBlueprintProtocol.Error.codes() |> Enum.map(&to_string/1) |> Enum.sort()

    documented = Enum.sort(table)
    missing = compiled -- documented
    invented = documented -- compiled

    assert missing == [] and invented == [],
           "the error semantics table drifted from Error.codes/0 — " <>
             "missing: #{inspect(missing)} invented: #{inspect(invented)}"
  end

  # Extracts the backticked first-column names of a section's tables.
  defp table_members(spec, heading) do
    spec
    |> String.split(~r/^## /m)
    |> Enum.find("", &String.starts_with?(&1, String.trim_leading(heading, "## ")))
    |> String.split("\n")
    |> Enum.flat_map(fn
      "| `" <> rest ->
        case Regex.run(~r/^([^`]+)`/, rest) do
          [_, name] -> [name]
          nil -> []
        end

      _ ->
        []
    end)
    |> Enum.uniq()
  end

  defp table_drift(spec, title, compiled) do
    section =
      spec
      |> String.split("### Member grammar — ")
      |> Enum.find("", &String.starts_with?(&1, title))

    if section == "" do
      ["the section is missing from the specification"]
    else
      # only the FIRST table of the section (the member grammar itself),
      # bounded by the next heading of either depth
      names =
        section
        |> String.split("\n")
        |> Enum.take_while(&(!String.starts_with?(&1, ["### ", "## "])))
        |> Enum.flat_map(fn
          "| `" <> _ = row ->
            [row |> String.replace_prefix("| `", "") |> String.split("`") |> hd()]

          _ ->
            []
        end)

      missing = compiled -- names
      invented = names -- compiled

      drifts =
        List.wrap(if missing != [], do: "missing members: #{inspect(missing)}") ++
          List.wrap(if invented != [], do: "invented members: #{inspect(invented)}")

      drifts
    end
  end
end
