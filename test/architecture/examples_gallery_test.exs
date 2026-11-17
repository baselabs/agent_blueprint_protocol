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

  @examples_dir "priv/examples"

  test "every example artifact is a byte-exact corpus case" do
    examples =
      for(
        relative <- :filelib.wildcard(~c"*.json", String.to_charlist(@examples_dir)),
        not Enum.any?(Path.split(List.to_string(relative)), &String.starts_with?(&1, ".")),
        do: Path.join(@examples_dir, List.to_string(relative))
      )
      |> Enum.sort()

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
      for(
        relative <- :filelib.wildcard(~c"*.json", String.to_charlist(@examples_dir)),
        not Enum.any?(Path.split(List.to_string(relative)), &String.starts_with?(&1, ".")),
        do: Path.join(@examples_dir, List.to_string(relative))
      )
      |> Enum.map(&Path.basename(&1, ".json"))

    assert Enum.any?(names, &String.contains?(&1, "blueprint")),
           "no blueprint example in the gallery"

    assert Enum.any?(names, &String.contains?(&1, "deployment")),
           "no deployment example in the gallery"
  end

  # VALID-verdict corpus case texts only: an example whose only corpus
  # appearances are DENIAL cases (tampered bytes, mismatched digests)
  # is not a verified example — the gallery shows artifacts the corpus
  # accepts.
  defp corpus_case_texts do
    "priv/conformance/cases/*.json"
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      %{"cases" => cases} = path |> File.read!() |> Jason.decode!()

      cases
      |> Enum.filter(&(&1["expected"]["verdict"] == "valid"))
      |> Enum.map(& &1["input"]["text"])
    end)
  end
end
