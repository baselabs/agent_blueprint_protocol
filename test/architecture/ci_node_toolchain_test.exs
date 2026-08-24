defmodule AgentBlueprintProtocol.CiNodeToolchainTest do
  use ExUnit.Case, async: true

  @setup_node_sha "820762786026740c76f36085b0efc47a31fe5020"
  @node_version "24.19.0"

  test "the quality job selects an immutable supported Node runtime" do
    workflow = File.read!(".github/workflows/ci.yml")
    [_, quality_job] = String.split(workflow, "\n  quality:", parts: 2)

    setup_node =
      "uses: actions/setup-node@#{@setup_node_sha} # v7.0.0\n" <>
        "        with:\n" <>
        "          node-version: \"#{@node_version}\"\n" <>
        "          package-manager-cache: false"

    assert length(Regex.scan(~r|uses: actions/setup-node@|, quality_job)) == 1,
           "the quality job must select Node exactly once"

    assert quality_job =~ setup_node,
           "the quality job must pin the setup action and the supported Node release"

    assert position!(quality_job, setup_node) < position!(quality_job, "run: mix quality"),
           "the selected Node runtime must be active before the complete quality gate"
  end

  defp position!(content, needle) do
    case :binary.match(content, needle) do
      {position, _length} -> position
      :nomatch -> flunk("expected workflow fragment: #{inspect(needle)}")
    end
  end
end
