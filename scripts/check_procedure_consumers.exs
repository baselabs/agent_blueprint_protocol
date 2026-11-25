# Run the real preceding release's consumers, with no replacement registry.
Code.require_file("gate_command.exs", __DIR__)
Code.require_file("../test/support/scratch.exs", __DIR__)

alias AgentBlueprintProtocol.{GateCommand, Scratch}

Mix.start()
Mix.env(:prod)

preceding_release = "v1.1.2"

Scratch.with_dir("procedure-consumers", fn scratch ->
  File.cp!(".tool-versions", Path.join(scratch, ".tool-versions"))
  {project, status} = GateCommand.capture("git", ["show", preceding_release <> ":mix.exs"])
  if status != 0, do: raise("the preceding release tag #{preceding_release} must be available")
  File.write!(Path.join(scratch, "mix.exs"), project)

  files =
    Mix.Project.in_project(:agent_blueprint_protocol, scratch, fn _ ->
      Mix.Project.config()[:package][:files]
    end)

  unless is_list(files) and files != [],
    do: raise("the preceding release must declare its package files")

  # The Hex package owns its compile inputs; the separate verifier is the TS consumer.
  archive = Path.join(scratch, "release.tar")

  {_, 0} =
    GateCommand.capture(
      "git",
      [
        "archive",
        "--format=tar",
        "--output",
        archive,
        preceding_release,
        "--" | Enum.uniq(files ++ ["verifier"])
      ],
      stderr_to_stdout: true
    )

  :ok = :erl_tar.extract(String.to_charlist(archive), cwd: String.to_charlist(scratch))
  corpus = :json.decode(File.read!("priv/conformance/cases/procedure-verify.json"))
  row = Enum.find(corpus["cases"], &(&1["id"] == "procedure-valid"))
  File.write!(Path.join(scratch, "procedure.json"), row["input"]["text"])

  File.write!(Path.join(scratch, "consumer.exs"), """
  alias AgentBlueprintProtocol.{Deployment, Error, Negotiation}
  {:ok, deployment} = Deployment.decode(File.read!("procedure.json"))
  support = %Negotiation.Support{revisions: MapSet.new([1])}
  {:error, %Error{code: :extension_unknown_critical}} = Negotiation.negotiate(deployment, support)
  IO.puts("legacy Elixir consumer denied extension_unknown_critical")
  """)

  File.write!(Path.join(scratch, "consumer.mjs"), """
  import {readFileSync} from 'node:fs';
  import {decode} from './verifier/deployment.ts';
  import {negotiate} from './verifier/negotiation.ts';
  const deployment=decode(readFileSync('procedure.json'));
  if(!deployment.ok)throw new Error(deployment.e);
  const result=negotiate(deployment.v.value,{revisions:new Set([1]),coreFields:new Set(),registry:{},schemas:{}});
  if(result.ok||result.e!=='extension_unknown_critical')throw new Error('legacy consumer accepted procedure semantics');
  console.log('legacy TypeScript consumer denied extension_unknown_critical');
  """)

  node = System.find_executable("node") || raise "node missing"

  for {program, args} <- [
        {"mix", ["run", "--no-start", "consumer.exs"]},
        {node, ["consumer.mjs"]}
      ] do
    {output, status} =
      GateCommand.capture(program, args,
        cd: scratch,
        env: [{"MIX_ENV", "prod"}],
        stderr_to_stdout: true
      )

    if status != 0, do: raise(output)
  end

  IO.puts(
    "procedure consumers: both real preceding-release verifiers denied extension_unknown_critical"
  )
end)
