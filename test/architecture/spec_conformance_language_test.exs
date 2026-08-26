defmodule AgentBlueprintProtocol.Architecture.SpecConformanceLanguageTest do
  @moduledoc """
  Specification-language gates. The normative document carries the
  BCP 14 conformance-language boilerplate and actually uses its
  keywords (uppercase, word-bounded), and every fenced `json` example
  in the specification is bound to a live conformance corpus case: the
  fence's info string names `corpus:<case-id>`, the id exists in the
  shipped corpus, and the fence's bytes equal that case's input text —
  a specification example can never drift from the corpus that
  enforces it.
  """

  use ExUnit.Case, async: true

  @spec_path "spec/protocol.md"
  @boilerplate_marks [
    "interpreted as described in",
    "BCP 14",
    "[RFC2119]",
    "[RFC8174]",
    "as shown here"
  ]
  # Compound keywords are single list entries (~w would split them);
  # keyword USE is counted over the document with the boilerplate
  # paragraph itself removed, so quoting a keyword is not using it.
  @keywords ["MUST", "MUST NOT", "SHOULD", "SHOULD NOT", "MAY"]

  test "the specification carries the conformance-language boilerplate and uses its keywords" do
    spec = File.read!(@spec_path)

    for mark <- @boilerplate_marks do
      assert spec =~ mark,
             "the BCP 14 boilerplate fragment #{inspect(mark)} is missing " <>
               "from the normative document"
    end

    body = strip_boilerplate(spec)

    for keyword <- @keywords do
      assert Regex.match?(keyword_pattern(keyword), body),
             "the normative document never uses the conformance keyword " <>
               "#{keyword} outside the boilerplate (uppercase, word-bounded)"
    end
  end

  test "every fenced specification example is bound to a live corpus case by exact bytes" do
    spec = File.read!(@spec_path)
    inputs = corpus_case_inputs()
    examples = json_fences(spec)

    offenders =
      for {info, body} <- examples, offence <- binding_offences(info, body, inputs) do
        {info, body, offence}
      end

    assert examples != [],
           "the specification carries no corpus-bound example — the " <>
             "example/corpus coupling gate would be vacuous"

    assert offenders == [],
           "a specification example is not corpus-bound:\n" <>
             Enum.map_join(offenders, "\n", fn {info, body, offence} ->
               "  fence #{inspect(info)} (#{String.slice(body, 0, 40)}…): #{offence}"
             end)
  end

  defp keyword_pattern("MUST NOT"), do: ~r/\bMUST NOT\b/
  defp keyword_pattern("MUST"), do: ~r/\bMUST\b(?! NOT)/
  defp keyword_pattern(other), do: ~r/\b#{Regex.escape(other)}\b/

  # Removes the boilerplate paragraph (from its opening quote block to
  # the closing "as shown here.") so keyword mentions inside it do not
  # satisfy the usage check.
  defp strip_boilerplate(spec) do
    String.replace(spec, ~r/The key words "MUST".*?as shown here\./s, "")
  end

  # A json fence MUST carry the info tag `corpus:<case-id>`; the id MUST
  # exist in the shipped corpus; the fence bytes MUST equal the case's
  # input text.
  defp binding_offences(info, body, inputs) do
    case Regex.run(~r/^ corpus:([^\s]+)$/, info) do
      nil ->
        ["no corpus case tag (expected `corpus:<case-id>` in the fence info)"]

      [_, id] ->
        id_offences(id, body, inputs)
    end
  end

  defp id_offences(id, _body, inputs) when not is_map_key(inputs, id) do
    ["names corpus case #{inspect(id)}, which is not in the corpus"]
  end

  defp id_offences(id, body, inputs) do
    # Exact bytes: the fence body is the case text plus exactly the one
    # newline that precedes the closing fence — nothing else may differ.
    if body == inputs[id] <> "\n" do
      []
    else
      ["does not byte-match corpus case #{inspect(id)}"]
    end
  end

  defp json_fences(spec) do
    ~r/```json([^\n]*)\n(.*?)```/s
    |> Regex.scan(spec)
    |> Enum.map(fn [_, info, body] -> {info, body} end)
  end

  defp corpus_case_inputs do
    "priv/conformance/cases/*.json"
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      %{"cases" => cases} = path |> File.read!() |> Jason.decode!()

      Enum.map(cases, fn case -> {case["id"], case["input"]["text"]} end)
    end)
    |> Map.new()
  end
end
