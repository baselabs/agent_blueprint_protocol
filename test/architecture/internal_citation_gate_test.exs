defmodule AgentBlueprintProtocol.Architecture.InternalCitationGateTest do
  @moduledoc """
  Repo-side citation gate: every tracked text file under `lib/`, `test/`,
  `scripts/`, and the TypeScript verifier tree (`verifier/`), in any
  language, stays free of internal tracker citations — numerals, slug
  forms, planning shorthand, and internal review-process vocabulary — so
  the public repository inherits no remediation debt. Private project, tool
  and repository names are refused by the publication privacy command's
  keyed fingerprints instead, so this public file never spells them. The
  shipped Hex archive is
  already covered by the publish guard; this extends the same posture to
  the working tree's code files (design history lives under docs/design
  and the local planning directory, which are not scanned).

  The publish guard's own pattern block NAMES what it bans (`bofn`,
  tracker-numeral examples, tool-name byte patterns) — as does this
  gate's moduledoc — so those two files are exempt by name: their
  literals are the enforcement, not citations. Legitimate literals
  (decimal fractions like `5.0001`, `0x`-prefixed and braced Unicode
  escapes) are spared by the same lookbehind shape the shipped guard
  uses; scripts that must PLANT a banned token split it at runtime so
  their source stays clean.
  """
  use ExUnit.Case, async: true

  # Every tracked file under these roots is scanned whatever its language:
  # shell, JavaScript and data files carry the same vocabulary risk as
  # Elixir and TypeScript. Files that are not UTF-8 text are skipped.
  @scan_roots ["lib", "test", "scripts", "verifier"]
  @exempt [
    "test/architecture/publish_guard_test.exs",
    "test/architecture/internal_citation_gate_test.exs"
  ]

  @citation_patterns [
    # tracker numerals and slug forms (word-bounded; the lookbehind
    # spares 0x-literals, U+0000-style escapes, and decimal fractions)
    ~r/(?<![+x.{])\b0\d{3}\b/,
    ~r/(?<![+x.{])\b0\d{3}-[a-z]/,
    ~r/\b(ticket|issue)\s+0\d{3}/i,
    ~r/\bthe ticket'?s?\b/i,
    # internal planning shorthand
    ~r/\bbofn\b/i,
    ~r/\bspec D\d/i,
    ~r/\bD\d{1,2}\b/,
    ~r/\bQ\d{1,2}\b/,
    ~r/\bphase\b/i,
    ~r/\b(this|that|the|owning|later|another|a) slice('s)?\b/i,
    # internal review-process vocabulary and finding identifiers
    ~r/\bP\d-\d\b/,
    ~r/\b(security-lens|cross-vendor|review (round|fix|fold|pass)|codex|fable|opus)\b/i
  ]

  test "no code file carries an internal tracker citation" do
    offenders =
      for path <- scan_files(),
          content = File.read!(path),
          content =
            AgentBlueprintProtocol.ArchitectureScan.public_record_text(
              content,
              path,
              Path.wildcard("docs/adr/[0-9][0-9][0-9][0-9]-*.md")
            ),
          pattern <- @citation_patterns,
          Regex.scan(pattern, content) != [] do
        {path, Regex.source(pattern), Enum.take(Regex.scan(pattern, content), 3)}
      end

    assert offenders == [],
           "internal citation found in a code file (the repo must stay " <>
             "citation-free so a public transition needs no scrub):\n" <>
             Enum.map_join(offenders, "\n", fn {p, pat, hits} ->
               "  #{p}: /#{pat}/ #{inspect(hits)}"
             end)
  end

  defp scan_files do
    {listing, 0} = System.cmd("git", ["ls-files", "-z", "--" | @scan_roots])

    listing
    |> String.split(<<0>>, trim: true)
    |> Enum.reject(&(&1 in @exempt))
    |> Enum.filter(&(File.regular?(&1) and String.valid?(File.read!(&1))))
    |> Enum.sort()
  end
end
