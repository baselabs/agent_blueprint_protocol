defmodule AgentBlueprintProtocol.Architecture.InternalCitationGateTest do
  @moduledoc """
  Repo-side citation gate: `lib/`, `test/`, `scripts/`, and the TypeScript
  verifier tree (`conformance/verifier/`) stay free of internal tracker
  citations — numerals, slug forms, planning shorthand, internal
  review-process vocabulary, and internal tool names — so the public
  repository inherits no remediation debt. The shipped Hex archive is
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

  @scan_roots ["lib", "test", "scripts"]
  # The repo-side TypeScript verifier tree ships in the public repository;
  # it is scanned for the same vocabulary (`.ts` files only — the JSON
  # testdata beside it is data, not prose).
  @ts_roots ["conformance/verifier"]
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
    ~r/\b(security-lens|cross-vendor|review (round|fix|fold|pass)|codex|fable|opus|kimosabe)\b/i
  ]

  test "no code file carries an internal tracker citation" do
    offenders =
      for path <- scan_files(),
          content = File.read!(path),
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
    files =
      (@scan_roots
       |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.{ex,exs}")))) ++
        (@ts_roots |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ts"))))

    files
    |> Enum.reject(&(&1 in @exempt))
    |> Enum.sort()
  end
end
