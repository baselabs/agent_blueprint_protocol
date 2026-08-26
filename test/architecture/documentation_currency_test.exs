defmodule AgentBlueprintProtocol.Architecture.DocumentationCurrencyTest do
  @moduledoc """
  Documentation-currency gate: the public documents' version and identity
  claims track the live project, so a release cannot ship naming an older
  line. The current version is read from `mix.exs`, the corpus identity
  from `priv/conformance/index.json`, the coverage threshold from the
  project config, and the test totals from a census of the live test
  tree — never a frozen copy that could drift:

  - the README install requirement pins the exact current version;
  - SECURITY.md's supported table names the current `major.minor` line;
  - CHANGELOG.md opens an entry for the current version, and that entry
    carries the live corpus digest and case total;
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

    assert security =~ "| #{line}.x |",
           "SECURITY.md supported table does not name the #{line}.x line"
  end

  test "the CHANGELOG entry for the current version carries the corpus identity" do
    version = current_version()
    changelog = File.read!(@changelog_path)

    assert changelog =~ "## [#{version}]",
           "CHANGELOG.md has no entry for the current version #{version}"

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

  # README's "N tests" claim states the ExUnit total (test macros plus
  # property macros); support files carry no macros.
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
