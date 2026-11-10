defmodule AgentBlueprintProtocol.Architecture.PublishWorkflowTest do
  use ExUnit.Case, async: true

  test "publishing stops after any failed preceding step and preserves registry skip guards" do
    workflow = File.read!(".github/workflows/publish.yml")
    steps = String.split(workflow, "      - name: ") |> tl()

    for name <- [
          "Publish the npm kit (staged trusted publishing, provenance)",
          "Publish the Hex package and docs",
          "Attach the verifier kit to the GitHub release"
        ] do
      step = Enum.find(steps, &String.starts_with?(&1, name <> "\n"))
      assert step, "missing publish step: #{name}"

      refute Regex.match?(~r/^\s+if:/m, step),
             "publish step overrides the default success condition: #{name}"

      assert step =~ "if "
      assert step =~ "already"
    end
  end
end
