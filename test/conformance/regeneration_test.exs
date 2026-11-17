defmodule AgentBlueprintProtocol.Conformance.RegenerationTest do
  use ExUnit.Case, async: false
  alias AgentBlueprintProtocol.Scratch

  @tag timeout: 180_000
  test "two fresh generations byte-agree with each other and every committed artifact" do
    Scratch.with_dir("regeneration", fn scratch ->
      generated =
        for name <- ["first", "second"] do
          output = Scratch.dir!(scratch, name)

          {_log, status} =
            System.cmd(
              "mix",
              [
                "run",
                "--no-start",
                "scripts/generate_conformance_corpus.exs",
                "--output",
                output
              ],
              env: [{"MIX_ENV", "test"}],
              stderr_to_stdout: true
            )

          assert status == 0, "fresh corpus generation failed"
          tree(output)
        end

      [first, second] = generated
      assert map_size(first) > 1, "generator did not populate the fresh output directory"
      assert first == second
      assert first == tree(".")
    end)
  end

  defp tree(root) do
    paths =
      Path.wildcard(Path.join(root, "priv/conformance/**/*")) ++
        Enum.map(
          ["spec/conformance/certified-results.json", "priv/examples/signed-blueprint.json"],
          &Path.join(root, &1)
        )

    for path <- paths,
        File.regular?(path),
        into: %{},
        do: {Path.relative_to(path, root), File.read!(path)}
  end
end
