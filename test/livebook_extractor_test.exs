Code.require_file(Path.expand("../scripts/extract_livebooks.exs", __DIR__))

defmodule AgentBlueprintProtocol.LivebookExtractorTest do
  use ExUnit.Case, async: true

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
