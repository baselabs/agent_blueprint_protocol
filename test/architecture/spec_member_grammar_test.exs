defmodule AgentBlueprintProtocol.Architecture.SpecMemberGrammarTest do
  @moduledoc """
  Grammar-coupling gates: the specification's member-grammar tables and
  error-semantics table cross-read against the compiled truth in both
  directions. A member renamed, dropped, or re-cardinalized on either
  side reds; the error table covers exactly the closed error vocabulary
  with no repeated rows.
  """

  use ExUnit.Case, async: true

  @spec_path "spec/protocol.md"

  test "the grammar tables match the compiled member tables in both directions" do
    spec = File.read!(@spec_path)

    expectations = [
      {"Blueprint Core",
       AgentBlueprintProtocol.Blueprint.table() |> Enum.map(&{&1.name, &1.required})},
      {"Deployment Manifest",
       AgentBlueprintProtocol.Deployment.table() |> Enum.map(&{&1.name, &1.required})},
      # Federation's compiled table is private: its names pin via
      # envelope_members/0 and its cardinality via the corpus (a nil card
      # in the expectation skips the cardinality arm for that member).
      {"Federation TaskEnvelope",
       AgentBlueprintProtocol.Federation.envelope_members() |> Enum.map(&{&1, nil})}
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

    duplicated = table -- Enum.uniq(table)
    documented = Enum.sort(Enum.uniq(table))
    missing = compiled -- documented
    invented = documented -- compiled

    assert duplicated == [],
           "the error semantics table repeats rows: #{inspect(Enum.uniq(duplicated))}"

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
  end

  # compiled: [{name, required?}] (required? nil = names-only). The spec
  # rows carry name + cardinality column ("1" / "0..1").
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
      rows =
        section
        |> String.split("\n")
        |> Enum.take_while(&(!String.starts_with?(&1, ["### ", "## "])))
        |> Enum.flat_map(&parse_grammar_row/1)

      spec_names = Enum.map(rows, &elem(&1, 0))
      compiled_names = Enum.map(compiled, &elem(&1, 0))
      missing = compiled_names -- spec_names
      invented = spec_names -- compiled_names

      card_mismatches =
        for {name, required} <- compiled,
            required != nil,
            row = List.keyfind(rows, name, 0),
            row != nil,
            drift = card_drift(row, required),
            drift != nil do
          drift
        end

      List.wrap(if missing != [], do: "missing members: #{inspect(missing)}") ++
        List.wrap(if invented != [], do: "invented members: #{inspect(invented)}") ++
        card_mismatches
    end
  end

  defp card_drift({name, documented}, required) do
    expected = if required, do: "1", else: "0..1"

    if documented == expected do
      nil
    else
      "#{name}: documented cardinality #{inspect(documented)}, compiled #{inspect(expected)}"
    end
  end

  defp parse_grammar_row("| `" <> _ = row) do
    case Regex.run(~r/^\| `([^`]+)` \| (1|0\.\.1) \|/, row) do
      [_, name, card] -> [{name, card}]
      nil -> []
    end
  end

  defp parse_grammar_row(_), do: []
end
