defmodule AgentBlueprintProtocol.Architecture.ReleaseScriptsTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 180_000
  @version "1.1.0"
  @checksum String.duplicate("a", 64)

  setup_all do
    path = "scripts/publish_hex_artifacts.exs"

    {:__block__, _, [{:defmodule, _, _} = definition, _main]} =
      File.read!(path) |> Code.string_to_quoted!(file: path)

    {{:module, uploader, _, _}, []} = Code.eval_quoted(definition, [], file: path)
    %{uploader: uploader}
  end

  test "only a matching unretired release with explicit docs state can reach a live upload",
       %{uploader: uploader} do
    release = %{
      "version" => @version,
      "retirement" => nil,
      "checksum" => @checksum,
      "has_docs" => false
    }

    assert uploader.release_state({:ok, {200, %{}, release}}, @version, @checksum) ==
             {:served, false}

    assert uploader.release_state(
             {:ok, {200, %{}, %{release | "has_docs" => true}}},
             @version,
             @checksum
           ) ==
             {:served, true}

    assert uploader.release_state({:ok, {404, %{}, nil}}, @version, @checksum) == :missing
    assert uploader.release_state({:ok, {403, %{}, release}}, @version, @checksum) == :unknown

    for {unconfirmed, state} <- [
          {%{release | "version" => "0.0.0"}, :unknown},
          {%{release | "retirement" => %{"reason" => "invalid"}}, :retired},
          {%{release | "checksum" => String.duplicate("b", 64)}, :different_package},
          {%{release | "has_docs" => "false"}, :unknown},
          {Map.delete(release, "has_docs"), :unknown}
        ] do
      assert uploader.release_state({:ok, {200, %{}, unconfirmed}}, @version, @checksum) ==
               state
    end
  end

  test "pending stages distinguish matching assets, conflicts, and terminal receipts",
       %{uploader: uploader} do
    approval = String.duplicate("b", 64)

    release = %{
      "name" => "name",
      "version" => @version,
      "status" => "staged",
      "kind" => "release",
      "checksum" => @checksum,
      "approval_checksum" => approval
    }

    assert uploader.stage_state(
             {:ok, {200, %{}, release}},
             "release",
             "name",
             @version,
             @checksum
           ) ==
             {:pending_release, approval}

    for invalid <- [
          %{release | "name" => "other"},
          %{release | "version" => "0.0.0"},
          %{release | "checksum" => approval},
          %{release | "kind" => "docs"},
          %{release | "status" => "unknown"},
          Map.delete(release, "approval_checksum")
        ] do
      assert uploader.stage_state(
               {:ok, {200, %{}, invalid}},
               "release",
               "name",
               @version,
               @checksum
             ) ==
               :invalid
    end

    for status <- ["expired", "rejected", "approved"] do
      terminal = %{release | "status" => status}

      assert uploader.stage_state(
               {:ok, {200, %{}, terminal}},
               "release",
               "name",
               @version,
               @checksum
             ) ==
               :absent
    end

    docs = %{release | "kind" => "docs", "checksum" => approval}

    assert uploader.stage_state({:ok, {200, %{}, docs}}, "docs", "name", @version, @checksum) ==
             :pending_docs

    assert uploader.stage_state({:ok, {404, %{}, nil}}, "docs", "name", @version, @checksum) ==
             :absent

    assert uploader.stage_state({:ok, {403, %{}, nil}}, "docs", "name", @version, @checksum) ==
             :invalid

    pending = {:pending_release, approval}
    fresh = {:staged, approval}
    assert uploader.package_action(:missing, pending, :absent) == :keep
    assert uploader.package_action(:missing, :absent, :pending_docs) == :wait
    assert uploader.package_action(:missing, :absent, :absent) == :upload
    assert uploader.package_action({:served, false}, :absent, :absent) == :skip

    assert uploader.docs_action(pending, :absent, :missing, fresh) == :attach
    assert uploader.docs_action(pending, :absent, :missing, :held) == :keep
    assert uploader.docs_action(pending, :absent, :missing, :skipped) == :keep
    assert uploader.docs_action({:pending_release, @checksum}, :absent, :missing, fresh) == :keep
    assert uploader.docs_action(pending, :pending_docs, :missing, fresh) == :keep
    assert uploader.docs_action(pending, :absent, {:served, false}, fresh) == :keep
    assert uploader.docs_action(:absent, :absent, {:served, false}, fresh) == :wait
    assert uploader.docs_action(:absent, :pending_docs, {:served, false}, :skipped) == :keep
    assert uploader.docs_action(:absent, :absent, {:served, false}, :skipped) == :upload
    assert uploader.docs_action(:absent, :absent, {:served, true}, :skipped) == :skip
  end

  test "live and staged package receipts must identify the inspected package",
       %{uploader: uploader} do
    package_url = "https://hex.pm/api/repos/example-org/packages/name"
    approval = String.duplicate("b", 64)
    live = %{"package_url" => package_url, "version" => @version, "checksum" => @checksum}

    staged = %{
      "name" => "name",
      "version" => @version,
      "checksum" => @checksum,
      "status" => "staged",
      "kind" => "release",
      "approval_checksum" => approval
    }

    assert uploader.package_receipt(live, "name", @version, @checksum, package_url) == :live

    assert uploader.package_receipt(staged, "name", @version, @checksum, package_url) ==
             {:staged, approval}

    for invalid <- [
          %{live | "package_url" => package_url <> "-other"},
          %{live | "version" => "0.0.0"},
          %{live | "checksum" => approval},
          Map.put(live, "status", "staged"),
          %{staged | "name" => "other"},
          %{staged | "version" => "0.0.0"},
          %{staged | "checksum" => approval},
          %{staged | "status" => "approved"},
          %{staged | "kind" => "docs"},
          Map.delete(staged, "approval_checksum"),
          nil
        ] do
      assert uploader.package_receipt(invalid, "name", @version, @checksum, package_url) ==
               :invalid
    end
  end

  test "both upload gates read stages before their final release GET" do
    script = File.read!("scripts/publish_hex_artifacts.exs")

    assert script =~
             "publish(opts[:organization], name, version, opts[:package], opts[:docs], checksum)"

    assert script =~ "release_config = uncached_config(repo, release_read_auth!(repo))"
    assert script =~ ~s|Map.put(&1, "cache-control", "no-cache")|
    assert script =~ "if target.repo, do: require_org_package!(target)"
    assert script =~ ":mix_hex_api_package.get(release_config, name)"
    assert script =~ ~s|{200, _headers, %{"name" => ^name, "repository" => ^repo}}|
    assert script =~ ":mix_hex_api_release.get(release_config, name, version)"
    assert script =~ "upload_config: uncached_config(repo, upload_auth)"
    assert script =~ ":mix_hex_api.get(target.upload_config, path)"

    assert script =~
             ~r/defp publish_package!.*?require_org_package!\(target\).*?pending_stages!\(target\)\s+case package_action\(served_release!\(target\), release_stage, docs_stage\) do.*?:upload ->\s+body =\s+Hex.API.Release.publish/s

    assert script =~
             ~r/defp publish_docs!.*?require_org_package!\(target\).*?pending_stages!\(target\).*?case docs_action\(release_stage, docs_stage, served_release!\(target\), package_result\) do\s+:attach ->\s+case upload_docs!/s

    assert script =~ "case upload_docs!(target, docs) do"
    assert script =~ ~s|"status" => "staged",|
    assert script =~ ~s|"kind" => "release",|
    assert length(:binary.matches(script, "Hex.API.ReleaseDocs.publish(")) == 1
  end

  test "release reads use anonymous public access or a separate organization API-read key" do
    script = File.read!("scripts/publish_hex_artifacts.exs")
    assert script =~ "defp release_read_auth!(nil), do: []"

    assert script =~
             ~r/defp release_read_auth!\(_repo\) do\s*key = System.fetch_env!\("HEX_ORG_KEY_PUBLISH_API_READ"\).*?\[key: key\]/s

    assert script =~ ~s|upload_key = System.fetch_env!("HEX_API_KEY")|
    assert script =~ "upload_auth = [key: upload_key]"
    assert script =~ "Hex.API.Release.publish(target.repo, archive, target.upload_auth,"

    assert script =~
             "Hex.API.ReleaseDocs.publish(target.repo, target.name, target.version, docs, target.upload_auth)"
  end

  test "organization uploads fail before any request when their API-read key is absent or blank" do
    AgentBlueprintProtocol.Scratch.with_dir("hex-org-read-key", fn dir ->
      args = [
        "--organization",
        "example-org",
        "name",
        @version,
        "--checksum",
        @checksum,
        "--docs",
        "docs"
      ]

      for value <- [nil, "", "  "] do
        {output, status} =
          hex("publish_hex_artifacts.exs", args, dir, [{"HEX_ORG_KEY_PUBLISH_API_READ", value}])

        assert status != 0
        assert output =~ "HEX_ORG_KEY_PUBLISH_API_READ"
        refute output =~ "HEX_API_KEY"
      end
    end)
  end

  test "no-project Hex scripts resolve Hex and refuse a loaded project before reading a key" do
    AgentBlueprintProtocol.Scratch.with_dir("hex-scripts", fn dir ->
      outside = Path.join(dir, "outside")
      inside = Path.join(dir, "inside")
      File.mkdir!(outside)
      File.mkdir!(inside)

      File.write!(Path.join(inside, "mix.exs"), """
      defmodule HexScriptProbe.MixProject do
        use Mix.Project
        def project, do: [app: :hex_script_probe, version: "0.0.0"]
      end
      """)

      args = [
        "agent_blueprint_protocol",
        @version,
        "--checksum",
        @checksum,
        "--docs",
        "docs.tar.gz"
      ]

      {output, status} = hex("publish_hex_artifacts.exs", args, outside)
      assert status != 0
      assert output =~ "HEX_API_KEY"
      refute output =~ "UndefinedFunctionError"
      refute output =~ "a Mix project is loaded"

      {output, status} = hex("publish_hex_artifacts.exs", args, outside, [{"HEX_API_KEY", ""}])
      assert status != 0
      assert output =~ "HEX_API_KEY"

      for {script, args} <- [
            {"publish_hex_artifacts.exs", args},
            {"hex_release_state.exs", ["plan", "agent_blueprint_protocol", @version, "p"]}
          ] do
        {output, status} = hex(script, args, inside)
        assert status != 0
        assert output =~ "a Mix project is loaded; run from a directory without mix.exs"
      end

      {output, status} = hex("publish_hex_artifacts.exs", ["name", @version], outside)
      assert status != 0
      assert output =~ "at least one archive is required"

      for checksum_args <- [[], ["--checksum", "invalid"]] do
        {output, status} =
          hex(
            "publish_hex_artifacts.exs",
            ["name", @version, "--docs", "docs" | checksum_args],
            outside
          )

        assert status != 0
        assert output =~ "--checksum must be a full lowercase SHA-256"
      end

      {output, status} =
        hex("hex_release_state.exs", ["plan", "name", @version, "p"], outside)

      assert status != 0
      assert output =~ "GITHUB_OUTPUT"
    end)
  end

  test "the real signed public registry refuses differing bytes and an unknown package name" do
    AgentBlueprintProtocol.Scratch.with_dir("hex-state-refusal", fn dir ->
      File.write!(Path.join(dir, "wrong"), "deliberately wrong archive")
      output_file = Path.join(dir, "output")
      env = [{"GITHUB_OUTPUT", output_file}]

      for {name, reason} <- [
            {"agent_blueprint_protocol", "served package bytes differ"},
            {"abp_release_probe_nonexistent_7e1d4cca8233", "has no package"}
          ] do
        {output, status} =
          hex("hex_release_state.exs", ["plan", name, @version, "wrong"], dir, env)

        assert status != 0
        assert output =~ reason
        assert output =~ name
        refute File.exists?(output_file)
      end
    end)
  end

  test "real served Hex docs count as present but read-back refuses missing provenance" do
    AgentBlueprintProtocol.Scratch.with_dir("hex-state-served", fn dir ->
      # Fetch actual public registry bytes through the installed pinned Hex client.
      fetch = Path.join(dir, "fetch.exs")

      File.write!(fetch, """
      Hex.start()
      Code.ensure_loaded!(Hex.Repo)
      for {kind, result} <- [
        {"package", Hex.Repo.get_tarball("hexpm", "agent_blueprint_protocol", "#{@version}")},
        {"docs", Hex.Repo.get_docs("hexpm", "agent_blueprint_protocol", "#{@version}")}
      ] do
        case result do
          {:ok, {200, _, bytes}} -> File.write!(kind, bytes)
          _ -> raise "could not fetch the real public release archives"
        end
      end
      """)

      assert {_, 0} = hex_path(fetch, [], dir, [])
      output_file = Path.join(dir, "output")
      env = [{"GITHUB_OUTPUT", output_file}]
      args = ["agent_blueprint_protocol", @version, "package"]
      assert {summary, 0} = hex("hex_release_state.exs", ["plan" | args], dir, env)
      assert summary =~ "package is already served with these bytes and its docs are served"

      checksum =
        :crypto.hash(:sha256, File.read!(Path.join(dir, "package")))
        |> Base.encode16(case: :lower)

      assert File.read!(output_file) == "package=served\ndocs=served\nchecksum=#{checksum}\n"
      repository = Path.join(dir, "repository")
      File.mkdir!(repository)
      AgentBlueprintProtocol.Scratch.init_git!(repository)
      git!(repository, ["commit", "--allow-empty", "--no-gpg-sign", "-m", "Dispatched"])
      dispatched = git!(repository, ["rev-parse", "HEAD"])
      served_docs = Path.join(dir, "served-docs.tar.gz")
      read_back = ["read-back" | args ++ [served_docs, dispatched, repository]]
      {output, status} = hex("hex_release_state.exs", read_back, dir)
      assert status != 0
      assert output =~ "docs archive is missing release.json"
      refute output =~ "published commit:"
      assert File.read!(served_docs) == File.read!(Path.join(dir, "docs"))
    end)
  end

  test "npm state compares real published integrity and emits only a missing upload for an absent version" do
    AgentBlueprintProtocol.Scratch.with_dir("npm-state", fn dir ->
      File.cp!(".tool-versions", Path.join(dir, ".tool-versions"))
      script = Path.expand("scripts/npm_release_state.mjs")
      File.write!(Path.join(dir, "wrong.tgz"), "deliberately wrong archive")
      output_file = Path.join(dir, "output")
      options = [cd: dir, env: [{"GITHUB_OUTPUT", output_file}], stderr_to_stdout: true]
      {output, status} = System.cmd("node", [script, "plan", @version, "wrong.tgz"], options)
      assert status != 0
      assert output =~ "served bytes differ"
      refute File.exists?(output_file)
      assert {_, 0} = System.cmd("node", [script, "plan", "9999.0.0", "wrong.tgz"], options)
      assert File.read!(output_file) == "npm=upload\n"

      fetch = Path.join(dir, "fetch.mjs")

      File.write!(fetch, """
      import {writeFileSync} from 'node:fs';
      const metadata = await fetch('https://registry.npmjs.org/@agent-blueprint-protocol%2fverifier/#{@version}');
      if (metadata.status !== 200) throw new Error('real npm metadata unavailable');
      const release = await metadata.json();
      const response = await fetch(release.dist.tarball);
      if (response.status !== 200) throw new Error('real npm archive unavailable');
      writeFileSync('package.tgz', Buffer.from(await response.arrayBuffer()));
      """)

      assert {_, 0} = System.cmd("node", [fetch], cd: dir, stderr_to_stdout: true)
      File.rm!(output_file)
      assert {_, 0} = System.cmd("node", [script, "plan", @version, "package.tgz"], options)
      assert File.read!(output_file) == "npm=served\n"
      assert {_, 0} = System.cmd("node", [script, "read-back", @version, "package.tgz"], options)
    end)
  end

  test "local docs provenance checks real archives against a real Git history without registry access" do
    AgentBlueprintProtocol.Scratch.with_dir("docs-provenance", fn dir ->
      repository = Path.join(dir, "repository")
      File.mkdir!(repository)
      AgentBlueprintProtocol.Scratch.init_git!(repository)
      git!(repository, ["config", "core.hooksPath", "/dev/null"])
      git!(repository, ["commit", "--allow-empty", "--no-gpg-sign", "-m", "Ancestor"])
      ancestor = git!(repository, ["rev-parse", "HEAD"])
      git!(repository, ["commit", "--allow-empty", "--no-gpg-sign", "-m", "Dispatched"])
      dispatched = git!(repository, ["rev-parse", "HEAD"])
      git!(repository, ["switch", "-c", "side", ancestor])
      git!(repository, ["commit", "--allow-empty", "--no-gpg-sign", "-m", "Side branch"])
      side = git!(repository, ["rev-parse", "HEAD"])
      git!(repository, ["switch", "main"])
      release = %{"package" => "agent_blueprint_protocol", "version" => @version}
      index = {~c"./index.html", "<!doctype html><title>Release docs</title>"}

      for commit <- [dispatched, ancestor] do
        archive = Path.join(dir, commit <> ".tar.gz")
        manifest = :json.encode(Map.put(release, "commit", commit)) |> IO.iodata_to_binary()

        assert :ok =
                 :erl_tar.create(
                   String.to_charlist(archive),
                   [index, {~c"./release.json", manifest}],
                   [:compressed]
                 )

        args = [
          "docs-provenance",
          "agent_blueprint_protocol",
          @version,
          archive,
          dispatched,
          repository
        ]

        assert {output, 0} = hex("hex_release_state.exs", args, dir)
        assert output =~ "published commit: #{commit}"
      end

      valid = Map.put(release, "commit", dispatched)

      manifest = fn value ->
        {~c"release.json", value |> :json.encode() |> IO.iodata_to_binary()}
      end

      for {label, files, reason} <- [
            {"side", [index, manifest.(Map.put(valid, "commit", side))],
             "not the dispatched commit or its ancestor"},
            {"no-release", [index], "missing release.json"},
            {"wrong-package", [index, manifest.(Map.put(valid, "package", "another_package"))],
             "release.json package does not match"},
            {"wrong-version", [index, manifest.(Map.put(valid, "version", "9999.0.0"))],
             "release.json version does not match"},
            {"no-index", [manifest.(valid)], "missing index.html"},
            {"invalid-json", [index, {~c"release.json", "{"}],
             "release.json is not a valid JSON object"},
            {"invalid-commit", [index, manifest.(Map.put(valid, "commit", "--help"))],
             "release.json commit is not a full Git SHA"},
            {"unknown-commit",
             [index, manifest.(Map.put(valid, "commit", String.duplicate("0", 40)))],
             "could not confirm docs release.json commit ancestry"},
            {"duplicate-release", [index, manifest.(valid), manifest.(valid)],
             "multiple release.json entries"}
          ] do
        archive = Path.join(dir, label <> ".tar.gz")
        assert :ok = :erl_tar.create(String.to_charlist(archive), files, [:compressed])

        args = [
          "docs-provenance",
          "agent_blueprint_protocol",
          @version,
          archive,
          dispatched,
          repository
        ]

        {output, status} = hex("hex_release_state.exs", args, dir)
        assert status != 0, label
        assert output =~ reason, "#{label}: #{output}"
        refute output =~ "published commit:"
      end

      for {label, bytes} <- [
            {"not-gzip", "not gzip bytes"},
            {"not-tar", :zlib.gzip("not a tar archive")}
          ] do
        archive = Path.join(dir, label <> ".tar.gz")
        File.write!(archive, bytes)

        args = [
          "docs-provenance",
          "agent_blueprint_protocol",
          @version,
          archive,
          dispatched,
          repository
        ]

        {output, status} = hex("hex_release_state.exs", args, dir)
        assert status != 0
        assert output =~ "not a readable gzip tar"
        refute output =~ "published commit:"
      end
    end)
  end

  defp git!(repository, args) do
    {output, status} = System.cmd("git", ["-C", repository | args], stderr_to_stdout: true)
    assert status == 0, output
    String.trim(output)
  end

  test "release notes extract exactly one dated section and refuse missing versions" do
    AgentBlueprintProtocol.Scratch.with_dir("release-notes", fn dir ->
      script = Path.expand("scripts/release_notes.exs")

      File.write!(Path.join(dir, "CHANGELOG.md"), """
      # Changelog

      ## [Unreleased]

      Pending.

      ## [9.8.7-rc.1] - 2026-11-18

      Current release.

      ### Details

      - Complete notes.

      ## [9.8.6] - 2026-11-17

      Earlier release.

      [Unreleased]: https://example.invalid/compare/v9.8.7-rc.1...HEAD
      [9.8.7-rc.1]: https://example.invalid/compare/v9.8.6...v9.8.7-rc.1
      [9.8.6]: https://example.invalid/releases/tag/v9.8.6
      """)

      assert {_, 0} = System.cmd("elixir", [script, "9.8.7-rc.1", "notes"], cd: dir)

      assert File.read!(Path.join(dir, "notes")) ==
               "Current release.\n\n### Details\n\n- Complete notes.\n"

      assert {_, 0} = System.cmd("elixir", [script, "9.8.6", "earlier-notes"], cd: dir)
      assert File.read!(Path.join(dir, "earlier-notes")) == "Earlier release.\n"

      {output, status} =
        System.cmd("elixir", [script, "9.8.7", "missing"], cd: dir, stderr_to_stdout: true)

      assert status != 0
      assert output =~ "must contain one dated ## [9.8.7] section"
      refute File.exists?(Path.join(dir, "missing"))
    end)
  end

  test "the existing artifact reader requires one equal source package version" do
    AgentBlueprintProtocol.Scratch.with_dir("release-inputs", fn dir ->
      File.cp!(".tool-versions", Path.join(dir, ".tool-versions"))
      script = Path.expand("scripts/release_artifact_info.mjs")

      File.mkdir_p!(Path.join(dir, "priv"))

      for file <- ["mix.exs", "package.json", "priv/release-metadata.json"] do
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

      metadata = :json.decode(File.read!("priv/release-metadata.json"))

      for mismatched <- [
            Map.put(metadata, "package_version", "0.0.0"),
            Map.delete(metadata, "package_version")
          ] do
        File.write!(Path.join(dir, "priv/release-metadata.json"), :json.encode(mismatched))

        assert {_, 1} =
                 System.cmd("node", [script, "version"], cd: dir, stderr_to_stdout: true)
      end

      File.cp!("priv/release-metadata.json", Path.join(dir, "priv/release-metadata.json"))

      for invalid <- ["", ~s|@version "1.0.0"\n@version "1.0.0"|, ~s|@version "main"|] do
        File.write!(Path.join(dir, "mix.exs"), invalid)

        assert {_, 1} =
                 System.cmd("node", [script, "version"], cd: dir, stderr_to_stdout: true)
      end
    end)
  end

  defp hex(script, args, dir, env \\ []) do
    hex_path(Path.expand("scripts/" <> script), args, dir, env)
  end

  defp hex_path(script, args, dir, env) do
    base = [
      {"HEX_API_KEY", nil},
      {"HEX_ORG_KEY_PUBLISH_API_READ", nil},
      {"HEX_HOME", Path.join(dir, "hex-home")},
      {"GITHUB_OUTPUT", nil},
      {"MIX_ENV", "dev"},
      {"MIX_EXS", nil},
      {"MIX_BUILD_PATH", nil},
      {"MIX_BUILD_ROOT", nil},
      {"MIX_DEPS_PATH", nil},
      {"MIX_LOCKFILE", nil}
    ]

    System.cmd("mix", ["run", "--no-mix-exs", script | args],
      cd: dir,
      env: Map.to_list(Map.merge(Map.new(base), Map.new(env))),
      stderr_to_stdout: true
    )
  end
end
