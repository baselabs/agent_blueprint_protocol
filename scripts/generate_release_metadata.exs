# Regenerates priv/release-metadata.json from live state.
#
#   MIX_ENV=test mix run --no-start scripts/generate_release_metadata.exs
#
# The field DERIVATIONS are owned by the shared release-identity module
# (also required by the release-candidate check — one source, no drift);
# the check then re-derives every field and compares on each run, so a
# hand-edited or stale file reds regardless of how it was written. The
# output is field-sorted, compact JSON, sorted at EVERY depth (the
# manifest is declared byte-identical across the Hex package and the npm
# kit, and relying on Erlang map term ordering is not a guarantee).

Code.require_file("release_identity.exs", __DIR__)

defmodule AgentBlueprintProtocol.ReleaseMetadataGenerator do
  # A recursive JSON encoder with deterministic member order at every
  # nesting level — byte-stable by construction, independent of map
  # term ordering.
  defp encoded(%{} = map) do
    "{" <>
      Enum.map_join(Enum.sort(map), ",", fn {field, value} ->
        Jason.encode!(field) <> ":" <> encoded(value)
      end) <> "}"
  end

  defp encoded(value) when is_list(value), do: "[" <> Enum.map_join(value, ",", &encoded/1) <> "]"
  defp encoded(value), do: Jason.encode!(value)

  def run do
    identity = AgentBlueprintProtocol.ReleaseIdentity
    metadata = identity.expected_metadata()
    json = encoded(metadata)

    path = Path.expand(Path.join([__DIR__, "..", identity.metadata_path()]), __DIR__)
    File.write!(path, json)

    IO.puts("release metadata: wrote #{path} (spec #{metadata["spec_digest"]})")
  end
end

AgentBlueprintProtocol.ReleaseMetadataGenerator.run()
