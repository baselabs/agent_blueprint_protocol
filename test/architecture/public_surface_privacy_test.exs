Code.require_file("../../scripts/check_public_privacy.exs", __DIR__)

defmodule AgentBlueprintProtocol.Architecture.PublicSurfacePrivacyTest do
  use ExUnit.Case, async: false

  import PublicPrivacyScan,
    only: [
      scan_repo: 3,
      historical_content_forbidden?: 3,
      forbidden?: 3,
      fingerprint: 2,
      privacy_scan_decision: 1
    ]

  @moduletag timeout: 600_000
  @test_canary "public privacy canary"
  @test_key "public-test-key-for-privacy-scan-32-bytes"
  @test_config %{
    "key_env" => "PUBLIC_PRIVACY_TEST_KEY",
    "mode_env" => "PUBLIC_PRIVACY_TEST_MODE"
  }
  @fork_skip_mode "fork-skip"

  # maintenance.auto false: a commit in the throwaway repository must not
  # start git's detached background maintenance (the geometric repack, the
  # default from git 2.54), which writes into .git after the command returns
  # and races the on_exit cleanup.
  @git_env [
    {"GIT_GRAFT_FILE", "/dev/null"},
    {"GIT_CONFIG_COUNT", "2"},
    {"GIT_CONFIG_KEY_0", "advice.graftFileDeprecated"},
    {"GIT_CONFIG_VALUE_0", "false"},
    {"GIT_CONFIG_KEY_1", "maintenance.auto"},
    {"GIT_CONFIG_VALUE_1", "false"}
  ]

  test "a fork run without the secret skips loudly instead of failing" do
    for key <- [nil, "", String.duplicate("k", 31), "  " <> String.duplicate("k", 31) <> "  "] do
      with_env(
        [{@test_config["mode_env"], @fork_skip_mode}, {@test_config["key_env"], key}],
        fn ->
          assert {:skip, banner} = privacy_scan_decision(@test_config)
          assert banner =~ "SKIPPED"
          assert banner =~ "NOT executed"
        end
      )
    end
  end

  test "an unknown scan-mode value fails closed like an enforcing run" do
    for mode <- [nil, "enforce", "banana"],
        key <- [nil, "", String.duplicate("k", 31), "  " <> String.duplicate("k", 31) <> "  "] do
      with_env([{@test_config["mode_env"], mode}, {@test_config["key_env"], key}], fn ->
        assert_raise RuntimeError, ~r/privacy key is required/, fn ->
          privacy_scan_decision(@test_config)
        end
      end)
    end
  end

  test "a fork run whose secret is present still enforces the scan" do
    with_env(
      [
        {@test_config["mode_env"], @fork_skip_mode},
        {@test_config["key_env"], "  " <> @test_key <> "  "}
      ],
      fn ->
        assert {:enforce, @test_key} = privacy_scan_decision(@test_config)
      end
    )
  end

  test "candidate normalization is red-capable without publishing protected terms" do
    test_hmacs = test_hmacs()
    assert forbidden?(@test_canary, test_hmacs, @test_key)

    parts = String.split(@test_canary, " ")

    for separator <- ["", " ", "_", "-"] do
      assert forbidden?(Enum.join(parts, separator), test_hmacs, @test_key)
    end
  end

  test "invalid UTF-8 is handled deterministically" do
    refute forbidden?(<<255, 254, 0, 1>>, test_hmacs(), @test_key)
    assert forbidden?("PUBLIC" <> <<255>> <> " PRIVACY CANARY", test_hmacs(), @test_key)
    assert forbidden?("publicpri" <> <<255>> <> "vacycanary", test_hmacs(), @test_key)
  end

  test "Git plumbing detects tracked, historical, merge, ref-name, and tag violations" do
    repo = AgentBlueprintProtocol.Scratch.dir!("public-privacy")

    on_exit(fn -> File.rm_rf!(repo) end)

    AgentBlueprintProtocol.Scratch.init_git!(repo)

    File.write!(Path.join(repo, "README.md"), "public protocol\n")
    git!(repo, ["add", "README.md"])
    git!(repo, ["commit", "-m", "clean root"])
    test_hmacs = test_hmacs()
    assert scan_repo(repo, test_hmacs, @test_key) == {0, false, false, false, false, false}

    canary = @test_canary |> String.split(" ") |> Enum.join()

    git!(repo, ["tag", "v-#{canary}"])
    assert scan_repo(repo, test_hmacs, @test_key) == {0, false, false, false, false, true}
    git!(repo, ["tag", "-d", "v-#{canary}"])

    git!(repo, ["tag", "-a", "v-canary", "-m", canary])
    assert scan_repo(repo, test_hmacs, @test_key) == {0, false, false, false, true, false}
    git!(repo, ["tag", "-d", "v-canary"])

    git!(repo, ["switch", "-c", "side"])
    File.write!(Path.join(repo, "side.txt"), "side\n")
    git!(repo, ["add", "side.txt"])
    git!(repo, ["commit", "-m", "side"])
    git!(repo, ["switch", "main"])
    File.write!(Path.join(repo, "main.txt"), "main\n")
    git!(repo, ["add", "main.txt"])
    git!(repo, ["commit", "-m", "main"])
    git!(repo, ["merge", "--no-commit", "side"])
    merge_path = canary <> ".txt"
    File.write!(Path.join(repo, merge_path), "merge-only path\n")
    git!(repo, ["add", merge_path])
    git!(repo, ["commit", "-m", "merge"])
    git!(repo, ["config", "log.diffMerges", "off"])

    original_merge = git!(repo, ["rev-parse", "HEAD"]) |> String.trim()
    first_parent = git!(repo, ["rev-parse", "HEAD^1"]) |> String.trim()
    second_parent = git!(repo, ["rev-parse", "HEAD^2"]) |> String.trim()
    clean_tree = git!(repo, ["rev-parse", "HEAD^1^{tree}"]) |> String.trim()

    replacement_merge =
      git!(repo, [
        "commit-tree",
        clean_tree,
        "-p",
        first_parent,
        "-p",
        second_parent,
        "-m",
        "merge"
      ])
      |> String.trim()

    git_with_replacements!(repo, ["replace", original_merge, replacement_merge])

    refute forbidden?(
             git_with_replacements!(repo, [
               "log",
               "--all",
               "--format=",
               "--name-only",
               "--diff-merges=separate"
             ]),
             test_hmacs,
             @test_key
           )

    merge_patch = git!(repo, ["show", "--format=", "--diff-merges=separate", "HEAD"])
    assert forbidden?(merge_patch, test_hmacs, @test_key)
    assert scan_repo(repo, test_hmacs, @test_key) == {1, false, true, false, false, false}

    git!(repo, ["rm", merge_path])
    git!(repo, ["commit", "-m", "remove merge-only file"])
    assert scan_repo(repo, test_hmacs, @test_key) == {0, false, true, false, false, false}

    content_path = "historical-content.txt"
    File.write!(Path.join(repo, content_path), canary <> "\n")
    git!(repo, ["add", content_path])
    git!(repo, ["commit", "-m", "historical content"])

    content_commit = git!(repo, ["rev-parse", "HEAD"]) |> String.trim()
    content_parent = git!(repo, ["rev-parse", "HEAD^1"]) |> String.trim()
    content_clean_tree = git!(repo, ["rev-parse", "HEAD^1^{tree}"]) |> String.trim()

    replacement_content =
      git!(repo, [
        "commit-tree",
        content_clean_tree,
        "-p",
        content_parent,
        "-m",
        "historical content"
      ])
      |> String.trim()

    git_with_replacements!(repo, ["replace", content_commit, replacement_content])

    {_output, replacement_grep_status} =
      System.cmd(
        "git",
        ["-C", repo, "grep", "--quiet", "-I", "-F", "-e", canary, content_commit, "--"],
        stderr_to_stdout: true
      )

    assert replacement_grep_status == 1
    assert historical_content_forbidden?(repo, test_hmacs, @test_key)

    git!(repo, ["rm", content_path])
    git!(repo, ["commit", "-m", "remove historical content"])
    assert scan_repo(repo, test_hmacs, @test_key) == {0, false, true, true, false, false}

    git_with_replacements!(repo, ["replace", "-d", original_merge])
    git_with_replacements!(repo, ["replace", "-d", content_commit])
    tip = git!(repo, ["rev-parse", "HEAD"]) |> String.trim()
    grafts_path = repo_git_path(repo, "info/grafts")
    shallow_path = repo_git_path(repo, "shallow")

    File.mkdir_p!(Path.dirname(grafts_path))
    File.write!(grafts_path, tip <> "\n")

    refute forbidden?(
             git_with_replacements!(repo, [
               "log",
               "--all",
               "--format=",
               "--name-only",
               "--diff-merges=separate"
             ]),
             test_hmacs,
             @test_key
           )

    assert scan_repo(repo, test_hmacs, @test_key) == {0, false, true, true, false, false}

    File.write!(shallow_path, tip <> "\n")

    assert_raise RuntimeError, ~r/full reachable history is required/, fn ->
      scan_repo(repo, test_hmacs, @test_key)
    end
  end

  test "the standalone command rejects a planted canary and accepts a clean repository" do
    AgentBlueprintProtocol.Scratch.with_dir("public-privacy-command", fn repo ->
      AgentBlueprintProtocol.Scratch.init_git!(repo)
      File.write!(Path.join(repo, "README.md"), "public protocol\n")
      git!(repo, ["add", "README.md"])
      git!(repo, ["commit", "-m", "clean root"])

      config_path = Path.join(repo, "privacy.json")

      File.write!(
        config_path,
        JSON.encode!(Map.put(@test_config, "forbidden_hmacs", MapSet.to_list(test_hmacs())))
      )

      script = Path.expand("scripts/check_public_privacy.exs")
      env = [{@test_config["mode_env"], "enforce"}, {@test_config["key_env"], @test_key}]

      assert {_output, 0} =
               System.cmd("elixir", [script, config_path, repo],
                 env: env,
                 stderr_to_stdout: true
               )

      File.write!(Path.join(repo, "README.md"), @test_canary <> "\n")

      {output, status} =
        System.cmd("elixir", [script, config_path],
          cd: repo,
          env: env,
          stderr_to_stdout: true
        )

      assert status != 0
      assert output =~ "tracked files"
      refute output =~ @test_canary
      refute output =~ @test_key
    end)
  end

  defp git!(repo, args) do
    {output, 0} =
      System.cmd("git", ["--no-replace-objects", "-C", repo | args],
        stderr_to_stdout: true,
        env: @git_env
      )

    output
  end

  defp git_with_replacements!(repo, args) do
    {output, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    output
  end

  defp repo_git_path(repo, name) do
    path = repo |> git_with_replacements!(["rev-parse", "--git-path", name]) |> String.trim()

    case Path.type(path) do
      :absolute -> path
      _relative -> Path.expand(path, repo)
    end
  end

  defp test_hmacs do
    [@test_canary, String.replace(@test_canary, " ", "")]
    |> Enum.map(&fingerprint(&1, @test_key))
    |> MapSet.new()
  end

  defp with_env(pairs, fun) do
    originals = Enum.map(pairs, fn {key, _} -> {key, System.get_env(key)} end)

    Enum.each(pairs, fn
      {key, nil} -> System.delete_env(key)
      {key, value} -> System.put_env(key, value)
    end)

    try do
      fun.()
    after
      Enum.each(originals, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end
end
