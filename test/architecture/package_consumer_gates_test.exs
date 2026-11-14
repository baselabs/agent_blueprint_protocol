defmodule AgentBlueprintProtocol.Architecture.PackageConsumerGatesTest do
  use ExUnit.Case, async: true, group: :project_build

  @tag timeout: 180_000
  test "every consumer gate runs when the quality aliases share one Mix process" do
    {output, status} =
      System.cmd(
        "mix",
        [
          "do",
          "livebooks.package",
          "+",
          "doctests.package",
          "+",
          "snippets.package",
          "+",
          "typescript.package"
        ],
        stderr_to_stdout: true
      )

    refute output =~ "using commas as separators in \"mix do\" is deprecated"
    assert status == 0, output

    for marker <- [
          "package Livebooks: 5 notebooks passed outside the checkout",
          "package doctests: agent_blueprint_protocol",
          "package snippets:",
          "package TypeScript: 13 examples passed outside the checkout"
        ] do
      assert output =~ marker
    end
  end
end
