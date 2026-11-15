defmodule AgentBlueprintProtocol.Architecture.TimeLimitTest do
  @moduledoc """
  Time limits belong where the duration is a property of the code under
  test, not of the machine that runs it.

  A test module that spawns `mix` or `npm` drives a project build whose
  duration depends on the runner's load, cache and disk, so a fixed test
  limit fails a correct tree on a busy runner. Such a module declares
  `@moduletag timeout: :infinity`. A fixed test limit is allowed only as a
  declared performance tripwire, where finishing inside the limit is the
  requirement under test.

  The bound against a hang is the workflow job's own limit: every job in
  every workflow declares `timeout-minutes`. A job that calls a reusable
  workflow in this repository cannot declare one; the jobs of the called
  workflow carry the limits, and they are scanned like every other job.

  Goes RED on: a build-spawning module without the unlimited module tag, a
  fixed test limit outside the declared tripwires, a tripwire that is no
  longer present, a workflow job without `timeout-minutes` that calls no
  scanned workflow of this repository, and a scan that
  no longer sees the known spawners or jobs, which would make either gate
  vacuous.
  """

  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)
  @spawns_build ~r/System\.cmd\(\s*"(?:mix|npm)"/
  @unlimited ~r/^  @moduletag timeout: :infinity$/m
  @time_limit ~r/^\s*@(?:module)?tag timeout: ([^\n]+)$/m
  # The two memoization tripwires: without (node, location) memoization the
  # evaluation cannot finish inside the limit, so the limit is the test.
  @tripwires [
    {"test/agent_blueprint_protocol/schema_test.exs", "2_000"},
    {"test/agent_blueprint_protocol/schema_test.exs", "2_000"}
  ]
  @known_spawners ["test/scratch_test.exs", "test/architecture/package_consumer_gates_test.exs"]
  @known_jobs [{".github/workflows/ci.yml", "quality"}]

  test "a test module that spawns a project build has no fixed test time limit" do
    sources =
      Path.wildcard(Path.join(@root, "test/**/*_test.exs"))
      |> Enum.map(&{Path.relative_to(&1, @root), File.read!(&1)})

    spawners = for {path, source} <- sources, Regex.match?(@spawns_build, source), do: path

    assert @known_spawners -- spawners == [],
           "the build-spawn scan no longer sees #{inspect(@known_spawners -- spawners)}"

    unlimited =
      for {path, source} <- sources,
          Regex.match?(@spawns_build, source),
          not Regex.match?(@unlimited, source),
          do: path

    assert unlimited == [],
           "test modules spawn a project build without @moduletag timeout: :infinity: " <>
             inspect(unlimited)

    limits =
      for {path, source} <- sources,
          [_, value] <- Regex.scan(@time_limit, source),
          value != ":infinity",
          do: {path, value}

    assert Enum.sort(limits) == Enum.sort(@tripwires),
           "fixed test time limits must equal the declared performance tripwires; " <>
             "found #{inspect(limits)}"

    assert Regex.match?(@spawns_build, ~s|System.cmd(\n  "npm", ["pack"])|)
    refute Regex.match?(@spawns_build, ~s|System.cmd("node", ["cli.mjs"])|)

    assert Regex.scan(@time_limit, "  @tag timeout: 120_000\n") == [
             ["  @tag timeout: 120_000", "120_000"]
           ]
  end

  test "every workflow job declares a job time limit" do
    jobs =
      for path <- Path.wildcard(Path.join(@root, ".github/workflows/*.yml")),
          relative = Path.relative_to(path, @root),
          {name, job} <- jobs(File.read!(path)),
          do: {relative, name, job}

    seen = for {path, name, _job} <- jobs, do: {path, name}

    assert @known_jobs -- seen == [],
           "the job scan no longer sees #{inspect(@known_jobs -- seen)}"

    scanned = jobs |> Enum.map(&elem(&1, 0)) |> MapSet.new()

    offenders =
      for {path, name, job} <- jobs,
          time_limit(job) == nil,
          not MapSet.member?(scanned, called_workflow(job)),
          do: {path, name}

    assert offenders == [], "workflow jobs without timeout-minutes: #{inspect(offenders)}"

    assert called_workflow("  check:\n    uses: ./.github/workflows/postpublish.yml\n") ==
             ".github/workflows/postpublish.yml"

    assert called_workflow("  check:\n    uses: other/repo/.github/workflows/x.yml@v1\n") == nil

    assert called_workflow("  check:\n    steps:\n      - uses: ./.github/workflows/x.yml\n") ==
             nil

    assert time_limit("  lint:\n    runs-on: x\n    timeout-minutes: 15\n    steps:\n") == 15
    assert time_limit("  lint:\n    runs-on: x\n    steps:\n      - timeout-minutes: 15\n") == nil
    assert time_limit("  lint:\n    timeout-minutes: 0\n") == nil
  end

  # The jobs of a workflow, each with its own text: the two-space keys
  # under `jobs:`.
  defp jobs(workflow) do
    [_, body] = String.split(workflow, ~r/^jobs:[ \t]*$/m, parts: 2)

    body
    |> String.split(~r/^(?=  [A-Za-z0-9_-]+:[ \t]*$)/m)
    |> Enum.flat_map(fn chunk ->
      case Regex.run(~r/\A  ([A-Za-z0-9_-]+):/, chunk, capture: :all_but_first) do
        [name] -> [{name, chunk}]
        nil -> []
      end
    end)
  end

  # The repository workflow a job calls with a job-level `uses:`, if any.
  defp called_workflow(job) do
    case Regex.run(~r/^    uses: \.\/(\.github\/workflows\/[A-Za-z0-9_.-]+\.ya?ml)[ \t]*$/m, job,
           capture: :all_but_first
         ) do
      [path] -> path
      nil -> nil
    end
  end

  # The job-level limit in minutes: a positive integer on a key directly
  # under the job, not on a step.
  defp time_limit(job) do
    case Regex.run(~r/^    timeout-minutes: ([1-9][0-9]*)[ \t]*$/m, job, capture: :all_but_first) do
      [minutes] -> String.to_integer(minutes)
      nil -> nil
    end
  end
end
