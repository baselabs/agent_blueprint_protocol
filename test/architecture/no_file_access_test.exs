defmodule AgentBlueprintProtocol.Architecture.NoFileAccessTest do
  @moduledoc """
  Shipped modules that verify in-memory artifacts and corpus data have no
  filesystem access. The registry is compiled in.

  The conformance CLI and package contents check read the roots supplied by
  their callers. Their filesystem calls are limited to the exact read-side
  functions listed here. BEAM inspection resolves aliases and covers both
  Elixir and Erlang filesystem modules.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.ArchitectureScan

  @lib_beams Path.wildcard("_build/test/lib/agent_blueprint_protocol/ebin/*.beam")

  @carve_out_beams [
    "Elixir.AgentBlueprintProtocol.Conformance.Cli.beam",
    "Elixir.AgentBlueprintProtocol.Conformance.Cli.Main.beam"
  ]

  @contents_beam "Elixir.AgentBlueprintProtocol.PackageContents.beam"
  @contents_calls [{:file, :list_dir_all}, {File, :lstat!}, {File, :read!}]

  test "the read-side modules exist" do
    names = Enum.map(@lib_beams, &Path.basename/1)

    for beam <- [@contents_beam | @carve_out_beams] do
      assert beam in names, "expected #{beam} to exist — the carve-out must track reality"
    end
  end

  test "only the named read-side modules make filesystem calls" do
    assert match?([_ | _], @lib_beams)

    offenders =
      for beam <- @lib_beams,
          Path.basename(beam) not in [@contents_beam | @carve_out_beams],
          {module, fun} <- ArchitectureScan.beam_remote_calls(beam),
          module in [File, :file, :filelib, :prim_file],
          do: {Path.basename(beam), module, fun}

    assert offenders == [],
           "unexpected filesystem calls: #{inspect(offenders)}"
  end

  test "the package contents check uses only read-side filesystem calls" do
    calls =
      for beam <- @lib_beams,
          Path.basename(beam) == @contents_beam,
          {module, fun} <- ArchitectureScan.beam_remote_calls(beam),
          module in [File, :file, :filelib, :prim_file],
          do: {module, fun}

    assert Enum.sort(Enum.uniq(calls)) == Enum.sort(@contents_calls)
  end

  test "the CLI carve-out contains no filesystem calls BEYOND read-side traversal" do
    # The CLI reads the corpus; it must never write, delete, or execute.
    offenders =
      for beam <- @lib_beams,
          Path.basename(beam) in @carve_out_beams,
          {module, fun} <- ArchitectureScan.beam_remote_calls(beam),
          # Read-side allowlist: reading files and listing paths.
          {module, fun} not in [
            {File, :read!},
            {File, :read},
            {File, :stat},
            {File, :lstat},
            {File, :ls},
            {File, :open},
            {File, :dir?},
            {Path, :wildcard},
            {Path, :join},
            {Path, :relative_to}
          ],
          module in [File, :file, :filelib, :prim_file],
          do: {Path.basename(beam), module, fun}

    assert offenders == [],
           "the CLI carve-out is read-only: #{inspect(offenders)}"

    {_ast, modes} =
      "lib/agent_blueprint_protocol/conformance/cli.ex"
      |> File.read!()
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {{:., _, [{:__aliases__, _, [:File]}, :open]}, _, [_path, modes, _reader]} = node, acc ->
          {node, [modes | acc]}

        node, acc ->
          {node, acc}
      end)

    assert modes == [[:read, :binary]], "the bounded reader must open regular files read-only"
  end
end
