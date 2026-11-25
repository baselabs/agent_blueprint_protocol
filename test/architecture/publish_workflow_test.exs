defmodule AgentBlueprintProtocol.Architecture.PublishWorkflowTest do
  use ExUnit.Case, async: true

  @owners ~s|contains(fromJSON('["corepay","palermo-git"]'), github.actor) && | <>
            ~s|contains(fromJSON('["corepay","palermo-git"]'), github.triggering_actor)|
  @changelog_stamp "Refuse a package whose changelog is not stamped for its version"
  @changelog_stamp_sha256 "2a912ae3e07700555d8827da491b8875207341808b4a6c1137c07129f0cbfa30"

  test "publication takes one required release commit and serializes owner-gated default-ref jobs" do
    workflow = workflow("publish")
    [_, triggers] = String.split(workflow, "\non:\n", parts: 2)
    [triggers | _] = String.split(triggers, "\npermissions:", parts: 2)

    expected = """
    workflow_dispatch:
        inputs:
          release_commit:
            description: Full 40-hex lowercase SHA of the qualified release commit
            required: true
            type: string
    """

    assert String.trim(triggers) == String.trim(expected)
    assert workflow =~ "group: publish\n  cancel-in-progress: false"

    assert Enum.map(jobs(workflow), &elem(&1, 0)) ==
             ~w(verify npm-publish npm-kit hex-publish hex-read-back smoke livebooks)

    for {name, job} <- jobs(workflow) do
      assert job =~ "    if: " <> @owners <> "\n"
      assert_default_branch_first(job)

      if name in ~w(npm-publish hex-publish),
        do: assert(job =~ "environment: publish"),
        else: refute(job =~ "environment:")
    end

    refute workflow =~ "contents: write"
    refute Regex.match?(~r/\bgh\s+release\b|^\s+git (?:push|tag)\b/m, workflow)
    refute File.exists?(".github/workflows/postpublish.yml")
  end

  test "the release SHA is validated before use and pins every source checkout" do
    workflow = workflow("publish")
    verify = job(workflow, "verify")
    validation = step(verify, "Validate the release commit")
    assert validation =~ "RELEASE_COMMIT: ${{ inputs.release_commit }}"
    assert validation =~ ~s|if [[ ! "$RELEASE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then|
    assert validation =~ "exit 1"
    assert validation =~ ~s|printf 'commit=%s\\n' "$RELEASE_COMMIT" >> "$GITHUB_OUTPUT"|
    assert_before(verify, "Validate the release commit", "uses: actions/checkout@")
    assert verify =~ "release_commit: ${{ steps.release.outputs.commit }}"
    refute Regex.match?(~r/\bHEAD\b/, workflow)
    assert length(Enum.filter(steps(workflow), &(&1 =~ "uses: actions/checkout@"))) == 8

    for {name, job} <- jobs(workflow), name not in ~w(npm-publish hex-publish) do
      [checkout] =
        Enum.filter(steps(job), fn step ->
          step =~ "uses: actions/checkout@" and
            not String.starts_with?(step, "Check out the workflow's Hex tool\n")
        end)

      refute checkout =~ "path:"

      reference =
        if name == "verify",
          do: "${{ steps.release.outputs.commit }}",
          else: "${{ needs.verify.outputs.release_commit }}"

      assert checkout =~ "ref: " <> reference
    end
  end

  test "Hex planning and upload use workflow-revision scripts over release-commit archives" do
    workflow = workflow("publish")
    verify = job(workflow, "verify")
    hex = job(workflow, "hex-publish")

    for job <- [verify, hex] do
      checkout = step(job, "Check out the workflow's Hex tool")
      assert checkout =~ "uses: actions/checkout@"
      assert checkout =~ "ref: ${{ github.sha }}"
      assert checkout =~ "path: workflow-tools"
      assert checkout =~ "sparse-checkout-cone-mode: false"
    end

    plan_checkout = step(verify, "Check out the workflow's Hex tool")

    assert plan_checkout =~
             "sparse-checkout: |\n            /scripts/hex_release_state.exs\n            /scripts/gate_command.exs"

    assert_before(verify, "Check out source", "Prepare the verified release artifacts")
    assert_before(verify, "Prepare the verified documentation archive", plan_checkout)
    assert_before(verify, plan_checkout, "Plan the Hex uploads")

    upload_checkout = step(hex, "Check out the workflow's Hex tool")

    assert upload_checkout =~
             "sparse-checkout: |\n            /scripts/publish_hex_artifacts.exs\n            /scripts/toolchain.sh\n"

    download = step(hex, "Download the verified release artifacts")
    assert download =~ "name: verified-release"
    assert download =~ "path: verified-release"
    assert_before(hex, upload_checkout, download)
    assert_before(hex, download, "Publish the verified Hex archive and docs")
    assert_before(hex, upload_checkout, "Publish the verified Hex archive and docs")
  end

  test "the first job checks ancestry, exact-commit qualification, versions and tag before building" do
    verify = workflow("publish") |> job("verify")
    assert step(verify, "Check out source") =~ "fetch-depth: 0"
    ancestry = step(verify, "Require default-branch ancestry")
    assert ancestry =~ "RELEASE_COMMIT: ${{ steps.release.outputs.commit }}"
    assert ancestry =~ "DEFAULT_BRANCH: ${{ github.event.repository.default_branch }}"

    assert ancestry =~
             ~s|git merge-base --is-ancestor "$RELEASE_COMMIT" "refs/remotes/origin/$DEFAULT_BRANCH"|

    assert ancestry =~ "exit 1"
    qualified = step(verify, "Require successful qualification of the release commit")
    assert qualified =~ "RELEASE_COMMIT: ${{ steps.release.outputs.commit }}"
    assert qualified =~ "GITHUB_TOKEN: ${{ github.token }}"
    assert qualified =~ ~s|os.environ["GITHUB_TOKEN"]|

    assert qualified =~
             ~s|/commits/{commit}/check-runs?check_name=qualified&filter=all&per_page=100&page={page}|

    assert qualified =~ ~s|check.get("name") == "qualified"|
    assert qualified =~ ~s|check.get("head_sha") == commit|
    assert qualified =~ ~s|check.get("conclusion") == "success"|
    assert qualified =~ "page += 1"
    assert qualified =~ "raise SystemExit"
    refute qualified =~ "continue-on-error"

    assert_before(verify, "Require default-branch ancestry", "Read the default toolchain")
    assert_before(verify, "Require successful qualification", "Read the default toolchain")

    assert_before(
      verify,
      "Read and compare the source package versions",
      "bash scripts/check_publication.sh"
    )

    assert_before(verify, "bash scripts/check_publication.sh", "Install the pinned Hex client")
    assert_before(verify, "bash scripts/check_publication.sh", "mix deps.get --check-locked")
  end

  test "only the qualification reader gets checks read permission" do
    workflow = workflow("publish")
    verify = job(workflow, "verify")
    [_, permissions] = Regex.run(~r/^    permissions:\n((?:      [^\n]+\n)+)/m, verify)
    assert permissions == "      contents: read\n      checks: read\n"
    assert length(Regex.scan(~r/^\s+checks: read$/m, workflow)) == 1
    refute workflow =~ "checks: write"
    refute workflow =~ "actions: read"

    for {name, job} <- jobs(workflow), name != "verify" do
      refute job =~ "checks:"
      refute job =~ "GITHUB_TOKEN:"
    end
  end

  test "credential-free published-package checks need the upload and retain their measured platforms" do
    workflow = workflow("publish")

    for {name, duration, run, limit} <- [
          {"smoke", "0.5", "44085034568", 5},
          {"livebooks", "2.9", "44022461020", 6}
        ] do
      job = job(workflow, name)
      assert job =~ "needs: [verify, hex-read-back]"
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

    assert kit =~
             "    # Split out of hex-publish; that whole job, including this check, bounds it.\n" <>
               "    # Twice the slowest green run, at least 5 min: 1.1 min, run 44085034568.\n" <>
               "    timeout-minutes: 5\n"

    refute kit =~ "environment:"
    refute kit =~ "secrets."
    assert kit =~ "node scripts/release_artifact_info.mjs npm-integrity"
    assert kit =~ ~s|if [ "$LIVE_INTEGRITY" != "$VERIFIED_INTEGRITY" ]; then|
    assert kit =~ ~s|cmp "$RUNNER_TEMP/kit-report.json" "$RUNNER_TEMP/escript-report.json"|
    hex = job(workflow, "hex-publish")
    refute hex =~ "npm install"
    refute hex =~ "npx"
  end

  test "only npm gets OIDC and only the conditional no-project Hex upload gets the keys" do
    workflow = workflow("publish")
    npm = job(workflow, "npm-publish")
    hex = job(workflow, "hex-publish")
    assert length(Regex.scan(~r/^\s+id-token: write$/m, workflow)) == 1
    assert npm =~ "id-token: write"
    assert npm =~ "needs: verify"
    assert hex =~ "needs: [verify, npm-kit]"
    key_step = step(hex, "Publish the verified Hex archive and docs to public hexpm")
    assert key_step =~ "working-directory: workflow-tools"

    assert key_step =~
             "if: needs.verify.outputs.hex_package == 'upload' || needs.verify.outputs.hex_docs == 'upload'"

    assert key_step =~ "HEX_PACKAGE: ${{ needs.verify.outputs.hex_package }}"
    assert key_step =~ "HEX_DOCS: ${{ needs.verify.outputs.hex_docs }}"
    assert key_step =~ "HEX_CHECKSUM: ${{ needs.verify.outputs.hex_checksum }}"
    assert key_step =~ "HEX_API_KEY: ${{ secrets.HEX_API_KEY }}"

    assert key_step =~
             "HEX_ORG_KEY_PUBLISH_API_READ: ${{ secrets.HEX_ORG_KEY_PUBLISH_API_READ }}"

    assert_before(
      key_step,
      ~s|set -- agent_blueprint_protocol "$VERSION" --checksum "$HEX_CHECKSUM"|,
      ~s|if [ "$HEX_PACKAGE" = upload ]|
    )

    assert key_step =~ ~s|if [ "$HEX_PACKAGE" = upload ]; then set -- "$@" --package|
    assert key_step =~ ~s|if [ "$HEX_DOCS" = upload ]; then set -- "$@" --docs|
    assert key_step =~ "--counterpart-repository baselabs"

    assert Regex.scan(~r/--counterpart-package ([a-z_]+)/, key_step, capture: :all_but_first) == [
             ["agent_blueprint_protocol"]
           ]

    assert key_step =~ ~s|--package "../verified-release/agent_blueprint_protocol-${VERSION}.tar"|
    assert key_step =~ "--docs ../verified-release/hex-docs.tar.gz"

    assert key_step =~
             ~s|mix run --no-mix-exs scripts/publish_hex_artifacts.exs "$@"|

    refute key_step =~ "--organization"
    assert length(Regex.scan(~r/^ +HEX_ORG_KEY_PUBLISH_API_READ:/m, workflow)) == 1
    assert length(Enum.filter(steps(workflow), &(&1 =~ "HEX_API_KEY"))) == 1
    refute npm =~ "HEX_API_KEY"
  end

  test "credential jobs consume verified inputs and run only workflow-owned commands" do
    workflow = workflow("publish")
    verify = job(workflow, "verify")
    npm = job(workflow, "npm-publish")
    hex = job(workflow, "hex-publish")

    for version <- ~w(nodejs elixir otp) do
      assert verify =~ version <> ": ${{ steps.versions.outputs." <> version <> " }}"
    end

    assert npm =~ "node-version: ${{ needs.verify.outputs.nodejs }}"
    assert hex =~ "elixir-version: ${{ needs.verify.outputs.elixir }}"
    assert hex =~ "otp-version: ${{ needs.verify.outputs.otp }}"
    assert length(Regex.scan(~r/uses: actions\/checkout@/, npm)) == 1
    assert npm =~ "sparse-checkout: /scripts/toolchain.sh\n"

    assert Regex.scan(~r/scripts\/[^\s]+/, npm) == [
             ["scripts/toolchain.sh"],
             ["scripts/toolchain.sh"]
           ]

    assert length(Regex.scan(~r/uses: actions\/checkout@/, hex)) == 1

    assert Regex.scan(~r/scripts\/[^\s]+/, hex) ==
             [
               ["scripts/publish_hex_artifacts.exs"],
               ["scripts/toolchain.sh"],
               ["scripts/toolchain.sh"],
               ["scripts/publish_hex_artifacts.exs"]
             ]

    for job <- [npm, hex] do
      refute job =~ "needs.verify.outputs.release_commit"
      refute job =~ ~s|scripts/toolchain.sh >> "$GITHUB_OUTPUT"|
      refute Regex.match?(~r/run: (?:\.\.\/)?scripts\//, job)
      refute job =~ "Read back"
    end

    for name <- ~w(npm-kit hex-read-back) do
      read_back = job(workflow, name)
      refute read_back =~ "environment:"
      refute read_back =~ "id-token:"
      refute read_back =~ "HEX_API_KEY"
      refute read_back =~ "HEX_ORG_KEY_PUBLISH_API_READ"
    end
  end

  test "source and artifacts are verified before read-only plans compare package bytes" do
    workflow = workflow("publish")
    verify = job(workflow, "verify")
    assert_before(verify, "bash scripts/check_publication.sh", "mix quality")
    assert_before(verify, "run: mix quality", "npm pack ./dist/package --ignore-scripts")
    assert_before(verify, "mix hex.build --output", "verify_release_packages.exs --local")
    assert_before(verify, "verify_release_packages.exs --local", "id: npm")
    assert verify =~ "--write-manifest verified-release/release-manifest.json"

    assert_before(
      verify,
      "verified-release/certified-results.json verified-release/release-manifest.json",
      "sha256sum -- * > SHA256SUMS"
    )

    assert_before(verify, "Docs checksum:", "id: hex")
    assert verify =~ "VERSION=$(node scripts/release_artifact_info.mjs version)"
    assert verify =~ "version: ${{ steps.inputs.outputs.version }}"
    assert verify =~ "npm: ${{ steps.npm.outputs.npm }}"
    assert verify =~ "hex_package: ${{ steps.hex.outputs.package }}"
    assert verify =~ "hex_docs: ${{ steps.hex.outputs.docs }}"
    assert verify =~ "hex_checksum: ${{ steps.hex.outputs.checksum }}"
    assert verify =~ "mix deps.get --check-locked"
    assert verify =~ "npm ci --ignore-scripts --no-audit --no-fund"
    assert verify =~ "mix release.promote --check"
    assert verify =~ "fetch-depth: 0"
    assert verify =~ "MIX_ENV=test mix release.asset --write"
    assert verify =~ "Check public privacy over full history"
    assert verify =~ ~s|cmp "$RUNNER_TEMP/packed-report.json" "$RUNNER_TEMP/verified-report.json"|
    assert verify =~ "node scripts/npm_release_state.mjs plan"
    hex_plan = step(verify, "Plan the Hex uploads")
    assert hex_plan =~ "working-directory: verified-release"

    assert_before(
      hex_plan,
      "mix run --no-mix-exs ../workflow-tools/scripts/hex_release_state.exs plan",
      ~s|if ! grep -Eq '^checksum=[0-9a-f]{64}$' "$GITHUB_OUTPUT"|
    )

    assert hex_plan =~ "exit 1"
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

  test "docs provenance and release assets include every consumer file and checksum" do
    workflow = workflow("publish")
    verify = job(workflow, "verify")
    assert verify =~ ~s|SOURCE_DATE_EPOCH=$(git log -1 --format=%ct "$RELEASE_COMMIT")|

    assert verify =~
             ~s|tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner|

    assert verify =~ "-cf - -C doc . | gzip -n > verified-release/hex-docs.tar.gz"
    assert verify =~ "Docs checksum:"
    assert File.read!("scripts/hex_release_state.exs") =~ "Package checksum:"
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
    archive = step(verify, "Prepare the verified documentation archive")
    assert archive =~ "RELEASE_COMMIT: ${{ steps.release.outputs.commit }}"
    assert archive =~ ~s|os.environ["RELEASE_COMMIT"]|
    assert archive =~ "json.dumps(release"
    assert_before(archive, ~s|Path("doc/release.json").write_text|, "tar --sort=name")
    assert_before(archive, "tar --sort=name", "hex_release_state.exs docs-provenance")
    assert archive =~ ~s|hex-docs.tar.gz "$RELEASE_COMMIT" "$GITHUB_WORKSPACE"|
    plan = step(verify, "Plan the Hex uploads")

    assert plan =~
             ~s|agent_blueprint_protocol "$VERSION" "agent_blueprint_protocol-${VERSION}.tar"|

    refute plan =~ "hex-docs"
    hex = job(workflow, "hex-read-back")
    assert hex =~ "needs: [verify, hex-publish]"
    assert step(hex, "Check out source") =~ "fetch-depth: 0"
    read_back = step(hex, "Read back the served Hex package and docs")
    assert read_back =~ "RELEASE_COMMIT: ${{ needs.verify.outputs.release_commit }}"

    assert read_back =~
             ~s|"release-assets/hex-docs-${VERSION}.tar.gz" "$RELEASE_COMMIT" "$GITHUB_WORKSPACE"|

    assert read_back =~ ~s|sha256sum -- "hex-docs-${VERSION}.tar.gz" >> SHA256SUMS|
    assert_before(read_back, "hex_release_state.exs read-back", "sha256sum")
    assert_before(hex, "hex_release_state.exs read-back", "name: release-assets")
    upload = step(hex, "Hand consumer release assets to maintainers")
    assert upload =~ "path: verified-release/release-assets/"
    assert upload =~ "if-no-files-found: error"
  end

  test "release notes rely on CHANGELOG.md shipping in the compared package" do
    assert "CHANGELOG.md" in Mix.Project.config()[:package][:files],
           "release-notes.md comes from the release commit's CHANGELOG.md; read-back's package " <>
             "comparison makes it the published commit's only while CHANGELOG.md ships in the package"
  end

  test "both packages get the verbatim changelog gate before upload planning or publication" do
    workflow = workflow("publish")
    verify = job(workflow, "verify")
    stamps = changelog_steps(verify)
    assert stamps == changelog_steps(workflow)
    assert length(stamps) == 2

    archives = [
      ~s|"verified-release/agent_blueprint_protocol-${VERSION}.tar"|,
      ~s|"verified-release/agent-blueprint-protocol-verifier-${VERSION}.tgz"|
    ]

    for {stamp, archive} <- Enum.zip(stamps, archives) do
      assert stamp =~ ~s|python3 -I - #{archive} "$VERSION" <<'PY'|

      normalized =
        ("- name: " <> String.trim_trailing(stamp, "\n") <> "\n")
        |> String.replace(~r/^ {6}/m, "")
        |> String.replace(archive, "path/to/package-archive", global: false)

      assert Base.encode16(:crypto.hash(:sha256, normalized), case: :lower) ==
               @changelog_stamp_sha256

      assert_before(verify, "Verify both built release packages", stamp)
      assert_before(verify, ~s|printf 'VERSION=%s\\n' "$VERSION" >> "$GITHUB_ENV"|, stamp)

      for later <- [
            "Plan the npm upload",
            "Plan the Hex uploads",
            "uses: actions/upload-artifact@",
            "npm stage publish",
            "mix run --no-mix-exs scripts/publish_hex_artifacts.exs"
          ] do
        assert_before(workflow, stamp, later)
      end
    end
  end

  @tag skip: match?({:win32, _}, :os.type())
  test "the actual changelog gates accept stamped archives and refuse Unreleased entries" do
    [hex_stamp, npm_stamp] = changelog_steps(workflow("publish"))
    version = Mix.Project.config()[:version]
    changelog = File.read!("CHANGELOG.md")

    unreleased =
      String.replace(changelog, "## [Unreleased]\n", "## [Unreleased]\n\n- Unshipped entry.\n",
        global: false
      )

    AgentBlueprintProtocol.Scratch.with_dir("changelog-stamp", fn dir ->
      script_path = Path.join(dir, "check.py")
      hex = Path.join(dir, "package.tar")
      contents = Path.join(dir, "contents.tar.gz")
      npm = Path.join(dir, "package.tgz")

      for {text, expected_status, message} <- [
            {changelog, 0, "the packaged CHANGELOG is stamped for #{version}"},
            {unreleased, 1, ~s|entries above #{version}, under "[Unreleased]"|}
          ] do
        assert :ok =
                 :erl_tar.create(
                   String.to_charlist(contents),
                   [{~c"CHANGELOG.md", text}],
                   [:compressed]
                 )

        assert :ok =
                 :erl_tar.create(
                   String.to_charlist(hex),
                   [{~c"contents.tar.gz", File.read!(contents)}],
                   []
                 )

        assert :ok =
                 :erl_tar.create(
                   String.to_charlist(npm),
                   [{~c"package/CHANGELOG.md", text}],
                   [:compressed]
                 )

        for {stamp, archive} <- [{hex_stamp, hex}, {npm_stamp, npm}] do
          [_, script] = Regex.run(~r/<<'PY'\n(.*?)^ {10}PY$/ms, stamp)
          File.write!(script_path, String.replace(script, ~r/^ {10}/m, ""))

          {output, status} =
            System.cmd("python3", ["-I", script_path, archive, version], stderr_to_stdout: true)

          assert status == expected_status, output
          assert output =~ message
        end
      end
    end)
  end

  test "served plans skip upload only and always complete registry read-back" do
    workflow = workflow("publish")
    npm = job(workflow, "npm-publish")
    hex = job(workflow, "hex-publish")
    npm_read_back = job(workflow, "npm-kit")
    hex_read_back = job(workflow, "hex-read-back")

    assert step(npm, "Publish the npm kit (staged trusted publishing, provenance)") =~
             "if: needs.verify.outputs.npm == 'upload'"

    assert npm =~ "npm stage publish"
    assert npm =~ "--ignore-scripts --access public --provenance"
    assert npm =~ ~s|grep -ih 'oidc' "$HOME"/.npm/_logs/*-debug-0.log|
    assert npm_read_back =~ "node scripts/npm_release_state.mjs read-back"
    refute step(npm_read_back, "Read back the served npm version") =~ "if:"
    assert hex_read_back =~ "mix run --no-mix-exs ../scripts/hex_release_state.exs read-back"
    refute step(hex_read_back, "Read back the served Hex package and docs") =~ "if:"
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

  test "publication executes no repository automation from the release commit" do
    # Promotion lets repository metadata under .github/ differ between candidate
    # and final only because Publish never runs a release-commit file from it.
    source = workflow("publish")
    refute Regex.match?(~r/^\s+uses:\s*\.\//m, source)
    refute source =~ ".github/"
  end

  test "every uploaded artifact expires after one day in-run or seven days for maintainers" do
    retention =
      for name <- ~w(ci pages publish),
          step <- steps(workflow(name)),
          Regex.match?(~r/uses: actions\/upload-(pages-)?artifact@/, step) do
        artifact =
          case Regex.run(~r/^\s+name: (\S+)$/m, step) do
            [_, artifact] -> artifact
            nil -> "#{name}:pages"
          end

        [_, days] = Regex.run(~r/^\s+retention-days: (\d+)$/m, step) || [nil, nil]
        {artifact, days}
      end

    assert Enum.sort(retention) ==
             [{"pages:pages", "1"}, {"release-assets", "7"}, {"verified-release", "1"}]
  end

  test "Pages stays an owner's default-branch dispatch" do
    pages = workflow("pages")
    refute pages =~ "head_sha"
    [_, triggers] = String.split(pages, "\non:\n", parts: 2)
    [triggers | _] = String.split(triggers, "\npermissions:", parts: 2)
    assert String.trim(triggers) == "workflow_dispatch:"

    for {_name, job} <- jobs(pages) do
      assert_default_branch_first(job)
      assert job =~ "    if: " <> @owners <> "\n"
    end

    assert job(pages, "deploy") =~ "name: github-pages"

    assert pages =~
             "# This default-branch checkout deploys site/; it does not identify a package release."
  end

  @tag skip: match?({:win32, _}, :os.type())
  test "the actual SHA guard refuses refs, malformed SHAs and shell text before use" do
    validation = workflow("publish") |> job("verify") |> step("Validate the release commit")
    [_, script] = String.split(validation, "        run: |\n", parts: 2)

    AgentBlueprintProtocol.Scratch.with_dir("release-sha", fn dir ->
      output = Path.join(dir, "output")
      sha = String.duplicate("a1", 20)

      assert {_, 0} =
               System.cmd("bash", ["-c", script],
                 env: [{"RELEASE_COMMIT", sha}, {"GITHUB_OUTPUT", output}]
               )

      assert File.read!(output) == "commit=#{sha}\n"
      File.rm!(output)

      for value <- [
            "",
            String.upcase(sha),
            "main",
            "refs/heads/main",
            String.duplicate("a", 39),
            String.duplicate("a", 41),
            String.duplicate("g", 40),
            " #{sha}",
            "#{sha}\n",
            "#{sha}\n#{sha}",
            "$(exit 0)"
          ] do
        assert {_, 1} =
                 System.cmd("bash", ["-c", script],
                   env: [{"RELEASE_COMMIT", value}, {"GITHUB_OUTPUT", output}]
                 )

        refute File.exists?(output)
      end
    end)
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

  defp changelog_steps(source) do
    Enum.filter(steps(source), &String.starts_with?(&1, @changelog_stamp <> "\n"))
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
end
