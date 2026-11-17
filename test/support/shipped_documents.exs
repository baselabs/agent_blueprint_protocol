defmodule AgentBlueprintProtocol.ShippedDocuments do
  @moduledoc false

  def paths do
    npm = Jason.decode!(File.read!("package.json"))

    entries =
      Mix.Project.config()[:package][:files] ++
        npm["files"] ++
        ["verifier/README.md", "documentation", "docs"]

    entries
    |> Enum.flat_map(&documents/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp documents("!" <> _), do: []
  defp documents("dist/spec"), do: documents("spec")

  defp documents(entry) do
    cond do
      File.dir?(entry) -> Path.wildcard(Path.join(entry, "**/*.{md,livemd,cheatmd}"))
      File.regular?(entry) and Path.extname(entry) in ~w(.md .livemd .cheatmd) -> [entry]
      true -> []
    end
  end
end
