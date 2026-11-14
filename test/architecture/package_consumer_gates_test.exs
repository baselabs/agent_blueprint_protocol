defmodule AgentBlueprintProtocol.Architecture.PackageConsumerGatesTest do
  use ExUnit.Case, async: true, group: :project_build

  @tag timeout: 180_000
  test "every consumer gate runs when the quality aliases share one Mix process" do
    {output, status} =
      System.cmd(
        "mix",
        [
          "do",
          "livebooks.package,",
          "doctests.package,",
          "snippets.package,",
          "typescript.package"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "package Livebooks: 5 notebooks passed outside the checkout"
    assert output =~ "package doctests: agent_blueprint_protocol"
    assert output =~ "package snippets:"
    assert output =~ "package TypeScript: 13 examples passed outside the checkout"
  end
end
