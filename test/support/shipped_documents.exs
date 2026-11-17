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
      File.dir?(entry) -> directory_documents(entry)
      File.regular?(entry) and Path.extname(entry) in ~w(.md .livemd .cheatmd) -> [entry]
      true -> []
    end
  end

  # The root is the lookup's working directory, never part of the pattern.
  # Packaging tools skip dot entries, so a dot segment is never a shipped document.
  defp directory_documents(root) do
    for relative <- :filelib.wildcard(~c"**/*.{md,livemd,cheatmd}", String.to_charlist(root)),
        relative = List.to_string(relative),
        not Enum.any?(Path.split(relative), &String.starts_with?(&1, ".")),
        do: Path.join(root, relative)
  end
end
