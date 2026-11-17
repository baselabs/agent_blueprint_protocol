defmodule AgentBlueprintProtocol.Architecture.PublishWorkflowTest do
  use ExUnit.Case, async: true

  @workflows ~w(ci publish pages postpublish)
  @owners [
    ~s|contains(fromJSON('["corepay","palermo-git"]'), github.actor)|,
    ~s|contains(fromJSON('["corepay","palermo-git"]'), github.triggering_actor)|
  ]

  test "publication is an input-free dispatch serialized without cancellation" do
    workflow = workflow("publish")
    [_, triggers] = String.split(workflow, "\non:\n", parts: 2)
    [triggers | _] = String.split(triggers, "\npermissions:", parts: 2)
    assert String.trim(triggers) == "workflow_dispatch:"
    assert workflow =~ "permissions:\n  contents: read\n"
    assert workflow =~ "group: publish\n  cancel-in-progress: false"
    refute workflow =~ "github.ref_type"
    refute workflow =~ "GITHUB_REF_NAME"
    refute workflow =~ "skipping"
    refute workflow =~ "idempotent"

    for name <- ["verify", "npm-publish", "hex-publish", "draft-release"] do
      job = job(workflow, name)
      assert job =~ "    if: " <> Enum.join(@owners, " && ") <> "\n"
      assert job =~ "    environment: publish\n"
      assert_default_branch_first(job)
    end
  end

  test "publishing credentials are scoped to their protected job and step" do
    workflow = workflow("publish")
    npm = job(workflow, "npm-publish")
    hex = job(workflow, "hex-publish")
    draft = job(workflow, "draft-release")
    assert length(Regex.scan(~r/^\s+id-token: write$/m, workflow)) == 1
    assert npm =~ "id-token: write"
    assert length(Regex.scan(~r/^\s+contents: write$/m, workflow)) == 1
    assert draft =~ "contents: write"
    assert npm =~ "needs: verify"
    assert hex =~ "needs: [verify, npm-publish]"
    assert draft =~ "needs: [verify, hex-publish]"
    refute npm =~ "HEX_API_KEY"

    key_step = step(hex, "Publish the verified Hex archive and docs to public hexpm")
    assert key_step =~ "        env:\n          HEX_API_KEY: ${{ secrets.HEX_API_KEY }}"
    assert key_step =~ "mix run --no-mix-exs scripts/publish_hex_artifacts.exs"
    [_, run] = String.split(key_step, "        run:", parts: 2)
    refute run =~ "HEX_API_KEY"
    assert length(Regex.scan(~r/HEX_API_KEY/, workflow)) == 3

    publisher = File.read!("scripts/publish_hex_artifacts.exs")
    assert publisher =~ ~s|System.fetch_env!("HEX_API_KEY")|
    assert publisher =~ "OptionParser.parse(argv, strict: [organization: :string])"
    assert publisher =~ "publish(opts[:organization], name, version, archive, docs)"
    assert publisher =~ "auth = [key: key]"

    assert publisher =~
             "absent!(Hex.API.Release.get(repo, name, version, auth), repo, name, version)"

    assert publisher =~ "Hex.API.Release.publish(repo, File.read!(archive), auth)"
    assert publisher =~ "Hex.API.ReleaseDocs.publish(repo, name, version, File.read!(docs), auth)"
    assert publisher =~ "defp absent!({:ok, {404, _headers, _body}}"
    assert publisher =~ "already has"
    assert publisher =~ "could not confirm"
    assert publisher =~ "when code in 200..299"
    assert publisher =~ ~s|body["status"] == "staged"|

    assert key_step =~
             ~s|publish_hex_artifacts.exs \\\n            agent_blueprint_protocol "$VERSION"|

    refute key_step =~ "--organization"
    assert_before(publisher, "absent!(Hex.API.Release.get", "Hex.API.Release.publish")
    assert_before(publisher, "Hex.API.Release.publish", "Hex.API.ReleaseDocs.publish")
    refute publisher =~ "File.write"
    refute publisher =~ "inspect("
    refute publisher =~ "hex.build"
  end

  test "all source actions are pinned, uncredentialed, and uncached" do
    for name <- @workflows do
      workflow = workflow(name)
      assert workflow =~ "permissions:\n  contents: read"
      refute workflow =~ "actions/cache"
      refute Regex.match?(~r/^\s+cache: (?!false$)/m, workflow)
      refute Regex.match?(~r/^\s+package-manager-cache: (?!false$)/m, workflow)
      refute workflow =~ "self-hosted"
      refute workflow =~ "BASELABS_RUNNER"

      for [_, action] <- Regex.scan(~r/^\s+uses: (.+)$/m, workflow) do
        assert String.starts_with?(action, "./.github/workflows/") or
                 Regex.match?(~r/@[0-9a-f]{40} # v\d+\.\d+\.\d+$/, action)
      end

      for action <- steps(workflow), action =~ "uses: actions/checkout@" do
        assert action =~ "persist-credentials: false"
      end

      for action <- steps(workflow), action =~ "uses: actions/setup-node@" do
        assert action =~ "package-manager-cache: false"
      end

      for action <- steps(workflow), action =~ "uses: erlef/setup-beam@" do
        assert action =~ "version-type: strict"
        assert action =~ "install-hex: false"
      end

      for action <- steps(workflow), action =~ "        run:" do
        [_, run] = String.split(action, "        run:", parts: 2)
        [run | _] = Regex.split(~r/^        (?:env|shell):/m, run, parts: 2)
        refute run =~ "${{", name
      end
    end

    for name <- ["publish", "pages"],
        [_, runner] <- Regex.scan(~r/^    runs-on: (.+)$/m, workflow(name)) do
      assert runner == "ubuntu-24.04"
    end

    for path <- Path.wildcard(".github/workflows/*.yml"),
        job <- Regex.split(~r/^  [a-z][a-z0-9-]*:\n/m, File.read!(path)),
        job =~ "uses: erlef/setup-beam@" do
      assert job =~ "install-hex: false", path

      assert Regex.scan(~r/mix local.hex (\d+\.\d+\.\d+) --force/, job) ==
               [["mix local.hex 2.7.0 --force", "2.7.0"]]
    end
  end

  test "the existing artifact reader requires one equal source package version" do
    AgentBlueprintProtocol.Scratch.with_dir("release-inputs", fn dir ->
      script = Path.expand("scripts/release_artifact_info.mjs")

      for file <- ["mix.exs", "package.json"] do
        File.cp!(file, Path.join(dir, file))
      end

      assert {version, 0} = System.cmd("node", [script, "version"], cd: dir)
      assert version == Mix.Project.config()[:version]

      package = :json.decode(File.read!("package.json"))
      mismatched = Map.put(package, "version", package["version"] <> "-mismatch")
      File.write!(Path.join(dir, "package.json"), :json.encode(mismatched))

      assert {_, 1} =
               System.cmd("node", [script, "version"],
                 cd: dir,
                 stderr_to_stdout: true
               )

      File.cp!("package.json", Path.join(dir, "package.json"))

      for invalid <- ["", ~s|@version "1.0.0"\n@version "1.0.0"|, ~s|@version "main"|] do
        File.write!(Path.join(dir, "mix.exs"), invalid)

        assert {_, 1} =
                 System.cmd("node", [script, "version"], cd: dir, stderr_to_stdout: true)
      end
    end)

    workflow = workflow("publish")
    verify = job(workflow, "verify")
    assert verify =~ "VERSION=$(node scripts/release_artifact_info.mjs version)"
    assert verify =~ ~S|printf 'VERSION=%s\n' "$VERSION" >> "$GITHUB_ENV"|
    assert verify =~ ~S|printf 'version=%s\n' "$VERSION" >> "$GITHUB_OUTPUT"|
    assert verify =~ "version: ${{ steps.inputs.outputs.version }}"

    for name <- ["npm-publish", "hex-publish", "draft-release"] do
      assert job(workflow, name) =~ "VERSION: ${{ needs.verify.outputs.version }}"
    end
  end

  test "occupied, partial, and unknown publication state refuse before uploading" do
    workflow = workflow("publish")
    verify = job(workflow, "verify")
    npm = job(workflow, "npm-publish")
    hex = job(workflow, "hex-publish")
    assert_before(verify, "bash scripts/check_publication.sh", "mix quality")
    assert_before(npm, "bash scripts/check_publication.sh", "npm stage publish")
    assert_before(hex, "bash scripts/check_publication.sh --after-npm", "mix run --no-mix-exs")
    check = File.read!("scripts/check_publication.sh")
    assert check =~ "set -euo pipefail"
    assert check =~ "EXPECTED_NPM=404"
    assert check =~ "EXPECTED_NPM=200"
    assert check =~ ~s|git ls-remote --tags origin "refs/tags/v${VERSION}"|
    assert check =~ ~s|"$NPM_STATUS" != "$EXPECTED_NPM"|
    assert check =~ ~s|"$HEX_STATUS" != 404|
    assert check =~ ~s|-n "$REMOTE_TAG"|
    assert check =~ "::error::Refusing occupied or unknown release state"
    assert check =~ "partial release or pending approval must be resolved by hand"
    assert check =~ "exit 1"
    refute check =~ "|| true"
    assert npm =~ "Do not redispatch: an occupied version is refused"
    assert npm =~ "::error::npm is pending or unreadable"

    check_hex = File.read!("scripts/check_hex_release.mjs")
    assert check_hex =~ "::error::Hex version is not live"
    assert check_hex =~ "process.exitCode=1"
    assert check_hex =~ "do not redispatch"
    refute workflow =~ "continue-on-error"
    refute workflow =~ "always()"

    for {job, name} <- [
          {npm, "Publish the npm kit (staged trusted publishing, provenance)"},
          {hex, "Publish the verified Hex archive and docs to public hexpm"},
          {job(workflow, "draft-release"), "Attach the verifier kit to a draft GitHub release"}
        ] do
      refute Regex.match?(~r/^\s+if:/m, step(job, name))
    end
  end

  test "quality and both local package gates precede publication of the exact archives" do
    workflow = workflow("publish")
    verify = job(workflow, "verify")
    npm = job(workflow, "npm-publish")
    hex = job(workflow, "hex-publish")
    assert verify =~ "mix deps.get --check-locked"
    refute Regex.match?(~r/mix deps.get(?! --check-locked)/, workflow)
    assert verify =~ "npm ci --ignore-scripts --no-audit --no-fund"
    assert verify =~ "mix release.promote --check"
    assert verify =~ "fetch-depth: 0"
    assert verify =~ "Check public privacy over full history"
    assert_before(verify, "run: mix quality", "npm pack ./dist/package --ignore-scripts")
    assert "docs --warnings-as-errors" in Mix.Project.config()[:aliases][:quality]
    assert_before(verify, "mix hex.build --output", "verify_release_packages.exs --local")
    assert_before(verify, "verify_release_packages.exs --local", "actions/upload-artifact@")
    assert verify =~ "MIX_ENV=test mix release.asset --write"
    assert verify =~ "Verify the packed npm artifact"
    assert verify =~ ~s|cmp "$RUNNER_TEMP/packed-report.json" "$RUNNER_TEMP/verified-report.json"|
    assert verify =~ "if-no-files-found: error"

    for job <- [npm, hex] do
      assert job =~ "actions/download-artifact@"
      assert job =~ "name: verified-release"
      refute job =~ "npm run build"
      refute job =~ "mix hex.build"
    end

    assert npm =~ ~s|"./verified-release/agent-blueprint-protocol-verifier-${VERSION}.tgz"|
    assert npm =~ "--ignore-scripts --access public --provenance"
    assert hex =~ ~s|"verified-release/agent_blueprint_protocol-${VERSION}.tar"|
    assert hex =~ "node scripts/release_artifact_info.mjs npm-integrity"
    assert hex =~ ~s|if [ "$LIVE_INTEGRITY" != "$VERIFIED_INTEGRITY" ]; then|
    assert hex =~ "node scripts/check_hex_release.mjs"

    package = :json.decode(File.read!("package.json"))
    lock = :json.decode(File.read!("package-lock.json"))
    assert lock["packages"][""]["devDependencies"] == package["devDependencies"]
  end

  test "the source release stays a draft targeted at the dispatched commit without a tag" do
    workflow = workflow("publish")
    draft = job(workflow, "draft-release")
    assert draft =~ "RELEASE_SHA: ${{ github.sha }}"
    assert draft =~ ~s|gh release create "v${VERSION}"|
    assert draft =~ ~s|--draft --target "$RELEASE_SHA"|
    assert draft =~ ~s|--title "v${VERSION}"|
    assert draft =~ ~s|"verified-release/verifier-${VERSION}.tar.gz"|
    assert draft =~ ~s|"verified-release/certified-results.json"|
    assert draft =~ ~s|git ls-remote --tags origin "refs/tags/v${VERSION}"|
    refute Regex.match?(~r/^\s+git (?:push|tag)\b/m, workflow)
    refute workflow =~ "gh release edit"
    assert workflow =~ "uses: ./.github/workflows/postpublish.yml"
    assert workflow =~ "version: ${{ needs.verify.outputs.version }}"
  end

  test "Pages deploys only by an owner's default-branch dispatch" do
    pages = workflow("pages")
    [_, triggers] = String.split(pages, "\non:\n", parts: 2)
    [triggers | _] = String.split(triggers, "\npermissions:", parts: 2)
    assert String.trim(triggers) == "workflow_dispatch:"
    refute pages =~ "workflow_run"
    assert pages =~ "path: site"

    for name <- ["build", "deploy"] do
      job = job(pages, name)
      assert_default_branch_first(job)
      assert job =~ "    if: " <> Enum.join(@owners, " && ") <> "\n"
    end

    assert job(pages, "deploy") =~ "      name: github-pages\n"

    postpublish = workflow("postpublish")
    assert postpublish =~ "workflow_call:"
    assert postpublish =~ "workflow_dispatch:"
    assert postpublish =~ "version:\n"
    assert postpublish =~ "elixir scripts/verify_release_packages.exs --registry"

    assert length(Regex.scan(~r/os: \[ubuntu-24.04, macos-15, windows-2025\]/, postpublish)) ==
             2

    for name <- ["pages", "postpublish"] do
      refute Regex.match?(~r/^  push:/m, workflow(name))
      refute Regex.match?(~r/^\s+tags:/m, workflow(name))
    end
  end

  @tag skip: match?({:win32, _}, :os.type())
  test "prereleases keep their npm distribution tag and draft prerelease flag" do
    workflow = workflow("publish")

    [npm] = Regex.run(~r/NPM_TAG=latest\n[^\n]*if \[\[ [^\n]*NPM_TAG=rc; fi/, workflow)

    [release] =
      Regex.run(~r/PRERELEASE_ARGS=\(\)\n[^\n]*if \[\[ [^\n]*--prerelease[^\n]*/, workflow)

    for {version, tag, flag} <- [
          {"1.0.0-rc.1", "rc", "--prerelease"},
          {"1.0.0", "latest", ""}
        ] do
      script = npm <> "\n" <> release <> ~s(\nprintf '%s\\n%s' "$NPM_TAG" "${PRERELEASE_ARGS[*]}")
      assert {output, 0} = System.cmd("bash", ["-c", script], env: [{"VERSION", version}])
      assert output == tag <> "\n" <> flag
    end
  end

  @tag skip: match?({:win32, _}, :os.type())
  test "the actual first-step script refuses branch and tag refs other than the default" do
    guard = workflow("publish") |> job("verify") |> steps() |> hd()
    [_, script] = String.split(guard, "        run: |\n", parts: 2)

    for {ref, default, status} <- [
          {"refs/heads/main", "main", 0},
          {"refs/heads/stable", "stable", 0},
          {"refs/heads/main", "stable", 1},
          {"refs/heads/feature", "main", 1},
          {"refs/tags/v1.0.0", "main", 1}
        ] do
      assert {_, ^status} =
               System.cmd("bash", ["-c", script],
                 env: [{"RELEASE_REF", ref}, {"DEFAULT_BRANCH", default}]
               )
    end
  end

  defp assert_default_branch_first(job) do
    [guard | _] = steps(job)
    assert String.starts_with?(guard, "Refuse refs outside the default branch\n")
    assert guard =~ "RELEASE_REF: ${{ github.ref }}"
    assert guard =~ "DEFAULT_BRANCH: ${{ github.event.repository.default_branch }}"
    assert guard =~ ~s|if [ "$RELEASE_REF" != "refs/heads/$DEFAULT_BRANCH" ]; then|
    assert guard =~ "exit 1"
  end

  defp assert_before(source, earlier, later) do
    {first, _} = :binary.match(source, earlier)
    {second, _} = :binary.match(source, later)
    assert first < second
  end

  defp workflow(name), do: File.read!(".github/workflows/#{name}.yml")

  defp job(workflow, name) do
    [_, rest] = String.split(workflow, "\n  #{name}:\n", parts: 2)
    [job | _] = Regex.split(~r/^  [a-z][a-z0-9-]*:\n/m, rest, parts: 2)
    job
  end

  defp steps(workflow) do
    workflow
    |> String.split("      - name: ")
    |> tl()
    |> Enum.map(fn step ->
      [step | _] = Regex.split(~r/^  [a-z][a-z0-9-]*:\n/m, step, parts: 2)
      step
    end)
  end

  defp step(job, name), do: Enum.find(steps(job), &String.starts_with?(&1, name <> "\n"))
end
