defmodule AgentBlueprintProtocol.Conformance.Report do
  @moduledoc """
    This module builds deterministic reports from corpus results.

    Use it when summarizing agreement and encoding a report for a loaded corpus.

    This module does not authorize operations.

    ## Example

    ```elixir
    corpus_root = Application.app_dir(:agent_blueprint_protocol, "priv/conformance")
    files =
      Path.wildcard(Path.join(corpus_root, "**/*"))
      |> Enum.filter(&File.regular?/1)
      |> Map.new(fn path ->
        {Path.relative_to(path, corpus_root), File.read!(path)}
      end)
    {:ok, corpus} = AgentBlueprintProtocol.Conformance.Corpus.load(files)
    results = AgentBlueprintProtocol.Conformance.Runner.run(corpus)
    match?(%AgentBlueprintProtocol.Conformance.Report{}, AgentBlueprintProtocol.Conformance.Report.build(corpus, results))
    ```
  """
  @moduledoc since: "1.0.0"

  alias AgentBlueprintProtocol.{Canonicalization, Conformance.Corpus, Conformance.Runner}

  @format "agent-blueprint-protocol-conformance-report"

  @enforce_keys [:agreement, :exit_status, :total, :agreed, :disagreed]
  defstruct [:agreement, :exit_status, :total, :agreed, :disagreed]

  @typedoc """
    The public data type for AgentBlueprintProtocol.Conformance.Report.
  """
  @type t :: %__MODULE__{
          agreement: boolean(),
          exit_status: 0 | 1,
          total: non_neg_integer(),
          agreed: non_neg_integer(),
          disagreed: non_neg_integer()
        }

  @spec build(Corpus.t(), [{binary(), [%{case_id: binary(), agree: boolean()}]}]) ::
          t() | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
    Summarizes the outcomes for each case in a loaded corpus.

    ## Example

    ```elixir
    corpus_root = Application.app_dir(:agent_blueprint_protocol, "priv/conformance")
    files =
      Path.wildcard(Path.join(corpus_root, "**/*"))
      |> Enum.filter(&File.regular?/1)
      |> Map.new(fn path ->
        {Path.relative_to(path, corpus_root), File.read!(path)}
      end)

    {:ok, corpus} = AgentBlueprintProtocol.Conformance.Corpus.load(files)
    results = AgentBlueprintProtocol.Conformance.Runner.run(corpus)
    match?(%AgentBlueprintProtocol.Conformance.Report{}, AgentBlueprintProtocol.Conformance.Report.build(corpus, results))
    ```
  """
  @doc since: "1.0.0"
  def build(%Corpus{}, results) when is_list(results) do
    if results_ok?(results),
      do: build_results(results),
      else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
  end

  def build(_, _), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp results_ok?([]), do: true

  defp results_ok?([{path, rows} | rest]) when is_binary(path),
    do: rows_ok?(rows) and results_ok?(rest)

  defp results_ok?(_), do: false

  defp rows_ok?([]), do: true

  defp rows_ok?([%{case_id: id, agree: agree} | rest]) when is_binary(id) and is_boolean(agree),
    do: rows_ok?(rest)

  defp rows_ok?(_), do: false

  defp build_results(results) do
    all = results |> Enum.flat_map(&elem(&1, 1))

    total = length(all)
    agreed = Enum.count(all, & &1.agree)
    disagreed = total - agreed
    agreement = total > 0 and disagreed == 0

    %__MODULE__{
      agreement: agreement,
      exit_status: if(agreement, do: 0, else: 1),
      total: total,
      agreed: agreed,
      disagreed: disagreed
    }
  end

  @spec to_bytes(Corpus.t(), [{binary(), [%{case_id: binary(), agree: boolean()}]}]) ::
          {:ok, binary()} | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
    Encodes the report as canonical JSON bytes.

    ## Example

    ```elixir
    corpus_root = Application.app_dir(:agent_blueprint_protocol, "priv/conformance")
    files =
      Path.wildcard(Path.join(corpus_root, "**/*"))
      |> Enum.filter(&File.regular?/1)
      |> Map.new(fn path ->
        {Path.relative_to(path, corpus_root), File.read!(path)}
      end)

    {:ok, corpus} = AgentBlueprintProtocol.Conformance.Corpus.load(files)
    results = AgentBlueprintProtocol.Conformance.Runner.run(corpus)
    match?(
      {:ok, bytes} when is_binary(bytes),
      AgentBlueprintProtocol.Conformance.Report.to_bytes(corpus, results)
    )
    ```
  """
  @doc since: "1.0.0"
  def to_bytes(%Corpus{identity: identity} = corpus, results) do
    with %__MODULE__{} = report <- build(corpus, results) do
      encode_report(identity, report)
    end
  end

  def to_bytes(_, _), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  @doc false
  @spec results_bytes(Corpus.t()) :: {:ok, binary()} | {:error, AgentBlueprintProtocol.Error.t()}
  def results_bytes(%Corpus{} = corpus) do
    rows =
      for {_path, cases} <- corpus.cases, row <- cases do
        %{
          "id" => row["id"],
          "surface" => row["surface"],
          "result" => Runner.project(row, corpus.data, corpus.raws)
        }
      end

    document = %{
      "format" => "agent-blueprint-protocol-conformance-results",
      "corpus_digest" => corpus.identity,
      "registry_digest" => corpus.index["registry_digest"],
      "results" => Enum.sort_by(rows, & &1["id"])
    }

    Canonicalization.encode(tagged(document))
  end

  def results_bytes(_), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp tagged(nil), do: :null
  defp tagged(value) when is_boolean(value), do: {:boolean, value}
  defp tagged(value) when is_integer(value), do: {:integer, value}
  defp tagged(value) when is_float(value), do: {:float, value}
  defp tagged(value) when is_binary(value), do: {:string, value}
  defp tagged(value) when is_list(value), do: {:array, Enum.map(value, &tagged/1)}

  defp tagged(value) when is_map(value),
    do: {:object, Enum.map(value, fn {k, v} -> {k, tagged(v)} end)}

  defp encode_report(identity, report) do
    value =
      {:object,
       [
         {"format", {:string, @format}},
         {"agreement", {:boolean, report.agreement}},
         {"exit_status", {:integer, report.exit_status}},
         {"total", {:integer, report.total}},
         {"agreed", {:integer, report.agreed}},
         {"disagreed", {:integer, report.disagreed}},
         {"corpus_digest", {:string, identity}}
       ]}

    Canonicalization.encode(value)
  end
end
