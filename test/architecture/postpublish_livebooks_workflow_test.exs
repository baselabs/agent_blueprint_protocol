defmodule AgentBlueprintProtocol.Architecture.PostpublishLivebooksWorkflowTest do
  use ExUnit.Case, async: true

  @workflow ".github/workflows/postpublish.yml"
  @setup_beam "54075bcc5e249e4758d363f27d099f55d843f124"

  test "the manual published-version workflow runs every notebook on three platforms" do
    workflow = File.read!(@workflow)
    [_, job] = Regex.split(~r/^  livebooks:\n/m, workflow, parts: 2)

    assert job =~ "os: [ubuntu-24.04, macos-15, windows-2025]"
    refute job =~ "actions/checkout@"
    assert job =~ "erlef/setup-beam@#{@setup_beam}"
    assert job =~ "elixir-version: \"1.20.3\""
    assert job =~ "otp-version: \"29.0.3\""
    assert job =~ "mix local.hex 2.7.0 --force"
    assert job =~ "ABP_VERSION: ${{ inputs.version }}"
    assert job =~ "repo.hex.pm/tarballs/agent_blueprint_protocol-"
    assert job =~ "scripts/postpublish_examples.mjs"
    assert job =~ "shell: pwsh"
    script = File.read!("scripts/postpublish_examples.mjs")

    for gate <- [
          "extract_livebooks.exs",
          "--doctests",
          "--snippets",
          "run_package_typescript_examples.mjs"
        ] do
      assert script =~ gate
    end

    assert script =~ "registry.npmjs.org"
    assert script =~ "finally"
  end

  test "the existing published kit check still uses the requested version" do
    workflow = File.read!(@workflow)
    assert workflow =~ "node scripts/postpublish_smoke.mjs \"$env:ABP_VERSION\""
    assert workflow =~ "name: Published kit"
  end
end
