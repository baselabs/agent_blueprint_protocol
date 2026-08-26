# Regenerates priv/release-metadata.json from live state.
#
#   MIX_ENV=test mix run --no-start scripts/generate_release_metadata.exs
#
# The field DERIVATIONS are owned by the shared release-identity module
# (also required by the release-candidate check — one source, no drift);
# the check then re-derives every field and compares on each run, so a
# hand-edited or stale file reds regardless of how it was written. The
# output is field-sorted, compact JSON (byte-stable across
# regenerations).

Code.require_file("release_identity.exs", __DIR__)

identity = AgentBlueprintProtocol.ReleaseIdentity
metadata = identity.expected_metadata()

json =
  "{" <>
    Enum.map_join(Enum.sort(metadata), ",", fn {field, value} ->
      Jason.encode!(field) <> ":" <> Jason.encode!(value)
    end) <> "}"

path = Path.expand(Path.join([__DIR__, "..", identity.metadata_path()]), __DIR__)
File.write!(path, json)

IO.puts("release metadata: wrote #{path} (spec #{metadata["spec_digest"]})")
