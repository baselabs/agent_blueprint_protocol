defmodule AgentBlueprintProtocol.Architecture.PublishWorkflowTest do
  use ExUnit.Case, async: true

  test "publishing stops after any failed preceding step and preserves registry skip guards" do
    workflow = File.read!(".github/workflows/publish.yml")
    steps = String.split(workflow, "      - name: ") |> tl()

    for name <- [
          "Publish the npm kit (staged trusted publishing, provenance)",
          "Publish the Hex package and docs",
          "Attach the verifier kit to the GitHub release"
        ] do
      step = Enum.find(steps, &String.starts_with?(&1, name <> "\n"))
      assert step, "missing publish step: #{name}"

      refute Regex.match?(~r/^\s+if:/m, step),
             "publish step overrides the default success condition: #{name}"

      assert step =~ "if "
      assert step =~ "already"
    end

    locked_installs()
    token_scope()
    verified_artifacts()
  end

  defp verified_artifacts do
    workflow = File.read!(".github/workflows/publish.yml")
    [_, verify, npm, publish] = Regex.split(~r/^  (?:verify|npm-publish|publish):\n/m, workflow)

    assert verify =~ "npm pack --ignore-scripts --pack-destination verified-release"
    assert verify =~ "MIX_ENV=test mix release.asset --write"
    assert verify =~ "mix hex.build --output"

    assert verify =~
             "tar -czf verified-release/kit-dist.tar.gz --exclude='.DS_Store' --exclude='._*' dist agent_blueprint_protocol_conformance"

    assert verify =~ "actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9"
    assert verify =~ "Verify the packed npm artifact"

    assert verify =~
             "diff --recursive --brief --exclude='self_checks.*' --exclude='.DS_Store' --exclude='._*' dist"

    assert verify =~ ~s(node "$RUNNER_TEMP/packed-kit/package/dist/kit/cli.mjs")
    assert verify =~ ~s(cmp "$RUNNER_TEMP/packed-report.json" "$RUNNER_TEMP/verified-report.json")
    assert verify =~ "if-no-files-found: error"
    assert String.split(verify, "run: mix quality") |> length() == 2
    [_, produced] = String.split(verify, "run: mix quality")
    assert produced =~ "npm pack --ignore-scripts"

    for job <- [npm, publish] do
      assert job =~ "actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333"
      assert job =~ "name: verified-release"
      refute job =~ "npm run build"
      refute job =~ "npm ci"
      refute job =~ "mix release.asset"
    end

    assert npm =~
             ~s(npm stage publish "verified-release/agent-blueprint-protocol-verifier-${VERSION}.tgz")

    assert publish =~ "tar -xzf verified-release/kit-dist.tar.gz"

    assert publish =~
             ~s(cmp rebuilt.tar "verified-release/agent_blueprint_protocol-${VERSION}.tar")

    assert publish =~ ~s("verified-release/verifier-${VERSION}.tar.gz")
  end

  defp locked_installs do
    package = :json.decode(File.read!("package.json"))
    lock = :json.decode(File.read!("package-lock.json"))
    assert lock["packages"][""]["devDependencies"] == package["devDependencies"]
    refute File.read!(".gitignore") =~ "package-lock.json"

    for path <- [
          ".github/workflows/ci.yml",
          ".github/workflows/docs-gates.yml",
          ".github/workflows/publish.yml",
          "mix.exs"
        ] do
      content = File.read!(path)
      assert content =~ "npm ci --ignore-scripts"
      refute content =~ "npm install --no-audit"
    end
  end

  defp token_scope do
    workflow = File.read!(".github/workflows/publish.yml")
    [root, jobs] = String.split(workflow, "jobs:", parts: 2)
    refute root =~ "id-token: write"

    [verify, npm, publish] =
      Regex.split(
        ~r/^  (?:verify|npm-publish|publish):\n/m,
        String.trim_leading(jobs, "\n"),
        trim: true
      )

    refute verify =~ "id-token: write"
    assert npm =~ "id-token: write"
    assert npm =~ "needs: verify"
    assert npm =~ "environment: GH TP for ABP"
    refute npm =~ "HEX_API_KEY"
    refute publish =~ "id-token: write"
    assert publish =~ "needs: npm-publish"
  end
end
