# Dependency-currency gate: every resolvable drift between mix.lock and the
# registry reds the build; a currency state that cannot be VERIFIED reds
# harder.
#
#   MIX_ENV=test mix deps.currency
#
# Contract:
#   - Runs in the caller's working directory (no script-relative directory
#     change) — CI gates each project from that project's own root.
#   - `mix hex.outdated` exits nonzero BOTH on drift and on lookup failure,
#     so classification reads the rendered result table (statuses are
#     anchored on trailing whitespace, which the table pads), never the
#     exit code.
#   - A registry lookup that fails over to the local cache is an
#     UNVERIFIED currency state: it never passes, table or no table.
#   - A drifted package whose every binding requirement still admits the
#     latest release ("Yes" across the requirement table) is resolvable
#     drift — exit 1 naming it. A drift blocked by some declared
#     requirement ("No" in the table) is printed with its requirement chain
#     and pinned deliberately in mix.exs with an inline reason.
#
# The gate is fail-closed end to end: an unclassifiable table row, a failed
# per-package lookup, or a missing table is a failure, never a pass.

defmodule AgentBlueprintProtocol.DepsCurrencyCheck do
  @header ~r/^Dependency\b.*\bStatus[[:space:]]*$/
  # Data-row statuses sit at end-of-line; the table pads every cell with
  # trailing whitespace, so the anchors tolerate it explicitly.
  @row ~r/^(?<name>\S+)\s.*\s(?<status>Up-to-date|Update possible)[[:space:]]*$/
  # Per-package requirement rows end in the Yes/No indicator.
  @req_row ~r/^(?<source>\S+)\s+(?<requirement>(?:~>|>=|=|<)\s?\S+(?:\s+or\s+(?:~>|>=|=|<)?\s?\S+)*)\s+(?<admits>Yes|No)[[:space:]]*$/
  @lookup_failure_markers ["Failed to fetch record", "using cache instead"]

  def run do
    {all_output, _status} = mix(["hex.outdated", "--all"])

    cond do
      output_unverifiable?(all_output) ->
        fail("registry lookup failed over to the local cache — currency state unverifiable")

      not table_rendered?(all_output) ->
        fail("no result table rendered — currency state unverifiable")

      true ->
        {drifted, unclassifiable} = classify_rows(all_output)

        if unclassifiable != [] do
          fail(
            "unclassifiable result rows (statuses must be Up-to-date or Update possible): " <>
              inspect(unclassifiable)
          )
        end

        case Enum.flat_map(drifted, &classify_drift/1) do
          [] ->
            IO.puts("deps currency: every dependency resolves at its latest release")
            :ok

          resolvable ->
            fail(
              "dependency currency drift (resolvable — run mix deps.update): " <>
                Enum.join(resolvable, ", ")
            )
        end
    end
  end

  defp mix(args) do
    System.cmd("mix", args, stderr_to_stdout: true)
  end

  defp output_unverifiable?(output) do
    Enum.any?(@lookup_failure_markers, &String.contains?(output, &1))
  end

  defp table_rendered?(output) do
    output |> table_region() != nil
  end

  # The table block starts at the header row and ends at the first blank
  # line; prose, warnings, and hint lines around it are not data rows.
  defp table_region(output) do
    output
    |> String.split("\n")
    |> Enum.drop_while(&(not Regex.match?(@header, &1)))
    |> Enum.take_while(&(&1 != ""))
  end

  defp classify_rows(output) do
    results =
      output
      |> table_region()
      |> Enum.drop(1)
      |> Enum.map(fn line ->
        case Regex.named_captures(@row, line) do
          %{"name" => name, "status" => "Update possible"} -> {:drift, name}
          %{} -> {:current, nil}
          nil -> {:unclassifiable, String.trim_trailing(line)}
        end
      end)

    drifted = for {:drift, name} <- results, do: name
    unclassifiable = for {:unclassifiable, line} <- results, do: line
    {drifted, unclassifiable}
  end

  defp classify_drift(name) do
    {detail, _status} = mix(["hex.outdated", name])

    req_rows =
      detail
      |> String.split("\n")
      |> Enum.flat_map(fn line ->
        case Regex.named_captures(@req_row, line) do
          nil -> []
          captures -> [captures]
        end
      end)

    cond do
      output_unverifiable?(detail) or req_rows == [] ->
        fail("requirement lookup for #{name} rendered no classifiable rows — drift unresolved")

      Enum.all?(req_rows, &(&1["admits"] == "Yes")) ->
        [name]

      true ->
        IO.puts(
          "deps currency: #{name} is resolver-blocked by a declared requirement " <>
            "(pin reason required inline in mix.exs); requirement chain:"
        )

        IO.puts(indent(detail))
        []
    end
  end

  defp indent(detail) do
    detail |> String.split("\n") |> Enum.map_join("\n", &"    #{&1}")
  end

  defp fail(message) do
    IO.puts("deps currency: violation: " <> message)
    System.halt(1)
  end
end

AgentBlueprintProtocol.DepsCurrencyCheck.run()
