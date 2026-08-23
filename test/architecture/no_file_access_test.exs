defmodule AgentBlueprintProtocol.Architecture.NoFileAccessTest do
  @moduledoc """
  The registry-drift gate (the registry acceptance line: "test asserts no
  runtime registry file read exists"): no shipped module touches the
  filesystem AT ALL — the compiled-in registry is data, and nothing in the
  package has any business reading files.

  Enforced at the BEAM level via `ArchitectureScan.beam_remote_calls/1`:
  aliases are expanded at compile time, so a renamed `File` cannot hide —
  and the census covers the ERLANG filesystem modules too (`:file`,
  `:filelib`, `:prim_file`), not just Elixir's `File` (the
  `module == File` filter passed `:file.read_file/1` green).
  Planted-red proven: a reachable `File.read!` call reds this gate.

  The conformance carve-out: the conformance CLI is the package's one legitimate
  filesystem consumer (reading the corpus directory the user points it at
  — the "only Conformance.Cli.Main touches the filesystem" rule
  posture, split here across the Cli + Cli.Main beams). The carve-out is
  keyed EXACTLY to those two beams: the test asserts they exist (deleting
  the CLI while keeping the carve-out reds) and no other module may join
  it — widening the exclusion to any other conformance module (the loader,
  the runner) reds the gate.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.ArchitectureScan

  @lib_beams Path.wildcard("_build/test/lib/agent_blueprint_protocol/ebin/*.beam")

  @carve_out_beams [
    "Elixir.AgentBlueprintProtocol.Conformance.Cli.beam",
    "Elixir.AgentBlueprintProtocol.Conformance.Cli.Main.beam"
  ]

  test "the carve-out modules exist (a deleted CLI with a kept carve-out reds)" do
    names = Enum.map(@lib_beams, &Path.basename/1)

    for beam <- @carve_out_beams do
      assert beam in names, "expected #{beam} to exist — the carve-out must track reality"
    end
  end

  test "no shipped beam outside the CLI carve-out makes any File remote call" do
    assert match?([_ | _], @lib_beams)

    offenders =
      for beam <- @lib_beams,
          Path.basename(beam) not in @carve_out_beams,
          {module, fun} <- ArchitectureScan.beam_remote_calls(beam),
          module in [File, :file, :filelib, :prim_file],
          do: {Path.basename(beam), module, fun}

    assert offenders == [],
           "shipped modules must never touch the filesystem: #{inspect(offenders)}"
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
            {File, :dir?},
            {Path, :wildcard},
            {Path, :join},
            {Path, :relative_to}
          ],
          module in [File, :file, :filelib, :prim_file],
          do: {Path.basename(beam), module, fun}

    assert offenders == [],
           "the CLI carve-out is read-only: #{inspect(offenders)}"
  end
end
