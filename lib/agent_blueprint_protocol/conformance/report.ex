defmodule AgentBlueprintProtocol.Conformance.Report do
  @moduledoc """
  The pure report builder over a loaded corpus and runner results: overall
  agreement, exit status, counts.

  Refuses vacuous green: agreement requires `total > 0` AND zero
  disagreements — an empty-but-valid corpus must never verify anything.
  (The loader's `:corpus_empty` denial is the first refusal; this floor is
  the second, independent one.)

  `to_bytes/2` emits deterministic JCS-canonical bytes through the package's
  own `Canonicalization` (one canonicalizer, no second encoder) and binds
  the run to the exact corpus loaded via its recomputed identity — two runs
  over two different corpora can never produce identical report bytes.
  The report states what the corpus agreed; it is not a decision.
  """

  alias AgentBlueprintProtocol.{Canonicalization, Conformance.Corpus}

  @format "agent-blueprint-protocol-conformance-report"

  @enforce_keys [:agreement, :exit_status, :total, :agreed, :disagreed]
  defstruct [:agreement, :exit_status, :total, :agreed, :disagreed]

  @type t :: %__MODULE__{
          agreement: boolean(),
          exit_status: 0 | 1,
          total: non_neg_integer(),
          agreed: non_neg_integer(),
          disagreed: non_neg_integer()
        }

  @doc "Builds the agreement report from the loaded corpus and runner results."
  @spec build(Corpus.t(), [{binary(), [%{case_id: binary(), agree: boolean()}]}]) ::
          t() | {:error, AgentBlueprintProtocol.Error.t()}
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

  @doc "Emits deterministic JCS-canonical report bytes, identity-bound."
  @spec to_bytes(Corpus.t(), [{binary(), [%{case_id: binary(), agree: boolean()}]}]) ::
          {:ok, binary()} | {:error, AgentBlueprintProtocol.Error.t()}
  def to_bytes(%Corpus{identity: identity} = corpus, results) do
    with %__MODULE__{} = report <- build(corpus, results) do
      encode_report(identity, report)
    end
  end

  def to_bytes(_, _), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

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
