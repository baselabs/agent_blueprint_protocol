defmodule AgentBlueprintProtocol.Architecture.DocumentationCurrencyTest do
  @moduledoc """
  Public documentation tracks the current package version, install pins,
  supported releases, and configured coverage threshold. Consumer examples
  resolve installed resources independently of the working directory.
  """

  use ExUnit.Case, async: true

  @readme_path "README.md"
  @security_path "SECURITY.md"

  test "consumer examples never locate resources relative to the working directory" do
    documents =
      Enum.uniq(
        shipped_markdown() ++
          Mix.Project.config()[:docs][:extras] ++
          Path.wildcard("lib/**/*.ex") ++ ["verifier/README.md"]
      )

    offenders =
      for file <- documents,
          source = File.read!(file),
          code <- consumer_code(file, source),
          reference <- relative_resources(code),
          do: {file, reference}

    assert offenders == [],
           "consumer examples depend on checkout-relative resources: #{inspect(offenders, limit: :infinity)}"
  end

  defp consumer_code("lib/" <> _, source) do
    {_ast, docs} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:@, _, [{name, _, [doc]}]} = node, docs
        when name in [:moduledoc, :doc, :typedoc] and is_binary(doc) ->
          {node, [doc | docs]}

        node, docs ->
          {node, docs}
      end)

    docs
  end

  defp consumer_code(_file, source) do
    ~r/^```(?:elixir|iex|js|javascript|ts|typescript)\r?\n(.*?)^```/ms
    |> Regex.scan(source, capture: :all_but_first)
    |> Enum.map(&hd/1)
  end

  defp relative_resources(code) do
    code =
      Regex.replace(
        ~r/Application\.app_dir\(\s*:agent_blueprint_protocol\s*,\s*"[^"]+"\s*\)/s,
        code,
        "installed_resource"
      )

    paths =
      ~r/["'](?:\.{1,2}\/)*(?:examples|priv|spec|documentation|docs|lib)(?:\/[^"'\n]*)?["']/
      |> Regex.scan(code)
      |> Enum.map(&hd/1)

    locators =
      ~r/Mix\.Project\.deps_paths\(\)|File\.cwd!\(\)/
      |> Regex.scan(code)
      |> Enum.map(&hd/1)

    paths ++ locators
  end

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

    # README npm commands pin this exact release in both candidate and final trees.
    # The npm view sentence lets readers inspect the registry tags.
    npm_commands =
      ~r/\b(?:npm install|npx)\s+(@agent-blueprint-protocol\/verifier(?:@[A-Za-z0-9.+-]+)?)/
      |> Regex.scan(readme)
      |> Enum.map(fn [_, command] -> command end)
      |> Enum.uniq()

    assert npm_commands == ["@agent-blueprint-protocol/verifier@" <> version],
           "README npm kit commands must pin the exact current version #{version}, found #{inspect(npm_commands)}"

    assert readme =~ "npm view @agent-blueprint-protocol/verifier",
           "README must say how to see which kit npx runs"

    refute Regex.match?(~r/\b\d+ tests\b|\(\d+ properties\)|\b\d+% coverage\b/, readme),
           "README must not carry test statistics"

    contributing = File.read!("CONTRIBUTING.md")

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

  test "no shipped document outside the release docs carries a stale concrete version claim" do
    version = current_version()
    # Release documents retain historical versions; other shipped markdown
    # may state only the current version or an explicitly permitted pin.
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

    # The promotion classifier owns which documents can change release pins.
    # Read it once, including package READMEs and pages outside the Hex package.
    {rules_json, 0} = System.cmd("node", ["scripts/check_release_promotion.mjs", "--rules"])
    rules = Jason.decode!(rules_json)

    documents =
      Enum.uniq(
        shipped_markdown() ++ Path.wildcard("verifier/*.md") ++ Path.wildcard("site/**/*.html")
      )

    pin_offenders =
      for file <- documents,
          rule = Map.fetch!(rules, file),
          rule != "changelog",
          ref <- release_pins(File.read!(file)),
          not current_release_ref?(file, ref, version, rule),
          uniq: true do
        {file, ref, rule}
      end

    assert pin_offenders == [],
           "documents must link the current release #{version} or main when frozen: " <>
             inspect(pin_offenders)

    assert release_pins(
             "[a](https://hexdocs.pm/agent_blueprint_protocol/0.9.9/x.html) " <>
               "https://raw.githubusercontent.com/baselabs/agent_blueprint_protocol/0123abc/x " <>
               ~s(<a href="https://github.com/baselabs/agent_blueprint_protocol/blob/v0.9.9/y">) <>
               "https://github.com/baselabs/agent_blueprint_protocol/tree/v0.9.9/z " <>
               "https://github.com/baselabs/agent_blueprint_protocol/releases/download/v0.9.9/a.tar.gz " <>
               "https://agent-blueprint-protocol.hexdocs.pm/0.9.9/ " <>
               "npx @agent-blueprint-protocol/verifier@0.9.9"
           ) == ["0.9.9", "0123abc", "v0.9.9", "v0.9.9", "v0.9.9", "0.9.9", "0.9.9"]

    refute current_release_ref?("README.md", "0123abc", "2.0.0", "version")
    assert current_release_ref?("README.md", "v2.0.0", "2.0.0", "version")
    refute current_release_ref?("README.md", "main", "2.0.0", "version")
    refute current_release_ref?("SUPPORT.md", "v2.0.0", "2.0.0", "frozen")
    refute current_release_ref?("SUPPORT.md", "0123abc", "2.0.0", "frozen")
    assert current_release_ref?("SUPPORT.md", "main", "2.0.0", "frozen")
    assert current_release_ref?("documentation/migrating-to-1.0.md", "v0.8.4", "2.0.0", "version")

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

  # Package entries include bare directories ("documentation", "priv/examples");
  # a flat ends_with?(".md") filter over the entries list silently skipped
  # every file inside them, which is how the guides' install pins drifted.
  # Livebooks (.livemd) are shipped documents too and carry the same claims.
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

  # The release a link names, read from the positions that identify one of
  # this project's releases: a HexDocs version, a GitHub ref of this
  # repository, and the npm verifier pin.
  defp release_pins(content) do
    [
      ~r{agent-blueprint-protocol\.hexdocs\.pm/([^/\s)"'#?]+)/},
      ~r{hexdocs\.pm/agent_blueprint_protocol/([^/\s)"'#?]+)/},
      ~r{github\.com/baselabs/agent_blueprint_protocol/(?:blob|tree)/([^/\s)"'#?]+)},
      ~r{github\.com/baselabs/agent_blueprint_protocol/releases/download/([^/\s)"'#?]+)},
      ~r{raw\.githubusercontent\.com/baselabs/agent_blueprint_protocol/([^/\s)"'#?]+)},
      ~r{@agent-blueprint-protocol/verifier@(\d[0-9A-Za-z.+-]*[0-9A-Za-z])}
    ]
    |> Enum.flat_map(&Regex.scan(&1, content, capture: :all_but_first, return: :index))
    |> List.flatten()
    |> Enum.sort()
    |> Enum.map(fn {start, length} -> binary_part(content, start, length) end)
  end

  # Frozen documents cannot change pins during promotion, so they link main.
  # Release documents name this version/tag or an existing allowed example.
  defp current_release_ref?(_file, ref, _version, "frozen"), do: ref == "main"

  defp current_release_ref?(file, ref, version, _rule) do
    ref in [version, "v" <> version] or
      (ref =~ ~r/^v?\d+\.\d+\.\d+/ and
         allowed_document_version?(file, String.trim_leading(ref, "v"), version))
  end

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

    assert claims != [], "document makes no #{label} claim"

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
end
