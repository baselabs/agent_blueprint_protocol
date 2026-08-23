defmodule AgentBlueprintProtocol.Architecture.PublishGuardTest do
  @moduledoc """
  Publish guard: no internal-planning reference, private-tool path, or
  home-directory path appears in any file that ships in the Hex archive.

  The archive file set is resolved from `package.files` against the
  working tree with `match_dot: true` — every entry resolves through
  `Path.wildcard`, literals and globs alike, so a glob entry can never
  ship files this scan skips. Any symlinked path in the set reds
  outright: the built archive preserves symlinks as target-path strings
  the content scan could never see (`Path.wildcard` DOES follow valid
  symlinked directories, so the content scan sees their files too).
  The frozen two-directional name allowlist in `PackageBoundaryTest`
  remains the name-level backstop.

  Pattern classes:

  - Byte patterns (any archive file, including binaries): `.kimosabe`,
    `kimosabe/`, `.claude/`, `.serena`, `.mcp.json`, `/Users/`, `/home/`,
    and the internal owner/org tokens (`ExampleCommerce`, `ExampleCommerce`,
    `baselabs.com`, `com.baselabs`). The first seven contain `.` or `/`,
    which the base64url alphabet excludes, so none can false-positive inside a
    digest, key, or signature token; the name patterns are long
    mixed-case strings that cannot arise in any encoded token.
  - Reference patterns (text files only: `.md`, `.ex`, `.exs`): tracker
    numerals `00NN` (word-bounded; quoted base64url digests are intact word
    tokens and the only shipped digest form is `sha-256:`-prefixed, so the
    token-leading case cannot arise), tracker slug form `00NN-…`, explicit
    `ticket`/`issue` phrasing, internal planning-directory names with their
    slash, internal design-shorthand citations (`bofn`, `spec D<n>`), and
    `file.ex:line` source citations.

  Deliberate exemptions, recorded here so the boundary is a decision and not
  an accident:

  - Registry data is RFC 2606 example-class content (`com.example.*`
    namespaces, `Example*` owners, `example.com` URIs) — the public
    package reveals no internal names; the real ones are banned BYTES
    everywhere in the archive (the 2026-08-23 user directive that
    superseded the compiled-registry ADR's published-by-design stance).
  - Corpus `.json` files carry the text-pattern-exempt class: they are
    digest-bound by `conformance.verify` (any edit reds the corpus hash),
    and byte patterns still apply to them.
  - The requirement map's fenced ```red blocks are verbatim machine
    output — recorded gate receipts, the map's whole purpose — so they
    quote the very tokens this guard bans, exactly as this guard's own
    pattern block names them. For that one file the fences are STRIPPED
    before both scans; every byte outside a fence is scanned like any
    other shipped file (pinned by the fence-scope test below: a banned
    token planted in the map OUTSIDE a fence still reds).

  Goes RED on: a `.kimosabe` path or reference planted in any archived file
  (README, a lib module, a corpus member); a tracker numeral or slug added
  to a shipped text file; an internal design citation left in shipped
  docs; any internal owner/org name in any archived file.
  """

  use ExUnit.Case, async: true

  @byte_patterns [
    ".kimosabe",
    "kimosabe/",
    ".claude/",
    ".serena",
    ".mcp.json",
    "/Users/",
    "/home/",
    "ExampleCommerce",
    "ExampleCommerce",
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
    ~r{\b(handoffs|intents|scout|risks|designs|dogfood|issues|research|reviews|specs)/},
    # internal design-shorthand citations
    ~r/\bkimosabe\b/i,
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

  @text_extensions [".md", ".ex", ".exs"]

  # The one shipped file whose fenced ```red blocks are recorded gate
  # receipts: they are stripped before scanning, and only for this file.
  @receipt_fenced_path "docs/design/requirement-map.md"
  @red_fence ~r/```red\n.*?```/s

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

  test "no archived file carries a private-path byte pattern" do
    offenders =
      for path <- archive_files(),
          pattern <- @byte_patterns,
          content = scan_content(path),
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
          pattern <- @text_patterns,
          content = scan_content(path),
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

  test "the requirement map's fence exemption is scoped (a banned token outside a fence reds)" do
    map = File.read!(@receipt_fenced_path)

    # The map itself, fences stripped, matches no pattern (the live exemption).
    stripped = strip_red_fences(map)

    assert byte_clean?(stripped) and text_clean?(stripped),
           "the requirement map carries banned material OUTSIDE its red fences — " <>
             "the exemption is for receipts only; scrub the prose"

    # A banned token planted OUTSIDE a fence survives the strip (the pin:
    # the strip is fence-scoped, never a whole-file pass).
    planted = stripped <> "\nsee .kimosabe/notes\n"

    assert String.contains?(planted, ".kimosabe") and
             not byte_clean?(strip_red_fences(planted)),
           "fence-strip exemption vacuous: out-of-fence content in the map is not scanned"
  end

  # The exemption record above ("registry data is published-by-design; no
  # pattern targets it") is mechanical, not prose: the live registry fixtures
  # must match no guard pattern, so a future pattern addition that would
  # accidentally cover exempted data reds HERE — naming the exemption
  # decision — instead of spurious-redning the main scan.

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
    planted = ~r/\b(ExampleCommerce|ExamplePlatform)\b/

    hits =
      for fixture <- registry_fixtures(),
          pattern <- [planted],
          Regex.match?(pattern, fixture),
          do: fixture

    assert hits != [],
           "exemption-pin calibration is vacuous: a pattern that targets " <>
             "owner data found no fixture — registry_fixtures/ is empty or broken"
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

  # The scanned content for a file: the requirement map's ```red receipt
  # fences are stripped (recorded machine output — see the exemption
  # record above); every other file scans whole.
  defp scan_content(path) do
    content = File.read!(path)
    if path == @receipt_fenced_path, do: strip_red_fences(content), else: content
  end

  defp strip_red_fences(content), do: Regex.replace(@red_fence, content, "")

  defp byte_clean?(content) do
    Enum.all?(@byte_patterns, &(not String.contains?(content, &1)))
  end

  defp text_clean?(content) do
    Enum.all?(@text_patterns, &(not Regex.match?(&1, content)))
  end

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

  # Every entry resolves through Path.wildcard — literals and globs alike —
  # so a glob entry in package.files can never ship files this scan skips.
  defp expand(entry) do
    case Path.wildcard(entry, match_dot: true) do
      [] -> if File.exists?(entry), do: [entry], else: []
      matches -> Enum.reject(Enum.flat_map(matches, &expand_match/1), &File.dir?/1)
    end
  end

  defp expand_match(path) do
    if File.dir?(path) do
      Path.wildcard(Path.join(path, "**/*"), match_dot: true)
    else
      [path]
    end
  end
end
