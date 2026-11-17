defmodule AgentBlueprintProtocol.Architecture.CIWorkflowTest do
  use ExUnit.Case, async: true

  @workflows ~w(ci publish pages postpublish)
  @runtimes [
    {"erlef/setup-beam", [{"elixir", "elixir-version"}, {"erlang", "otp-version"}]},
    {"actions/setup-node", [{"nodejs", "node-version"}]},
    {"actions/setup-go", [{"golang", "go-version"}]}
  ]

  test "qualification runs once on landing pushes and requires every job to succeed" do
    ci = workflow("ci")
    [_, triggers] = String.split(ci, "\non:\n", parts: 2)
    [triggers | _] = String.split(triggers, "\npermissions:", parts: 2)
    assert String.trim(triggers) == "push:\n    branches: ['kci/**']"
    refute ci =~ "pull_request"
    refute ci =~ "workflow_dispatch"
    assert ci =~ "ABP_PUBLIC_PRIVACY_HMAC_KEY: ${{ secrets.ABP_PUBLIC_PRIVACY_HMAC_KEY }}"

    jobs = jobs(ci)
    assert {"qualified", qualified} = List.last(jobs)
    assert qualified =~ "    if: always()\n"
    [_, needs] = Regex.run(~r/^    needs: \[([^\]]+)\]$/m, qualified)
    expected = for {name, _} <- jobs, name != "qualified", do: name
    assert needs |> String.split(", ") |> Enum.sort() == Enum.sort(expected)
    assert qualified =~ "NEEDS: ${{ toJSON(needs) }}"
    assert qualified =~ "job['result'] != 'success'"
    assert qualified =~ "sys.exit(bool(failed) or not results)"
    refute qualified =~ "continue-on-error"
  end

  test "one shared reader supplies defaults and compatibility lanes" do
    ci = workflow("ci")
    jobs = Map.new(jobs(ci))
    reader = Map.fetch!(jobs, "toolchain")
    assert reader =~ ~s|sh scripts/toolchain.sh >> "$GITHUB_OUTPUT"|

    for output <- ~w(elixir otp nodejs golang beam_lanes nodejs_lanes) do
      assert reader =~ "#{output}: ${{ steps.versions.outputs.#{output} }}"
    end

    for {name, job} <- jobs, name not in ["toolchain", "qualified"] do
      assert job =~ "    needs: toolchain\n", name
      refute job =~ ~s|sh scripts/toolchain.sh >> "$GITHUB_OUTPUT"|, name
    end

    assert jobs["compatibility"] =~
             "include: ${{ fromJSON(needs.toolchain.outputs.beam_lanes) }}"

    assert jobs["typescript-consumers"] =~
             "node: ${{ fromJSON(needs.toolchain.outputs.nodejs_lanes) }}"

    refute File.exists?("scripts/read_release_inputs.py")

    for name <- @workflows do
      source = workflow(name)
      refute source =~ "read_release_inputs.py"
      refute source =~ "version-file:"
      refute Regex.match?(~r/^\s+(?:elixir|otp|node):\s*[\["'\d]/m, source)

      for {_name, job} <- jobs(source),
          {action, _tools} <- @runtimes,
          job =~ "uses: #{action}@" do
        if name != "ci" do
          assert job =~ "id: versions"
          assert job =~ ~s|sh scripts/toolchain.sh >> "$GITHUB_OUTPUT"|
        end
      end
    end
  end

  test "every runtime uses reader outputs and immediately verifies its installed version" do
    for name <- @workflows,
        {job_name, job} <- jobs(workflow(name)),
        {setup, index} <- job |> steps() |> Enum.with_index(),
        {action, tools} <- @runtimes,
        setup =~ "uses: #{action}@" do
      check = Enum.at(steps(job), index + 1)
      assert is_binary(check), "#{name}/#{job_name}: missing installed check"
      assert check =~ "shell: bash"

      arguments =
        for {tool, input} <- tools do
          [_, version] = Regex.run(~r/^          #{input}: (.+)$/m, setup)

          default = %{
            "elixir" => "elixir",
            "erlang" => "otp",
            "nodejs" => "nodejs",
            "golang" => "golang"
          }

          expected =
            case {name, job_name, tool} do
              {"ci", "compatibility", "elixir"} -> "${{ matrix.elixir }}"
              {"ci", "compatibility", "erlang"} -> "${{ matrix.otp }}"
              {"ci", "typescript-consumers", "nodejs"} -> "${{ matrix.node }}"
              {"ci", _, _} -> "${{ needs.toolchain.outputs.#{default[tool]} }}"
              _ -> "${{ steps.versions.outputs.#{default[tool]} }}"
            end

          assert version == expected, "#{name}/#{job_name}: #{input}"
          variable = "TOOLCHAIN_" <> String.upcase(tool)
          assert check =~ "#{variable}: #{version}\n"
          tool <> ~s|="$#{variable}"|
        end

      assert check =~
               "run: sh scripts/toolchain.sh --installed " <> Enum.join(arguments, " ") <> "\n"

      assert length(Regex.scan(~r/^          TOOLCHAIN_[A-Z]+:/m, check)) == length(tools)

      if action == "erlef/setup-beam" do
        assert setup =~ "version-type: strict"
        assert setup =~ "install-hex: false"
      end

      if action == "actions/setup-go" do
        assert setup =~ "actions/setup-go@d8cbb8045d7f43706b9177cceb36c1f91a6644d5 # v7.1.0"
      end
    end
  end

  test "every runner job has twice its measured green duration with a two-minute floor" do
    for name <- @workflows, {job_name, job} <- jobs(workflow(name)) do
      if job =~ "    runs-on:" do
        if {name, job_name} == {"publish", "draft-release"} do
          assert job =~ "# No predecessor; gh release create only.\n    timeout-minutes: 2"
        else
          assert [_, duration, _run, timeout] =
                   Regex.run(
                     ~r/# Twice the slowest green run: (\d+\.\d+) min, (?:private )?run (\d+)\.\n    timeout-minutes: (\d+)\n/,
                     job
                   )

          assert String.to_integer(timeout) == max(2, ceil(2 * String.to_float(duration)))
        end
      else
        # Reusable workflow callers cannot set timeout-minutes. The callee's
        # runner jobs are checked by this same loop.
        assert name == "publish" and job_name == "postpublish"
        assert job =~ "uses: ./.github/workflows/postpublish.yml"
        refute job =~ "timeout-minutes:"
      end
    end
  end

  test "all runners are pinned public images and every checkout discards credentials" do
    for name <- @workflows do
      source = workflow(name)
      refute source =~ "vars."
      refute source =~ "self-hosted"
      refute source =~ "BASELABS_RUNNER"
      refute source =~ "kimosabe-remote"

      for {_name, job} <- jobs(source),
          [_, runner] <- Regex.scan(~r/^    runs-on: (.+)$/m, job) do
        assert runner in ["ubuntu-24.04", "${{ matrix.os }}"]

        if runner == "${{ matrix.os }}" do
          assert job =~ "os: [ubuntu-24.04, macos-15, windows-2025]"
        end
      end

      for step <- steps(source), step =~ "uses: actions/checkout@" do
        assert step =~ "persist-credentials: false"
      end
    end
  end

  test "project dependency fetches are locked and qualification includes both audits" do
    for name <- ["ci", "publish"] do
      source = workflow(name)
      assert source =~ "mix deps.get --check-locked"
      refute Regex.match?(~r/mix deps.get(?! --check-locked)/, source)
    end

    quality = Mix.Project.config()[:aliases][:quality]
    assert "hex.audit" in quality
    assert "deps.audit" in quality
    assert Map.new(jobs(workflow("ci")))["quality"] =~ "run: mix quality"
  end

  defp workflow(name), do: File.read!(".github/workflows/#{name}.yml")

  defp jobs(workflow) do
    [_, jobs] = String.split(workflow, "\njobs:\n", parts: 2)

    for [_, name, body] <-
          Regex.scan(~r/^  ([a-z][a-z0-9-]*):\n(.*?)(?=^  [a-z][a-z0-9-]*:\n|\z)/ms, jobs),
        do: {name, body}
  end

  defp steps(source), do: source |> String.split("      - name: ") |> tl()
end
