Code.require_file("gate_command.exs", __DIR__)

defmodule PublicPrivacyScan do
  @moduledoc """
  Build-free publication guard for tracked files and full reachable Git history.

  History is what a repository can publish: every branch, tag and
  remote-tracking ref. Refs that local tools keep outside those namespaces,
  such as editor checkpoints, are never pushed and are not scanned.

  Repository fingerprints and environment variable names come only from the
  supplied JSON configuration. Loading this file defines the module without
  running the command.

  `forbidden_hmacs` hold for every surface across all reachable history. The
  optional `recent` section adds fingerprints that hold for tracked files and
  ref names, for history outside the ancestry of its `since` commit, and for the
  message of every annotated tag except the tag objects listed in its
  `published_tags`. Names ruled private after `since` was published are refused
  in everything new while the published history before it stays as it is.
  """

  @git_env [
    {"GIT_GRAFT_FILE", "/dev/null"},
    {"GIT_CONFIG_COUNT", "2"},
    {"GIT_CONFIG_KEY_0", "advice.graftFileDeprecated"},
    {"GIT_CONFIG_VALUE_0", "false"},
    {"GIT_CONFIG_KEY_1", "maintenance.auto"},
    {"GIT_CONFIG_VALUE_1", "false"}
  ]

  def main(argv) do
    {config_path, repo} =
      case argv do
        [config_path] -> {config_path, "."}
        [config_path, repo] -> {config_path, repo}
        _ -> raise "usage: elixir check_public_privacy.exs <config.json> [repo_path]"
      end

    config = load_config!(config_path)
    key = privacy_key!(config)
    result = scan_repo(repo, MapSet.new(config["forbidden_hmacs"]), key)

    result =
      case config["recent"] do
        nil ->
          result

        %{"since" => since, "published_tags" => tags, "forbidden_hmacs" => recent_hmacs} ->
          recent = scan_repo(repo, MapSet.new(recent_hmacs), key, {since, MapSet.new(tags)})
          merge_results(result, recent)
      end

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
  rescue
    error in RuntimeError ->
      IO.puts(:stderr, "[privacy-scan] REFUSED: " <> Exception.message(error))
      1

    _error ->
      IO.puts(:stderr, "[privacy-scan] REFUSED: unable to read configuration or scan repository")
      1
  end

  @published_refs ["refs/heads", "refs/tags", "refs/remotes"]
  @published_history ["--branches", "--tags", "--remotes"]

  @config_keys [["forbidden_hmacs", "key_env"], ["forbidden_hmacs", "key_env", "recent"]]

  def load_config!(path) do
    config = path |> File.read!() |> JSON.decode!()

    valid? =
      is_map(config) and
        Enum.sort(Map.keys(config)) in @config_keys and
        is_binary(config["key_env"]) and
        Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_]*\z/, config["key_env"]) and
        digests?(config["forbidden_hmacs"]) and
        (not Map.has_key?(config, "recent") or recent?(config["recent"]))

    unless valid?, do: raise("invalid privacy scan configuration")
    config
  end

  defp recent?(recent) do
    is_map(recent) and
      Enum.sort(Map.keys(recent)) == ["forbidden_hmacs", "published_tags", "since"] and
      object_id?(recent["since"]) and is_list(recent["published_tags"]) and
      Enum.all?(recent["published_tags"], &object_id?/1) and
      digests?(recent["forbidden_hmacs"])
  end

  defp object_id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{40}\z/, id)

  defp digests?(digests) do
    is_list(digests) and digests != [] and
      Enum.all?(digests, &(is_binary(&1) and Regex.match?(~r/\A[0-9a-f]{64}\z/, &1)))
  end

  # A surface fails when either fingerprint set finds it.
  defp merge_results(left, right) do
    left
    |> Tuple.to_list()
    |> Enum.zip(Tuple.to_list(right))
    |> Enum.map(fn
      {left, right} when is_integer(left) -> left + right
      {left, right} -> left or right
    end)
    |> List.to_tuple()
  end

  def privacy_key!(config) do
    key = config["key_env"] |> System.get_env() |> then(&String.trim(&1 || ""))

    if byte_size(key) < 32 do
      raise "public-history privacy key is required and must be at least 32 bytes"
    end

    key
  end

  # `boundary` is nil for all reachable history, or `{since, published_tags}`.
  def scan_repo(repo, forbidden_hmacs, key, boundary \\ nil) do
    assert_full_history!(repo)
    {since, published_tags} = boundary || {nil, nil}
    history = history_range!(repo, since)

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

    messages = git!(repo, ["log" | history] ++ ["--format=fuller"])

    historical_paths =
      git!(repo, ["log" | history] ++ ["--format=", "--name-only", "--diff-merges=separate"])

    tag_messages = tag_messages!(repo, published_tags)
    ref_names = git!(repo, ["for-each-ref", "--format=%(refname)" | @published_refs])

    {tracked_findings, forbidden?(messages, forbidden_hmacs, key),
     forbidden?(historical_paths, forbidden_hmacs, key),
     historical_content_forbidden?(repo, forbidden_hmacs, key, since),
     forbidden?(tag_messages, forbidden_hmacs, key), forbidden?(ref_names, forbidden_hmacs, key)}
  end

  def historical_content_forbidden?(repo, forbidden_hmacs, key, since \\ nil) do
    history = history_range!(repo, since)

    # Git's own reachability walk lists every reachable object once, so each distinct
    # file version is scanned once however many commits carry it. With `since`, the
    # objects reachable from it are excluded.
    ids =
      repo
      |> git!(["rev-list" | history] ++ ["--objects", "--no-object-names"])
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
      AgentBlueprintProtocol.GateCommand.open(
        git,
        ["--no-replace-objects", "-C", repo, "cat-file", "--batch"],
        [
          :binary,
          :exit_status,
          :hide,
          env: Enum.map(@git_env, fn {name, value} -> {~c"#{name}", ~c"#{value}"} end)
        ]
      )

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
    case AgentBlueprintProtocol.GateCommand.capture(
           "git",
           ["--no-replace-objects", "-C", repo | args],
           stderr_to_stdout: true,
           env: @git_env
         ) do
      {output, 0} -> output
      {_output, status} -> raise "git plumbing failed with #{status}"
    end
  end

  defp tag_messages!(repo, nil),
    do: git!(repo, ["for-each-ref", "--format=%(contents)", "refs/tags"])

  # Every annotated tag's message except the grandfathered tag objects.
  defp tag_messages!(repo, published_tags) do
    refs =
      repo
      |> git!(["for-each-ref", "--format=%(objectname) %(objecttype) %(refname)", "refs/tags"])
      |> String.split("\n", trim: true)
      |> Enum.flat_map(fn line ->
        case String.split(line, " ", parts: 3) do
          [id, "tag", ref] -> if MapSet.member?(published_tags, id), do: [], else: [ref]
          _lightweight -> []
        end
      end)

    case refs do
      [] -> ""
      refs -> git!(repo, ["for-each-ref", "--format=%(contents)" | refs])
    end
  end

  # All reachable history, or the history no `since` ancestry contains. `since` must be
  # a commit present here: a missing boundary refuses rather than scanning nothing.
  defp history_range!(_repo, nil), do: @published_history

  defp history_range!(repo, since) do
    case AgentBlueprintProtocol.GateCommand.capture(
           "git",
           [
             "--no-replace-objects",
             "-C",
             repo,
             "rev-parse",
             "--verify",
             "--quiet",
             since <> "^{commit}"
           ],
           stderr_to_stdout: true,
           env: @git_env
         ) do
      {_output, 0} -> @published_history ++ ["^" <> since]
      {_output, _status} -> raise "the recent boundary commit is not in this repository"
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
