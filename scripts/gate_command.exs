defmodule AgentBlueprintProtocol.GateCommand do
  @moduledoc false

  # Only command identity is logged. Options can contain credentials and must
  # never be inspected, even when the child fails.
  def announce(program, args, options) do
    cwd = options |> Keyword.get(:cd, File.cwd!()) |> Path.relative_to_cwd()
    IO.puts(:stderr, "command: #{inspect([program | args])} (cwd: #{cwd})")
  end

  def capture(program, args, options \\ []) do
    announce(program, args, options)
    System.cmd(program, args, options)
  end

  def open(program, args, options) do
    announce(program, args, [])
    Port.open({:spawn_executable, program}, [args: args] ++ options)
  end
end
