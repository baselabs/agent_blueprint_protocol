Code.require_file("../scripts/package_examples.exs", __DIR__)

defmodule AgentBlueprintProtocol.PackageExamplesTest do
  use ExUnit.Case, async: true, group: :project_build

  @moduletag timeout: :infinity

  import ExUnit.CaptureIO
  alias AgentBlueprintProtocol.Scratch

  test "each snippet document runs in its own consumer project" do
    Scratch.with_dir("snippet-isolation", fn root ->
      archive = Path.join(root, "package.tar")

      {build, status} =
        System.cmd("mix", ["hex.build", "--output", archive], stderr_to_stdout: true)

      assert status == 0, build

      probe = """
      ```elixir
      if File.exists?(".consumer-probe"), do: raise("document reused another consumer project")
      File.write!(".consumer-probe", "executed")
      ```
      """

      documents =
        for index <- 1..2 do
          path = Path.join(root, "guide-#{index}.md")
          File.write!(path, probe)
          path
        end

      output =
        capture_io(fn ->
          result =
            try do
              PackageExamples.run(archive, :snippets, documents)
            rescue
              error -> {:failed, Exception.message(error)}
            end

          send(self(), {:snippet_run, result})
        end)

      assert_received {:snippet_run, result}
      refute output =~ "document reused another consumer project", output
      assert result == :ok, "#{inspect(result)}\n" <> output
      assert output =~ "package snippets: 2 blocks in 2 documents passed outside the checkout"
    end)
  end

  test "interactive signing examples group key bindings and retain later block bindings" do
    files = ["documentation/compose-and-sign.md" | Path.wildcard("docs/livebooks/*.livemd")]

    for file <- files,
        cell <- PackageExamples.cells(File.read!(file), file),
        file == "documentation/compose-and-sign.md" or String.contains?(cell.code, "private_key") do
      code = String.trim(cell.code)

      assert String.starts_with?(code, "(\n") and String.ends_with?(code, "\n)"),
             "#{file} block #{cell.index}: interactive key examples must be one parenthesized expression"
    end

    Scratch.with_dir("interactive-signing", fn root ->
      input = Path.join(root, "input.exs")
      source = File.read!("documentation/compose-and-sign.md")

      code =
        PackageExamples.cells(source, "compose-and-sign.md") |> Enum.map_join("\n", & &1.code)

      File.write!(
        input,
        "Application.ensure_all_started(:crypto)\n" <> code <> "\nSystem.halt(0)\n"
      )

      {output, status} =
        System.cmd("sh", ["-c", ~s(iex --dot-iex "" < "$1"), "iex", input],
          cd: root,
          env: [{"ERL_LIBS", Path.join(Mix.Project.build_path(), "lib")}],
          stderr_to_stdout: true
        )

      assert status == 0, "interactive signing failed (exit #{status})"
      assert output =~ "reloaded_pair: true", "interactive blocks lost their bindings"
      refute output =~ "** (", "interactive signing raised an exception"

      refute Regex.match?(~r/\{<<[0-9, .\n]+>>, <<[0-9, .\n]+>>\}/, output),
             "interactive signing displayed key material"
    end)
  end

  test "snippet extraction preserves order and source lines and skips only marked fragments" do
    source =
      "```elixir\nx = 1\n```\n```elixir fragment\nmissing()\n```\n```sh\nfalse\n```\n```elixir\nx + 1\n```\n"

    assert [%{code: "x = 1\n", index: 1, line: 2}, %{code: "x + 1\n", index: 3, line: 11}] =
             PackageExamples.cells(source, "guide.md")
  end

  test "an unknown snippet marking fails instead of hiding unrunnable code" do
    assert_raise RuntimeError, ~r/guide.md block 1: unknown Elixir fence marking/, fn ->
      PackageExamples.cells("```elixir ignored\nmissing()\n```\n", "guide.md")
    end
  end
end
