# Extract the existing dated CHANGELOG section, using the promotion gate's heading convention.
#   elixir scripts/release_notes.exs VERSION OUT
case System.argv() do
  [version, output] ->
    heading = ~r/^## \[#{Regex.escape(version)}\] - \d{4}-\d{2}-\d{2}\n(.*?)(?=^## \[|\z)/ms

    case Regex.scan(heading, File.read!("CHANGELOG.md"), capture: :all_but_first) do
      [[body]] -> File.write!(output, String.trim(body) <> "\n")
      _ -> raise "CHANGELOG.md must contain one dated ## [#{version}] section"
    end

  _ ->
    raise "usage: release_notes.exs VERSION OUT"
end
