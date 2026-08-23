defmodule AgentBlueprintProtocol.Conformance.Cli.Main do
  @moduledoc """
  The escript entry: the one place the package halts the VM. Delegates to
  `AgentBlueprintProtocol.Conformance.Cli.run/1` for everything else — argv
  parsing, corpus loading, execution, and the report are all tested pure
  surfaces there.
  The escript entry reports conformance facts; it never authorizes anything.
  """

  alias AgentBlueprintProtocol.Conformance.Cli

  @spec main([binary()]) :: no_return()
  def main(argv), do: System.halt(Cli.run(argv))
end
