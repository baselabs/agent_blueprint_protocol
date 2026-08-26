defmodule AgentBlueprintProtocol.Architecture.PackageBoundaryTest do
  @moduledoc """
  Package-boundary gate: the Hex archive ships exactly the public allowlist and
  nothing else, verified both directions. Private planning material, tests,
  dependencies, and generated output must never ship.

  This allowlist is expected to grow as the package gains conformance data and
  registry content; it is frozen here against the current verified archive.
  """
  use ExUnit.Case, async: false

  # The exact, frozen set of paths the built archive is allowed to contain.
  # `hex_metadata.config` is emitted by `mix hex.build`; the rest are the
  # declared public files. Verified against a real build 2026-08-20.
  @allowed_archive_files ~w(
    .formatter.exs
    CHANGELOG.md
    LICENSE
    NOTICE
    README.md
    SECURITY.md
    hex_metadata.config
    docs/federation-mapping.md
    docs/adr/compiled-registry.md
    docs/adr/deny-default-clamps.md
    docs/adr/detached-jws-envelope.md
    docs/adr/federation-lanes.md
    docs/adr/no-versioning-rule.md
    docs/adr/non-authorizing-boundary.md
    docs/adr/producer-surface.md
    docs/adr/product-extension-registration.md
    docs/adr/two-consumer-amendment.md
    priv/release-metadata.json
    spec/protocol.md
    spec/README.md
    spec/LICENSE
    spec/NOTICE
    spec/grammar/blueprint.cddl
    spec/grammar/deployment.cddl
    spec/grammar/taskenvelope.cddl
    spec/grammar/derived/blueprint.schema.json
    spec/grammar/derived/deployment.schema.json
    spec/grammar/derived/taskenvelope.schema.json
    lib/agent_blueprint_protocol.ex
    lib/agent_blueprint_protocol/base64url.ex
    lib/agent_blueprint_protocol/blueprint.ex
    lib/agent_blueprint_protocol/bounds.ex
    lib/agent_blueprint_protocol/bounds_algebra.ex
    lib/agent_blueprint_protocol/canonicalization.ex
    lib/agent_blueprint_protocol/compatibility.ex
    lib/agent_blueprint_protocol/conformance/cli.ex
    lib/agent_blueprint_protocol/conformance/cli/main.ex
    lib/agent_blueprint_protocol/conformance/corpus.ex
    lib/agent_blueprint_protocol/conformance/report.ex
    lib/agent_blueprint_protocol/conformance/runner.ex
    lib/agent_blueprint_protocol/deployment.ex
    lib/agent_blueprint_protocol/evidence.ex
    lib/agent_blueprint_protocol/federation.ex
    lib/agent_blueprint_protocol/negotiation.ex
    lib/agent_blueprint_protocol/digest.ex
    lib/agent_blueprint_protocol/error.ex
    lib/agent_blueprint_protocol/extension.ex
    lib/agent_blueprint_protocol/extension_registry.ex
    lib/agent_blueprint_protocol/json.ex
    lib/agent_blueprint_protocol/portability.ex
    lib/agent_blueprint_protocol/predicate.ex
    lib/agent_blueprint_protocol/reconcile.ex
    lib/agent_blueprint_protocol/registry.ex
    lib/agent_blueprint_protocol/schema.ex
    lib/agent_blueprint_protocol/signature.ex
    mix.exs
    usage-rules.md
  )

  # The exact, ordered `package.files` allowlist declared in mix.exs. A planted
  # contaminant path here fails this test immediately, before any build.
  @declared_files ~w(
    lib
    priv/conformance
    priv/release-metadata.json
    docs/federation-mapping.md
    docs/adr/compiled-registry.md
    docs/adr/deny-default-clamps.md
    docs/adr/detached-jws-envelope.md
    docs/adr/federation-lanes.md
    docs/adr/no-versioning-rule.md
    docs/adr/non-authorizing-boundary.md
    docs/adr/producer-surface.md
    docs/adr/product-extension-registration.md
    docs/adr/two-consumer-amendment.md
    spec/protocol.md
    spec/README.md
    spec/LICENSE
    spec/NOTICE
    spec/grammar
    .formatter.exs
    mix.exs
    README.md
    CHANGELOG.md
    LICENSE
    NOTICE
    SECURITY.md
    usage-rules.md
  )

  @build_dir "_build/architecture_pkg_check"

  # The minimum quality-alias gate set. The release-candidate check reads
  # the LIVE alias to derive map obligations — this freezes the floor, so
  # deleting a gate step cannot silently delete its map requirement.
  @minimum_quality_steps [
    "hex.audit",
    "deps.unlock --check-unused",
    "deps.audit",
    "format --check-formatted",
    "compile --warnings-as-errors",
    "credo --strict",
    "test --cover --seed 42",
    "conformance.verify",
    "conformance.mutations",
    "verifier.agreement",
    "dialyzer",
    "docs --warnings-as-errors",
    "spec.extraction",
    "grammar.derivation",
    "release.candidate"
  ]

  test "the quality alias carries the minimum gate set" do
    steps = Mix.Project.config()[:aliases][:quality]
    missing = @minimum_quality_steps -- steps

    assert missing == [],
           "quality alias lost gate steps (each step owes a requirement-map entry): #{inspect(missing)}"
  end

  test "package.files declares exactly the allowlisted entries" do
    assert Mix.Project.config()[:package][:files] == @declared_files
  end

  test "the built Hex archive ships exactly the allowlist, both directions" do
    {unpack_dir, shipped} = build_and_list_archive()

    {corpus_files, code_files} =
      shipped |> Enum.split_with(&String.starts_with?(&1, "priv/conformance/"))

    # Code + docs stay on the frozen name allowlist.
    allowed = MapSet.new(@allowed_archive_files)
    actual = MapSet.new(code_files)

    unexpected = MapSet.difference(actual, allowed) |> MapSet.to_list()
    missing = MapSet.difference(allowed, actual) |> MapSet.to_list()

    assert actual == allowed,
           "archive contents drifted from the allowlist\n" <>
             "  unexpected (contaminant leaked into the package): #{inspect(unexpected)}\n" <>
             "  missing (declared public file dropped): #{inspect(missing)}"

    # The corpus subtree is verified the STRONGER way (the corpus-verification
    # installed-package smoke): EVERY shipped file — dotfiles included —
    # feeds the loader, whose hash-indexed file-set equality reds on an
    # extra, missing, or corrupt file; then the runner must agree.
    corpus_map =
      Enum.into(corpus_files, %{}, fn rel ->
        {String.replace_prefix(rel, "priv/conformance/", ""),
         File.read!(Path.join(unpack_dir, rel))}
      end)

    alias AgentBlueprintProtocol.Conformance.{Corpus, Report, Runner}

    {:ok, corpus} = Corpus.load(corpus_map)
    results = Runner.run(corpus)
    report = Report.build(corpus, results)

    assert report.agreement,
           "the installed corpus does not verify: #{inspect(Map.from_struct(report))}"

    File.rm_rf!(@build_dir)
  end

  # Keeps the unpacked archive alive for the installed-corpus smoke; the
  # caller owns cleanup.
  defp build_and_list_archive do
    File.rm_rf!(@build_dir)
    File.mkdir_p!(@build_dir)
    unpack_dir = Path.join(@build_dir, "pkg")

    {_out, 0} =
      System.cmd("mix", ["hex.build", "--unpack", "--output", unpack_dir],
        stderr_to_stdout: true,
        env: [{"MIX_QUIET", "1"}]
      )

    files =
      Path.join(unpack_dir, "**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(&File.dir?/1)
      |> Enum.map(&Path.relative_to(&1, unpack_dir))
      |> Enum.sort()

    {unpack_dir, files}
  end
end
