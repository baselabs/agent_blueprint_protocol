Code.require_file("../scripts/package_examples.exs", __DIR__)

defmodule AgentBlueprintProtocol.PackageExamplesTest do
  use ExUnit.Case, async: true

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
