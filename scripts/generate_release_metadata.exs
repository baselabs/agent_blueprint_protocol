# Regenerates priv/release-metadata.json from live state.
#
#   MIX_ENV=test mix run --no-start scripts/generate_release_metadata.exs
#
# The field DERIVATIONS are owned by the release-candidate check (this
# script requires that module in library mode — one source, no drift);
# the check then re-derives every field and compares on each run, so a
# hand-edited or stale file reds regardless of how it was written. The
# output is field-sorted, compact JSON (byte-stable across
# regenerations).

System.put_env("ABP_RC_NO_RUN", "1")
Code.require_file("check_release_candidate.exs", __DIR__)

metadata = AgentBlueprintProtocol.ReleaseCandidateCheck.expected_metadata()

json =
  "{" <>
    Enum.map_join(Enum.sort(metadata), ",", fn {field, value} ->
      Jason.encode!(field) <> ":" <> Jason.encode!(value)
    end) <> "}"

path = Path.expand(Path.join([__DIR__, "..", "priv", "release-metadata.json"]), __DIR__)
File.write!(path, json)

IO.puts("release metadata: wrote #{path} (spec #{metadata["spec_digest"]})")
