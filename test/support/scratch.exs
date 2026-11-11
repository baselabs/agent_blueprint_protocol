defmodule AgentBlueprintProtocol.Scratch do
  @moduledoc false

  def dir!(label) do
    validate_label!(label)
    suffix = Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
    dir!(System.tmp_dir!(), "abp-#{label}-#{suffix}")
  end

  # Named children belong inside an already private scope. mkdir is
  # exclusive for both forms: an existing directory or symlink is an error.
  def dir!(parent, label) do
    validate_label!(label)
    path = Path.join(parent, label)
    File.mkdir!(path)
    path
  end

  def with_dir(label, fun) do
    path = dir!(label)

    try do
      fun.(path)
    after
      File.rm_rf!(path)
    end
  end

  def with_replica(label, opts, fun) do
    root = Keyword.get(opts, :root, File.cwd!()) |> Path.expand()

    with_dir(label, fn replica ->
      {listing, 0} =
        System.cmd("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard"],
          cd: root,
          stderr_to_stdout: true
        )

      files =
        listing
        |> String.split(<<0>>, trim: true)
        |> Enum.uniq()
        |> Enum.reject(fn path ->
          File.lstat(Path.join(root, path)) in [{:error, :enoent}, {:error, :enotdir}]
        end)

      for path <- files do
        target = Path.join(replica, path)
        File.mkdir_p!(Path.dirname(target))
        File.cp_r!(Path.join(root, path), target)
      end

      if Keyword.get(opts, :git, false), do: initialize_git_repo!(replica, files)

      File.ln_s!(Path.join(root, "deps"), Path.join(replica, "deps"))

      for env <- ~w(dev test), source = Path.join(root, "_build/#{env}"), File.dir?(source) do
        target = Path.join(replica, "_build/#{env}")
        File.mkdir_p!(Path.dirname(target))
        File.cp_r!(source, target)
      end

      fun.(replica)
    end)
  end

  defp validate_label!(label) do
    unless is_binary(label) and Regex.match?(~r/\A[a-z0-9-]+\z/, label) do
      raise ArgumentError,
            "scratch label must contain only lowercase letters, digits, and hyphens"
    end
  end

  # The scratch repository never runs git's automatic maintenance. From git
  # 2.54 the default maintenance strategy is "geometric", and `git commit`
  # starts `git maintenance run --auto --detach`: a detached repack that
  # keeps writing packs into .git after `git commit` returns. Under load it
  # outlived the plant command and refilled .git/objects while File.rm_rf!
  # emptied the scratch (hosted CI, git 2.55, October 14, 2026:
  # `could not remove files and directories recursively ... file already
  # exists`). With maintenance.auto false, git starts no such process.
  def init_git!(replica) do
    commands = [
      ["init", "--initial-branch=main"],
      ["config", "maintenance.auto", "false"],
      ["config", "gc.auto", "0"],
      ["config", "user.email", "scratch@example.invalid"],
      ["config", "user.name", "Scratch"]
    ]

    Enum.each(commands, fn args ->
      {_output, 0} = System.cmd("git", args, cd: replica, stderr_to_stdout: true)
    end)
  end

  defp initialize_git_repo!(replica, files) do
    init_git!(replica)
    pathspec = Path.join(replica, ".git/replica-paths")
    File.write!(pathspec, Enum.map(files, &[&1, <<0>>]))

    for args <- [
          [
            "--literal-pathspecs",
            "add",
            "--force",
            "--pathspec-from-file=#{pathspec}",
            "--pathspec-file-nul"
          ],
          ["commit", "--allow-empty", "-m", "baseline"]
        ] do
      {_output, 0} = System.cmd("git", args, cd: replica, stderr_to_stdout: true)
    end

    File.rm!(pathspec)
  end
end
