Code.require_file(Path.expand("../scripts/extract_livebooks.exs", __DIR__))

defmodule AgentBlueprintProtocol.LivebookExtractorTest do
  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.LivebookExtractor

  test "extracts ordered Elixir cells and pins the selected package version" do
    fence = String.duplicate(<<96>>, 3)

    notebook =
      fence <>
        "elixir\nMix.install([{:agent_blueprint_protocol, \"~> 1.0.0-rc.1\"}])\n" <>
        fence <>
        "\n\nText between cells.\n\n" <>
        fence <>
        "elixir\nvalue = 7\n" <>
        fence <>
        "\n\n<!-- livebook:{\"output\":true} -->\n\n" <>
        fence <>
        "\nvalue\n" <>
        fence <>
        "\n\n" <>
        fence <> "elixir\nvalue + 1\n" <> fence <> "\n"

    for source_version <- ["1.0.0-rc.1", "1.0.0-rc.2", "1.0.0", "2.3.4", "2.3"] do
      source = String.replace(notebook, "~> 1.0.0-rc.1", "~> " <> source_version)
      assert {:ok, script} = LivebookExtractor.extract(source, "1.0.0-rc.7")
      assert script =~ ~s|Mix.install([{:agent_blueprint_protocol, "== 1.0.0-rc.7"}])|
    end

    assert {:ok, script} = LivebookExtractor.extract(notebook, "1.0.0-rc.7")

    assert String.starts_with?(
             script,
             "Mix.install([{:agent_blueprint_protocol, \"== 1.0.0-rc.7\"}])"
           )

    assert script =~ "Code.eval_quoted_with_env"
    assert script =~ "value = 7"
    assert script =~ "value + 1"
    refute script =~ "Text between cells"
    refute script =~ ~s({"output":true})

    assert :binary.match(script, "value = 7") < :binary.match(script, "value + 1")
  end

  test "rejects a missing setup cell, an incorrect source pin, and another install cell" do
    fence = String.duplicate(<<96>>, 3)
    prefix = fence <> "elixir\n"
    suffix = "\n" <> fence <> "\n"

    missing = prefix <> "value = 1" <> suffix

    wrong_pin =
      prefix <>
        ~s|Mix.install([{:agent_blueprint_protocol, "== 1.0.0"}])| <>
        suffix <>
        prefix <> "value = 1" <> suffix

    duplicate =
      prefix <>
        ~s|Mix.install([{:agent_blueprint_protocol, "~> 1.0.0-rc.1"}])| <>
        suffix <>
        prefix <>
        ~s|Mix.install([{:agent_blueprint_protocol, "~> 1.0.0-rc.1"}])| <>
        suffix

    assert {:error, :invalid_notebook} = LivebookExtractor.extract(missing, "1.0.0-rc.7")

    for invalid <- [
          wrong_pin,
          String.replace(wrong_pin, "== 1.0.0", "~> invalid"),
          String.replace(wrong_pin, "== 1.0.0", "~> "),
          String.replace(wrong_pin, "== 1.0.0", "~> 1.0.0\"}]); :ok; #"),
          String.replace(duplicate, ":agent_blueprint_protocol", ":other_package")
        ] do
      assert {:error, :invalid_notebook} = LivebookExtractor.extract(invalid, "1.0.0-rc.7")
    end

    assert {:error, :invalid_notebook} = LivebookExtractor.extract(duplicate, "1.0.0-rc.7")
  end

  test "extracts every checked-in notebook into one script each" do
    root =
      Path.join(System.tmp_dir!(), "abp-livebook-extractor-#{System.unique_integer([:positive])}")

    input = Path.expand("../docs/livebooks", __DIR__)
    output = Path.join(root, "scripts")

    on_exit(fn -> File.rm_rf!(root) end)

    assert {:ok, paths} = LivebookExtractor.extract_directory(input, output, "1.0.0-rc.7")
    assert length(paths) == length(Path.wildcard(Path.join(input, "*.livemd")))
    assert Enum.all?(paths, &String.ends_with?(&1, ".exs"))
    assert Enum.all?(paths, &(File.read!(&1) =~ ~s("== 1.0.0-rc.7")))

    invalid_dir = Path.expand(Path.join(root, "invalid"))
    File.mkdir_p!(invalid_dir)
    invalid_path = Path.join(invalid_dir, "invalid.livemd")
    File.write!(invalid_path, "```elixir\nMix.install([])\n```\n")

    assert {:error, {:invalid_notebook, ^invalid_path}} =
             LivebookExtractor.extract_directory(invalid_dir, output, "1.0.0-rc.7")
  end
end
