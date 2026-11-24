defmodule AgentBlueprintProtocol.MixProject do
  use Mix.Project

  @version "1.1.2"
  @source_url "https://github.com/baselabs/agent_blueprint_protocol"

  def project do
    [
      app: :agent_blueprint_protocol,
      version: @version,
      elixir: "~> 1.19",
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      escript: escript(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      name: "Agent Blueprint Protocol",
      description: "Portable, non-authorizing agent blueprint and deployment manifest protocol.",
      source_url: @source_url,
      homepage_url: @source_url,
      test_coverage: [
        summary: [threshold: 100],
        ignore_modules: [
          AgentBlueprintProtocol.Conformance.Cli.Main,
          ~r/AgentBlueprintProtocol\.Conformance\.Cli\.Main/
        ]
      ],
      test_ignore_filters: [&String.starts_with?(&1, "test/support/")],
      dialyzer: [plt_core_path: "_build/plts", plt_local_path: "_build/plts"]
    ]
  end

  def cli do
    [preferred_envs: [audit: :test, quality: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [extra_applications: [:crypto]]
  end

  def escript do
    [
      path: "agent_blueprint_protocol_conformance",
      main_module: AgentBlueprintProtocol.Conformance.Cli.Main,
      embed_elixir: true
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.3", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["rjpalermo"],
      files: [
        "lib",
        "priv/conformance",
        "priv/release-metadata.json",
        "priv/release-history.json",
        "docs/ROADMAP.md",
        "docs/federation-mapping.md",
        "docs/ard-mapping.md",
        "docs/livebooks/abp-walkthrough.livemd",
        "docs/livebooks/producing-artifacts.livemd",
        "docs/livebooks/host-import.livemd",
        "docs/livebooks/extensions-and-federation.livemd",
        "docs/livebooks/conformance-and-attacks.livemd",
        "docs/adr/0001-compiled-registry.md",
        "docs/adr/0002-deny-default-clamps.md",
        "docs/adr/0003-detached-jws-envelope.md",
        "docs/adr/0004-federation-lanes.md",
        "docs/adr/0005-no-versioning-rule.md",
        "docs/adr/0006-non-authorizing-boundary.md",
        "docs/adr/0007-two-consumer-amendment.md",
        "docs/adr/0008-producer-surface.md",
        "docs/adr/0009-product-extension-registration.md",
        "docs/adr/0010-supported-otp-set.md",
        "docs/adr/0011-release-identity-semantics.md",
        "docs/adr/0012-conformance-product.md",
        "docs/adr/0013-stability-policy.md",
        "docs/adr/0014-three-platform-support.md",
        "docs/adr/0015-typescript-library-surface.md",
        "docs/adr/0016-verification-results.md",
        "docs/adr/0017-artifact-portability.md",
        "docs/adr/0018-normative-extraction.md",
        "docs/adr/0019-runtime-boundary.md",
        "docs/adr/0020-kit-cli.md",
        "spec/protocol.md",
        "spec/README.md",
        "spec/LICENSE",
        "spec/NOTICE",
        "spec/grammar",
        "spec/conformance",
        "spec/registry/registry.json",
        "spec/IPR.md",
        "spec/FOUNDATION-TRANSITION.md",
        "spec/registry/OPERATIONS.md",
        "spec/errata.md",
        "CONTRIBUTING.md",
        "CODE_OF_CONDUCT.md",
        "SUPPORT.md",
        "documentation",
        "priv/examples",
        "scripts/extract_livebooks.exs",
        "scripts/package_examples.exs",
        "scripts/run_package_typescript_examples.mjs",
        "scripts/consumer_examples.exs",
        ".formatter.exs",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "NOTICE",
        "SECURITY.md",
        "usage-rules.md"
      ],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Security policy" => "#{@source_url}/blob/main/SECURITY.md",
        "Documentation" => "https://hexdocs.pm/agent_blueprint_protocol",
        "Specification" => "#{@source_url}/blob/v#{@version}/spec/protocol.md",
        "npm" => "https://www.npmjs.com/package/@agent-blueprint-protocol/verifier"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      # Released changelog entries retain names that are now implementation details.
      skip_code_autolink_to: [
        "AgentBlueprintProtocol.Extension",
        "AgentBlueprintProtocol.Registry",
        "AgentBlueprintProtocol.Blueprint.table/0"
      ],
      source_url: @source_url,
      groups_for_modules: [
        Facade: [AgentBlueprintProtocol],
        Artifacts: [
          AgentBlueprintProtocol.Blueprint,
          AgentBlueprintProtocol.Deployment,
          AgentBlueprintProtocol.Deployment.Observations,
          AgentBlueprintProtocol.Federation,
          AgentBlueprintProtocol.Federation.Context,
          AgentBlueprintProtocol.Federation.Mapping.Row
        ],
        Verification: [
          AgentBlueprintProtocol.Signature,
          AgentBlueprintProtocol.Signature.Attributes,
          AgentBlueprintProtocol.Signature.PublicKey,
          AgentBlueprintProtocol.Digest,
          AgentBlueprintProtocol.Reconcile,
          AgentBlueprintProtocol.Reconcile.Inputs,
          AgentBlueprintProtocol.Evidence,
          AgentBlueprintProtocol.Evidence.Binding,
          AgentBlueprintProtocol.Evidence.Signatures,
          AgentBlueprintProtocol.Compatibility,
          AgentBlueprintProtocol.Compatibility.Observed,
          AgentBlueprintProtocol.Negotiation,
          AgentBlueprintProtocol.Negotiation.Outcome,
          AgentBlueprintProtocol.Negotiation.Support,
          AgentBlueprintProtocol.Portability,
          AgentBlueprintProtocol.Predicate,
          AgentBlueprintProtocol.Schema
        ],
        Bounds: [
          AgentBlueprintProtocol.Bounds,
          AgentBlueprintProtocol.BoundsAlgebra,
          AgentBlueprintProtocol.BoundsAlgebra.Bound,
          AgentBlueprintProtocol.BoundsAlgebra.BoundSet,
          AgentBlueprintProtocol.BoundsAlgebra.ClampEvidence,
          AgentBlueprintProtocol.BoundsAlgebra.Result,
          AgentBlueprintProtocol.BoundsAlgebra.Sources
        ],
        Extensions: [AgentBlueprintProtocol.ExtensionRegistry],
        Conformance: [
          AgentBlueprintProtocol.Conformance.Corpus,
          AgentBlueprintProtocol.Conformance.Runner,
          AgentBlueprintProtocol.Conformance.Report
        ],
        Encoding: [
          AgentBlueprintProtocol.Canonicalization,
          AgentBlueprintProtocol.Json,
          AgentBlueprintProtocol.Base64Url
        ],
        Errors: [AgentBlueprintProtocol.Error]
      ],
      groups_for_extras: [
        "Start here": [
          "README.md",
          "documentation/quickstart.md",
          "documentation/typescript.md",
          "documentation/migrating-to-1.0.md",
          "documentation/stability.md"
        ],
        Livebooks: [
          "docs/livebooks/abp-walkthrough.livemd",
          "docs/livebooks/producing-artifacts.livemd",
          "docs/livebooks/host-import.livemd",
          "docs/livebooks/extensions-and-federation.livemd",
          "docs/livebooks/conformance-and-attacks.livemd"
        ],
        Concepts: [
          "documentation/architecture.md",
          "documentation/what-a-blueprint-is.md",
          "documentation/what-a-deployment-is.md",
          "documentation/portability.md",
          "documentation/federation.md",
          "documentation/evidence-commitments.md",
          "documentation/positioning.md"
        ],
        "How-to guides": [
          "documentation/compose-and-sign.md",
          "documentation/handling-errors.md",
          "documentation/verifying-in-ci.md",
          "documentation/reading-evidence.md",
          "documentation/producer.md",
          "documentation/host-integration.md",
          "documentation/extensions.md"
        ],
        Reference: [
          "documentation/errors.md",
          "documentation/cheatsheet.cheatmd",
          "documentation/faq.md",
          "documentation/glossary.md",
          "documentation/security-model.md",
          "documentation/verifying-releases.md",
          "documentation/examples.md",
          "documentation/upgrading.md",
          "docs/ROADMAP.md",
          "docs/federation-mapping.md",
          "docs/ard-mapping.md",
          "CHANGELOG.md"
        ],
        Specification: [
          "spec/protocol.md",
          "spec/conformance/runner.md",
          "spec/conformance/execution.md"
        ],
        Conformance: ["documentation/conformance.md"],
        "Design records": [
          "docs/adr/0001-compiled-registry.md",
          "docs/adr/0002-deny-default-clamps.md",
          "docs/adr/0003-detached-jws-envelope.md",
          "docs/adr/0004-federation-lanes.md",
          "docs/adr/0005-no-versioning-rule.md",
          "docs/adr/0006-non-authorizing-boundary.md",
          "docs/adr/0007-two-consumer-amendment.md",
          "docs/adr/0008-producer-surface.md",
          "docs/adr/0009-product-extension-registration.md",
          "docs/adr/0010-supported-otp-set.md",
          "docs/adr/0011-release-identity-semantics.md",
          "docs/adr/0012-conformance-product.md",
          "docs/adr/0013-stability-policy.md",
          "docs/adr/0014-three-platform-support.md",
          "docs/adr/0015-typescript-library-surface.md",
          "docs/adr/0016-verification-results.md",
          "docs/adr/0017-artifact-portability.md",
          "docs/adr/0018-normative-extraction.md",
          "docs/adr/0019-runtime-boundary.md",
          "docs/adr/0020-kit-cli.md"
        ],
        Governance: [
          "spec/IPR.md",
          "spec/errata.md",
          "spec/registry/OPERATIONS.md",
          "CONTRIBUTING.md",
          "SUPPORT.md",
          "CODE_OF_CONDUCT.md",
          "SECURITY.md",
          "usage-rules.md",
          "LICENSE",
          "NOTICE"
        ]
      ],
      extras: [
        "README.md",
        "CHANGELOG.md",
        "documentation/quickstart.md",
        "documentation/typescript.md",
        "documentation/migrating-to-1.0.md",
        "documentation/stability.md",
        "docs/livebooks/abp-walkthrough.livemd",
        "docs/livebooks/producing-artifacts.livemd",
        "docs/livebooks/host-import.livemd",
        "docs/livebooks/extensions-and-federation.livemd",
        "docs/livebooks/conformance-and-attacks.livemd",
        "documentation/what-a-blueprint-is.md",
        "documentation/what-a-deployment-is.md",
        "documentation/portability.md",
        "documentation/federation.md",
        "documentation/architecture.md",
        "documentation/evidence-commitments.md",
        "documentation/positioning.md",
        "documentation/compose-and-sign.md",
        "documentation/handling-errors.md",
        "documentation/verifying-in-ci.md",
        "documentation/reading-evidence.md",
        "documentation/producer.md",
        "documentation/host-integration.md",
        "documentation/extensions.md",
        "documentation/errors.md",
        "documentation/cheatsheet.cheatmd",
        "documentation/faq.md",
        "documentation/upgrading.md",
        "documentation/security-model.md",
        "documentation/verifying-releases.md",
        "documentation/examples.md",
        "docs/ROADMAP.md",
        "docs/federation-mapping.md",
        "docs/ard-mapping.md",
        "documentation/glossary.md",
        "spec/protocol.md",
        "spec/conformance/runner.md",
        "spec/conformance/execution.md",
        "documentation/conformance.md",
        "docs/adr/0001-compiled-registry.md",
        "docs/adr/0002-deny-default-clamps.md",
        "docs/adr/0003-detached-jws-envelope.md",
        "docs/adr/0004-federation-lanes.md",
        "docs/adr/0005-no-versioning-rule.md",
        "docs/adr/0006-non-authorizing-boundary.md",
        "docs/adr/0007-two-consumer-amendment.md",
        "docs/adr/0008-producer-surface.md",
        "docs/adr/0009-product-extension-registration.md",
        "docs/adr/0010-supported-otp-set.md",
        "docs/adr/0011-release-identity-semantics.md",
        "docs/adr/0012-conformance-product.md",
        "docs/adr/0013-stability-policy.md",
        "docs/adr/0014-three-platform-support.md",
        "docs/adr/0015-typescript-library-surface.md",
        "docs/adr/0016-verification-results.md",
        "docs/adr/0017-artifact-portability.md",
        "docs/adr/0018-normative-extraction.md",
        "docs/adr/0019-runtime-boundary.md",
        "docs/adr/0020-kit-cli.md",
        "CONTRIBUTING.md",
        "SUPPORT.md",
        "CODE_OF_CONDUCT.md",
        "SECURITY.md",
        "spec/errata.md",
        "spec/IPR.md",
        "spec/registry/OPERATIONS.md",
        "usage-rules.md",
        "LICENSE",
        "NOTICE"
      ]
    ]
  end

  defp aliases do
    [
      audit: ["hex.audit", "deps.unlock --check-unused", "deps.audit"],
      "conformance.verify": [
        "escript.build",
        "cmd escript agent_blueprint_protocol_conformance --corpus priv/conformance"
      ],
      "conformance.product": [
        "escript.build",
        "run --no-start scripts/check_conformance_product.exs"
      ],
      "release.promote": ["run --no-start scripts/check_release_promotion.exs"],
      "conformance.mutations": [
        "run --no-start scripts/check_conformance_mutations.exs"
      ],
      "verifier.agreement": [
        "run --no-start scripts/check_verifier_agreement.exs"
      ],
      "compatibility.replay": [
        "run --no-start scripts/check_compatibility_replay.exs"
      ],
      "kit.build": [
        "cmd npm ci --ignore-scripts --no-audit --no-fund --loglevel=error",
        "cmd npm run build"
      ],
      "release.candidate": [
        "run --no-start scripts/check_release_candidate.exs"
      ],
      "spec.extraction": [
        "run --no-start scripts/check_spec_extraction.exs"
      ],
      "grammar.derivation": [
        "run --no-start scripts/check_grammar_derivation.exs"
      ],
      "registry.equality": [
        "run --no-start scripts/check_registry_equality.exs"
      ],
      "release.asset": [
        "run --no-start scripts/check_release_asset.exs"
      ],
      "typescript.guide": [
        "run --no-start scripts/check_typescript_guide.exs"
      ],
      "livebooks.package": ["run --no-start scripts/check_packaged_livebooks.exs"],
      "doctests.package": ["run --no-start scripts/check_packaged_doctests.exs"],
      "snippets.package": ["run --no-start scripts/check_packaged_examples.exs"],
      "typescript.package": ["cmd node scripts/check_packaged_typescript.mjs"],
      quality: [
        "hex.audit",
        "deps.unlock --check-unused",
        "deps.audit",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "test --cover --seed 42 --warnings-as-errors",
        "conformance.verify",
        "conformance.mutations",
        "kit.build",
        "conformance.product",
        "typescript.guide",
        "livebooks.package",
        "doctests.package",
        "snippets.package",
        "typescript.package",
        "verifier.agreement",
        "compatibility.replay",
        "dialyzer",
        "docs --warnings-as-errors",
        "spec.extraction",
        "grammar.derivation",
        "registry.equality",
        "release.asset",
        "release.promote",
        "release.candidate"
      ]
    ]
  end
end
