defmodule AgentBlueprintProtocol.Architecture.PublishWorkflowTest do
  use ExUnit.Case, async: true

  @tag skip:
         if(match?({:win32, _}, :os.type()),
           do: "Publishing shell evaluation runs in the Linux maintainer lane",
           else: false
         )
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

      refute Regex.match?(~r/^\s+if:/m, step) and
               name != "Attach the verifier kit to the GitHub release",
             "publish step overrides the default success condition: #{name}"

      assert step =~ "if "
      assert step =~ "already"
    end

    # A manual dispatch may only publish from a release tag ref.
    assert workflow =~ "if: github.ref_type == 'tag' && startsWith(github.ref, 'refs/tags/v')"
    assert workflow =~ ~s("$GITHUB_REF_TYPE" != tag || "$GITHUB_REF" != refs/tags/v*)

    locked_installs()
    token_scope()
    verified_artifacts()
    pinned_hex_clients(workflow)
    staged_hex_message(workflow)
    live_hex_release(workflow)
    prerelease_versions(workflow)
    assert workflow =~ "if: needs.npm-publish.outputs.live == 'true'"
    assert workflow =~ "live=false"
    assert workflow =~ "Hex and the GitHub release did not run"

    {live_check, _} =
      :binary.match(workflow, "name: Verify the live npm version before further publication")

    {hex_publish, _} = :binary.match(workflow, "name: Publish the Hex package and docs")
    assert live_check < hex_publish
    refute workflow =~ "/tmp/"
  end

  defp pinned_hex_clients(workflow) do
    [_, verify, _, publish] = Regex.split(~r/^  (?:verify|npm-publish|publish):\n/m, workflow)

    pins =
      for job <- [verify, publish] do
        assert job =~ "install-hex: false"
        assert [[_, pin]] = Regex.scan(~r/mix local.hex (\d+\.\d+\.\d+) --force/, job)
        {installed, _} = :binary.match(job, "mix local.hex " <> pin <> " --force")
        {build, _} = :binary.match(job, "mix hex.build")
        assert installed < build
        pin
      end

    assert pins == ["2.7.0", "2.7.0"]

    for path <- Path.wildcard(".github/workflows/*.yml"),
        job <- Regex.split(~r/^  [a-z][a-z0-9-]*:\n/m, File.read!(path)),
        String.contains?(job, "uses: erlef/setup-beam@") do
      assert job =~ "install-hex: false", path

      assert Regex.scan(~r/mix local.hex (\d+\.\d+\.\d+) --force/, job) ==
               [["mix local.hex 2.7.0 --force", "2.7.0"]]
    end
  end

  defp staged_hex_message(workflow) do
    [_, publish] = String.split(workflow, "      - name: Publish the Hex package and docs\n")
    [matcher] = Regex.run(~r/grep [^;\n]+hex-publish\.log"/, publish)

    AgentBlueprintProtocol.Scratch.with_dir("publish-workflow", fn dir ->
      for {message, status} <- [
            {"HTTP status code: 409", 1},
            {"version: is awaiting approval", 0},
            {"request 409 failed", 1},
            {"already staged: unrelated failure", 1},
            {"version: is awaiting approval for another request", 1}
          ] do
        path = Path.join(dir, "hex-publish.log")
        File.write!(path, message <> "\n")

        assert {_, ^status} =
                 System.cmd("bash", ["-c", matcher], env: [{"RUNNER_TEMP", dir}])
      end
    end)
  end

  defp live_hex_release(workflow) do
    {check, _} = :binary.match(workflow, "name: Report live or pending Hex state")
    {release, _} = :binary.match(workflow, "name: Attach the verifier kit to the GitHub release")
    assert check < release
    assert workflow =~ "id: hex-live"
    assert workflow =~ "if: steps.hex-live.outputs.live == 'true'"
    assert workflow =~ "node scripts/check_hex_release.mjs"
    assert workflow =~ "hex: already staged"
    refute workflow =~ "stage publish ships with npm 11.19"
  end

  defp prerelease_versions(workflow) do
    [npm] = Regex.run(~r/NPM_TAG=latest\n[^\n]*if \[\[ [^\n]*NPM_TAG=rc; fi/, workflow)

    [release] =
      Regex.run(~r/PRERELEASE_ARGS=\(\)\n[^\n]*if \[\[ [^\n]*--prerelease[^\n]*/, workflow)

    assert workflow =~ ~s(--tag "$NPM_TAG")
    assert workflow =~ ~s("${PRERELEASE_ARGS[@]}")

    for {version, tag, flag} <- [
          {"1.0.0-rc.1", "rc", "--prerelease"},
          {"1.0.0-rc.2+build", "rc", "--prerelease"},
          {"1.0.0", "latest", ""},
          {"1.0.0+build-with-hyphen", "latest", ""}
        ] do
      script = npm <> "\n" <> release <> ~s(\nprintf '%s\\n%s' "$NPM_TAG" "${PRERELEASE_ARGS[*]}")
      assert {output, 0} = System.cmd("bash", ["-c", script], env: [{"VERSION", version}])
      assert output == tag <> "\n" <> flag
    end
  end

  defp verified_artifacts do
    workflow = File.read!(".github/workflows/publish.yml")
    [_, verify, npm, publish] = Regex.split(~r/^  (?:verify|npm-publish|publish):\n/m, workflow)

    assert verify =~
             "npm pack ./dist/package --ignore-scripts --pack-destination verified-release"

    assert verify =~ "MIX_ENV=test mix release.asset --write"
    assert verify =~ "mix hex.build --output"

    assert verify =~
             "tar -czf verified-release/kit-dist.tar.gz --exclude='.DS_Store' --exclude='._*' dist agent_blueprint_protocol_conformance"

    assert verify =~ "actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9"
    assert verify =~ "Verify the packed npm artifact"

    assert verify =~
             "diff --recursive --brief --exclude='package' --exclude='self_checks.*' --exclude='.DS_Store' --exclude='._*' dist"

    assert verify =~ ~s(node "$RUNNER_TEMP/packed-kit/package/dist/kit/cli.mjs")
    assert verify =~ ~s(cmp "$RUNNER_TEMP/packed-report.json" "$RUNNER_TEMP/verified-report.json")
    assert verify =~ "if-no-files-found: error"
    assert verify =~ "overwrite: true"
    assert String.split(verify, "run: mix quality") |> length() == 2
    [_, produced] = String.split(verify, "run: mix quality")
    assert produced =~ "npm pack ./dist/package --ignore-scripts"

    for job <- [npm, publish] do
      assert job =~ "actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333"
      assert job =~ "name: verified-release"
      refute job =~ "npm run build"
      refute job =~ "npm ci"
      refute job =~ "mix release.asset"
    end

    assert npm =~
             ~s(npm stage publish "./verified-release/agent-blueprint-protocol-verifier-${VERSION}.tgz")

    assert publish =~ "tar -xzf verified-release/kit-dist.tar.gz"

    assert publish =~
             ~s(cmp rebuilt.tar "verified-release/agent_blueprint_protocol-${VERSION}.tar")

    assert publish =~ ~s("verified-release/verifier-${VERSION}.tar.gz")
    assert publish =~ ~s(npm view "${NPM_PACKAGE}@${VERSION}" dist.integrity)
    assert publish =~ ~s|createHash("sha512")|
    assert publish =~ ~s(if [ "$LIVE_INTEGRITY" != "$VERIFIED_INTEGRITY" ]; then)
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
