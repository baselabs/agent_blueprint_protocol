defmodule AgentBlueprintProtocol.Architecture.DocumentationCurrencyTest do
  @moduledoc """
  Public documentation tracks the current package version, install pins,
  supported releases, and configured coverage threshold. Consumer examples
  resolve installed resources independently of the working directory.
  """

  use ExUnit.Case, async: true

  @readme_path "README.md"
  @security_path "SECURITY.md"

  test "release instructions describe dispatch, refusal, and DevOps-created tags" do
    for path <- [
          "AGENTS.md",
          "CONTRIBUTING.md",
          "docs/adr/0021-release-publication.md",
          "docs/adr/0029-release-site.md"
        ] do
      source = File.read!(path)
      assert source =~ "dispatch", path
      assert source =~ "publish", path
      refute source =~ "The tag starts the publish workflow", path
      refute source =~ "rerun the workflow on the same tag", path
      refute source =~ "deploys `site/` on tags", path
      refute source =~ "workflow_run", path
      refute source =~ "DevOps owner", path
    end

    publication = File.read!("docs/adr/0021-release-publication.md")
    assert publication =~ "A second dispatch on the same commit finishes a held release"
    assert publication =~ "new tag"
    assert publication =~ "No workflow creates a release or tag"
    assert publication =~ "`HEX_API_KEY` as an environment secret"
    assert publication =~ "environment **`publish`**"
    assert publication =~ "owner review and default-branch deployment"

    site = File.read!("docs/adr/0029-release-site.md")
    assert site =~ "Pages accepts only `workflow_dispatch`"
    assert site =~ "No tag push or workflow event starts Pages"
    refute site =~ "head_sha"

    for path <- [
          "CONTRIBUTING.md",
          "docs/adr/0019-continuous-integration.md",
          "docs/adr/0021-release-publication.md"
        ] do
      source = File.read!(path)
      assert source =~ "kci/**", path
      assert source =~ "qualified", path
      assert source =~ "scripts/toolchain.sh", path
    end

    assert publication =~
             "scripts/publish_hex_artifacts.exs [--organization ORG] NAME VERSION [--package ARCHIVE] [--docs DOCS]"

    assert publication =~ "`github-pages` environment"
  end

  test "shipped document fences have at most a bare language info string" do
    offenders =
      for file <- shipped_markdown(),
          {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          [_, info] <- Regex.scan(~r/^ {0,3}(?:`{3,}|~{3,})([^`~]*)$/, line),
          length(String.split(info)) > 1,
          do: "#{file}:#{number}: #{String.trim(info)}"

    assert offenders == [],
           "fence info strings must contain only a language; use a preceding <!-- fragment --> comment:\n" <>
             Enum.join(offenders, "\n")
  end

  test "the migration checklist distinguishes historical and current verification semantics" do
    metadata = Jason.decode!(File.read!("priv/release-metadata.json"))
    history = Jason.decode!(File.read!("priv/release-history.json"))
    historic = Enum.find(history["rows"], &(&1["package_version"] == "1.0.0"))

    checklist =
      File.read!("documentation/migrating-to-1.0.md")
      |> String.split("## Migration checklist")
      |> List.last()

    line = current_version() |> String.split(".") |> Enum.take(2) |> Enum.join(".")

    assert checklist =~
             "verification semantics is `#{historic["verification_semantics_version"]}` at 1.0 and `#{metadata["verification_semantics_version"]}` from #{line}",
           "migration checklist must distinguish 1.0 semantics from current release semantics #{metadata["verification_semantics_version"]}"

    assert checklist =~ "[1.1 changes](upgrading.md)",
           "migration checklist must link the current upgrade instructions"
  end

  test "TypeScript import tables map aggregate reports separately from per-case results" do
    facade = File.read!("verifier/facade.ts")

    exports =
      Regex.scan(~r/export function (\w+)\(/, facade, capture: :all_but_first) |> List.flatten()

    mappings = [
      {"blueprint", "decode", "decodeBlueprint"},
      {"deployment", "decode", "decodeDeployment"},
      {"federation", "decode", "decodeFederationEnvelope"},
      {"negotiation", "negotiate", "negotiate"},
      {"bounds_algebra", "intersect", "intersect"},
      {"compatibility", "verify", "verifyCompatibility"},
      {"signature", "verify", "verifySignature"},
      {"corpus", "load", "loadCorpus"},
      {"runner", "run", "runCorpus"},
      {"report", "build", "buildReport"}
    ]

    for file <- ~w(documentation/typescript.md documentation/migrating-to-1.0.md) do
      source = File.read!(file)

      for {mod, previous, replacement} <- mappings do
        assert replacement in exports

        assert source =~ "| `dist/verifier/#{mod}.js`: `#{previous}` | `#{replacement}`",
               "#{file}: #{mod}.#{previous} must map to #{replacement} in its own row"
      end

      assert source =~ "| Artifact modules: `canonicalBytes` | `canonicalBytes` |"
      assert "canonicalBytes" in exports

      assert source =~ "| `dist/verifier/report.js`: `toBytes` | No package-root byte encoder.",
             "#{file}: report.toBytes must name the missing aggregate byte API, not buildResultsDocument"

      assert source =~
               "npx @agent-blueprint-protocol/verifier@#{current_version()} --corpus <dir> > report.json",
             "#{file}: report.toBytes migration must show the canonical aggregate-report CLI command"
    end
  end

  test "locally installed npm commands use pinned npx" do
    readme = File.read!("verifier/README.md")

    refute Regex.match?(~r/^agent-blueprint-protocol\s/m, readme),
           "npm README must use pinned npx for its locally installed CLI"
  end

  test "directly spawned walkthrough adapters use a portable executable" do
    for file <- ~w(documentation/conformance.md docs/livebooks/conformance-and-attacks.livemd) do
      source = File.read!(file)

      adapters =
        Regex.scan(~r/^.*conformance run .* -- (.+)$/m, source, capture: :all_but_first)
        |> List.flatten()

      assert length(adapters) == 2

      for adapter <- adapters do
        assert String.starts_with?(
                 adapter,
                 "node node_modules/@agent-blueprint-protocol/verifier/dist/kit/cli.mjs "
               ),
               "#{file}: walkthrough adapters must run the installed CLI with node, not a Windows batch launcher"
      end

      assert source =~ "started directly without a shell"
      assert source =~ "`.cmd` or `.bat` launcher must be run through its interpreter"
    end
  end

  test "every TypeScript doc comment directly precedes a declaration" do
    offenders =
      for file <- Path.wildcard("verifier/*.ts"),
          source = File.read!(file),
          [{at, size}] <- Regex.scan(~r{/\*\*.*?\*/}s, source, return: :index),
          following = binary_part(source, at + size, byte_size(source) - at - size),
          not Regex.match?(
            ~r/\A\s*(?:(?:export|declare)\s+)*(?:async\s+)?(?:function|const|let|var|class|interface|type|enum|namespace)\b|\A\s*export\s*[\{*]/,
            following
          ),
          do: "#{file}:#{length(String.split(binary_part(source, 0, at), "\n"))}"

    assert offenders == [], "orphan TypeScript doc comments: " <> Enum.join(offenders, ", ")
  end

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

  defp shipped_markdown, do: AgentBlueprintProtocol.ShippedDocuments.paths()

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
  # replaces. CONTRIBUTING may name the exact configured toolchain versions.
  defp allowed_document_version?("documentation/migrating-to-1.0.md", claim, version),
    do: claim in [version, "0.8.4"]

  defp allowed_document_version?("documentation/verifying-releases.md", claim, version),
    do: claim in [version, "0.8.4", hd(String.split(version, "-"))]

  # These guides reproduce the shipped echo Deployment Manifest, whose
  # build identities intentionally name the fixtures' original package versions.
  defp allowed_document_version?(file, claim, version)
       when file in ["documentation/examples.md", "documentation/what-a-deployment-is.md"],
       do: claim in [version, "0.1.0", "0.1.0-dev.abc"]

  defp allowed_document_version?("CONTRIBUTING.md", claim, version) do
    claim == version or claim in configured_toolchain_versions()
  end

  defp allowed_document_version?(file, claim, version)
       when file in [
              "documentation/stability.md",
              "documentation/typescript.md",
              "docs/adr/0014-stability-policy.md",
              "spec/protocol.md",
              "verifier/README.md"
            ] do
    package = :json.decode(File.read!("package.json"))

    floor =
      String.replace_prefix(package["devDependencies"]["typescript-floor"], "npm:typescript@", "")

    claim == version or claim == floor
  end

  defp allowed_document_version?(_file, claim, version), do: claim == version

  defp configured_toolchain_versions do
    {output, 0} = System.cmd("scripts/toolchain.sh", [])

    ~r/\b(\d+(?:\.\d+)+)(?:-otp-\d+)?/
    |> Regex.scan(output)
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
