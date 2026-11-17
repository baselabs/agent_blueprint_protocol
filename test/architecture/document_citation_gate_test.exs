defmodule AgentBlueprintProtocol.Architecture.DocumentCitationGateTest do
  @moduledoc """
  Document-citation gate: a shipped document may only cite documents that
  exist. Shipped text also carries no em or en dash. Its surface is derived
  from the Hex files, ExDoc extras, npm packed files and build inputs,
  TypeScript source inputs, site, issue templates, and the release title
  and notes the publish workflow writes. Citation forms are
  checked across every markdown file the package ships:

  - a NAMED section citation (`A2A §7.6.4`, `ECMA-262 §7.1.12.1`) names a
    document immediately before the `§` — that document must be a pinned
    external standard or another document in the SHIPPED set (a citation
    of a repo-only or nonexistent document reds equally);
  - published HTML links and anchors must resolve inside the generated
    documentation, including every ExDoc extra and module page;
  - every markdown link target without a scheme must resolve, relative
    to the directory of the document containing it, to a packaged file.
    Every GitHub blob/tree URL into this repository must resolve to a
    repository file (those are repository-root-relative).

  Bare section numbers (`§3.2.2.2`) and requirement numbers after a
    standard's designation (`RFC 4648 §3.3`) inherit their target from the
  surrounding prose and are not checked. The gate's own allowlist names
  what it permits, as does this moduledoc.
  """

  use ExUnit.Case, async: true, group: :project_build

  @moduletag timeout: :infinity

  @external_standards ~w(A2A MCP RFC ECMA-262 FIPS JOSE JCS)
  @root Path.expand("../..", __DIR__)

  test "shipped documents carry no em or en dash" do
    documents = shipped_documents()
    assert documents != []
    assert "CHANGELOG.md" in documents
    assert "spec/protocol.md" in documents
    assert Enum.any?(documents, &String.starts_with?(&1, "lib/"))
    assert Enum.any?(documents, &String.match?(&1, ~r{^site/.*\.html$}))
    assert "verifier/README.md" in documents

    offenders =
      for {file, source, first_line} <-
            Enum.map(documents, &{&1, File.read!(&1), 1}) ++
              kit_generated_text() ++ release_text(),
          String.valid?(source),
          {line, number} <- source |> String.split("\n") |> Enum.with_index(first_line),
          String.contains?(line, ["\u2014", "\u2013"]),
          do: "#{file}:#{number}: #{line}"

    assert offenders == [],
           "shipped documents carry an em or en dash:\n" <> Enum.join(offenders, "\n")
  end

  defp shipped_documents do
    config = Mix.Project.config()
    build = File.read!("scripts/build_kit.mjs")

    # Source inputs to the kit (including the README renamed in the archive).
    inputs =
      for [_, arguments] <- Regex.scan(~r/join\(root,\s*((?:"[^"]+"\s*,?\s*)+)/, build) do
        ~r/"([^"]+)"/
        |> Regex.scan(arguments)
        |> Enum.map(fn [_, part] -> part end)
        |> Path.join()
      end

    packed =
      Jason.decode!(File.read!("package.json"))["files"]
      |> Enum.reject(&String.starts_with?(&1, "!"))
      |> Enum.map(&String.replace_prefix(&1, "dist/", ""))

    inputs = Enum.reject(inputs, &(&1 == "dist" or String.starts_with?(&1, "dist/")))
    sources = Jason.decode!(File.read!("tsconfig.json"))["include"]

    (config[:package][:files] ++
       config[:docs][:extras] ++ sources ++ inputs ++ packed ++ ["site", ".github/ISSUE_TEMPLATE"])
    |> Enum.flat_map(&document_files/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # The builder's template literals become shipped text without a source file
  # of their own. Report their original script line, including in clean replicas.
  defp kit_generated_text do
    file = "scripts/build_kit.mjs"
    build = File.read!(file)
    templates = Regex.scan(~r/(?:const|let) \w+ = `([^`]+)`;/s, build, return: :index)
    assert templates != []

    for [_whole, {offset, size}] <- templates do
      first_line = build |> binary_part(0, offset) |> String.split("\n") |> length()
      {file, binary_part(build, offset, size), first_line}
    end
  end

  # The published release's own text: every title and notes argument a
  # workflow passes to `gh release`.
  defp release_text do
    lines =
      for file <- Path.wildcard(".github/workflows/*.yml"),
          {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          String.match?(line, ~r/--(?:title|notes)\b/),
          do: {file, line, number}

    assert Enum.any?(lines, fn {_file, line, _number} -> line =~ "--title" end)
    lines
  end

  defp document_files(pattern) do
    pattern
    |> Path.wildcard(match_dot: true)
    |> Enum.flat_map(&document_match/1)
    |> Enum.filter(&File.regular?/1)
  end

  defp document_match(path) do
    if File.dir?(path) do
      for relative <- :filelib.wildcard(~c"**/*", String.to_charlist(path)),
          do: Path.join(path, List.to_string(relative))
    else
      [path]
    end
  end

  test "versioned repository links pin the release and resolve locally" do
    expected_ref = "v" <> Mix.Project.config()[:version]

    documents =
      Enum.map(versioned_documents(), &{&1, link_targets(File.read!(&1))}) ++
        [
          {"mix.exs package Specification",
           [Mix.Project.config()[:package][:links]["Specification"]]}
        ]

    offenders =
      for {file, targets} <- documents,
          target <- targets,
          reason <- versioned_link_offences(target, expected_ref),
          uniq: true,
          do: "#{file}: #{target}; expected ref #{expected_ref}; #{reason}"

    assert offenders == [], Enum.join(offenders, "\n")

    root = "https://github.com/baselabs/agent_blueprint_protocol"
    valid = root <> "/blob/#{expected_ref}/spec/protocol.md"
    assert versioned_link_offences(valid, expected_ref) == []

    assert versioned_link_offences(root <> "/tree/#{expected_ref}/spec/conformance", expected_ref) ==
             []

    for invalid <- [
          String.replace(valid, expected_ref, "main"),
          String.replace(valid, expected_ref, "v0.0.0"),
          String.replace(valid, "spec/protocol.md", "spec/missing-link-probe.md"),
          root
        ] do
      assert versioned_link_offences(invalid, expected_ref) != []
    end
  end

  test "HexDocs extras link directly to other rendered extras" do
    extras = MapSet.new(Mix.Project.config()[:docs][:extras])

    offenders =
      for file <- extras,
          target <- link_targets(File.read!(file)),
          %{kind: "blob", path: path} <- github_repo_path(target),
          MapSet.member?(extras, path),
          do: "#{file}: #{target}; use the relative extra #{path}"

    assert offenders == [], Enum.join(offenders, "\n")
  end

  defp versioned_documents do
    (["README.md", "verifier/README.md"] ++
       Enum.flat_map(~w(documentation spec docs/livebooks site), fn directory ->
         for relative <- :filelib.wildcard(~c"**/*", String.to_charlist(directory)),
             do: Path.join(directory, List.to_string(relative))
       end))
    |> Enum.filter(&File.regular?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp versioned_link_offences(target, expected_ref) do
    for link <- github_repo_path(target),
        link.kind in ["blob", "tree", nil],
        not live_repository_route?(target),
        reason <- [
          link.repo != "agent_blueprint_protocol" && "unexpected repository link",
          link.ref != expected_ref && "found ref #{inspect(link.ref)}",
          not repository_path_exists?(link) && "no matching repository file or directory"
        ],
        is_binary(reason),
        do: reason
  end

  defp live_repository_route?(target) do
    uri = URI.parse(target)

    Regex.match?(
      ~r{^/baselabs/agent_blueprint_protocol/(?:actions/|issues|security|releases)},
      uri.path || ""
    )
  end

  defp repository_path_exists?(%{kind: kind, path: path}) when kind in ["blob", "tree"] do
    absolute = Path.expand(path, @root)
    within_repo = absolute == @root or String.starts_with?(absolute, @root <> "/")
    within_repo and if(kind == "blob", do: File.regular?(absolute), else: File.dir?(absolute))
  end

  defp repository_path_exists?(_link), do: false

  test "published documentation links resolve to a published page and anchor" do
    root = AgentBlueprintProtocol.Scratch.dir!("published-docs")
    on_exit(fn -> File.rm_rf!(root) end)

    {output, status} =
      System.cmd("mix", ["docs", "--warnings-as-errors", "--output", root],
        stderr_to_stdout: true
      )

    assert status == 0, output

    pages =
      for relative <- :filelib.wildcard(~c"*.html", String.to_charlist(root)),
          not Enum.any?(Path.split(List.to_string(relative)), &String.starts_with?(&1, ".")),
          do: Path.join(root, List.to_string(relative))

    published =
      for(
        relative <- :filelib.wildcard(~c"**/*", String.to_charlist(root)),
        not Enum.any?(Path.split(List.to_string(relative)), &String.starts_with?(&1, ".")),
        do: Path.join(root, List.to_string(relative))
      )
      |> Enum.filter(&File.regular?/1)

    assert pages != []
    assert published_target?(hd(pages), URI.parse("#content"), published)
    refute published_target?(hd(pages), URI.parse("#missing-anchor-probe"), published)

    offenders =
      for page <- pages,
          [_, target] <- Regex.scan(~r/<a\b[^>]*\bhref="([^"]+)"/, File.read!(page)),
          uri = URI.parse(target),
          is_nil(uri.scheme) and is_nil(uri.host) and
            not published_target?(page, uri, published),
          uniq: true,
          do: {Path.basename(page), target}

    assert offenders == [], "unpublished documentation links: #{inspect(offenders)}"
  end

  test "public ExDoc footer links use the package and preview routes for this version" do
    root = AgentBlueprintProtocol.Scratch.dir!("footer-docs")
    on_exit(fn -> File.rm_rf!(root) end)

    {output, status} =
      System.cmd("mix", ["docs", "--warnings-as-errors", "--output", root],
        stderr_to_stdout: true
      )

    assert status == 0, output
    html = File.read!(Path.join(root, "readme.html"))
    version = Mix.Project.config()[:version]
    assert html =~ ~s(href="https://hex.pm/packages/agent_blueprint_protocol/#{version}")
    assert html =~ ~s(href="https://preview.hex.pm/preview/agent_blueprint_protocol/#{version}")
    refute Mix.Project.config()[:docs][:footer] == false
  end

  defp published_target?(page, uri, pages) do
    target =
      if uri.path in [nil, ""],
        do: page,
        else: Path.expand(URI.decode(uri.path), Path.dirname(page))

    target in pages and
      (uri.fragment in [nil, ""] or
         URI.decode(uri.fragment) in Enum.map(
           Regex.scan(~r/\bid="([^"]+)"/, File.read!(target)),
           fn [_, id] -> id end
         ))
  end

  test "named section citations name a shipped document or a pinned standard" do
    allowed = MapSet.new(@external_standards ++ repo_doc_stems())

    offenders =
      for {file, source} <-
            Enum.map(shipped_markdown(), &{&1, File.read!(&1)}) ++ private_citations(),
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

  test "shipped markdown links resolve to packaged files" do
    packaged =
      Mix.Project.config()[:package][:files]
      |> Enum.flat_map(&document_files/1)
      |> Enum.map(&Path.expand/1)
      |> MapSet.new()

    unpackaged_extras =
      Mix.Project.config()[:docs][:extras]
      |> Enum.reject(&MapSet.member?(packaged, Path.expand(&1)))

    assert unpackaged_extras == [],
           "HexDocs extras outside the package: #{inspect(unpackaged_extras)}"

    offenders =
      for file <- shipped_markdown(),
          source = File.read!(file),
          target <- link_targets(source),
          is_nil(URI.parse(target).scheme),
          path <- repo_path(file, target),
          not MapSet.member?(packaged, path),
          uniq: true,
          do: {file, target}

    assert offenders == [],
           "a shipped document links outside the package: #{inspect(offenders)}"

    repo_offenders =
      for file <- Enum.uniq(shipped_markdown() ++ versioned_documents()),
          target <- link_targets(File.read!(file)),
          path <- repo_path(file, target),
          not File.exists?(path),
          uniq: true,
          do: {file, target}

    assert repo_offenders == [],
           "a public document links to a file that does not exist: #{inspect(repo_offenders)}"
  end

  defp private_citations do
    for file <- Path.wildcard("{lib,verifier,test,scripts}/**/*"),
        File.regular?(file),
        source = File.read!(file),
        Regex.match?(~r/\bbase[-\s]*§/i, source),
        do: {file, "base" <> " §1"}
  end

  # The scanned set is exactly the markdown the package ships — a document
  # outside the archive may cite repo-only documents freely. Directory
  # entries ("documentation") are expanded: filtering the entries list by
  # extension alone skipped every guide inside them. Livebooks (.livemd)
  # are shipped documents with the same link semantics.
  defp shipped_markdown do
    Mix.Project.config()[:package][:files]
    |> Enum.flat_map(&markdown_entry/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp markdown_entry(entry) do
    cond do
      String.ends_with?(entry, [".md", ".livemd", ".cheatmd"]) ->
        [entry]

      File.dir?(entry) ->
        for relative <-
              :filelib.wildcard(~c"**/*.{md,livemd,cheatmd}", String.to_charlist(entry)),
            not Enum.any?(Path.split(List.to_string(relative)), &String.starts_with?(&1, ".")),
            do: Path.join(entry, List.to_string(relative))

      true ->
        []
    end
  end

  # The citation allowlist stems from the SHIPPED set only: a shipped
  # document citing a repo-only document by name is as dangling as citing
  # one that exists nowhere, for a reader of the archive.
  defp repo_doc_stems do
    shipped_markdown()
    |> Enum.map(&(&1 |> Path.basename(".md") |> Path.basename(".livemd")))
  end

  # Captures the document token naming a section: `A2A §7.6.4` → "A2A",
  # `protocol-§5` → "protocol". Numeric or absent prefixes (bare `§3.2.2.2`,
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

    html =
      ~r/\b(?:href|src)=(?:"([^"]+)"|'([^']+)')/
      |> Regex.scan(source)
      |> Enum.map(&angle_or_bare(Enum.at(&1, 1), Enum.at(&1, 2)))

    repository_urls =
      ~r{https?://github\.com/baselabs/agent_blueprint_protocol(?:/[^\s<>"')\]]*)?}
      |> Regex.scan(source)
      |> Enum.map(&hd/1)

    (inline ++ references ++ html ++ repository_urls)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
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
      is_binary(URI.parse(target).scheme) ->
        for %{kind: kind, path: path} <- github_repo_path(target),
            kind in ["blob", "tree"],
            do: Path.expand(path, @root)

      String.starts_with?(target, "#") or String.starts_with?(target, "mailto:") ->
        []

      true ->
        [Path.expand(strip_anchor(target), Path.dirname(Path.expand(file)))]
    end
  end

  defp github_repo_path(url) do
    case URI.parse(url) do
      %URI{host: "github.com", path: path} when is_binary(path) ->
        case String.split(URI.decode(path), "/", parts: 6) do
          ["", "baselabs", "agent_blueprint_protocol" = repo | rest] ->
            [repository_target(repo, rest)]

          _ ->
            []
        end

      _ ->
        []
    end
  end

  defp repository_target(repo, [kind, ref | path]) when kind in ["blob", "tree"],
    do: %{repo: repo, kind: kind, ref: ref, path: Enum.join(path, "/")}

  defp repository_target(repo, _rest), do: %{repo: repo, kind: nil, ref: nil, path: ""}

  defp strip_anchor(path), do: URI.parse(path).path || ""
end
