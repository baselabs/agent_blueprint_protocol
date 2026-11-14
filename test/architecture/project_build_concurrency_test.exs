defmodule AgentBlueprintProtocol.Architecture.ProjectBuildConcurrencyTest do
  @moduledoc """
  Test modules that spawn `mix` share the project's build directory, and
  Mix serializes builds with a lock: a second `mix` waits and prints
  "Waiting for lock on the build directory" into the output the test reads.
  Two such modules must therefore never run at the same time.

  A synchronous module (`async: false`) already runs alone. An asynchronous
  module that spawns `mix` joins the `:project_build` group, which ExUnit
  runs one module at a time.

  Goes RED on: an `async: true` test module that spawns `mix` without
  `group: :project_build`.
  """

  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)
  @spawns_mix ~r/System\.cmd\(\s*"mix"/
  @async ~r/use ExUnit\.Case,[^\n]*async: true/
  @grouped ~r/use ExUnit\.Case,[^\n]*group: :project_build/

  test "every asynchronous test module that spawns mix joins the project build group" do
    sources =
      Path.wildcard(Path.join(@root, "test/**/*_test.exs"))
      |> Enum.map(&{Path.relative_to(&1, @root), File.read!(&1)})

    spawning = for {path, source} <- sources, Regex.match?(@spawns_mix, source), do: path
    assert "test/scratch_test.exs" in spawning, "the mix-spawn scan found no known spawner"

    offenders =
      for {path, source} <- sources,
          Regex.match?(@spawns_mix, source),
          Regex.match?(@async, source),
          not Regex.match?(@grouped, source),
          do: path

    assert offenders == [],
           "asynchronous test modules spawn mix outside the :project_build group: " <>
             inspect(offenders)
  end
end
