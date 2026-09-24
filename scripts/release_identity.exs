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

  The specification digest covers EVERY file under spec/ EXCEPT the
  macOS Finder artifacts (`.DS_Store`, `._*` — machine-local droppings
  with no release meaning, invisible to git), framed per file: u64
  path length, path, u64 byte length, bytes, concatenated in
  path-sorted order; total SHA-256, tagged
  `sha-256:<unpadded base64url>` — the same encoding as every other
  digest the package ships.
  """

  @metadata_path "priv/release-metadata.json"
  @metadata_format "agent-blueprint-protocol-release-metadata"
  @verifier_major_floor 24

  # ---- the manifest contract (versioned shape, additive-only within a shape)
  #
  # `manifest_version` versions the SHAPE of priv/release-metadata.json: the
  # pre-contract file (0.3.0 – 0.7.1) is implicitly 1; within a shape,
  # fields are added, never removed, retyped, or resemanticized. A breaking
  # shape change bumps this integer and is itself a release.
  @manifest_version 2

  # ---- the semantics/census split
  #
  # `verification_semantics_version` changes ONLY when verification rules or
  # verdicts for inputs certified under a prior census change — including
  # canonicalization, digest computation, decode verdicts, bounds
  # computation, negotiation outcomes, and signature verification behavior.
  # Census growth (corpus cases, registry entries) is NOT a semantics
  # change. The claim is certified per release by `mix compatibility.replay`
  # (a disagreement under an "equivalent" claim reds the battery); the
  # integer itself is authored intent, never gate-derived.
  @verification_semantics_version 1

  # The closed digest scheme, named so a consumer can bind the computation
  # identity without a registry lookup (unchanged across every release; an
  # algorithm succession is a data change plus a protocol revision, and a
  # semantics bump).
  @digest_identity "rfc8785-jcs+sha-256+domain-separated+base64url-unpadded"

  # The compatibility claims: wire revisions this package verifies, and the
  # certified equivalence verdict per PRIOR census digest (the current
  # census is this release's own, not a prior one). Verdict vocabulary:
  # "equivalent" (per-case verdict agreement, replay-certified),
  # "diverged_by_registry_census" (divergences explained by registry growth
  # between the census's release and this one), "not_equivalent" (authored
  # semantics-break claim; stops replay, never inverse-checked).
  @protocol_revisions_supported [1]
  @prior_census_verdicts %{
    "sha-256:sg6Fo7p8nZpJDzxFn4dXHBWgbGvEvtOk-7t3m7OT7Yo" => "equivalent"
  }

  def metadata_path, do: @metadata_path
  def metadata_format, do: @metadata_format
  def verifier_major_floor, do: @verifier_major_floor
  def manifest_version, do: @manifest_version
  def verification_semantics_version, do: @verification_semantics_version

  # macOS Finder droppings are never artifact content; a stray .DS_Store
  # would shift digests and red file-set equality on any Mac.
  defp macos_artifact?(path) do
    name = Path.basename(path)
    name == ".DS_Store" or String.starts_with?(name, "._")
  end

  @spec spec_digest() :: String.t()
  def spec_digest do
    framed =
      "spec/**/*"
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(fn path -> macos_artifact?(path) or File.dir?(path) end)
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
      "manifest_version" => @manifest_version,
      "package" => Mix.Project.config()[:app] |> to_string(),
      "package_version" => Mix.Project.config()[:version],
      "verification_semantics_version" => @verification_semantics_version,
      "digest_identity" => @digest_identity,
      "protocol_revisions_supported" => @protocol_revisions_supported,
      "prior_census_verdicts" => @prior_census_verdicts,
      "spec_digest" => spec_digest(),
      "corpus_digest" => extract_json_string(index, "corpus_digest"),
      "registry_digest" => extract_json_string(index, "registry_digest"),
      "index_sha256_base64url" => Base.url_encode64(:crypto.hash(:sha256, index), padding: false),
      "verifier_runtime" => "node>=#{@verifier_major_floor}",
      "verifier_kit" => verifier_kit(),
      "archive_is_publication_authorization" => false
    }
  end

  # The kit identity is DERIVED from package.json (never hand-carried): its
  # version is separately bound equal to the Hex line by the version-sync
  # gate in the agreement check — one release line, two registries.
  defp verifier_kit do
    %{
      "name" => package_json_string("name"),
      "registry" => "npm",
      "version" => package_json_string("version")
    }
  end

  defp package_json_string(key) do
    path = Path.expand("../package.json", __DIR__)

    case Regex.run(~r/"#{key}"\s*:\s*"([^"]+)"/, read!(path)) do
      [_, value] -> value
      _ -> raise "release identity: package.json carries no readable #{key} member"
    end
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
