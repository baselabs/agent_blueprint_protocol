defmodule AgentBlueprintProtocol.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/baselabs/agent_blueprint_protocol"

  def project do
    [
      app: :agent_blueprint_protocol,
      version: @version,
      elixir: "~> 1.20",
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
        # The escript entry's only line is System.halt over a fully tested
        # function; executing it in-process would halt the test VM, so the
        # shim is excluded from the coverage census (not from any other gate).
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
        "docs/protocol.md",
        "docs/federation-mapping.md",
        "docs/adr/compiled-registry.md",
        "docs/adr/deny-default-clamps.md",
        "docs/adr/detached-jws-envelope.md",
        "docs/adr/federation-lanes.md",
        "docs/adr/no-versioning-rule.md",
        "docs/adr/non-authorizing-boundary.md",
        "docs/adr/producer-surface.md",
        "docs/adr/product-extension-registration.md",
        "docs/adr/two-consumer-amendment.md",
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
        "Security policy" => "#{@source_url}/blob/main/SECURITY.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "docs/protocol.md",
        "docs/federation-mapping.md",
        "docs/adr/compiled-registry.md",
        "docs/adr/deny-default-clamps.md",
        "docs/adr/detached-jws-envelope.md",
        "docs/adr/federation-lanes.md",
        "docs/adr/no-versioning-rule.md",
        "docs/adr/non-authorizing-boundary.md",
        "docs/adr/producer-surface.md",
        "docs/adr/product-extension-registration.md",
        "docs/adr/two-consumer-amendment.md",
        "LICENSE",
        "NOTICE",
        "SECURITY.md",
        "usage-rules.md"
      ]
    ]
  end

  defp aliases do
    [
      audit: ["hex.audit", "deps.unlock --check-unused", "deps.audit"],
      "conformance.verify": [
        "escript.build",
        "cmd ./agent_blueprint_protocol_conformance --corpus priv/conformance"
      ],
      "conformance.mutations": [
        "run --no-start scripts/check_conformance_mutations.exs"
      ],
      "verifier.agreement": [
        "run --no-start scripts/check_verifier_agreement.exs"
      ],
      "release.candidate": [
        "run --no-start scripts/check_release_candidate.exs"
      ],
      quality: [
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
        "release.candidate"
      ]
    ]
  end
end
