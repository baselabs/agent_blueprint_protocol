# The registry equality gate: spec/registry/registry.json is the
# governance-canonical registry source; BOTH compiled twins (the Elixir
# module and the TypeScript verifier's registry) stay hand-written, and
# this LOCAL offline gate binds all three — the canonical digest over
# registry.json's entries must equal the Elixir twin's digest, the
# TypeScript twin's digest, and the corpus index's pinned registry
# digest. A hand-edit on any side reds.
#
#   mix registry.equality
#
# The projection mirrors ExtensionRegistry.digest/0 exactly (entries
# keyed by namespace, the declared field set per entry, JCS-canonical,
# hashed under the extension_registry domain separator).

defmodule AgentBlueprintProtocol.RegistryEqualityGate do
  @registry_path "spec/registry/registry.json"
  @index_path "priv/conformance/index.json"

  def run do
    for invalid <- [
          "1example.org/name",
          "com.example-/name",
          "com.mcp/name",
          "org.modelcontextprotocol.api/name",
          "com.example/-name",
          "com.example/name_",
          "com.example/name/other"
        ] do
      if valid_namespace?(invalid),
        do: raise("registry namespace validation accepted an invalid key")
    end

    findings =
      case json_findings() do
        [] -> elixir_findings() ++ typescript_findings() ++ index_findings() ++ shape_findings()
        missing -> missing
      end

    if findings != [] do
      raise """
      registry equality: FAILED

      #{Enum.join(findings, "\n")}
      """
    end

    digest = canonical_digest()
    count = length(entry_rows())

    IO.puts(
      "registry equality: ok (#{count} entries; governance json, Elixir twin, " <>
        "TypeScript twin, and corpus index all carry #{digest})"
    )
  end

  defp canonical_digest do
    projected =
      {:object,
       Enum.map(entry_rows(), fn row ->
         {row["namespace"],
          {:object,
           [
             {"a2a_uri", {:string, row["a2a_uri"]}},
             {"criticality", {:string, row["criticality"]}},
             {"owner", {:string, row["owner"]}},
             {"promoted_at_revision", number_or_null(row["promoted_at_revision"])},
             {"schema_digest", string_or_null(row["schema_digest"])},
             {"state", {:string, row["state"]}}
           ]}}
       end)}

    alias AgentBlueprintProtocol.{Canonicalization, Digest}
    {:ok, jcs} = Canonicalization.encode(projected)
    Digest.to_tagged(Digest.hash(:extension_registry, jcs))
  end

  defp number_or_null(nil), do: :null
  defp number_or_null(n) when is_integer(n), do: {:integer, n}

  defp string_or_null(nil), do: :null
  defp string_or_null(s) when is_binary(s), do: {:string, s}

  defp entry_rows do
    %{"entries" => rows} = @registry_path |> File.read!() |> Jason.decode!()
    rows
  end

  defp json_findings do
    if File.exists?(@registry_path) do
      []
    else
      [
        "#{@registry_path} is missing — the governance-canonical source ships with the specification"
      ]
    end
  end

  # Closed-world shape: the governance json carries exactly the declared
  # fields — an edit to unprojected content (the format member, an
  # invented entry field) reds here even though the digest projection
  # only covers the declared entry fields.
  @entry_fields ~w(a2a_uri criticality namespace owner promoted_at_revision schema_digest state)

  defp shape_findings do
    raw = @registry_path |> File.read!() |> Jason.decode!()

    top =
      List.wrap(
        if Map.keys(raw) |> Enum.sort() != ["entries", "format"],
          do:
            "the governance json's top-level members are #{inspect(Map.keys(raw) |> Enum.sort())} — exactly entries and format are declared"
      )

    format =
      List.wrap(
        if raw["format"] != "agent-blueprint-protocol-registry",
          do: "the governance json's format member is #{inspect(raw["format"])}"
      )

    rows =
      for row <- entry_rows(),
          extra = Map.keys(row) -- @entry_fields,
          extra != [] do
        "entry #{inspect(row["namespace"])} carries undeclared members: #{inspect(Enum.sort(extra))}"
      end

    namespaces =
      for row <- entry_rows(),
          not valid_namespace?(row["namespace"]),
          do: "registered namespace violates the MCP metadata key grammar"

    top ++ format ++ rows ++ namespaces
  end

  # MCP revision 2026-07-28, Basic protocol / General fields / _meta.
  # Registration is stricter than artifact decoding so existing signed bytes stay valid.
  def valid_namespace?(namespace) when is_binary(namespace) do
    case String.split(namespace, "/") do
      [prefix, name] ->
        labels = String.split(prefix, ".")

        length(labels) >= 2 and Enum.at(labels, 1) not in ["mcp", "modelcontextprotocol"] and
          Enum.all?(labels, &Regex.match?(~r/\A[a-z](?:[a-z0-9-]*[a-z0-9])?\z/, &1)) and
          Regex.match?(~r/\A[a-z0-9](?:[a-z0-9_.-]*[a-z0-9])?\z/, name)

      _ ->
        false
    end
  end

  def valid_namespace?(_), do: false

  defp elixir_findings do
    digest = canonical_digest()

    elixir =
      AgentBlueprintProtocol.ExtensionRegistry.digest()
      |> AgentBlueprintProtocol.Digest.to_tagged()

    if digest == elixir do
      []
    else
      ["the Elixir twin's digest is #{elixir} — the governance json says #{digest}"]
    end
  end

  defp typescript_findings do
    digest = to_string(canonical_digest())

    case typescript_digest() do
      {:ok, ^digest} ->
        []

      {:ok, ts} ->
        ["the TypeScript twin's digest is #{ts} — the governance json says #{digest}"]

      {:error, reason} ->
        ["the TypeScript twin could not be read: #{reason}"]
    end
  end

  defp index_findings do
    digest = canonical_digest()
    index = @index_path |> File.read!()
    pinned = extract(index, "registry_digest")

    if pinned == to_string(digest) do
      []
    else
      ["the corpus index pins registry digest #{pinned} — the governance json says #{digest}"]
    end
  end

  defp extract(json, key) do
    case Regex.run(~r/"#{key}"\s*:\s*"([^"]+)"/, json) do
      [_, value] -> value
      _ -> ""
    end
  end

  # The twin is hand-written TypeScript; the digest is read by running
  # the verifier's own registry module under Node (local, offline).
  defp typescript_digest do
    script =
      "import { registryDigest } from './verifier/registry.ts'; " <>
        "console.log(registryDigest());"

    case System.cmd("node", ["--input-type=module", "-e", script],
           stderr_to_stdout: true,
           env: [{"NODE_NO_WARNINGS", "1"}]
         ) do
      {out, 0} -> {:ok, out |> String.trim() |> String.split("\n") |> List.last()}
      {out, code} -> {:error, "exit #{code}: #{String.slice(out, 0, 200)}"}
    end
  end
end

AgentBlueprintProtocol.RegistryEqualityGate.run()
