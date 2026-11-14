Code.require_file(Path.expand("../scripts/extract_livebooks.exs", __DIR__))

defmodule AgentBlueprintProtocol.LivebookExtractorTest do
  use ExUnit.Case, async: true, group: :project_build

  @moduletag timeout: :infinity

  import ExUnit.CaptureIO
  alias AgentBlueprintProtocol.Scratch

  test "each notebook has its own Mix installation and consumer directory" do
    Scratch.with_dir("notebook-isolation", fn root ->
      archive = Path.join(root, "package.tar")

      {build, status} =
        System.cmd("mix", ["hex.build", "--output", archive], stderr_to_stdout: true)

      assert status == 0, build

      source =
        notebook([
          "Mix.install([{:agent_blueprint_protocol, \"~> 1.0\"}])",
          """
          install_probe = Path.join(Mix.install_project_dir(), ".consumer-probe")
          if File.exists?(install_probe), do: raise("notebook reused another consumer's installation")
          File.write!(install_probe, "installed")
          if File.exists?(".consumer-probe"), do: raise("notebook reused another consumer's directory")
          File.write!(".consumer-probe", "executed")
          """
        ])

      notebooks =
        for index <- 1..2 do
          path = Path.join(root, "notebook-#{index}.livemd")
          File.write!(path, source)
          path
        end

      output =
        capture_io(fn ->
          result =
            try do
              PackageLivebooks.run(archive, notebooks)
            rescue
              error -> {:failed, Exception.message(error)}
            end

          send(self(), {:notebook_run, result})
        end)

      assert_received {:notebook_run, result}
      reused_install = String.contains?(output, "notebook reused another consumer's installation")
      reused_directory = String.contains?(output, "notebook reused another consumer's directory")
      refute reused_install, output
      refute reused_directory, output
      assert result == :ok, "#{inspect(result)}\n" <> output
    end)
  end

  test "extracts notebook cells against an unpacked package path" do
    source = File.read!("docs/livebooks/abp-walkthrough.livemd")

    assert {:ok, script} =
             PackageLivebooks.extract(source, :another_package, "/unpacked", "tour.livemd")

    assert script =~ "Mix.install([{:another_package, path:"
    refute script =~ "organization:"
    assert script =~ "Code.eval_quoted_with_env"
  end

  test "extracts ordered Elixir cells without persisted output or prose" do
    source = notebook(["Mix.install([{:some_package, \"~> 1.0\"}])", "value = 7", "value + 1"])
    source = source <> "\nText.\n\n<!-- livebook:{\"output\":true} -->\n\n```\n8\n```\n"

    assert {:ok, script} =
             PackageLivebooks.extract(source, :some_package, "/package", "tour.livemd")

    assert :binary.match(script, "value = 7") < :binary.match(script, "value + 1")
    refute script =~ "Text."
    refute script =~ "persist_outputs"
    assert script =~ "cell.index"
    assert script =~ "cell.line"
  end

  test "a path installation drops all Hex and install options" do
    source =
      notebook([
        "Mix.install([{:some_package, \"~> 1.0\", organization: \"private-org\"}], force: true)",
        ":ok"
      ])

    assert {:ok, script} =
             PackageLivebooks.extract(source, :some_package, "/package", "tour.livemd")

    refute script =~ "private-org"
    refute script =~ "force: true"
    assert script =~ "Mix.install([{:some_package, path:"
  end

  test "rejects absent, duplicate, nested, or syntactically invalid install cells" do
    for cells <- [
          ["value = 1"],
          ["Mix.install([])", "Mix.install([])"],
          ["if true, do: Mix.install([])"],
          ["Mix.install([]); :ok"],
          ["Mix.install([])", "("]
        ] do
      assert {:error, reason} =
               PackageLivebooks.extract(
                 notebook(cells),
                 :some_package,
                 "/package",
                 "broken.livemd"
               )

      assert reason =~ "broken.livemd cell"
    end
  end

  test "extracts every checked-in notebook using a single package-independent implementation" do
    paths = Path.wildcard("docs/livebooks/*.livemd")
    assert paths != []

    for path <- paths do
      assert {:ok, script} =
               PackageLivebooks.extract(File.read!(path), :some_package, "/package", path)

      assert script =~ "Mix.install([{:some_package, path:"
      refute script =~ "organization:"
    end
  end

  defp notebook(cells) do
    Enum.map_join(cells, "\n", &"```elixir\n#{&1}\n```\n")
  end
end
