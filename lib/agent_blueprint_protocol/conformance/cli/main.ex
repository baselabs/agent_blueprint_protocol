defmodule AgentBlueprintProtocol.Conformance.Cli.Main do
  @moduledoc false

  alias AgentBlueprintProtocol.Conformance.Cli

  @spec main([binary()]) :: no_return()
  def main(argv), do: System.halt(Cli.run(argv))
end
