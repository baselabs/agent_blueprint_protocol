defmodule AgentBlueprintProtocol.Architecture.PostpublishLivebooksWorkflowTest do
  use ExUnit.Case, async: true

  @workflow ".github/workflows/postpublish.yml"
  @setup_beam "54075bcc5e249e4758d363f27d099f55d843f124"

  test "the published-version workflow runs every notebook on three platforms" do
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

  # A GitHub release created with the workflow token starts no other
  # workflow, so a release-event trigger would never fire. The release job
  # instead hands its version to the postpublish workflow inside the same run.
  test "every release run verifies its published packages" do
    workflow = File.read!(@workflow)
    [triggers, _] = String.split(workflow, ~r/^permissions:/m, parts: 2)

    for trigger <- ["workflow_call", "workflow_dispatch"] do
      assert triggers =~
               ~r/^  #{trigger}:\n    inputs:\n      version:\n(?:        .*\n)*        required: true\n/m,
             "the #{trigger} trigger must require the published version"
    end

    publish = File.read!(".github/workflows/publish.yml")
    [_, release_job] = Regex.split(~r/^  publish:\n/m, publish, parts: 2)

    assert release_job =~ ~r/^  postpublish:\n/m,
           "the release run must call the postpublish workflow as a job"

    [release_job, call] = Regex.split(~r/^  postpublish:\n/m, release_job, parts: 2)

    assert release_job =~ "released: ${{ steps.release.outputs.version }}",
           "the release job must publish the released version as an output"

    [_, attach] =
      String.split(release_job, "- name: Attach the verifier kit to the GitHub release\n")

    assert attach =~ "id: release"

    assert attach =~
             ~r/\n          fi\n          echo "version=\$\{VERSION\}" >> "\$GITHUB_OUTPUT"\n/,
           "the released version must be recorded after both release branches"

    for line <- [
          "needs: publish",
          "if: needs.publish.outputs.released != ''",
          "uses: ./.github/workflows/postpublish.yml",
          "version: ${{ needs.publish.outputs.released }}"
        ] do
      assert call =~ line, "the release run must call postpublish: missing #{line}"
    end
  end

  test "the existing published kit check still uses the requested version" do
    workflow = File.read!(@workflow)
    assert workflow =~ "node scripts/postpublish_smoke.mjs \"$env:ABP_VERSION\""
    assert workflow =~ "name: Published kit"
  end
end
