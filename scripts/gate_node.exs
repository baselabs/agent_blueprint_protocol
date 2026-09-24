# The shared node locator for the gate scripts (the verifier agreement
# gate and the compatibility replay gate): finds the runtime by name and
# enforces the major-version floor from the shared release-identity
# module. This file defines the module and nothing else: no auto-run, no
# environment seam — the fail-closed posture of the gates that consume
# it stays intact.

Code.require_file("release_identity.exs", __DIR__)

defmodule AgentBlueprintProtocol.GateNode do
  @doc """
  Locates the Node runtime and asserts the major-version floor
  (`ReleaseIdentity.verifier_major_floor/0`). Raises, never skips: a
  gate that needs the TS verifier cannot run green without it.
  """
  @spec find_node!() :: String.t()
  def find_node! do
    executable = if(match?({:win32, _}, :os.type()), do: "node.exe", else: "node")
    floor = AgentBlueprintProtocol.ReleaseIdentity.verifier_major_floor()

    case System.find_executable(executable) do
      nil ->
        raise "node not found: a gate requires Node >= #{floor} for the TypeScript verifier"

      path ->
        {version_out, 0} = System.cmd(path, ["--version"], stderr_to_stdout: true)

        major =
          version_out
          |> String.trim()
          |> String.replace_leading("v", "")
          |> String.split(".")
          |> hd()
          |> String.to_integer()

        if major >= floor,
          do: path,
          else: raise("node #{major} below the >= #{floor} floor")
    end
  end
end
