defmodule AgentBlueprintProtocol.Architecture.DocumentationCurrencyTest do
  @moduledoc """
  Documentation-currency gate: the public documents' version and identity
  claims track the live project, so a release cannot ship naming an older
  line. The current version is read from `mix.exs`, the corpus identity
  from `priv/conformance/index.json`, the coverage threshold from the
  project config, and the test totals from a census of the live test
  tree — never a frozen copy that could drift:

  - the README install requirement pins the exact current version;
  - SECURITY.md's supported table opens with the current `major.minor`
    line marked supported;
  - CHANGELOG.md opens with the entry for the current version, and that
    entry carries the live corpus digest and case total;
  - every count claim in README (tests, properties, corpus cases,
    coverage) matches the live value.
  """

  use ExUnit.Case, async: true

  @readme_path "README.md"
  @security_path "SECURITY.md"
  @changelog_path "CHANGELOG.md"
  @index_path "priv/conformance/index.json"

  test "README and SECURITY.md name the current released version" do
    version = current_version()
    line = version |> String.split(".") |> Enum.take(2) |> Enum.join(".")

    readme = File.read!(@readme_path)
    pins = requirement_pins(readme)

    assert pins != [], "README must carry the install requirement snippet"

    assert Enum.uniq(pins) == ["~> " <> version],
           "README install requirement is stale: #{inspect(pins)} — the " <>
             "current version is #{version}"

    security = File.read!(@security_path)

    assert first_supported_row(security) == {"#{line}.x", "yes"},
           "SECURITY.md supported table's first row must be the #{line}.x " <>
             "line marked yes (got #{inspect(first_supported_row(security))})"
  end

  test "the CHANGELOG entry for the current version carries the corpus identity" do
    version = current_version()
    changelog = File.read!(@changelog_path)
    first = first_version_heading(changelog)

    assert first == version,
           "CHANGELOG.md's first entry is #{inspect(first)} — the current " <>
             "release entry (#{version}) must open the changelog"

    entry = current_entry(changelog, version)
    index = File.read!(@index_path)
    digest = json_string(index, "corpus_digest")
    total = json_number(index, "total_cases")

    assert digest != "" and total != "",
           "the corpus index is missing its digest or case-total identity"

    assert entry =~ digest,
           "the CHANGELOG entry for #{version} does not carry the live " <>
             "corpus digest #{digest}"

    assert Regex.match?(~r/\b#{total} cases\b/, entry),
           "the CHANGELOG entry for #{version} does not state \"#{total} cases\""
  end

  test "no shipped document outside the release docs carries a stale concrete version claim" do
    version = current_version()
    # README/SECURITY/CHANGELOG carry version claims gated by their own
    # arms; every OTHER shipped markdown may state only the current
    # version or no concrete version at all.
    release_docs = ["README.md", "SECURITY.md", "CHANGELOG.md"]

    offenders =
      for file <- Mix.Project.config()[:package][:files],
          String.ends_with?(file, ".md"),
          file not in release_docs,
          content = File.read!(file),
          claim <- version_claims(content),
          claim != version,
          uniq: true do
        {file, claim}
      end

    assert offenders == [],
           "shipped documents carry stale concrete version claims " <>
             "(only #{version} may appear): #{inspect(offenders)}"
  end

  # A version claim is a three-part number standing ALONE (not a
  # §-prefixed section reference, not part of a longer dotted
  # sequence like RFC subsection numbering). Bare-number matches
  # require a word boundary, so a `v`-tagged token (v1.0.0) does not
  # match — external projects' release tags (the A2A v1.x tags in the
  # federation mapping) stay exempt BY that mechanism. Every
  # this-project version is 0.x, so v-tagged 0.x tokens are scanned
  # separately and must also name the current version.
  defp version_claims(content) do
    bare = ~r/(?<!§)(?<!\.)\b\d+\.\d+\.\d+\b(?!\.)/ |> Regex.scan(content) |> Enum.map(&hd/1)

    vtagged =
      ~r/v(0\.\d+\.\d+)\b/
      |> Regex.scan(content)
      |> Enum.map(fn [_, v] -> "v" <> v end)

    bare ++ vtagged
  end

  test "README count claims match the live test tree and corpus index" do
    readme = File.read!(@readme_path)
    index = File.read!(@index_path)

    assert_claim(readme, ~r/\b(\d+) tests\b/, live_test_count(), "test count")
    assert_claim(readme, ~r/\((\d+) properties\)/, live_property_count(), "property count")

    assert_claim(
      readme,
      ~r/\b(\d+)(?:-case\b|\s+cases\b)/,
      json_number(index, "total_cases"),
      "corpus case count"
    )

    assert_claim(readme, ~r/\b(\d+)% coverage\b/, coverage_threshold(), "coverage threshold")
  end

  # Every match of the claim pattern must state the live value, and at
  # least one claim of each kind must stay present — a README that stops
  # making the claim is as stale as one making a wrong one.
  defp assert_claim(doc, regex, expected, label) do
    claims = regex |> Regex.scan(doc) |> Enum.map(fn [_, value] -> value end)

    assert claims != [], "README makes no #{label} claim — the claim must stay present"

    stale = Enum.uniq(claims) -- [to_string(expected)]

    assert stale == [],
           "README #{label} claims #{inspect(stale)} — the live value is #{expected}"
  end

  defp current_version, do: Mix.Project.config()[:version]

  defp coverage_threshold, do: Mix.Project.config()[:test_coverage][:summary][:threshold]

  # Every hex requirement string in README is an install pin; they must all
  # name the current version.
  defp requirement_pins(readme) do
    ~r/"(~> [\d.]+)"/
    |> Regex.scan(readme)
    |> Enum.map(fn [_, pin] -> pin end)
  end

  defp current_entry(changelog, version) do
    case Regex.split(~r/^## \[#{Regex.escape(version)}\].*$/m, changelog, parts: 2) do
      [_before, rest] ->
        rest |> String.split(~r/^## \[/m, parts: 2) |> hd()

      [_] ->
        ""
    end
  end

  # The supported table's first DATA row (a stale first row — wrong line,
  # or the current line marked no — reds; older lines may follow).
  defp first_supported_row(security) do
    case Regex.run(
           ~r/^\| Version \| Supported \|\n\| -+ \| -+ \|\n\| ([^|]+?) \| ([^|]+?) \|/m,
           security
         ) do
      [_, version, status] -> {String.trim(version), String.trim(status)}
      nil -> {nil, nil}
    end
  end

  # The changelog's first version heading must be the current release.
  defp first_version_heading(changelog) do
    case Regex.run(~r/^## \[([^\]]+)\]/m, changelog) do
      [_, heading] -> heading
      nil -> ""
    end
  end

  # README's "N tests" claim states the ExUnit total (test macros plus
  # property macros); the suite-registered count (.test_census, written
  # at suite end) is tied to this census by the release-candidate
  # check, which runs AFTER the test step of the battery.
  defp live_test_count, do: macro_census("test") + macro_census("property")

  defp live_property_count, do: macro_census("property")

  # The census counts test/property macros across the test tree (support
  # files carry none) — the same total ExUnit reports for this suite.
  defp macro_census(kind) do
    pattern = ~r/^\s*#{kind} "/m

    "test/**/*_test.exs"
    |> Path.wildcard()
    |> Enum.map(&File.read!/1)
    |> Enum.map(fn source -> source |> length_of_scan(pattern) end)
    |> Enum.sum()
  end

  defp length_of_scan(source, pattern), do: length(Regex.scan(pattern, source))

  defp json_string(json, key) do
    case Regex.run(~r/"#{key}"\s*:\s*"([^"]+)"/, json) do
      [_, value] -> value
      _ -> ""
    end
  end

  defp json_number(json, key) do
    case Regex.run(~r/"#{key}"\s*:\s*(\d+)/, json) do
      [_, value] -> value
      _ -> ""
    end
  end
end
