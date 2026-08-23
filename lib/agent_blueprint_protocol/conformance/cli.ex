defmodule AgentBlueprintProtocol.Conformance.Cli do
  @moduledoc """
  The conformance CLI : `--corpus <dir>` is REQUIRED
  — no default, so a vacuous run is impossible — and the exit status is the
  agreement verdict:

  - `0` complete agreement;
  - `1` any disagreement;
  - `2` usage error or corpus integrity failure.

  This module and its `Main` entry are the ONLY filesystem touchers in the
  package (the `no_file_access` architecture gate carves out exactly these
  beams). Everything downstream of reading the directory is the pure
  loader/runner/report.
  The CLI reports conformance facts; it never authorizes anything.
  The CLI reports conformance facts; it never authorizes anything.
  """

  alias AgentBlueprintProtocol.Conformance.{Corpus, Report, Runner}

  @usage "usage: agent_blueprint_protocol_conformance --corpus <dir>"

  @doc """
  Runs the CLI over `argv`. Returns the exit status (never halts — the
  escript entry owns `System.halt/1`).
  """
  @spec run([binary()]) :: 0 | 1 | 2
  def run(argv) do
    with {:ok, dir} <- parse(argv),
         {:ok, map} <- read_corpus(dir),
         {:ok, corpus} <- Corpus.load(map) do
      results = Runner.run(corpus)
      report = Report.build(corpus, results)

      # The report shape is fixed and fully canonicalizable, so encoding
      # cannot fail; a mismatch here is an internal invariant and escapes
      # loudly rather than laundering into an exit code.
      {:ok, bytes} = Report.to_bytes(corpus, results)
      IO.binwrite(bytes)
      report.exit_status
    else
      :usage ->
        IO.puts(:stderr, @usage)
        2

      :unreadable ->
        # Value-free by construction: no path rides the channel.
        IO.puts(
          :stderr,
          "corpus unreadable: a file is missing, unreadable, or over the byte ceiling"
        )

        2

      {:error, %_{} = error} ->
        IO.puts(:stderr, "corpus integrity failure: #{inspect(error.code)}")
        2
    end
  end

  defp parse(["--corpus", dir]) when is_binary(dir) and dir != "", do: {:ok, dir}
  defp parse(_), do: :usage

  # Reads EVERY file under the corpus directory — dotfiles included — so the
  # loader's file-set equality sees exactly what the directory carries.
  # The read is size-capped and total-failure typed: a hostile corpus
  # directory cannot exhaust memory or crash past the exit-code contract
  # (Bounds' byte ceiling is the single resource regime, applied here at
  # the byte source rather than only at decode).
  defp read_corpus(dir) do
    files =
      dir
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(&File.dir?/1)

    cap = AgentBlueprintProtocol.Bounds.maximum().bytes

    files
    |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, acc} ->
      rel = Path.relative_to(path, dir)

      with {:ok, stat} <- File.stat(path),
           true <- stat.size <= cap,
           {:ok, bytes} <- File.read(path) do
        {:cont, {:ok, Map.put(acc, rel, bytes)}}
      else
        _ -> {:halt, :unreadable}
      end
    end)
    |> case do
      {:ok, map} -> {:ok, map}
      :unreadable -> :unreadable
    end
  end
end
