defmodule AgentBlueprintProtocol.Architecture.ReleaseScriptsTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 180_000
  @version "1.1.0"

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

      args = ["agent_blueprint_protocol", @version, "--docs", "docs.tar.gz"]
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
      assert File.read!(output_file) == "package=served\ndocs=served\n"
      {dispatched, 0} = System.cmd("git", ["rev-parse", "HEAD"])
      served_docs = Path.join(dir, "served-docs.tar.gz")
      read_back = ["read-back" | args ++ [served_docs, String.trim(dispatched), File.cwd!()]]
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
      git!(repository, ["init", "--initial-branch=main"])
      git!(repository, ["config", "user.name", "Release provenance test"])
      git!(repository, ["config", "user.email", "release-probe@example.test"])
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
      """)

      assert {_, 0} = System.cmd("elixir", [script, "9.8.7-rc.1", "notes"], cd: dir)

      assert File.read!(Path.join(dir, "notes")) ==
               "Current release.\n\n### Details\n\n- Complete notes.\n"

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
  end

  defp hex(script, args, dir, env \\ []) do
    hex_path(Path.expand("scripts/" <> script), args, dir, env)
  end

  defp hex_path(script, args, dir, env) do
    base = [
      {"HEX_API_KEY", nil},
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
