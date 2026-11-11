defmodule PublicPrivacyScan do
  @moduledoc """
  Build-free publication guard for tracked files and full reachable Git history.

  Repository fingerprints and environment variable names come only from the
  supplied JSON configuration. Loading this file defines the module without
  running the command.
  """

  @git_env [
    {"GIT_GRAFT_FILE", "/dev/null"},
    {"GIT_CONFIG_COUNT", "2"},
    {"GIT_CONFIG_KEY_0", "advice.graftFileDeprecated"},
    {"GIT_CONFIG_VALUE_0", "false"},
    {"GIT_CONFIG_KEY_1", "maintenance.auto"},
    {"GIT_CONFIG_VALUE_1", "false"}
  ]
  # Fork pull requests receive no repository secrets, so the enforcing scan
  # cannot run there. The ONLY relaxation is an exact "fork-skip" mode set
  # by CI for github.event.pull_request.head.repo.fork; every other mode
  # value (including typos) stays enforcing and fails closed without a key.
  @fork_skip_mode "fork-skip"

  @fork_skip_banner """
  [privacy-scan] SKIPPED: fork pull request without access to the privacy secret.
  The full-history consumer-topology scan was NOT executed on this run.
  The enforcing scan runs on every push, on maintainer pull requests, and on
  any run whose secret IS present; merging requires one of those contexts.
  """

  def main(argv) do
    {config_path, repo} =
      case argv do
        [config_path] -> {config_path, "."}
        [config_path, repo] -> {config_path, repo}
        _ -> raise "usage: elixir check_public_privacy.exs <config.json> [repo_path]"
      end

    config = load_config!(config_path)

    case privacy_scan_decision(config) do
      {:skip, banner} ->
        IO.puts(banner)
        0

      {:enforce, key} ->
        result = scan_repo(repo, MapSet.new(config["forbidden_hmacs"]), key)

        findings =
          [
            "tracked files",
            "commit messages",
            "historical paths",
            "historical contents",
            "tag messages",
            "ref names"
          ]
          |> Enum.zip(Tuple.to_list(result))
          |> Enum.filter(fn {_surface, finding} -> finding not in [0, false] end)

        Enum.each(findings, fn {surface, _finding} ->
          IO.puts(:stderr, "[privacy-scan] FAILED: #{surface}")
        end)

        if findings == [], do: 0, else: 1
    end
  rescue
    error in RuntimeError ->
      IO.puts(:stderr, "[privacy-scan] REFUSED: " <> Exception.message(error))
      1

    _error ->
      IO.puts(:stderr, "[privacy-scan] REFUSED: unable to read configuration or scan repository")
      1
  end

  def load_config!(path) do
    config = path |> File.read!() |> JSON.decode!()

    valid? =
      is_map(config) and
        Enum.sort(Map.keys(config)) == ["forbidden_hmacs", "key_env", "mode_env"] and
        Enum.all?(["key_env", "mode_env"], fn field ->
          is_binary(config[field]) and Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_]*\z/, config[field])
        end) and
        config["key_env"] != config["mode_env"] and
        is_list(config["forbidden_hmacs"]) and config["forbidden_hmacs"] != [] and
        Enum.all?(config["forbidden_hmacs"], fn digest ->
          is_binary(digest) and Regex.match?(~r/\A[0-9a-f]{64}\z/, digest)
        end)

    unless valid?, do: raise("invalid privacy scan configuration")
    config
  end

  def privacy_scan_decision(config) do
    key = config["key_env"] |> System.get_env() |> then(&String.trim(&1 || ""))

    cond do
      byte_size(key) >= 32 ->
        {:enforce, key}

      System.get_env(config["mode_env"]) == @fork_skip_mode ->
        {:skip, @fork_skip_banner}

      true ->
        raise "public-history privacy key is required and must be at least 32 bytes"
    end
  end

  def scan_repo(repo, forbidden_hmacs, key) do
    assert_full_history!(repo)

    tracked_paths =
      repo
      |> git!(["ls-files", "-z"])
      |> String.split(<<0>>, trim: true)

    tracked_findings =
      tracked_paths
      # Deleted paths are still scanned from reachable history below.
      |> Enum.filter(&File.exists?(Path.join(repo, &1)))
      |> parallel(fn path ->
        forbidden?(path <> "\n" <> File.read!(Path.join(repo, path)), forbidden_hmacs, key)
      end)
      |> Enum.count(& &1)

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

  def historical_content_forbidden?(repo, forbidden_hmacs, key) do
    commits =
      repo
      |> git!(["rev-list", "--all"])
      |> String.split("\n", trim: true)

    # Every file of every commit, scanned once per distinct content: an unchanged file is
    # the same blob in every commit that carries it, so the scan grows with the number of
    # file versions, not commits × files (that was 1625s of a 1632s suite at 0.8.2).
    commits
    |> Enum.flat_map(fn commit ->
      repo
      |> git!(["ls-tree", "-r", "-z", commit])
      |> String.split(<<0>>, trim: true)
      |> Enum.map(&tree_entry_blob!/1)
    end)
    |> Enum.uniq()
    |> parallel(&historical_blob_forbidden?(repo, &1, forbidden_hmacs, key))
    |> Enum.any?()
  end

  # Fingerprinting dominates the scan and each item is independent: one task per scheduler.
  defp parallel(items, fun) do
    items
    |> Task.async_stream(fun, ordered: false, timeout: :infinity)
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp tree_entry_blob!(entry) do
    case Regex.run(~r/\A\d+ (\w+) ([0-9a-f]+)\t/, entry, capture: :all_but_first) do
      ["blob", id] -> id
      _other -> raise "unexpected tree entry (only files are scanned)"
    end
  end

  defp historical_blob_forbidden?(repo, id, forbidden_hmacs, key) do
    case System.cmd(
           "git",
           ["--no-replace-objects", "-C", repo, "cat-file", "blob", id],
           stderr_to_stdout: true,
           env: @git_env
         ) do
      {content, 0} -> forbidden?(content, forbidden_hmacs, key)
      {_output, status} -> raise "git cat-file failed with #{status}"
    end
  end

  defp git!(repo, args) do
    case System.cmd("git", ["--no-replace-objects", "-C", repo | args],
           stderr_to_stdout: true,
           env: @git_env
         ) do
      {output, 0} -> output
      {_output, status} -> raise "git plumbing failed with #{status}"
    end
  end

  defp assert_full_history!(repo) do
    case repo |> git!(["rev-parse", "--is-shallow-repository"]) |> String.trim() do
      "false" -> :ok
      state -> raise "full reachable history is required; shallow state=#{state}"
    end
  end

  def forbidden?(content, forbidden_hmacs, key) do
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

  def fingerprint(value, key) do
    :crypto.mac(:hmac, :sha256, key, value) |> Base.encode16(case: :lower)
  end
end

# The VM's first plain argument is the executed script. Code.require_file/2
# leaves it pointing at the caller (or Mix), so loading never invokes main.
case :init.get_plain_arguments() do
  [script | _args] ->
    if Path.expand(List.to_string(script)) == __ENV__.file do
      System.halt(PublicPrivacyScan.main(System.argv()))
    end

  [] ->
    :ok
end
