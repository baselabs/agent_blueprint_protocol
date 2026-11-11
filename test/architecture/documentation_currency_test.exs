defmodule AgentBlueprintProtocol.Architecture.DocumentationCurrencyTest do
  @moduledoc """
  Documentation-currency gate: the public documents' version and identity
  claims track the live project, so a release cannot ship naming an older
  line. The current version is read from `mix.exs`, the corpus identity
  from `priv/conformance/index.json`, the coverage threshold from the
  project config, and the test totals from a census of the live test
  tree, never a frozen copy that could drift:

  - the README install requirement pins the exact current version;
  - SECURITY.md's supported table opens with the current `major.minor`
    line marked supported;
  - CHANGELOG.md opens with the entry for the current version (below an
    optional `Unreleased` section), and that entry carries the live corpus
    digest and case total;
  - CONTRIBUTING.md states the live test, property, and coverage values;
  - README.md states the live corpus case total and carries no other
    test statistics.
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
           "README install requirement is stale: #{inspect(pins)}. The " <>
             "current version is #{version}"

    notebooks = Path.wildcard("docs/livebooks/*.livemd")
    assert notebooks != [], "the Livebook set is missing"

    for notebook <- notebooks do
      pins = requirement_pins(File.read!(notebook))

      assert pins == ["~> " <> version],
             "#{notebook} must pin the current package version, found #{inspect(pins)}"
    end

    # README npm commands use the release-candidate tag. The generic npm
    # view sentence lets readers check the version available in the registry.
    npm_pins =
      ~r/@agent-blueprint-protocol\/verifier@[A-Za-z0-9.+-]+/
      |> Regex.scan(readme)
      |> Enum.map(&hd/1)
      |> Enum.uniq()

    assert npm_pins ==
             if(Version.parse!(version).pre == [],
               do: [],
               else: ["@agent-blueprint-protocol/verifier@rc"]
             ),
           "README npm kit commands must use the release-candidate tag, found #{inspect(npm_pins)}"

    assert readme =~ "npm view @agent-blueprint-protocol/verifier",
           "README must say how to see which kit npx runs"

    refute Regex.match?(~r/\b\d+ tests\b|\(\d+ properties\)|\b\d+% coverage\b/, readme),
           "README must not carry test statistics"

    contributing = File.read!("CONTRIBUTING.md")
    assert_claim(contributing, ~r/\b(\d+) tests\b/, live_test_count(), "test count")

    assert_claim(
      contributing,
      ~r/\((\d+) properties\)/,
      live_property_count(),
      "property count"
    )

    assert_claim(
      contributing,
      ~r/\b(\d+)% coverage\b/,
      coverage_threshold(),
      "coverage threshold"
    )

    security = File.read!(@security_path)

    supported = if Version.parse!(version).pre == [], do: "#{line}.x", else: version

    assert first_supported_row(security) == {supported, "yes"},
           "SECURITY.md supported table's first row must be the #{line}.x " <>
             "line marked yes (got #{inspect(first_supported_row(security))})"
  end

  test "the CHANGELOG entry for the current version carries the corpus identity" do
    version = current_version()
    changelog = File.read!(@changelog_path)
    first = first_version_heading(changelog)

    assert first == version,
           "CHANGELOG.md's first entry is #{inspect(first)}. The current " <>
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

    readme = File.read!(@readme_path)
    assert_claim(readme, ~r/\b(\d+)(?:-case\b|\s+cases\b)/, total, "corpus case count")

    assert_optional_claim(
      File.read!("CONTRIBUTING.md"),
      ~r/\b(\d+)(?:-case\b|\s+cases\b)/,
      total,
      "corpus case count"
    )
  end

  test "no shipped document outside the release docs carries a stale concrete version claim" do
    version = current_version()
    # README/SECURITY/CHANGELOG carry version claims gated by their own
    # arms; every OTHER shipped markdown may state only the current
    # version or no concrete version at all.
    release_docs = ["README.md", "SECURITY.md", "CHANGELOG.md"]

    offenders =
      for file <- shipped_markdown(),
          file not in release_docs,
          content = File.read!(file),
          claim <- version_claims(content),
          not allowed_document_version?(file, String.trim_leading(claim, "v"), version),
          uniq: true do
        {file, claim}
      end

    assert offenders == [],
           "shipped documents carry stale concrete version claims " <>
             "(only #{version} may appear): #{inspect(offenders)}"

    assert version_claims("1.0.0-rc.1") == ["1.0.0-rc.1"]

    assert allowed_document_version?("documentation/verifying-releases.md", "2.0.0", "2.0.0-rc.1")
    refute allowed_document_version?("documentation/verifying-releases.md", "1.0.0", "2.0.0-rc.1")

    document = File.read!("documentation/errors.md")

    listed =
      document
      |> String.split("\n")
      |> Enum.flat_map(fn line ->
        case Regex.run(~r/^\| ([a-z][a-z0-9_]*(?::[a-z_]+)?) \|/, line) do
          [_, code] -> [code]
          _ -> []
        end
      end)

    expected_errors = Enum.map(AgentBlueprintProtocol.Error.codes(), &Atom.to_string/1)

    expected_ceilings =
      Enum.map(AgentBlueprintProtocol.Error.ceiling_keys(), &"ceiling:#{Atom.to_string(&1)}")

    assert Enum.sort(listed) == Enum.sort(expected_errors ++ expected_ceilings)
    assert length(listed) == length(Enum.uniq(listed))
  end

  test "the landing page's visible text names only the current version" do
    version = current_version()

    # Tags and attribute values (SVG path data carries dotted numbers) are
    # stripped first; what remains is the text a visitor reads.
    visible = Regex.replace(~r/<[^>]*>/s, File.read!("site/index.html"), " ")

    stale =
      ~r/(?<![\d.])\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?(?![\d.])/
      |> Regex.scan(visible)
      |> Enum.map(&hd/1)
      |> Enum.uniq()
      |> Kernel.--([version])

    assert stale == [],
           "site/index.html names stale versions #{inspect(stale)}. Only #{version} may appear"

    source = File.read!("site/extensions/federation/index.html")
    registry = File.read!("spec/registry/registry.json") |> Jason.decode!()
    entry = Enum.find(registry["entries"], &(&1["namespace"] == "io.github.baselabs/federation"))

    for field <- ["namespace", "criticality", "state", "schema_digest"] do
      assert source =~ entry[field]
    end

    assert source =~ "spec/protocol.md#11-federation-profile"
    assert source =~ "spec/registry/registry.json"
    assert File.read!(".github/workflows/pages.yml") =~ "path: site"
    assert File.exists?(Path.expand("../../styles.css", "site/extensions/federation"))
  end

  # Package entries include bare directories ("documentation", "examples");
  # a flat ends_with?(".md") filter over the entries list silently skipped
  # every file inside them, which is how the guides' install pins drifted.
  # Livebooks (.livemd) are shipped documents too and carry the same claims.
  defp shipped_markdown do
    Mix.Project.config()[:package][:files]
    |> Enum.flat_map(fn entry ->
      cond do
        String.ends_with?(entry, [".md", ".livemd"]) -> [entry]
        File.dir?(entry) -> Path.wildcard(Path.join(entry, "**/*.{md,livemd}"))
        true -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # A version claim is a three-part number standing ALONE (not a
  # §-prefixed section reference, not part of a longer dotted
  # sequence like RFC subsection numbering). Bare-number matches
  # require a word boundary, so a `v`-tagged token does not match. Scan
  # this-project version tags separately so they must name the current
  # release, including its prerelease identifier.
  defp version_claims(content) do
    # Version text in a Markdown link destination can include an archive
    # extension, which is not a package-version claim (for example, a
    # release asset ending in `.tar.gz`). Scan the linked label and prose.
    content = Regex.replace(~r/\]\([^)]*\)/, content, "](link)")

    bare =
      ~r/(?<!§)(?<!\.)\b\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?(?:\+[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?\b(?![0-9A-Za-z-]|\.[0-9A-Za-z])/
      |> Regex.scan(content)
      |> Enum.map(&hd/1)

    vtagged =
      ~r/@version\s+"(v?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)"/
      |> Regex.scan(content)
      |> Enum.map(fn [_, value] -> value end)

    bare ++ vtagged
  end

  defp current_version, do: Mix.Project.config()[:version]

  # The migration guide must show the exact previous package pin it
  # replaces. CONTRIBUTING may name the exact toolchain versions from CI.
  defp allowed_document_version?("documentation/migrating-to-1.0.md", claim, version),
    do: claim in [version, "0.8.4"]

  defp allowed_document_version?("documentation/verifying-releases.md", claim, version),
    do: claim in [version, "0.8.4", hd(String.split(version, "-"))]

  # These guides reproduce the shipped echo Deployment Manifest, whose
  # build identity intentionally names the fixture's original package version.
  defp allowed_document_version?(file, claim, version)
       when file in ["documentation/examples.md", "documentation/what-a-deployment-is.md"],
       do: claim in [version, "0.1.0"]

  defp allowed_document_version?("CONTRIBUTING.md", claim, version) do
    claim == version or claim in ci_toolchain_versions()
  end

  defp allowed_document_version?(file, claim, version)
       when file in [
              "documentation/stability.md",
              "documentation/typescript.md",
              "docs/adr/stability-policy.md",
              "spec/protocol.md",
              "verifier/README.md"
            ] do
    package = :json.decode(File.read!("package.json"))

    floor =
      String.replace_prefix(package["devDependencies"]["typescript-floor"], "npm:typescript@", "")

    claim == version or claim == floor
  end

  defp allowed_document_version?(_file, claim, version), do: claim == version

  defp ci_toolchain_versions do
    workflow = File.read!(".github/workflows/ci.yml")

    ~r/(?:node-version|elixir-version|otp-version|elixir):\s*"(\d+\.\d+\.\d+)(?:-otp-\d+(?:\.\d+)*)?"/
    |> Regex.scan(workflow)
    |> Enum.map(fn [_, version] -> version end)
    |> Enum.uniq()
  end

  defp coverage_threshold, do: Mix.Project.config()[:test_coverage][:summary][:threshold]

  defp assert_claim(doc, regex, expected, label) do
    claims = regex |> Regex.scan(doc) |> Enum.map(fn [_, value] -> value end)

    assert claims != [], "CONTRIBUTING.md or README.md makes no #{label} claim"

    stale = Enum.uniq(claims) -- [to_string(expected)]
    assert stale == [], "#{label} claims #{inspect(stale)}. The live value is #{expected}"
  end

  defp assert_optional_claim(doc, regex, expected, label) do
    claims = regex |> Regex.scan(doc) |> Enum.map(fn [_, value] -> value end)
    stale = Enum.uniq(claims) -- [to_string(expected)]
    assert stale == [], "#{label} claims #{inspect(stale)}. The live value is #{expected}"
  end

  # Every hex requirement string in README is an install pin; they must all
  # name the current version.
  defp requirement_pins(readme) do
    ~r/"(~> [^"]+)"/
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

  # The supported table's first DATA row (a stale first row, a wrong line,
  # or the current line marked no, reds; older lines may follow).
  defp first_supported_row(security) do
    case Regex.run(
           ~r/^\| Version \| Supported \|\n\| -+ \| -+ \|\n\| ([^|]+?) \| ([^|]+?) \|/m,
           security
         ) do
      [_, version, status] -> {String.trim(version), String.trim(status)}
      nil -> {nil, nil}
    end
  end

  # The changelog's first version heading must be the current release. An
  # `## [Unreleased]` section may sit above it (changes landed on main
  # after the current release); it is not a version heading.
  defp first_version_heading(changelog) do
    case Regex.run(~r/^## \[(?!Unreleased\])([^\]]+)\]/m, changelog) do
      [_, heading] -> heading
      nil -> ""
    end
  end

  # CONTRIBUTING's "N tests" claim states the ExUnit total (test macros plus
  # property macros); the suite-registered count (.test_census, written
  # at suite end) is tied to this census by the release-candidate
  # check, which runs AFTER the test step of the battery.
  defp live_test_count, do: macro_census("test") + macro_census("property")

  defp live_property_count, do: macro_census("property")

  # The census counts test/property macros across the test tree (support
  # files carry none), the same total ExUnit reports for this suite.
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
