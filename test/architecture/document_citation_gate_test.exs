defmodule AgentBlueprintProtocol.Architecture.DocumentCitationGateTest do
  @moduledoc """
  Document-citation gate: a shipped document may only cite documents that
  exist. Two citation forms are checked across every markdown file the
  package ships:

  - a NAMED section citation (`A2A §7.6.4`, `ECMA-262 §7.1.12.1`) names a
    document immediately before the `§` — that document must be a pinned
    external standard or another document in the SHIPPED set (a citation
    of a repo-only or nonexistent document reds equally);
  - every markdown link target without a scheme must resolve, relative
    to the directory of the document containing it, to a file in this
    repository, as must every GitHub blob/tree URL into this repository
    (those are repository-root-relative).

  Bare section numbers (`§3.2.2.2`) and requirement numbers after a
    standard's designation (`RFC 4648 §3.3`) inherit their target from the
  surrounding prose and are not checked. The gate's own allowlist names
  what it permits, as does this moduledoc.
  """

  use ExUnit.Case, async: true

  @external_standards ~w(A2A MCP RFC ECMA-262 FIPS JOSE JCS)

  test "named section citations name a shipped document or a pinned standard" do
    allowed = MapSet.new(@external_standards ++ repo_doc_stems())

    offenders =
      for file <- shipped_markdown(),
          source = File.read!(file),
          token <- citation_tokens(source),
          not MapSet.member?(allowed, token),
          uniq: true do
        {file, token}
      end

    assert offenders == [],
           "a shipped document cites a document that exists nowhere:\n" <>
             Enum.map_join(offenders, "\n", fn {file, token} ->
               "  #{file}: \"#{token} §…\" names no shipped document or standard"
             end)
  end

  test "shipped markdown links resolve to real files" do
    offenders =
      for file <- shipped_markdown(),
          source = File.read!(file),
          target <- link_targets(source),
          path <- repo_path(file, target),
          not File.exists?(path),
          uniq: true do
        {file, target}
      end

    assert offenders == [],
           "a shipped document links to a file that does not exist:\n" <>
             Enum.map_join(offenders, "\n", fn {file, target} ->
               "  #{file}: #{target} resolves to no file in this repository"
             end)
  end

  # The scanned set is exactly the markdown the package ships — a document
  # outside the archive may cite repo-only documents freely.
  defp shipped_markdown do
    Mix.Project.config()[:package][:files]
    |> Enum.filter(&String.ends_with?(&1, ".md"))
    |> Enum.sort()
  end

  # The citation allowlist stems from the SHIPPED set only: a shipped
  # document citing a repo-only document by name is as dangling as citing
  # one that exists nowhere, for a reader of the archive.
  defp repo_doc_stems do
    shipped_markdown()
    |> Enum.map(&Path.basename(&1, ".md"))
  end

  # Captures the document token naming a section: `A2A §7.6.4` → "A2A",
  # `base-§8.2` → "base". Numeric or absent prefixes (bare `§3.2.2.2`,
  # `RFC 4648 §3.3`) match nothing and stay unchecked by construction.
  defp citation_tokens(source) do
    ~r/\b([A-Za-z][A-Za-z0-9-]*?)[- ]?§\s*\d/
    |> Regex.scan(source)
    |> Enum.map(fn [_, token] -> token end)
  end

  # Markdown link destinations in every shipped-relevant form: inline
  # `[x](target)`, `[x](target "title")`, `[x](<target file>)`, and
  # reference definitions (`[x]: target`). Schemed URLs and anchors are
  # filtered by repo_path.
  defp link_targets(source) do
    inline =
      ~r/\]\(\s*(?:<([^>]*)>|([^)\s>]+))(?:\s+"[^"]*")?\s*\)/
      |> Regex.scan(source)
      |> Enum.map(&angle_or_bare(Enum.at(&1, 1), Enum.at(&1, 2)))

    references =
      ~r/^\s{0,3}\[[^\]]+\]:\s*(?:<([^>]*)>|(\S+))/m
      |> Regex.scan(source)
      |> Enum.map(&angle_or_bare(Enum.at(&1, 1), Enum.at(&1, 2)))

    (inline ++ references) |> Enum.reject(&(&1 in [nil, ""]))
  end

  # Unmatched alternation groups come back absent (nil) or empty — both
  # fall through to the other arm.
  defp angle_or_bare(nil, bare), do: bare
  defp angle_or_bare("", bare), do: bare
  defp angle_or_bare(angle, _bare), do: angle

  # A target resolves to a repo file when it is relative to the CONTAINING
  # document's directory (markdown link semantics; GitHub blob/tree URLs
  # are repository-root-relative); other URLs and pure anchors are
  # external and not checked.
  defp repo_path(file, target) do
    cond do
      String.contains?(target, "://") -> github_repo_path(target)
      String.starts_with?(target, "#") or String.starts_with?(target, "mailto:") -> []
      true -> [Path.expand(strip_anchor(target), Path.dirname(Path.expand(file)))]
    end
  end

  defp github_repo_path(url) do
    case Regex.run(
           ~r{^https://github\.com/baselabs/agent_blueprint_protocol/(?:blob|tree)/[^/]+/(.+)$},
           url
         ) do
      [_, path] -> [strip_anchor(path)]
      nil -> []
    end
  end

  defp strip_anchor(path), do: path |> String.split("#") |> hd()
end
