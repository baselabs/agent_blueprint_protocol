# The specification-extraction check: spec/ + priv/conformance extract as
# a standalone tree that renders with no dangling references.
#
#   mix spec.extraction                # extract the working tree's two paths
#   mix spec.extraction --tree <dir>   # verify an ALREADY-extracted tree
#
# Asserts over the extracted tree:
#   1. the required members exist (specification document, directory
#      README, license copies, corpus index);
#   2. every relative markdown link resolves, relative to its containing
#      document, INSIDE the extracted tree — a repository-relative
#      citation dangles post-extraction and reds;
#   3. a named section citation names a pinned external standard or a
#      document inside the extracted tree;
#   4. no `../` or `docs/` path literal appears in the specification's
#      markdown (self-containment by construction).
#
# The local form copies the working tree's two paths into a scratch; the
# continuous-integration workflow runs the literal repository-filter
# extraction (git filter-repo --path spec/ --path priv/conformance) and
# re-runs this script with --tree over the result — both forms share
# these assertions, so the extraction is tested on every run and every
# push.

defmodule AgentBlueprintProtocol.SpecExtractionCheck do
  @required_members [
    "spec/protocol.md",
    "spec/README.md",
    "spec/LICENSE",
    "spec/NOTICE",
    "spec/grammar/blueprint.cddl",
    "spec/grammar/deployment.cddl",
    "spec/grammar/taskenvelope.cddl",
    "spec/grammar/derived/blueprint.schema.json",
    "spec/grammar/derived/deployment.schema.json",
    "spec/grammar/derived/taskenvelope.schema.json",
    "spec/registry/registry.json",
    "priv/conformance/index.json"
  ]

  @external_standards ~w(A2A MCP RFC ECMA-262 FIPS JOSE JCS)

  def run do
    case System.argv() do
      [] ->
        scratch = scratch_dir()

        try do
          File.mkdir_p!(scratch)
          File.mkdir_p!(Path.join(scratch, "priv"))
          {:ok, _} = File.cp_r("spec", Path.join(scratch, "spec"))
          {:ok, _} = File.cp_r("priv/conformance", Path.join(scratch, "priv/conformance"))
          verify(scratch)
        after
          File.rm_rf!(scratch)
        end

      ["--tree", tree] ->
        verify(tree)
    end
  end

  defp verify(tree) do
    findings =
      shape_findings(tree) ++
        link_findings(tree) ++
        citation_findings(tree) ++
        containment_findings(tree)

    if findings != [] do
      raise """
      spec extraction: FAILED

      #{Enum.join(findings, "\n")}
      """
    end

    count =
      tree
      |> Path.join("spec/**/*.md")
      |> Path.wildcard()
      |> length()

    IO.puts("spec extraction: ok (#{count} markdown files render self-contained)")
  end

  defp shape_findings(tree) do
    for member <- @required_members, not File.exists?(Path.join(tree, member)) do
      "extraction shape: #{member} is missing from the extracted tree"
    end
  end

  defp link_findings(tree) do
    for file <- markdown_files(tree),
        target <- link_targets(File.read!(Path.join(tree, file))),
        path <- in_tree_path(file, target),
        not File.exists?(Path.join(tree, path)),
        uniq: true do
      "dangling reference: #{file} links #{target}, which is absent from the extracted tree"
    end
  end

  defp citation_findings(tree) do
    stems =
      tree
      |> markdown_files()
      |> Enum.map(&Path.basename(&1, ".md"))

    allowed = MapSet.new(@external_standards ++ stems)

    for file <- markdown_files(tree),
        token <- citation_tokens(File.read!(Path.join(tree, file))),
        not MapSet.member?(allowed, token),
        uniq: true do
      "dangling citation: #{file} cites \"#{token} §…\", which names no " <>
        "external standard or in-tree document"
    end
  end

  defp containment_findings(tree) do
    for file <- markdown_files(tree),
        content = File.read!(Path.join(tree, file)) |> strip_external_urls(),
        pattern <- ["../", "docs/"],
        String.contains?(content, pattern) do
      "self-containment: #{file} carries the path literal #{inspect(pattern)} — " <>
        "a repository-relative reference that dangles post-extraction"
    end
  end

  # Schemed URLs are external by the link rule; the path-literal scan
  # runs over content with them removed, so an external URL containing
  # "docs/" cannot false-red the containment check.
  defp strip_external_urls(content), do: String.replace(content, ~r/[a-z]+:\/\/\S+/, "")

  defp markdown_files(tree) do
    tree
    |> Path.join("spec/**/*.md")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, tree))
    |> Enum.sort()
  end

  # Markdown link destinations in every shipped-relevant form: inline
  # `[x](target)`, `[x](target "title")`, `[x](<target file>)`, and
  # reference definitions (`[x]: target`). Schemed URLs and anchors are
  # filtered by the caller.
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

  # A target is checked when it is relative to the containing document
  # (markdown link semantics); schemed URLs and pure anchors are external.
  defp in_tree_path(file, target) do
    cond do
      String.contains?(target, "://") -> []
      String.starts_with?(target, "#") or String.starts_with?(target, "mailto:") -> []
      true -> [relativize(Path.dirname(file), strip_anchor(target))]
    end
  end

  # Resolves a target relative to its containing document into a
  # tree-relative path; `..` clamps at the tree root (an out-of-tree
  # reference then resolves to a missing file and reds as dangling).
  defp relativize(dir, target) do
    (Path.split(dir) ++ Path.split(target))
    |> Enum.reduce([], fn
      ".", acc -> acc
      "..", [_ | acc] -> acc
      "..", [] -> []
      segment, acc -> [segment | acc]
    end)
    |> Enum.reverse()
    |> Enum.join("/")
  end

  defp strip_anchor(path), do: path |> String.split("#") |> hd()

  # Captures the document token naming a section (`A2A §7.6.4` → "A2A");
  # numeric or absent prefixes inherit their target from prose.
  defp citation_tokens(source) do
    ~r/\b([A-Za-z][A-Za-z0-9-]*?)[- ]?§\s*\d/
    |> Regex.scan(source)
    |> Enum.map(fn [_, token] -> token end)
  end

  # Unpredictable scratch names in the world-writable temp dir (the same
  # pre-planted-symlink posture as the release-candidate scratches).
  defp scratch_dir do
    rand = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    Path.join(System.tmp_dir!(), "abp-spec-extraction-#{rand}")
  end
end

AgentBlueprintProtocol.SpecExtractionCheck.run()
