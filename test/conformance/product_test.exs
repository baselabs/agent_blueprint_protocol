defmodule AgentBlueprintProtocol.Conformance.ProductTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias AgentBlueprintProtocol.Conformance.{Cli, Corpus, Report, Runner}

  defp corpus do
    map =
      for path <- Path.wildcard("priv/conformance/**/*"),
          File.regular?(path),
          into: %{},
          do: {Path.relative_to(path, "priv/conformance"), File.read!(path)}

    {:ok, corpus} = Corpus.load(map)
    corpus
  end

  test "the complete projected census equals the certified results" do
    corpus = corpus()
    assert {:ok, bytes} = Report.results_bytes(corpus)
    assert bytes == File.read!("spec/conformance/certified-results.json")
    assert {:error, %{code: :invalid_type}} = Report.results_bytes(nil)

    for {_path, cases} <- corpus.cases, row <- cases do
      assert is_map(Runner.project(row, corpus.data, corpus.raws))
    end
  end

  test "results mode emits canonical bytes and the existing exit status" do
    output =
      capture_io(fn ->
        capture_io(:stderr, fn ->
          assert Cli.run(["--results", "--corpus", "priv/conformance"]) == 0
        end)
      end)

    assert output == File.read!("spec/conformance/certified-results.json")
  end

  test "the adapter exchanges identity and projects a request without an expected answer" do
    corpus = corpus()

    hello = %{
      "protocol" => "agent-blueprint-protocol-conformance-execution",
      "version" => 1,
      "corpus_digest" => corpus.identity,
      "registry_digest" => corpus.index["registry_digest"]
    }

    request = %{
      "id" => "example-case",
      "surface" => "predicate",
      "input" => %{
        "mode" => "validate",
        "predicate" => %{"op" => "present", "path" => ["request"]},
        "port_names" => ["request"]
      }
    }

    input = Enum.map_join([hello, request], "\n", &IO.iodata_to_binary(:json.encode(&1))) <> "\n"

    output =
      capture_io([input: input], fn ->
        capture_io(:stderr, fn ->
          assert Cli.run(["--serve", "--corpus", "priv/conformance"]) == 0
        end)
      end)

    [first, second] = String.split(output, "\n", trim: true)
    assert :json.decode(first) == hello

    assert :json.decode(second) == %{
             "id" => "example-case",
             "result" => %{"verdict" => "valid", "valid" => true}
           }

    capture_io([input: "{}\n"], fn ->
      capture_io(:stderr, fn ->
        assert Cli.run(["--serve", "--corpus", "priv/conformance"]) == 2
      end)
    end)
  end

  test "malformed composed inputs and predicate modes deny without raising" do
    row = fn surface, input ->
      %{"id" => "example-input", "surface" => surface, "input" => input, "expected" => %{}}
    end

    predicate = %{"op" => "present", "path" => ["request"]}

    for input <- [
          %{"predicate" => predicate},
          %{"predicate" => predicate, "port_names" => ["request"], "mode" => "unknown"},
          %{
            "predicate" => predicate,
            "port_names" => ["request"],
            "mode" => "evaluate",
            "ports" => nil
          }
        ] do
      assert %{"verdict" => "invalid", "code" => "invalid_type"} =
               Runner.project(row.("predicate", input), %{}, %{})
    end

    assert %{"code" => "invalid_type"} =
             Runner.project(
               row.("reconcile", %{"blueprint" => "{}", "deployment" => "{}", "inputs" => nil}),
               %{},
               %{}
             )

    assert %{"code" => "invalid_type"} = Runner.project(%{"input" => []}, %{}, %{})
  end

  test "the adapter rejects malformed and oversized lines and preserves null" do
    corpus = corpus()

    hello = %{
      "protocol" => "agent-blueprint-protocol-conformance-execution",
      "version" => 1,
      "corpus_digest" => corpus.identity,
      "registry_digest" => corpus.index["registry_digest"]
    }

    header = IO.iodata_to_binary(:json.encode(hello)) <> "\n"

    for tail <- ["[]\n", "invalid\n", String.duplicate("x", 5_000_001) <> "\n", "{}"] do
      capture_io([input: header <> tail], fn ->
        capture_io(:stderr, fn ->
          assert Cli.run(["--serve", "--corpus", "priv/conformance"]) == 2
        end)
      end)
    end

    request =
      ~s({"id":"example-null","surface":"json.decode","input":{"text":"null","unused":null}}) <>
        "\n"

    output =
      capture_io([input: header <> request], fn ->
        capture_io(:stderr, fn ->
          assert Cli.run(["--serve", "--corpus", "priv/conformance"]) == 0
        end)
      end)

    assert output =~ ~s("value":null)
  end
end
