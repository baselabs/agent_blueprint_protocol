# Build ABP's release archive and pass it to the standalone package notebook gate.
Code.require_file("extract_livebooks.exs", __DIR__)
Code.require_file("../test/support/scratch.exs", __DIR__)

AgentBlueprintProtocol.Scratch.with_dir("packaged-livebooks", fn scratch ->
  archive = Path.join(scratch, "package.tar")

  {_, status} =
    System.cmd("mix", ["hex.build", "--output", archive],
      into: IO.stream(),
      stderr_to_stdout: true
    )

  if status != 0, do: raise("mix hex.build exited #{status}")
  notebooks = Path.wildcard("docs/livebooks/*.livemd") |> Enum.sort()
  PackageLivebooks.run(archive, notebooks)
end)
