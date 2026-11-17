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
    # Git's own reachability walk lists every reachable object once, so each distinct
    # file version is scanned once however many commits carry it.
    ids =
      repo
      |> git!(["rev-list", "--all", "--objects", "--no-object-names"])
      |> String.split("\n", trim: true)

    repo
    |> read_blobs!(ids)
    |> parallel(&forbidden?(&1, forbidden_hmacs, key))
    |> Enum.any?()
  end

  # Fingerprinting dominates the scan and each item is independent: one task per scheduler.
  defp parallel(items, fun) do
    items
    |> Task.async_stream(fun, ordered: false, timeout: :infinity)
    |> Enum.map(fn {:ok, result} -> result end)
  end

  # One `git cat-file --batch` reads every object; only file contents are kept.
  # Objects are framed by their declared size, never by lines.
  defp read_blobs!(_repo, []), do: []

  defp read_blobs!(repo, ids) do
    git = System.find_executable("git") || raise "git executable not found"

    port =
      Port.open({:spawn_executable, git}, [
        :binary,
        :exit_status,
        :hide,
        args: ["--no-replace-objects", "-C", repo, "cat-file", "--batch"],
        env: Enum.map(@git_env, fn {name, value} -> {~c"#{name}", ~c"#{value}"} end)
      ])

    Port.command(port, Enum.map(ids, &[&1, ?\n]))

    try do
      collect_blobs(port, length(ids), "", [])
    after
      Port.close(port)
    end
  end

  defp collect_blobs(_port, 0, "", blobs), do: blobs
  defp collect_blobs(_port, 0, _extra, _blobs), do: raise("unexpected git cat-file output")

  defp collect_blobs(port, remaining, buffer, blobs) do
    case next_object(buffer) do
      {:ok, {"blob", content}, rest} ->
        collect_blobs(port, remaining - 1, rest, [content | blobs])

      {:ok, {_type, _content}, rest} ->
        collect_blobs(port, remaining - 1, rest, blobs)

      :more ->
        collect_blobs(port, remaining, buffer <> receive_output!(port), blobs)
    end
  end

  defp receive_output!(port) do
    receive do
      {^port, {:data, data}} -> data
      {^port, {:exit_status, status}} -> raise "git cat-file failed with #{status}"
    end
  end

  defp next_object(buffer) do
    with [header, rest] <- :binary.split(buffer, "\n") do
      case String.split(header, " ") do
        [_id, type, size] ->
          size = String.to_integer(size)

          case rest do
            <<content::binary-size(^size), ?\n, rest::binary>> -> {:ok, {type, content}, rest}
            _incomplete when byte_size(rest) <= size -> :more
            _malformed -> raise "unexpected git cat-file output"
          end

        _missing ->
          raise "git cat-file could not read a reachable object"
      end
    else
      [_partial_header] -> :more
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

  def candidates(content) do
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
    for size <- 1..max_size, window <- Enum.chunk_every(tokens, size, 1, :discard), do: window
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
