defmodule AgentBlueprintProtocol.Architecture.DecisionRecordsTest do
  use ExUnit.Case, async: true

  test "tracked decision records have contiguous numbers, matching headings, and one status" do
    {listing, 0} = System.cmd("git", ["ls-files", "-z", "--", "docs/adr"])
    paths = listing |> String.split(<<0>>, trim: true) |> Enum.sort()
    assert paths != []

    for {path, number} <- Enum.with_index(paths, 1) do
      prefix = number |> Integer.to_string() |> String.pad_leading(4, "0")
      assert Regex.match?(~r|\Adocs/adr/[0-9]{4}-[a-z][a-z0-9-]*\.md\z|, path), path
      assert String.starts_with?(Path.basename(path), prefix <> "-"), path
      source = File.read!(path)
      assert Regex.match?(~r/\A# #{prefix}: [^\n]+\n\nStatus: [^\n]+\n/, source), path
      assert length(Regex.scan(~r/^Status:/m, source)) == 1, path
    end
  end
end
