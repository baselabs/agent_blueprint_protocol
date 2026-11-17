Code.require_file("package_examples.exs", __DIR__)
Code.require_file("../test/support/scratch.exs", __DIR__)

AgentBlueprintProtocol.Scratch.with_dir("packaged-doctests", fn scratch ->
  archive = Path.join(scratch, "package.tar")

  {_, status} =
    System.cmd("mix", ["hex.build", "--output", archive],
      into: IO.stream(),
      stderr_to_stdout: true
    )

  if status != 0, do: raise("mix hex.build exited #{status}")
  PackageExamples.run(archive, :doctests, [])
end)
