defmodule AgentBlueprintProtocol.Architecture.GlobRootTest do
  @moduledoc """
  Only a glob pattern is glob syntax. A filesystem root belongs in
  `:filelib.wildcard/2`'s working-directory argument, never joined into
  the pattern. Windows backslashes are glob escapes, and brackets and
  braces in real paths would otherwise change the lookup.

  Scans tracked Elixir and documentation sources, including copied consumer
  recipes. Known bad forms must fail and the working-directory form must pass.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{ArchitectureScan, Scratch}

  @self "test/architecture/glob_root_test.exs"
  @roots ~w(lib scripts test documentation docs README.md usage-rules.md)
  @extensions ~w(.ex .exs .md .cheatmd .livemd)
  @patterns [
    ~r/Path\.wildcard\(\s*Path\.join\(/,
    ~r/Path\.join\((?:[^()]|\([^()]*\))*\)\s*\|>\s*Path\.wildcard\b/
  ]

  test "tracked sources keep filesystem roots out of glob patterns" do
    {output, 0} = System.cmd("git", ["ls-files", "-z", "--" | @roots])

    files =
      output
      |> String.split(<<0>>, trim: true)
      |> Enum.filter(&(Path.extname(&1) in @extensions))
      |> Enum.reject(&(&1 == @self))

    for known <- [
          "lib/agent_blueprint_protocol/conformance/corpus.ex",
          "scripts/check_spec_extraction.exs",
          "test/support/architecture_scan.exs",
          "documentation/quickstart.md",
          "docs/livebooks/abp-walkthrough.livemd",
          "docs/livebooks/conformance-and-attacks.livemd",
          "README.md",
          "usage-rules.md"
        ] do
      assert known in files, "the scan no longer sees #{known}"
    end

    offenders =
      for file <- files,
          offset <- offences(File.read!(file)),
          do: {file, offset}

    assert offenders == [], "filesystem roots joined into glob patterns: #{inspect(offenders)}"
  end

  test "the tripwire detects joined roots in direct and piped calls" do
    for source <- [
          ~s|Path.wildcard(Path.join(root, "**/*"))|,
          "Path.wildcard(\n  Path.join(root, \"**/*\"), match_dot: true)",
          ~s'root |> Path.join("*.livemd") |> Path.wildcard()',
          "root\n|> Path.join(\"*.livemd\")\n|> Path.wildcard(match_dot: true)",
          ~s'Path.join(Path.dirname(root), "*.html") |> Path.wildcard()',
          ~s|Path.wildcard(Path.join("lib", "**/*.ex"))|
        ] do
      assert offences(source) != [], "the tripwire missed a known bad form"
    end
  end

  test "the tripwire accepts a pattern with a separate working directory" do
    assert offences("""
           pattern
           |> String.to_charlist()
           |> :filelib.wildcard(String.to_charlist(root))
           |> Enum.map(&Path.join(root, List.to_string(&1)))
           """) == []
  end

  test "source scans treat roots literally and exclude hidden relative segments" do
    Scratch.with_dir("glob-root", fn scratch ->
      root = Path.join(scratch, "r[1]{a}")

      for relative <- ["visible.ex", ".hidden.ex", ".hidden/nested.ex", "dir/.hidden.exs"] do
        path = Path.join(root, relative)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, "")
      end

      assert ArchitectureScan.source_files([root]) == [Path.join(root, "visible.ex")]
      segments = ArchitectureScan.path_segments([root])
      assert "visible" in segments
      refute ".hidden" in segments
      refute "nested" in segments
    end)
  end

  test "all consumer corpus recipes agree and include hidden regular files under literal roots" do
    recipes =
      for {file, count} <- [
            {"lib/agent_blueprint_protocol/conformance/corpus.ex", 2},
            {"lib/agent_blueprint_protocol/conformance/report.ex", 3},
            {"lib/agent_blueprint_protocol/conformance/runner.ex", 2},
            {"documentation/quickstart.md", 1},
            {"docs/livebooks/abp-walkthrough.livemd", 1},
            {"docs/livebooks/conformance-and-attacks.livemd", 1}
          ],
          reduce: [] do
        recipes ->
          found =
            Regex.scan(
              ~r/files =\s+for relative <-.*?do: \{List.to_string\(relative\), File.read!\(path\)\}/s,
              File.read!(file)
            )

          assert length(found) == count, "the scan must see every corpus recipe in #{file}"
          recipes ++ Enum.map(found, fn [source] -> Code.string_to_quoted!(source) end)
      end

    assert recipes |> Enum.map(&Macro.to_string/1) |> Enum.uniq() |> length() == 1

    Scratch.with_dir("corpus-glob-root", fn scratch ->
      root = Path.join(scratch, "r[1]{a}")
      expected = %{"visible.json" => "visible", ".hidden" => "hidden", ".dir/file" => "nested"}

      for {relative, bytes} <- expected do
        path = Path.join(root, relative)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, bytes)
      end

      for recipe <- recipes do
        {files, _binding} = Code.eval_quoted(recipe, corpus_root: root)
        assert files == expected
      end
    end)
  end

  defp offences(source) do
    for pattern <- @patterns,
        [{offset, _length}] <- Regex.scan(pattern, source, return: :index),
        do: source |> binary_part(0, offset) |> String.split("\n") |> length()
  end
end
