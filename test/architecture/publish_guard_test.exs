defmodule AgentBlueprintProtocol.Architecture.PublishGuardTest do
  @moduledoc """
  Publish guard: no internal-planning reference, private-tool path, or
  home-directory path appears in any file that ships in the Hex archive.

  The archive file set is resolved from `package.files` against the
  working tree with `match_dot: true`. Every entry resolves through
  `Path.wildcard`, literals and globs alike, so a glob entry can never
  ship files this scan skips. Any symlinked path in the set reds
  outright: the built archive preserves symlinks as target-path strings
  the content scan could never see (`Path.wildcard` DOES follow valid
  symlinked directories, so the content scan sees their files too).
  The frozen two-directional name allowlist in `PackageBoundaryTest`
  remains the name-level backstop.

  Pattern classes:

  - Byte patterns (any archive file, including binaries): `.claude/`,
    `.serena`, `.mcp.json`, `/Users/`, `/home/`, `baselabs.com`, and
    `com.baselabs`. These contain `.` or `/`, which the base64url alphabet
    excludes, so none can false-positive inside a digest, key, or signature
    token. Private project, tool and repository names are never spelled in
    this public file: the publication privacy command refuses them in
    tracked paths and contents with keyed fingerprints, and
    `PublicSurfacePrivacyTest` exercises that command with a test key and
    canary.
  - Reference patterns (text files only: `.md`, `.cheatmd`, `.ex`, `.exs`): tracker
    numerals `00NN` (word-bounded; quoted base64url digests are intact word
    tokens and the only shipped digest form is `sha-256:`-prefixed, so the
    token-leading case cannot arise), tracker slug form `00NN-…`, explicit
    `ticket`/`issue` phrasing, internal planning-directory names with their
    slash, internal design-shorthand citations (`bofn`, `spec D<n>`), and
    `file.ex:line` source citations.

  Deliberate exemptions, recorded here so the boundary is a decision and not
  an accident:

  - Registry data is RFC 2606 example-class content (`com.example.*`
    namespaces, `Example*` owners, `example.com` URIs). The public
    package reveals no internal names; the publication privacy command
    independently checks tracked paths and history.
  - Corpus `.json` files carry the text-pattern-exempt class: they are
    digest-bound by `conformance.verify` (any edit reds the corpus hash),
    and byte patterns still apply to them.
  - Public decision records retain their numbers in known ADR paths,
    their own first heading, and the changelog's declared public range.
    Other numbered references remain scanned.

  Goes RED on: a private-tool path planted in any archived file
  (README, a lib module, a corpus member); a tracker numeral or slug added
  to a shipped text file; an internal design citation left in shipped
  docs; or any archive member absent from the tracked source tree. The
  publication privacy command separately checks tracked paths and history.
  """

  use ExUnit.Case, async: true

  @byte_patterns [
    ".claude/",
    ".serena",
    ".mcp.json",
    "/Users/",
    "/home/",
    "baselabs.com",
    "com.baselabs"
  ]

  @text_patterns [
    # tracker numerals and slug forms (word-bounded; base64url tokens have
    # no internal word boundaries and shipped digests are "sha-256:"-tagged;
    # the lookbehind spares legitimate hex/Unicode literals like `U+0000`;
    # the horizon is any 4-digit zero-padded numeral, so the pattern does
    # not silently go dark at 0100)
    ~r/(?<![+x])\b0\d{3}\b/,
    ~r/(?<![+x])\b0\d{3}-[a-z]/,
    ~r/\b(ticket|issue)\s+0\d{3}/i,
    # internal planning directory names (the actual internal corpus layout)
    Regex.compile!(
      "(?<!#{Regex.escape(String.replace_prefix(Mix.Project.config()[:source_url], "https://", "") <> "/")})" <>
        "\\b(handoffs|intents|scout|risks|designs|dogfood|issues|research|reviews|specs)/"
    ),
    # internal design-shorthand citations
    ~r/\bbofn\b/i,
    ~r/\bspec D\d/,
    ~r/\bD1[0-9]\b/,
    # source file:line citations into repo internals
    ~r/\w+\.(ex|exs|md):\d+/,
    # internal portfolio product names with no shipped-data role
    ~r/\b(BAP|BARA)\b/
  ]

  # Extensionless shipped files that are still text and still carry prose
  # (LICENSE, NOTICE) join the text-pattern scan.
  @text_basenames ["LICENSE", "NOTICE"]

  @text_extensions [".md", ".cheatmd", ".ex", ".exs"]

  test "every declared package file exists" do
    missing = for entry <- declared_paths(), expand(entry) == [], do: entry

    assert missing == [],
           "package.files declares entries that resolve to nothing: #{inspect(missing)}"
  end

  test "no archived path is a symlink" do
    offenders =
      for path <- archive_files(),
          File.lstat!(path).type == :symlink do
        path
      end

    assert offenders == [],
           "publish-guard violation: a shipped path is a symlink (the archive " <>
             "would carry the target path itself):\n" <>
             Enum.map_join(offenders, "\n", &"  #{&1}")
  end

  test "every archived file is tracked" do
    {tracked, 0} = System.cmd("git", ["ls-files", "-z"], stderr_to_stdout: true)
    tracked = tracked |> String.split(<<0>>, trim: true) |> MapSet.new()

    offenders = Enum.reject(archive_files(), &MapSet.member?(tracked, &1))

    assert offenders == [],
           "publish-guard violation: an unexpected untracked file would ship in the archive:\n" <>
             Enum.map_join(offenders, "\n", &"  #{&1}")
  end

  test "no archived file carries a private-path byte pattern" do
    offenders =
      for path <- archive_files(),
          pattern <- @byte_patterns,
          content = File.read!(path),
          String.contains?(content, pattern) do
        {path, pattern}
      end

    assert offenders == [],
           "publish-guard violation: a shipped file carries a private path:\n" <>
             Enum.map_join(offenders, "\n", fn {p, pat} -> "  #{p}: #{pat}" end)
  end

  test "no archived text file carries an internal reference" do
    offenders =
      for path <- archive_files(),
          text_file?(path),
          content = File.read!(path),
          content =
            AgentBlueprintProtocol.ArchitectureScan.public_record_text(
              content,
              path,
              AgentBlueprintProtocol.ArchitectureScan.public_records()
            ),
          pattern <- @text_patterns,
          Regex.scan(pattern, content) != [] do
        {path, Regex.source(pattern), Enum.take(Regex.scan(pattern, content), 3)}
      end

    assert offenders == [],
           "publish-guard violation: a shipped text file references internal material:\n" <>
             Enum.map_join(offenders, "\n", fn {p, pat, hits} ->
               "  #{p}: /#{pat}/ #{inspect(hits)}"
             end)
  end

  # ---- exemption pins -------------------------------------------------------------

  # The exemption record above ("registry data is published-by-design; no
  # pattern targets it") is mechanical, not prose: the live registry fixtures
  # must match no guard pattern, so a future pattern addition that would
  # accidentally cover exempted data reds HERE. Naming the exemption
  # decision here avoids spurious findings in the main scan.

  test "live registry data matches no guard pattern (exemption pin)" do
    byte_offenders =
      for fixture <- registry_fixtures(),
          pattern <- @byte_patterns,
          String.contains?(fixture, pattern),
          do: {pattern, fixture}

    text_offenders =
      for fixture <- registry_fixtures(),
          pattern <- @text_patterns,
          Regex.match?(pattern, fixture),
          do: {Regex.source(pattern), fixture}

    assert {byte_offenders, text_offenders} == {[], []},
           "publish-guard pattern covers exempted registry data (update the " <>
             "exemption decision, not the data):\n" <>
             Enum.map_join(byte_offenders ++ text_offenders, "\n", fn {p, f} ->
               "  pattern #{inspect(p)} covers #{f}"
             end)
  end

  test "the exemption pin can fire (calibration)" do
    planted = ~r/\bAgent Blueprint Protocol\b/

    hits =
      for fixture <- registry_fixtures(),
          pattern <- [planted],
          Regex.match?(pattern, fixture),
          do: fixture

    assert hits != [],
           "exemption-pin calibration is vacuous: a pattern that targets " <>
             "owner data found no fixture: registry_fixtures/ is empty or broken"
  end

  test "only known public decision record paths and their own headings spare numbers" do
    records = AgentBlueprintProtocol.ArchitectureScan.public_records()
    assert length(records) == 20

    for path <- records do
      basename = Path.basename(path)
      [number | _] = String.split(basename, "-", parts: 2)
      source = "# #{number}: Public record\n\n[record](#{basename})\n#{path}\n../#{path}"

      text = AgentBlueprintProtocol.ArchitectureScan.public_record_text(source, path, records)
      assert Enum.filter(@text_patterns, &Regex.match?(&1, text)) == []

      for source <- [
            "#{number}",
            "#{number}-internal.md",
            Path.join("docs/adr", "#{number}-unknown.md"),
            "#{path}.bak",
            "issues/#{basename}",
            "# #{number}: Unrelated heading"
          ] do
        text =
          AgentBlueprintProtocol.ArchitectureScan.public_record_text(source, "README.md", records)

        assert Enum.any?(@text_patterns, &Regex.match?(&1, text)), source
      end
    end
  end

  test "repository routes are spared and planning directories still red (exemption pin)" do
    repository = Mix.Project.config()[:source_url]

    spared = [
      "#{repository}/issues/new?template=security_report.yml",
      "[issues](#{repository}/issues)"
    ]

    caught = [
      "see issues/ for the tracker",
      "#{repository}/blob/v1.0.0/issues/0001-example.md",
      "#{repository}/tree/main/scout/topic",
      "https://github.com/another/repository/issues/new"
    ]

    hits = fn text -> Enum.filter(@text_patterns, &Regex.match?(&1, text)) end

    assert Enum.filter(spared, &(hits.(&1) != [])) == []
    assert Enum.filter(caught, &(hits.(&1) == [])) == []
  end

  test "corpus json members are byte-scanned but text-exempt (exemption pin)" do
    corpus = Enum.filter(archive_files(), &String.ends_with?(&1, ".json"))

    assert corpus != [], "no corpus .json members resolved into the archive set"

    text_scanned = Enum.filter(corpus, &text_file?/1)

    assert text_scanned == [],
           "corpus .json members must stay text-exempt (byte patterns still " <>
             "apply): #{inspect(text_scanned)}"
  end

  defp registry_fixtures do
    AgentBlueprintProtocol.ExtensionRegistry.registered_extensions()
    |> Enum.flat_map(&[&1.owner, &1.namespace, &1.a2a_uri])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  # ---- helpers ------------------------------------------------------------------

  defp declared_paths do
    Mix.Project.config()[:package][:files]
  end

  defp text_file?(path) do
    Path.extname(path) in @text_extensions or Path.basename(path) in @text_basenames
  end

  defp archive_files do
    for entry <- declared_paths(),
        path <- expand(entry),
        not File.dir?(path),
        uniq: true,
        do: path
  end

  # Every entry resolves through Path.wildcard, literals and globs alike,
  # so a glob entry in package.files can never ship files this scan skips.
  defp expand(entry) do
    case Path.wildcard(entry, match_dot: true) do
      [] -> if File.exists?(entry), do: [entry], else: []
      matches -> Enum.reject(Enum.flat_map(matches, &expand_match/1), &File.dir?/1)
    end
  end

  defp expand_match(path) do
    if File.dir?(path) do
      for relative <- :filelib.wildcard(~c"**/*", String.to_charlist(path)),
          do: Path.join(path, List.to_string(relative))
    else
      [path]
    end
  end
end
