# Validate the normative document, release identity, and release history.
#
#   mix release.candidate

Code.require_file("release_identity.exs", __DIR__)

defmodule AgentBlueprintProtocol.ReleaseCandidateCheck do
  @protocol_path "spec/protocol.md"

  def run do
    findings =
      protocol_presence_findings() ++
        protocol_coupling_findings() ++
        identity_chain_findings() ++ release_history_findings()

    if findings != [] do
      raise """
      release candidate: FAILED

      #{Enum.join(findings, "\n")}
      """
    end

    IO.puts("release candidate: ok (protocol.md coupled, release identity and history verified)")
  end

  # ---- 2. exactly one normative document -------------------------------------------

  defp protocol_presence_findings do
    findings = []

    findings =
      if File.exists?(@protocol_path) do
        findings
      else
        ["release candidate: #{@protocol_path} does not exist" | findings]
      end

    findings =
      if File.exists?("docs/protocol.md") do
        [
          "release candidate: docs/protocol.md exists — the normative " <>
            "document is #{@protocol_path}; a second copy reds"
          | findings
        ]
      else
        findings
      end

    files = Mix.Project.config()[:package][:files] || []

    findings =
      if @protocol_path in files do
        findings
      else
        ["release candidate: #{@protocol_path} missing from package.files" | findings]
      end

    boundary_test = read!("test/architecture/package_boundary_test.exs")

    if String.contains?(boundary_test, @protocol_path) do
      findings
    else
      [
        "release candidate: #{@protocol_path} missing from the package-boundary allowlists"
        | findings
      ]
    end
  end

  # ---- 3. protocol.md coupling ---------------------------------------------------

  defp protocol_coupling_findings do
    # A missing protocol.md raises in read! below — fail-closed; the
    # presence finding names it cleanly for the message.
    protocol = read!(@protocol_path)

    facade_functions =
      AgentBlueprintProtocol.__info__(:functions)
      |> Enum.map(fn {name, _arity} -> Atom.to_string(name) end)
      |> Enum.uniq()

    namespaces =
      AgentBlueprintProtocol.ExtensionRegistry.registered_extensions()
      |> Enum.map(& &1.namespace)

    index = read!("priv/conformance/index.json")
    digest = extract_json_string(index, "corpus_digest")
    total = extract_json_number(index, "total_cases")

    # A missing or unparseable corpus-identity field is a finding, not a
    # silent skip — the coupling check must not degrade quietly.
    corpus_field_findings =
      for {field, value} <- [corpus_digest: digest, total_cases: total], value == "" do
        "protocol.md coupling: corpus index field #{inspect(field)} missing or unparseable"
      end

    empty_registry =
      if namespaces == [] do
        ["protocol.md coupling: registered_extensions() is empty — namespace coupling is vacuous"]
      else
        []
      end

    drift =
      [
        {:facade_function, facade_functions},
        {:registry_namespace, namespaces},
        {:corpus_identity, [digest]}
      ]
      |> Enum.flat_map(fn {label, required} ->
        for item <- required,
            is_binary(item),
            item != "",
            not documented?(protocol, label, item) do
          "protocol.md drift: #{label} #{inspect(item)} not documented in #{@protocol_path}"
        end
      end)

    # The case total couples as a word-bounded "N cases" phrase, not a
    # bare number that any substring satisfies.
    total_finding =
      if total != "" and not Regex.match?(~r/\b#{total} cases\b/, protocol) do
        ["protocol.md drift: corpus total #{total} not stated as \"#{total} cases\""]
      else
        []
      end

    empty_registry ++ corpus_field_findings ++ drift ++ total_finding ++ stance_finding(protocol)
  end

  defp stance_finding(protocol) do
    if String.contains?(String.downcase(protocol), "non-authorizing") do
      []
    else
      ["protocol.md drift: the non-authorizing stance is not stated"]
    end
  end

  # Minimal JSON field extraction over the flat index header (the corpus
  # loader itself remains the integrity authority; this is doc coupling).
  defp extract_json_string(json, key) do
    case Regex.run(~r/"#{key}"\s*:\s*"([^"]+)"/, json) do
      [_, value] -> value
      _ -> ""
    end
  end

  defp extract_json_number(json, key) do
    case Regex.run(~r/"#{key}"\s*:\s*(\d+)/, json) do
      [_, value] -> value
      _ -> ""
    end
  end

  # Facade functions must appear as name/arity tokens ("negotiate/2");
  # namespaces and digests as exact substrings.
  defp documented?(protocol, :facade_function, name), do: String.contains?(protocol, "#{name}/")
  defp documented?(protocol, _label, item), do: String.contains?(protocol, item)

  # ---- 4. release identity chain ------------------------------------------
  #
  # priv/release-metadata.json pins the release identity: the
  # specification digest, package version, corpus/registry digests, the
  # corpus index hash, the verifier runtime floor, and the
  # archive-authorization stance. Every field is re-derived from live
  # state by the shared ReleaseIdentity derivations and compared — the
  # file is never trusted (a tampered, stale, or unexpected field reds).
  # This chain is what certifies that the specification and its evidence
  # co-version.

  defp identity_chain_findings do
    expected = AgentBlueprintProtocol.ReleaseIdentity.expected_metadata()
    metadata_path = AgentBlueprintProtocol.ReleaseIdentity.metadata_path()

    if File.exists?(metadata_path) do
      actual = Jason.decode!(read!(metadata_path))

      mismatched =
        for field <- Enum.sort(Map.keys(expected)),
            Map.get(actual, field) != expected[field] do
          "identity chain: #{field} is #{inspect(Map.get(actual, field))} — " <>
            "the live value is #{inspect(expected[field])}"
        end

      unexpected =
        for field <- Enum.sort(Map.keys(actual) -- Map.keys(expected)) do
          "identity chain: unexpected field #{inspect(field)} in #{metadata_path}"
        end

      mismatched ++ unexpected
    else
      ["identity chain: #{metadata_path} is missing"]
    end
  end

  # ---- 5. the release history (append-only record) --------------------------
  #
  # priv/release-history.json is the RETROACTIVE MAPPING: one row per
  # manifest-era release, append-only, never edited. The static arms here
  # (runnable without git): exact format member, row shape, unique versions, and the row for
  # the CURRENT package_version equals the live manifest identity. The
  # tag-tree verification of HISTORICAL rows lives in the compatibility
  # replay gate, which has git.

  @history_path "priv/release-history.json"
  @history_format "agent-blueprint-protocol-release-history"

  defp release_history_findings do
    history = Jason.decode!(read!(@history_path))
    rows = history["rows"] || []

    shape_findings =
      if history["format"] == @history_format and is_list(rows) and rows != [] do
        []
      else
        ["release history: #{@history_path} must carry the exact format member and rows"]
      end

    row_shape_findings =
      rows
      |> Enum.with_index()
      |> Enum.flat_map(fn {row, index} ->
        valid? =
          is_map(row) and is_binary(row["package_version"]) and row["package_version"] != "" and
            is_binary(row["corpus_digest"]) and is_binary(row["registry_digest"]) and
            is_binary(row["spec_digest"]) and
            is_integer(row["verification_semantics_version"]) and
            row["verification_semantics_version"] >= 1

        if valid?, do: [], else: ["release history: row #{index} is malformed"]
      end)

    versions = Enum.map(rows, & &1["package_version"])

    duplicate_findings =
      if length(Enum.uniq(versions)) == length(versions) do
        []
      else
        ["release history: duplicate package_version rows (append-only, one row per release)"]
      end

    current = Mix.Project.config()[:version] |> to_string()

    current_row_findings =
      case Enum.find(rows, &(&1["package_version"] == current)) do
        nil ->
          ["release history: no row for the current version #{current} — append it at release"]

        row ->
          expected = AgentBlueprintProtocol.ReleaseIdentity.expected_metadata()

          [
            {"corpus_digest", row["corpus_digest"], expected["corpus_digest"]},
            {"registry_digest", row["registry_digest"], expected["registry_digest"]},
            {"spec_digest", row["spec_digest"], expected["spec_digest"]},
            {"verification_semantics_version", row["verification_semantics_version"],
             AgentBlueprintProtocol.ReleaseIdentity.verification_semantics_version()}
          ]
          |> Enum.flat_map(fn {field, recorded, live} ->
            if recorded == live,
              do: [],
              else: ["release history: #{field} at #{current} is stale — re-sync the row"]
          end)
      end

    shape_findings ++ row_shape_findings ++ duplicate_findings ++ current_row_findings
  end

  defp read!(path) do
    if File.exists?(path) do
      File.read!(path)
    else
      raise "release candidate: required file missing: #{path}"
    end
  end
end

AgentBlueprintProtocol.ReleaseCandidateCheck.run()
