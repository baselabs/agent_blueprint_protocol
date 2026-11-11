defmodule AgentBlueprintProtocol.Architecture.PostpublishLivebooksWorkflowTest do
  use ExUnit.Case, async: true

  @workflow ".github/workflows/postpublish.yml"
  @checkout "3d3c42e5aac5ba805825da76410c181273ba90b1"
  @setup_beam "54075bcc5e249e4758d363f27d099f55d843f124"

  test "the manual published-version workflow runs every notebook on three platforms" do
    workflow = File.read!(@workflow)
    [_, job] = Regex.split(~r/^  livebooks:\n/m, workflow, parts: 2)

    assert job =~ "os: [ubuntu-24.04, macos-15, windows-2025]"
    assert job =~ "actions/checkout@#{@checkout}"
    assert job =~ "erlef/setup-beam@#{@setup_beam}"
    assert job =~ "elixir-version: \"1.20.3\""
    assert job =~ "otp-version: \"29.0.3\""
    assert job =~ "mix local.hex 2.7.0 --force"
    assert job =~ "scripts/extract_livebooks.exs --version \"$env:ABP_VERSION\""
    assert job =~ "ABP_VERSION: ${{ inputs.version }}"
    assert job =~ "elixir $script.FullName"
    assert job =~ "Expected five notebook scripts"
    assert job =~ "shell: pwsh"
  end

  test "the existing published kit check still uses the requested version" do
    workflow = File.read!(@workflow)
    assert workflow =~ "node scripts/postpublish_smoke.mjs \"$env:ABP_VERSION\""
    assert workflow =~ "name: Published kit"
  end
end
