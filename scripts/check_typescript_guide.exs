# The TypeScript guide gate: the import example in
# documentation/typescript.md runs as written against the PACKED npm kit.
#
#   mix typescript.guide      (after `mix kit.build`)
#
# The built kit is packed with `npm pack` (package.json `files` decides
# what ships, exactly as on the registry) and installed from that tarball
# into a scratch project, beside the shipped echo example; the example's
# import resolves through the installed package, so a file the tarball
# leaves out fails here. Its output must equal the value its trailing
# comment claims. The same program over an edited copy of the example must
# print something else (the vacuous-sample guard). The kit is build state:
# a missing build raises, never skips. This gate reads a documentation
# path, so the doc-gates workflow runs it.

Code.require_file("gate_node.exs", __DIR__)

defmodule AgentBlueprintProtocol.TypeScriptGuideGate do
  @root Path.expand("..", __DIR__)
  @guide "documentation/typescript.md"
  @built "dist/verifier/blueprint.js"
  @example "examples/echo-blueprint.json"

  def run do
    # The runtime this tree pins: a version manager's shim resolves its
    # version from the working directory, and the scratch project lives
    # outside the tree, so the sample runs the real executable directly.
    shim = AgentBlueprintProtocol.GateNode.find_node!()
    {exec_path, 0} = System.cmd(shim, ["-p", "process.execPath"], cd: @root)
    node = String.trim(exec_path)

    unless File.exists?(Path.join(@root, @built)) do
      raise "npm kit not built — run `mix kit.build` before the TypeScript guide gate"
    end

    {sample, claimed} = sample!()

    dir =
      Path.join(System.tmp_dir!(), "abp-typescript-guide-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    try do
      install_packed_kit!(dir)
      File.write!(Path.join(dir, "verify.mjs"), sample)
      example = File.read!(Path.join(@root, @example))

      case run_sample(node, dir, example) do
        {^claimed, 0} ->
          :ok

        other ->
          raise "#{@guide} import example drift: it claims #{claimed}, it ran #{inspect(other)}"
      end

      edited = String.replace(example, ~s("max_attempts":3), ~s("max_attempts":4))
      if edited == example, do: raise("the sample seed did not edit #{@example}")

      case run_sample(node, dir, edited) do
        {^claimed, _status} -> raise "the sample seed did not diverge (vacuous sample check)"
        _diverged -> :ok
      end
    after
      File.rm_rf!(dir)
    end

    {version, 0} = System.cmd(node, ["--version"])

    IO.puts(
      "typescript guide: the import example runs as written on node " <>
        "#{String.trim(version)} (prints #{claimed})"
    )
  end

  defp sample! do
    guide = File.read!(Path.join(@root, @guide))

    sample =
      case Regex.run(~r/```js\n(.*?)```/s, guide, capture: :all_but_first) do
        [sample] -> sample
        nil -> raise "#{@guide} lost its js import example"
      end

    case Regex.run(~r{console\.log\(.*\); // (\S+)\n}, sample, capture: :all_but_first) do
      [claimed] -> {sample, claimed}
      nil -> raise "the #{@guide} import example no longer states its output"
    end
  end

  # `npm pack --ignore-scripts` packs the kit already built from this tree
  # (the prepack rebuild is the kit.build step's job), then the tarball is
  # installed into the scratch project the way a consumer installs it.
  defp install_packed_kit!(dir) do
    npm =
      System.find_executable("npm") ||
        raise "npm not found: the TypeScript guide gate packs the kit"

    pack_dir = Path.join(dir, "pack")
    File.mkdir_p!(pack_dir)

    {packed, 0} =
      System.cmd(npm, ["pack", "--ignore-scripts", "--pack-destination", pack_dir],
        cd: @root,
        stderr_to_stdout: false
      )

    tarball = Path.join(pack_dir, packed |> String.split("\n", trim: true) |> List.last())
    File.write!(Path.join(dir, "package.json"), ~s({"private":true}))

    case System.cmd(
           npm,
           ["install", "--no-audit", "--no-fund", "--ignore-scripts", tarball],
           cd: dir,
           stderr_to_stdout: true
         ) do
      {_out, 0} -> :ok
      {out, status} -> raise "installing the packed kit failed (exit #{status}):\n#{out}"
    end
  end

  defp run_sample(node, dir, bytes) do
    File.write!(Path.join(dir, "echo-blueprint.json"), bytes)
    {out, status} = System.cmd(node, ["verify.mjs"], cd: dir, stderr_to_stdout: true)
    {String.trim_trailing(out), status}
  end
end

AgentBlueprintProtocol.TypeScriptGuideGate.run()
