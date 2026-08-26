# The release-identity derivations — the single source for the
# specification digest and every priv/release-metadata.json field.
#
# Required by the release-candidate check (which re-derives and compares
# on every run — the metadata file is never trusted) and by the
# release-metadata generator. This file defines the module and nothing
# else: no auto-run, no environment seam, no exit — the fail-closed
# posture of the gates that consume it stays intact.

defmodule AgentBlueprintProtocol.ReleaseIdentity do
  @moduledoc """
  Release-identity derivations, shared by the release-candidate check
  and the release-metadata generator so the two can never drift.

  The specification digest covers EVERY file under spec/ (dotfiles
  included — everything the repository-filter extraction carries),
  framed per file: u64 path length, path, u64 byte length, bytes,
  concatenated in path-sorted order; total SHA-256, tagged
  `sha-256:<unpadded base64url>` — the same encoding as every other
  digest the package ships.
  """

  @metadata_path "priv/release-metadata.json"
  @metadata_format "agent-blueprint-protocol-release-metadata"
  @verifier_major_floor 24

  def metadata_path, do: @metadata_path
  def metadata_format, do: @metadata_format
  def verifier_major_floor, do: @verifier_major_floor

  @spec spec_digest() :: String.t()
  def spec_digest do
    framed =
      "spec/**/*"
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(&File.dir?/1)
      |> Enum.sort()
      |> Enum.map_join(fn path ->
        bytes = File.read!(path)
        <<byte_size(path)::unsigned-64>> <> path <> <<byte_size(bytes)::unsigned-64>> <> bytes
      end)

    "sha-256:" <> Base.url_encode64(:crypto.hash(:sha256, framed), padding: false)
  end

  @spec expected_metadata() :: %{optional(String.t()) => term()}
  def expected_metadata do
    index = read!("priv/conformance/index.json")

    %{
      "format" => @metadata_format,
      "package" => Mix.Project.config()[:app] |> to_string(),
      "package_version" => Mix.Project.config()[:version],
      "spec_digest" => spec_digest(),
      "corpus_digest" => extract_json_string(index, "corpus_digest"),
      "registry_digest" => extract_json_string(index, "registry_digest"),
      "index_sha256_base64url" => Base.url_encode64(:crypto.hash(:sha256, index), padding: false),
      "verifier_runtime" => "node>=#{@verifier_major_floor}",
      "archive_is_publication_authorization" => false
    }
  end

  defp extract_json_string(json, key) do
    case Regex.run(~r/"#{key}"\s*:\s*"([^"]+)"/, json) do
      [_, value] -> value
      _ -> ""
    end
  end

  defp read!(path) do
    if File.exists?(path) do
      File.read!(path)
    else
      raise "release identity: required file missing: #{path}"
    end
  end
end
