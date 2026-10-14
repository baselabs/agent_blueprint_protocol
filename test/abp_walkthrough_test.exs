defmodule AgentBlueprintProtocol.WalkthroughTest do
  @moduledoc """
  Runs the Livebook walkthrough (`docs/livebooks/abp-walkthrough.livemd`) as a
  test. Every code cell is evaluated in order with one shared binding, as
  Livebook evaluates it, against this package's source; only the
  `Mix.install` cell is skipped, and that cell must pin the current version.
  Each evaluated cell must be followed by its persisted output block, and the
  output block, evaluated, must equal the cell's value: a cell that stops
  running, or a result that drifts from the printed one, fails here.

  The remaining assertions restate the verdicts the prose relies on and tie
  the notebook's own Ed25519 arithmetic to the independent strict-Ed25519
  test fixture.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.Ed25519StrictFixture, as: StrictFixture

  @notebook Path.expand("../docs/livebooks/abp-walkthrough.livemd", __DIR__)

  setup_all do
    {cells, skipped} = notebook_cells(File.read!(@notebook))
    {results, binding} = evaluate(cells)
    %{cells: cells, skipped: skipped, results: results, binding: binding}
  end

  test "the install cell pins the current package version", %{skipped: skipped} do
    version = Mix.Project.config()[:version]

    assert [install] = skipped
    assert install =~ ~s({:agent_blueprint_protocol, "~> #{version}"})
  end

  test "every notebook cell runs, in order, and prints its pinned output", %{results: results} do
    assert results |> Enum.map(& &1.section) |> Enum.uniq() == Enum.map(1..8, &to_string/1)

    for %{section: section, line: line, value: value, output: output} <- results do
      assert output != nil,
             "the cell at line #{line} (section #{section}) has no persisted output block"

      {pinned, _binding} = Code.eval_string(output, [], file: @notebook)

      assert value == pinned,
             "the cell at line #{line} (section #{section}) evaluated to " <>
               "#{inspect(value, pretty: true)} but the notebook prints #{output}"
    end
  end

  test "the notebook's verdicts are the ones its prose states", %{results: results} do
    [composed] = section_values(results, "1")
    assert composed.content_digest =~ ~r/\Asha-256:[A-Za-z0-9_-]{43}\z/

    assert [%{round_trip_exact?: true, recomputed_digest: digest}] = section_values(results, "2")
    assert digest == composed.content_digest

    assert [%{verify: {:ok, :verified}, signed_digest_unchanged?: true}] =
             section_values(results, "3")

    [negotiated] = section_values(results, "4")
    assert negotiated.weather.quarantined_extensions == ["org.example.weather/units"]
    assert negotiated.weather.optional_retained == ["com.example.platform/estate"]
    assert negotiated.unknown_critical == {:error, :extension_unknown_critical}
    assert negotiated.revision_unsupported == {:error, :protocol_revision_unsupported}

    [reconciled] = section_values(results, "5")
    assert reconciled.binds?
    assert reconciled.deny_posture == :protected_bound_clamp_denied
    assert reconciled.without_the_producer_key == :signature_key_unsupported
    assert length(reconciled.not_verified) == 7

    index = File.read!("priv/conformance/index.json") |> JSON.decode!()
    total = index["total_cases"]

    assert [%{agreement: true, agreed: ^total, disagreed: 0, total: ^total}] =
             section_values(results, "6")

    [attacks] = section_values(results, "7")
    assert attacks.backend_accepts_small_order_forgery == true
    assert map_size(attacks.rejections) == 6

    assert Enum.all?(attacks.rejections, fn {_attack, verdict} -> match?({:error, _}, verdict) end)

    assert section_values(results, "8") == [
             %{
               honest: %{backend: true, package: {:ok, :verified}},
               identity_r: %{backend: true, package: {:error, :signature_not_verified}},
               s_plus_l: %{backend: false, package: {:error, :signature_not_verified}}
             }
           ]
  end

  test "the notebook's Ed25519 arithmetic matches the independent fixture", %{binding: binding} do
    assert binding[:l] == StrictFixture.l()
    assert binding[:identity_r] == StrictFixture.identity()
    assert StrictFixture.small_order?(binding[:small_order_key].key)

    assert binding[:identity_signature] ==
             StrictFixture.key_holder_signature(
               binding[:producer_private],
               StrictFixture.identity(),
               binding[:signing_input]
             )

    refute StrictFixture.strict_signature?(binding[:identity_signature])
    refute StrictFixture.strict_signature?(binding[:s_plus_l_signature])
    assert StrictFixture.strict_signature?(binding[:signature])
  end

  # The notebook prints that :crypto accepts its small-order forgery. That
  # must hold for every message, not by luck on the one it signs: over 200
  # envelopes naming random content digests, :crypto accepts the forgery
  # under the small-order key every time, and the package denies every one.
  test "the small-order forgery is universal for :crypto and always denied", %{
    binding: binding
  } do
    alias AgentBlueprintProtocol.{Base64Url, Digest, Signature}

    key = binding[:small_order_key]
    forgery = binding[:small_order_forgery]
    {:object, protected_members} = binding[:protected]
    {:object, attribute_members} = binding[:signed_attributes]

    verdicts =
      for _ <- 1..200 do
        digest = Digest.to_tagged(Digest.of(:crypto.strong_rand_bytes(32)))

        attributes =
          List.keystore(
            attribute_members,
            "content_digest",
            0,
            {"content_digest", {:string, digest}}
          )

        envelope =
          {:object,
           [
             {"protected", {:object, protected_members}},
             {"signed_attributes", {:object, attributes}},
             {"signature", {:string, Base64Url.encode(forgery)}}
           ]}

        {:ok, input} = Signature.signing_input(envelope)

        {:crypto.verify(:eddsa, :none, input, forgery, [key.key, :ed25519]),
         Signature.verify(envelope, [key])}
      end

    assert Enum.uniq(verdicts) == [{true, {:error, :signature_algorithm_unsupported}}]
  end

  # Splits the notebook into its elixir cells, each with the numbered
  # section it sits in, its first code line, and the persisted output block
  # that follows it (nil when absent). The Mix.install cell is returned
  # separately.
  defp notebook_cells(text) do
    {cells, _section, _state} =
      text
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reduce({[], nil, :prose}, &step/2)

    {skipped, evaluated} =
      cells |> Enum.reverse() |> Enum.split_with(&(&1.code =~ "Mix.install("))

    {evaluated, Enum.map(skipped, & &1.code)}
  end

  # One line of the notebook against the parser state: :prose, a code cell
  # being read, :after_code (a cell just closed), the output marker seen,
  # or an output block being read.
  defp step({"```", _number}, {cells, section, {:code, start, body}}) do
    cell = %{section: section, line: start, code: join(body), output: nil}
    {[cell | cells], section, :after_code}
  end

  defp step({line, _number}, {cells, section, {:code, start, body}}),
    do: {cells, section, {:code, start, [line | body]}}

  defp step({"```", _number}, {[cell | rest], section, {:output, body}}),
    do: {[%{cell | output: join(body)} | rest], section, :prose}

  defp step({line, _number}, {cells, section, {:output, body}}),
    do: {cells, section, {:output, [line | body]}}

  defp step({"```", _number}, {cells, section, :after_output_marker}),
    do: {cells, section, {:output, []}}

  defp step({"```elixir", number}, {cells, section, _state}),
    do: {cells, section, {:code, number + 1, []}}

  defp step({"<!-- livebook:{\"output\":true} -->", _number}, {cells, section, :after_code}),
    do: {cells, section, :after_output_marker}

  defp step({"", _number}, {cells, section, state})
       when state in [:after_code, :after_output_marker],
       do: {cells, section, state}

  defp step({"## " <> heading, _number}, {cells, _section, _state}),
    do: {cells, section_number(heading), :prose}

  defp step({_prose, _number}, {cells, section, _state}), do: {cells, section, :prose}

  defp join(reversed_lines), do: reversed_lines |> Enum.reverse() |> Enum.join("\n")

  defp section_number(heading) do
    case Regex.run(~r/\A(\d+)\. /, heading) do
      [_, number] -> number
      nil -> nil
    end
  end

  # Evaluates the cells in order with one shared binding and environment.
  defp evaluate(cells) do
    {results, binding, _env} =
      Enum.reduce(cells, {[], [], Code.env_for_eval(file: @notebook)}, fn cell,
                                                                          {results, binding, env} ->
        assert cell.section != nil,
               "the notebook cell at line #{cell.line} sits outside a numbered section"

        quoted = Code.string_to_quoted!(cell.code, file: @notebook, line: cell.line)
        {value, binding, env} = Code.eval_quoted_with_env(quoted, binding, env)
        {[Map.put(cell, :value, value) | results], binding, env}
      end)

    {Enum.reverse(results), binding}
  end

  defp section_values(results, section),
    do: for(%{section: ^section, value: value} <- results, do: value)
end
