defmodule AgentBlueprintProtocol.Architecture.PackageBoundaryTest do
  @moduledoc """
  Package-boundary gate: the Hex archive ships exactly the public allowlist and
  nothing else, verified both directions. Private planning material, tests,
  dependencies, and generated output must never ship.

  This allowlist is expected to grow as the package gains conformance data and
  registry content; it is frozen here against the current verified archive.
  """
  use ExUnit.Case, async: false

  @moduletag timeout: :infinity

  # The exact, frozen set of paths the built archive is allowed to contain.
  # `hex_metadata.config` is emitted by `mix hex.build`; the rest are the
  # declared public files.
  @allowed_archive_files ~w(
    .formatter.exs
    CHANGELOG.md
    LICENSE
    NOTICE
    README.md
    SECURITY.md
    hex_metadata.config
    docs/ROADMAP.md
    docs/federation-mapping.md
    docs/ard-mapping.md
    docs/livebooks/abp-walkthrough.livemd
    docs/livebooks/producing-artifacts.livemd
    docs/livebooks/host-import.livemd
    docs/livebooks/extensions-and-federation.livemd
    docs/livebooks/conformance-and-attacks.livemd
    docs/adr/0001-compiled-registry.md
    docs/adr/0002-deny-default-clamps.md
    docs/adr/0003-detached-jws-envelope.md
    docs/adr/0004-federation-lanes.md
    docs/adr/0005-no-versioning-rule.md
    docs/adr/0006-non-authorizing-boundary.md
    docs/adr/0007-two-consumer-amendment.md
    docs/adr/0008-producer-surface.md
    docs/adr/0009-product-extension-registration.md
    docs/adr/0010-supported-otp-set.md
    docs/adr/0011-release-identity-semantics.md
    docs/adr/0017-artifact-portability.md
    docs/adr/0018-normative-extraction.md
    docs/adr/0019-runtime-boundary.md
    docs/adr/0020-kit-cli.md
    priv/release-metadata.json
    priv/release-history.json
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
    spec/registry/registry.json
    spec/IPR.md
    spec/FOUNDATION-TRANSITION.md
    spec/registry/OPERATIONS.md
    spec/errata.md
    CONTRIBUTING.md
    CODE_OF_CONDUCT.md
    SUPPORT.md
    documentation/errors.md
    documentation/evidence-commitments.md
    documentation/architecture.md
    documentation/cheatsheet.cheatmd
    documentation/compose-and-sign.md
    documentation/extensions.md
    documentation/faq.md
    documentation/federation.md
    documentation/handling-errors.md
    documentation/host-integration.md
    documentation/portability.md
    documentation/positioning.md
    documentation/producer.md
    documentation/reading-evidence.md
    documentation/security-model.md
    documentation/upgrading.md
    documentation/verifying-in-ci.md
    documentation/verifying-releases.md
    documentation/what-a-blueprint-is.md
    documentation/what-a-deployment-is.md
    documentation/quickstart.md
    documentation/typescript.md
    documentation/examples.md
    scripts/extract_livebooks.exs
    scripts/package_examples.exs
    scripts/run_package_typescript_examples.mjs
    scripts/consumer_examples.exs
    priv/examples/echo-blueprint.json
    priv/examples/echo-deployment.json
    priv/examples/federation-envelope.json
    priv/examples/signed-blueprint.json
    priv/examples/extension-blueprint.json
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
    docs/adr/0012-conformance-product.md
    docs/adr/0013-stability-policy.md
    docs/adr/0014-three-platform-support.md
    docs/adr/0015-typescript-library-surface.md
    docs/adr/0016-verification-results.md
    documentation/stability.md
    documentation/conformance.md
    documentation/glossary.md
    documentation/migrating-to-1.0.md
    spec/conformance/base64url-decode.schema.json
    spec/conformance/blueprint-decode.schema.json
    spec/conformance/bounds-new.schema.json
    spec/conformance/bounds_algebra-intersect.schema.json
    spec/conformance/canonicalization-encode.schema.json
    spec/conformance/case-file.schema.json
    spec/conformance/certified-results.json
    spec/conformance/claim.schema.json
    spec/conformance/compatibility-verify.schema.json
    spec/conformance/deployment-decode.schema.json
    spec/conformance/digest-tagged.schema.json
    spec/conformance/execution.md
    spec/conformance/evidence.schema.json
    spec/conformance/extension-resolve.schema.json
    spec/conformance/federation-decode.schema.json
    spec/conformance/federation-verify_commitment.schema.json
    spec/conformance/index.schema.json
    spec/conformance/json-decode.schema.json
    spec/conformance/negotiation-negotiate.schema.json
    spec/conformance/portability-scan.schema.json
    spec/conformance/predicate.schema.json
    spec/conformance/reconcile.schema.json
    spec/conformance/runner.md
    spec/conformance/schema-validate_instance.schema.json
    spec/conformance/signature-verify.schema.json
    spec/conformance/support.schema.json
  )

  # The exact, ordered `package.files` allowlist declared in mix.exs. A planted
  # contaminant path here fails this test immediately, before any build.
  @declared_files ~w(
    lib
    priv/conformance
    priv/release-metadata.json
    priv/release-history.json
    docs/ROADMAP.md
    docs/federation-mapping.md
    docs/ard-mapping.md
    docs/livebooks/abp-walkthrough.livemd
    docs/livebooks/producing-artifacts.livemd
    docs/livebooks/host-import.livemd
    docs/livebooks/extensions-and-federation.livemd
    docs/livebooks/conformance-and-attacks.livemd
    docs/adr/0001-compiled-registry.md
    docs/adr/0002-deny-default-clamps.md
    docs/adr/0003-detached-jws-envelope.md
    docs/adr/0004-federation-lanes.md
    docs/adr/0005-no-versioning-rule.md
    docs/adr/0006-non-authorizing-boundary.md
    docs/adr/0007-two-consumer-amendment.md
    docs/adr/0008-producer-surface.md
    docs/adr/0009-product-extension-registration.md
    docs/adr/0010-supported-otp-set.md
    docs/adr/0011-release-identity-semantics.md
    docs/adr/0012-conformance-product.md
    docs/adr/0013-stability-policy.md
    docs/adr/0014-three-platform-support.md
    docs/adr/0015-typescript-library-surface.md
    docs/adr/0016-verification-results.md
    docs/adr/0017-artifact-portability.md
    docs/adr/0018-normative-extraction.md
    docs/adr/0019-runtime-boundary.md
    docs/adr/0020-kit-cli.md
    spec/protocol.md
    spec/README.md
    spec/LICENSE
    spec/NOTICE
    spec/grammar
    spec/conformance
    spec/registry/registry.json
    spec/IPR.md
    spec/FOUNDATION-TRANSITION.md
    spec/registry/OPERATIONS.md
    spec/errata.md
    CONTRIBUTING.md
    CODE_OF_CONDUCT.md
    SUPPORT.md
    documentation
    priv/examples
    scripts/extract_livebooks.exs
    scripts/package_examples.exs
    scripts/run_package_typescript_examples.mjs
    scripts/consumer_examples.exs
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

  test "package.files declares exactly the allowlisted entries" do
    assert Mix.Project.config()[:package][:files] == @declared_files
  end

  # The kit's shipped declarations import `node:` types, so they compile against
  # the oldest Node the package supports, never a newer one.
  test "Node typings track the engines floor" do
    package = :json.decode(File.read!("package.json"))
    lock = :json.decode(File.read!("package-lock.json"))
    [floor] = Regex.run(~r/\A>=(\d+)\z/, package["engines"]["node"], capture: :all_but_first)

    assert package["devDependencies"]["@types/node"] == "^#{floor}.0.0"

    assert [^floor | _] =
             String.split(lock["packages"]["node_modules/@types/node"]["version"], ".")
  end

  test "the built Hex archive ships exactly the allowlist, both directions" do
    on_exit(fn -> File.rm_rf!(@build_dir) end)
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
    # installed-package smoke): EVERY shipped file, dotfiles included,
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
      for(
        relative <- :filelib.wildcard(~c"**/*", String.to_charlist(unpack_dir)),
        do: Path.join(unpack_dir, List.to_string(relative))
      )
      |> Enum.reject(&File.dir?/1)
      |> Enum.map(&Path.relative_to(&1, unpack_dir))
      |> Enum.sort()

    {unpack_dir, files}
  end
end
