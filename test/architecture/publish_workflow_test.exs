defmodule AgentBlueprintProtocol.Architecture.PublishWorkflowTest do
  use ExUnit.Case, async: true

  @owners ~s|contains(fromJSON('["corepay","palermo-git"]'), github.actor) && | <>
            ~s|contains(fromJSON('["corepay","palermo-git"]'), github.triggering_actor)|

  test "publication is input-free and serialized, with every job owner gated and default-ref guarded" do
    workflow = workflow("publish")
    [_, triggers] = String.split(workflow, "\non:\n", parts: 2)
    [triggers | _] = String.split(triggers, "\npermissions:", parts: 2)
    assert String.trim(triggers) == "workflow_dispatch:"
    assert workflow =~ "group: publish\n  cancel-in-progress: false"

    assert Enum.map(jobs(workflow), &elem(&1, 0)) ==
             ~w(verify npm-publish npm-kit hex-publish smoke livebooks)

    for {name, job} <- jobs(workflow) do
      assert job =~ "    if: " <> @owners <> "\n"
      assert_default_branch_first(job)

      if name in ~w(verify npm-publish hex-publish),
        do: assert(job =~ "environment: publish"),
        else: refute(job =~ "environment:")
    end

    refute workflow =~ "contents: write"
    refute Regex.match?(~r/\bgh\s+release\b|^\s+git (?:push|tag)\b/m, workflow)
    refute File.exists?(".github/workflows/postpublish.yml")
  end

  test "credential-free published-package checks need the upload and retain their measured platforms" do
    workflow = workflow("publish")

    for {name, duration, run, limit} <- [
          {"smoke", "0.5", "44085034568", 5},
          {"livebooks", "2.9", "44022461020", 6}
        ] do
      job = job(workflow, name)
      assert job =~ "needs: [verify, hex-publish]"
      assert job =~ "permissions:\n      contents: read"
      assert job =~ "ABP_VERSION: ${{ needs.verify.outputs.version }}"
      assert job =~ "os: [ubuntu-24.04, macos-15, windows-2025]"
      assert job =~ "# Measured as this repository's postpublish.yml #{name} job."
      assert job =~ "#{duration} min, run #{run}.\n    timeout-minutes: #{limit}"
      refute job =~ "environment:"
      refute job =~ "secrets."
      refute job =~ "HEX_HOME"
    end

    assert job(workflow, "smoke") =~ "node scripts/postpublish_smoke.mjs"
    livebooks = job(workflow, "livebooks")
    assert livebooks =~ "fetch-depth: 0"
    assert livebooks =~ "elixir scripts/verify_release_packages.exs --registry"
  end

  test "the published npm kit is checked without credentials before the Hex upload" do
    workflow = workflow("publish")
    kit = job(workflow, "npm-kit")
    assert kit =~ "needs: [verify, npm-publish]"
    assert kit =~ "permissions:\n      contents: read"
    assert kit =~ "run\n    # 44085034568. Measured under 2.5 min, so 5.\n    timeout-minutes: 5"
    refute kit =~ "environment:"
    refute kit =~ "secrets."
    assert kit =~ "node scripts/release_artifact_info.mjs npm-integrity"
    assert kit =~ ~s|if [ "$LIVE_INTEGRITY" != "$VERIFIED_INTEGRITY" ]; then|
    assert kit =~ ~s|cmp "$RUNNER_TEMP/kit-report.json" "$RUNNER_TEMP/escript-report.json"|
    hex = job(workflow, "hex-publish")
    refute hex =~ "npm install"
    refute hex =~ "npx"
  end

  test "only npm gets OIDC and only the conditional no-project Hex upload gets the key" do
    workflow = workflow("publish")
    npm = job(workflow, "npm-publish")
    hex = job(workflow, "hex-publish")
    assert length(Regex.scan(~r/^\s+id-token: write$/m, workflow)) == 1
    assert npm =~ "id-token: write"
    assert npm =~ "needs: verify"
    assert hex =~ "needs: [verify, npm-kit]"
    key_step = step(hex, "Publish the verified Hex archive and docs to public hexpm")
    assert key_step =~ "working-directory: verified-release"

    assert key_step =~
             "if: needs.verify.outputs.hex_package == 'upload' || needs.verify.outputs.hex_docs == 'upload'"

    assert key_step =~ "HEX_PACKAGE: ${{ needs.verify.outputs.hex_package }}"
    assert key_step =~ "HEX_DOCS: ${{ needs.verify.outputs.hex_docs }}"
    assert key_step =~ "HEX_API_KEY: ${{ secrets.HEX_API_KEY }}"
    assert key_step =~ ~s|if [ "$HEX_PACKAGE" = upload ]; then set -- "$@" --package|
    assert key_step =~ ~s|if [ "$HEX_DOCS" = upload ]; then set -- "$@" --docs|
    assert key_step =~ ~s|mix run --no-mix-exs ../scripts/publish_hex_artifacts.exs "$@"|
    refute key_step =~ "--organization"
    assert length(Enum.filter(steps(workflow), &(&1 =~ "HEX_API_KEY"))) == 1
    refute npm =~ "HEX_API_KEY"
  end

  test "source and artifacts are verified before read-only plans compare the exact built bytes" do
    workflow = workflow("publish")
    verify = job(workflow, "verify")
    assert_before(verify, "bash scripts/check_publication.sh", "mix quality")
    assert_before(verify, "run: mix quality", "npm pack ./dist/package --ignore-scripts")
    assert_before(verify, "mix hex.build --output", "verify_release_packages.exs --local")
    assert_before(verify, "verify_release_packages.exs --local", "id: npm")
    assert_before(verify, "Docs checksum:", "id: hex")
    assert verify =~ "VERSION=$(node scripts/release_artifact_info.mjs version)"
    assert verify =~ "version: ${{ steps.inputs.outputs.version }}"
    assert verify =~ "npm: ${{ steps.npm.outputs.npm }}"
    assert verify =~ "hex_package: ${{ steps.hex.outputs.package }}"
    assert verify =~ "hex_docs: ${{ steps.hex.outputs.docs }}"
    assert verify =~ "mix deps.get --check-locked"
    assert verify =~ "npm ci --ignore-scripts --no-audit --no-fund"
    assert verify =~ "mix release.promote --check"
    assert verify =~ "fetch-depth: 0"
    assert verify =~ "MIX_ENV=test mix release.asset --write"
    assert verify =~ "Check public privacy over full history"
    assert verify =~ ~s|cmp "$RUNNER_TEMP/packed-report.json" "$RUNNER_TEMP/verified-report.json"|
    assert verify =~ "node scripts/npm_release_state.mjs plan"
    assert verify =~ "mix run --no-mix-exs ../scripts/hex_release_state.exs plan"
    assert step(verify, "Plan the Hex uploads") =~ "working-directory: verified-release"
    assert verify =~ ~s|[ "$NPM_STATE" = upload ]|
    assert verify =~ ~s|[ "$HEX_PACKAGE" = served ] \|\| [ "$HEX_DOCS" = served ]|
    refute workflow =~ "continue-on-error"

    check = File.read!("scripts/check_publication.sh")
    assert check =~ "set -euo pipefail"
    assert check =~ "NPM_PACKAGE_STATUS="
    assert check =~ "HEX_PACKAGE_STATUS="
    assert check =~ "this workflow never creates a package"
    assert check =~ ~s|git ls-remote --tags origin "refs/tags/v${VERSION}"|
    refute check =~ "--after-npm"
    refute check =~ "NPM_STATUS="
    refute check =~ "/releases/${VERSION}"
  end

  test "deterministic docs omit EPUB and release assets include every consumer file and checksum" do
    workflow = workflow("publish")
    verify = job(workflow, "verify")
    assert Mix.Project.config()[:docs][:formatters] == ["html", "markdown"]
    assert verify =~ "SOURCE_DATE_EPOCH=$(git log -1 --format=%ct HEAD)"

    assert verify =~
             ~s|tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner|

    assert verify =~ "-cf - -C doc . | gzip -n > verified-release/hex-docs.tar.gz"
    assert verify =~ "Docs checksum:"
    assert verify =~ "Package checksum:"
    assets = step(verify, "Prepare consumer release assets")

    for file <- [
          "agent_blueprint_protocol-${VERSION}.tar",
          "agent-blueprint-protocol-verifier-${VERSION}.tgz",
          "verifier-${VERSION}.tar.gz",
          "certified-results.json",
          "release-notes.md"
        ] do
      assert assets =~ file
    end

    assert assets =~ "elixir scripts/release_notes.exs"
    assert assets =~ "sha256sum -- * > SHA256SUMS"
    refute assets =~ "hex-docs.tar.gz"
    hex = job(workflow, "hex-publish")
    assert_before(hex, "hex_release_state.exs read-back", "name: release-assets")
    upload = step(hex, "Hand consumer release assets to infra")
    assert upload =~ "path: verified-release/release-assets/"
    assert upload =~ "if-no-files-found: error"
  end

  test "served plans skip upload only and always complete registry read-back" do
    workflow = workflow("publish")
    npm = job(workflow, "npm-publish")
    hex = job(workflow, "hex-publish")

    assert step(npm, "Publish the npm kit (staged trusted publishing, provenance)") =~
             "if: needs.verify.outputs.npm == 'upload'"

    assert npm =~ "npm stage publish"
    assert npm =~ "--ignore-scripts --access public --provenance"
    assert npm =~ "node scripts/npm_release_state.mjs read-back"
    refute step(npm, "Read back the served npm version") =~ "if:"
    assert hex =~ "mix run --no-mix-exs ../scripts/hex_release_state.exs read-back"
    refute step(hex, "Read back the served Hex package and docs") =~ "if:"
    refute hex =~ "check_hex_release.mjs"
    refute hex =~ "check_publication.sh"

    for job <- [npm, hex] do
      assert job =~ "name: verified-release"
      refute job =~ "mix hex.build"
      refute job =~ "npm run build"
    end
  end

  test "actions stay fully pinned and uncached and shell inputs enter through env" do
    for name <- ~w(ci publish pages) do
      source = workflow(name)
      assert source =~ "permissions:\n  contents: read"
      refute source =~ "actions/cache"
      refute source =~ "BASELABS_RUNNER"

      for [_, action] <- Regex.scan(~r/^\s+uses: (.+)$/m, source) do
        assert Regex.match?(~r/@[0-9a-f]{40} # v\d+\.\d+\.\d+$/, action)
      end

      for step <- steps(source) do
        if step =~ "uses: actions/checkout@", do: assert(step =~ "persist-credentials: false")
        if step =~ "uses: actions/setup-node@", do: assert(step =~ "package-manager-cache: false")

        if step =~ "uses: erlef/setup-beam@" do
          assert step =~ "version-type: strict"
          assert step =~ "install-hex: false"
        end

        if step =~ "        run:" do
          [_, run] = String.split(step, "        run:", parts: 2)
          [run | _] = Regex.split(~r/^        (?:env|shell):/m, run, parts: 2)
          refute run =~ "${{"
        end
      end
    end
  end

  test "Pages stays an owner's default-branch dispatch" do
    pages = workflow("pages")
    [_, triggers] = String.split(pages, "\non:\n", parts: 2)
    [triggers | _] = String.split(triggers, "\npermissions:", parts: 2)
    assert String.trim(triggers) == "workflow_dispatch:"

    for {_name, job} <- jobs(pages) do
      assert_default_branch_first(job)
      assert job =~ "    if: " <> @owners <> "\n"
    end

    assert job(pages, "deploy") =~ "name: github-pages"
  end

  @tag skip: match?({:win32, _}, :os.type())
  test "the actual ref guard and prerelease npm tag selection execute correctly" do
    workflow = workflow("publish")

    [_, guard] =
      workflow |> job("verify") |> steps() |> hd() |> String.split("        run: |\n", parts: 2)

    for {ref, default, status} <- [
          {"refs/heads/main", "main", 0},
          {"refs/heads/stable", "stable", 0},
          {"refs/heads/main", "stable", 1},
          {"refs/tags/v1.0.0", "main", 1}
        ] do
      assert {_, ^status} =
               System.cmd("bash", ["-c", guard],
                 env: [{"RELEASE_REF", ref}, {"DEFAULT_BRANCH", default}]
               )
    end

    [npm] = Regex.run(~r/NPM_TAG=latest\n[^\n]*if \[\[ [^\n]*NPM_TAG=rc; fi/, workflow)

    for {version, tag} <- [{"1.0.0-rc.1", "rc"}, {"1.0.0", "latest"}] do
      assert {^tag, 0} =
               System.cmd("bash", ["-c", npm <> ~s(\nprintf '%s' "$NPM_TAG")],
                 env: [{"VERSION", version}]
               )
    end
  end

  defp workflow(name), do: File.read!(".github/workflows/#{name}.yml")

  defp jobs(source) do
    [_, body] = String.split(source, "\njobs:\n", parts: 2)

    for [_, name, job] <-
          Regex.scan(~r/^  ([a-z][a-z0-9-]*):\n(.*?)(?=^  [a-z][a-z0-9-]*:\n|\z)/ms, body),
        do: {name, job}
  end

  defp job(source, name), do: source |> jobs() |> Map.new() |> Map.fetch!(name)

  defp steps(source) do
    source
    |> String.split("      - name: ")
    |> tl()
    |> Enum.map(fn step ->
      Regex.split(~r/^  [a-z][a-z0-9-]*:\n/m, step, parts: 2) |> hd()
    end)
  end

  defp step(job, name), do: Enum.find(steps(job), &String.starts_with?(&1, name <> "\n"))

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
end
