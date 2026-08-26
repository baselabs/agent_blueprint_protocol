defmodule AgentBlueprintProtocol.Architecture.DocumentCitationGateTest do
  @moduledoc """
  Document-citation gate: a shipped document may only cite documents that
  exist. Two citation forms are checked across every markdown file the
  package ships:

  - a NAMED section citation (`A2A §7.6.4`, `ECMA-262 §7.1.12.1`) names a
    document immediately before the `§` — that document must be a pinned
    external standard or a shipped in-repo document; a citation of a
    document that exists nowhere (the historical `base §6` form) reds;
  - every markdown link target without a scheme must resolve to a file in
    this repository, as must every GitHub blob/tree URL into this
    repository.

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
          path <- repo_path(target),
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

  defp repo_doc_stems do
    (Path.wildcard("*.md") ++ Path.wildcard("docs/**/*.md"))
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

  defp link_targets(source) do
    ~r/\]\(\s*([^)\s]+)\s*\)/
    |> Regex.scan(source)
    |> Enum.map(fn [_, target] -> target end)
  end

  # A target resolves to a repo file when it is relative (no scheme) or a
  # GitHub blob/tree URL into this repository; other URLs and pure anchors
  # are external and not checked.
  defp repo_path(target) do
    cond do
      String.contains?(target, "://") -> github_repo_path(target)
      String.starts_with?(target, "#") or String.starts_with?(target, "mailto:") -> []
      true -> [strip_anchor(target)]
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
