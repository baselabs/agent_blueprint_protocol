defmodule AgentBlueprintProtocol.Architecture.PublicSurfacePrivacyTest do
  use ExUnit.Case, async: false

  # The history scan is O(tracked files × commits); observed 150–190s
  # under load at the 0.2.1 tree, so the budget carries headroom rather
  # than sitting inside noise of the runtime (a timeout here is a flake,
  # not a privacy finding).
  @moduletag timeout: 480_000

  @forbidden_hmacs MapSet.new([
                     "b588ad7e20b48289a4be8ca875a2fbfc461914717baba46fc18ba63c462205e0",
                     "ecf032819c99d09c0807342342a626248077b33cca17575ea451b942301c0fe9",
                     "bb5fb7f543e2c8712481de0580e61c34414cf8a37a3db958d4d7ccbb258eb9fb",
                     "652e0e51914736b1b207b8a183e431f97088943498a3eb83aed22e6d2ff721fd",
                     "e0cdad5e181bc30934181f34ff84c875316efc69cac4b1d09933b062d0adcf86",
                     "02a265de3e85d26812dda2281b29f468a5e7744cd0ab3c2b6c27c4d8f75c0dce",
                     "3b82b1451497669d7a2dd9491129ba08085980d951b29ebd7fdf7f46a2d9b699",
                     "3bc616492d07f944a4ea8708fe80cdba21829581b17a774482972918e4976848",
                     "c0a721664e882da1af1078d44234372f94224912c08544d479f8e3486d3f01f5"
                   ])
  @test_canary "public privacy canary"
  @test_key "public-test-key"
  @git_env [
    {"GIT_GRAFT_FILE", "/dev/null"},
    {"GIT_CONFIG_COUNT", "1"},
    {"GIT_CONFIG_KEY_0", "advice.graftFileDeprecated"},
    {"GIT_CONFIG_VALUE_0", "false"}
  ]
  test "tracked files and reachable history contain no consumer-specific topology" do
    result = scan_repo(".", @forbidden_hmacs, production_key!())

    assert result == {0, false, false, false, false, false}
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
  end

  test "Git plumbing detects tracked, historical, merge, ref-name, and tag violations" do
    repo =
      Path.join(System.tmp_dir!(), "abp-public-privacy-#{System.unique_integer([:positive])}")

    File.mkdir_p!(repo)
    on_exit(fn -> File.rm_rf!(repo) end)

    git!(repo, ["init", "--initial-branch=main"])
    git!(repo, ["config", "user.email", "privacy-gate@example.invalid"])
    git!(repo, ["config", "user.name", "Privacy Gate"])

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

  defp scan_repo(repo, forbidden_hmacs, key) do
    assert_full_history!(repo)

    tracked_findings =
      repo
      |> git!(["ls-files", "-z"])
      |> String.split(<<0>>, trim: true)
      |> Enum.count(fn path ->
        forbidden?(path <> "\n" <> File.read!(Path.join(repo, path)), forbidden_hmacs, key)
      end)

    messages = git!(repo, ["log", "--all", "--format=fuller"])

    historical_paths =
      git!(repo, ["log", "--all", "--format=", "--name-only", "--diff-merges=separate"])

    tag_messages = git!(repo, ["for-each-ref", "--format=%(contents)", "refs/tags"])
    ref_names = git!(repo, ["for-each-ref", "--format=%(refname)"])

    {tracked_findings, forbidden?(messages, forbidden_hmacs, key),
     forbidden?(historical_paths, forbidden_hmacs, key),
     historical_content_forbidden?(repo, forbidden_hmacs, key),
     forbidden?(tag_messages, forbidden_hmacs, key), forbidden?(ref_names, forbidden_hmacs, key)}
  end

  defp historical_content_forbidden?(repo, forbidden_hmacs, key) do
    commits =
      repo
      |> git!(["rev-list", "--all"])
      |> String.split("\n", trim: true)

    Enum.any?(commits, fn commit ->
      repo
      |> git!(["ls-tree", "-r", "--name-only", commit])
      |> String.split("\n", trim: true)
      |> Enum.any?(&historical_file_forbidden?(repo, commit, &1, forbidden_hmacs, key))
    end)
  end

  defp historical_file_forbidden?(repo, commit, path, forbidden_hmacs, key) do
    case System.cmd(
           "git",
           ["--no-replace-objects", "-C", repo, "show", "#{commit}:#{path}"],
           stderr_to_stdout: true,
           env: @git_env
         ) do
      {content, 0} -> forbidden?(content, forbidden_hmacs, key)
      {output, status} -> raise "git show failed with #{status}: #{output}"
    end
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

  defp assert_full_history!(repo) do
    case repo |> git!(["rev-parse", "--is-shallow-repository"]) |> String.trim() do
      "false" -> :ok
      state -> raise "full reachable history is required; shallow state=#{state}"
    end
  end

  defp repo_git_path(repo, name) do
    path = repo |> git_with_replacements!(["rev-parse", "--git-path", name]) |> String.trim()

    case Path.type(path) do
      :absolute -> path
      _relative -> Path.expand(path, repo)
    end
  end

  defp forbidden?(content, forbidden_hmacs, key) do
    content
    |> String.replace_invalid("")
    |> String.downcase()
    |> candidates()
    |> Enum.any?(&(fingerprint(&1, key) in forbidden_hmacs))
  end

  defp candidates(content) do
    tokens =
      ~r/[a-z0-9_]+(?:-[a-z0-9_]+)*/
      |> Regex.scan(content, capture: :first)
      |> List.flatten()

    components = Enum.flat_map(tokens, &String.split(&1, ["-", "_"], trim: true))

    (windows(tokens, 3) ++ windows(components, 3))
    |> Enum.flat_map(fn parts ->
      [Enum.join(parts), Enum.join(parts, " "), Enum.join(parts, "_"), Enum.join(parts, "-")]
    end)
    |> Enum.uniq()
  end

  defp windows(tokens, max_size) do
    case length(tokens) do
      0 ->
        []

      count ->
        for size <- 1..min(max_size, count),
            offset <- 0..(count - size),
            do: Enum.slice(tokens, offset, size)
    end
  end

  defp test_hmacs do
    [@test_canary, String.replace(@test_canary, " ", "")]
    |> Enum.map(&fingerprint(&1, @test_key))
    |> MapSet.new()
  end

  defp production_key! do
    case System.fetch_env("ABP_PUBLIC_PRIVACY_HMAC_KEY") do
      {:ok, key} ->
        key = String.trim(key)

        if byte_size(key) >= 32 do
          key
        else
          raise "ABP public-history privacy key is required and must be at least 32 bytes"
        end

      :error ->
        raise "ABP public-history privacy key is required and must be at least 32 bytes"
    end
  end

  defp fingerprint(value, key) do
    :crypto.mac(:hmac, :sha256, key, value) |> Base.encode16(case: :lower)
  end
end
