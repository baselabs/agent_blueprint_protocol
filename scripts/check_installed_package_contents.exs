# Runs in a consumer project whose dependency is the extracted Hex release.
[manifest, hex, npm] = System.argv()
%{"package_checksums" => checksums} = manifest |> File.read!() |> :json.decode()

for {distribution, root} <- [hex: hex, npm: npm] do
  :ok =
    AgentBlueprintProtocol.PackageContents.verify(
      root,
      distribution,
      Map.fetch!(checksums, Atom.to_string(distribution))
    )
end
