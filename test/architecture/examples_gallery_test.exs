defmodule AgentBlueprintProtocol.Architecture.ExamplesGalleryTest do
  @moduledoc """
  Examples-gallery gate: every example artifact is a byte-exact
  conformance corpus case — the gallery cannot drift from the corpus
  that verifies it — and the quickstart executes green end-to-end
  exactly as written (its claims are mirror-checked by the
  documentation mirror gate; this gate additionally proves the example
  FILES are corpus bytes).
  """

  use ExUnit.Case, async: true

  @examples_dir "examples"

  test "every example artifact is a byte-exact corpus case" do
    examples = Path.wildcard(Path.join(@examples_dir, "*.json")) |> Enum.sort()

    assert examples != [],
           "no example artifacts found — the gallery would be vacuous"

    corpus_texts = corpus_case_texts()

    offenders =
      for path <- examples,
          bytes = File.read!(path),
          bytes not in corpus_texts do
        "#{path} is not a byte-exact conformance corpus case"
      end

    assert offenders == [],
           "example artifacts drifted from the corpus:\n" <> Enum.join(offenders, "\n")
  end

  test "the gallery documents at least one blueprint + deployment pair" do
    names =
      Path.wildcard(Path.join(@examples_dir, "*.json")) |> Enum.map(&Path.basename(&1, ".json"))

    assert Enum.any?(names, &String.contains?(&1, "blueprint")),
           "no blueprint example in the gallery"

    assert Enum.any?(names, &String.contains?(&1, "deployment")),
           "no deployment example in the gallery"
  end

  defp corpus_case_texts do
    "priv/conformance/cases/*.json"
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      %{"cases" => cases} = path |> File.read!() |> Jason.decode!()
      Enum.map(cases, & &1["input"]["text"])
    end)
  end
end
