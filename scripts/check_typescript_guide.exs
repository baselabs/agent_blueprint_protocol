# The TypeScript guide gate: the import example in
# documentation/typescript.md runs as written against the built npm kit.
#
#   mix typescript.guide      (after `mix kit.build`)
#
# The example is copied into a scratch directory beside the shipped echo
# example, with node_modules linking the package name to this tree, so its
# import resolves the way an installed dependency resolves. Its output must
# equal the value its trailing comment claims. The same program over an
# edited copy of the example must print something else (the vacuous-sample
# guard). The kit is build state: a missing build raises, never skips. This
# gate reads a documentation path, so the doc-gates workflow runs it.

Code.require_file("gate_node.exs", __DIR__)

defmodule AgentBlueprintProtocol.TypeScriptGuideGate do
  @root Path.expand("..", __DIR__)
  @guide "documentation/typescript.md"
  @built "dist/verifier/blueprint.js"
  @example "examples/echo-blueprint.json"

  def run do
    node = AgentBlueprintProtocol.GateNode.find_node!()

    unless File.exists?(Path.join(@root, @built)) do
      raise "npm kit not built — run `mix kit.build` before the TypeScript guide gate"
    end

    {sample, claimed} = sample!()

    dir =
      Path.join(System.tmp_dir!(), "abp-typescript-guide-#{System.unique_integer([:positive])}")

    scope = Path.join([dir, "node_modules", "@agent-blueprint-protocol"])
    File.mkdir_p!(scope)

    try do
      :ok = File.ln_s(@root, Path.join(scope, "verifier"))
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

    IO.puts("typescript guide: the import example runs as written (prints #{claimed})")
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

  defp run_sample(node, dir, bytes) do
    File.write!(Path.join(dir, "echo-blueprint.json"), bytes)
    {out, status} = System.cmd(node, ["verify.mjs"], cd: dir, stderr_to_stdout: true)
    {String.trim_trailing(out), status}
  end
end

AgentBlueprintProtocol.TypeScriptGuideGate.run()
