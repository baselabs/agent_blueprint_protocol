defmodule AgentBlueprintProtocol.CiGoToolchainTest do
  @moduledoc """
  Every workflow job that runs a Go command selects the pinned Go toolchain
  first, with one setup step: the setup-go release commit and the Go release
  below. A runner's ambient Go is never used. The BaseLabs runner image ships
  no Go, and a hosted image's Go moves with the image, so the pinned step
  makes every runner build actionlint and gitleaks with the same toolchain.
  The public and private repositories carry the same step, so a merge
  between them cannot drop it.

  Goes RED on: a Go job without the step, the step after the first Go
  command, a second setup step, a different action commit or Go release,
  and a scan that no longer sees the known Go jobs, which would make the
  gate vacuous.
  """

  use ExUnit.Case, async: true

  @setup_go_sha "b7ad1dad31e06c5925ef5d2fc7ad053ef454303e"
  @go_version "1.27.4"
  @setup_go "uses: actions/setup-go@#{@setup_go_sha} # v7.0.0\n" <>
              "        with:\n" <>
              "          go-version: \"#{@go_version}\"\n" <>
              "          cache: false"
  @known_go_jobs [
    {".github/workflows/ci.yml", "workflow-syntax"},
    {".github/workflows/ci.yml", "secret-scan"}
  ]

  test "every job that runs Go selects the pinned Go toolchain first" do
    go_jobs =
      for path <- Path.wildcard(".github/workflows/*.yml"),
          {name, job} <- jobs(File.read!(path)),
          go_command(job) != nil,
          do: {path, name, job}

    seen = for {path, name, _job} <- go_jobs, do: {path, name}

    assert @known_go_jobs -- seen == [],
           "the scan no longer sees #{inspect(@known_go_jobs -- seen)}"

    offenders =
      for {path, name, job} <- go_jobs, reason <- offences(job), do: {path, name, reason}

    assert offenders == [], "Go jobs without the pinned toolchain: #{inspect(offenders)}"

    step = "      - name: Set up Go\n        #{@setup_go}\n\n"
    run = "      - name: Run tool\n        run: go run example.com/tool@0123456789abcdef\n"
    good = "  lint:\n    steps:\n" <> step <> run

    assert offences(good) == []
    assert offences("  lint:\n    steps:\n" <> run) != []
    assert offences("  lint:\n    steps:\n" <> run <> step) != []
    assert offences("  lint:\n    steps:\n" <> step <> step <> run) != []
    assert offences(String.replace(good, @go_version, "1.27.1")) != []
    assert offences(String.replace(good, @setup_go_sha, String.duplicate("0", 40))) != []

    assert jobs("on:\n  push:\njobs:\n" <> good) |> Enum.map(&elem(&1, 0)) == ["lint"]
    assert go_command("        # `go run` fetches the module by commit\n") == nil
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

  # The position of the first Go command outside a comment, or nil.
  defp go_command(job) do
    # Comments are blanked, not removed, so positions stay comparable.
    code = Regex.replace(~r/^[ \t]*#[^\n]*$/m, job, &String.duplicate(" ", byte_size(&1)))

    case Regex.run(~r/\bgo (?:run|install|build|test|vet|get|mod)\b/, code, return: :index) do
      [{position, _length}] -> position
      nil -> nil
    end
  end

  defp offences(job) do
    setups = Regex.scan(~r/uses: actions\/setup-go@/, job) |> length()

    pinned =
      case :binary.match(job, @setup_go) do
        {position, _length} -> position
        :nomatch -> nil
      end

    first_go = go_command(job)

    [
      setups != 1 && "selects Go #{setups} times, not once",
      pinned == nil && "does not pin setup-go v7.0.0 with Go #{@go_version}",
      (pinned != nil and first_go != nil and pinned > first_go) &&
        "runs Go before selecting the pinned toolchain"
    ]
    |> Enum.filter(&is_binary/1)
  end
end
