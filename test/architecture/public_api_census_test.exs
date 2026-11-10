defmodule AgentBlueprintProtocol.Architecture.PublicApiCensusTest do
  use ExUnit.Case, async: true

  @public %{
    AgentBlueprintProtocol.Negotiation.Support => [],
    AgentBlueprintProtocol.BoundsAlgebra.Bound => [narrower: 2],
    AgentBlueprintProtocol.BoundsAlgebra.ClampEvidence => [],
    AgentBlueprintProtocol.Deployment => [
      binds?: 2,
      bound_release: 1,
      canonical_bytes: 1,
      content_digest: 1,
      decode: 1,
      decode: 2,
      digest_covered?: 1,
      digest_input: 1,
      from_value: 1,
      from_value: 2,
      to_value: 1,
      verify_binding: 3,
      verify_content_digest: 1
    ],
    AgentBlueprintProtocol.BoundsAlgebra => [
      from_blueprint: 1,
      from_deployment: 1,
      intersect: 1,
      widens?: 2
    ],
    AgentBlueprintProtocol.Conformance.Runner => [run: 1],
    AgentBlueprintProtocol.Predicate => [evaluate: 2, validate: 2],
    AgentBlueprintProtocol.Signature.PublicKey => [],
    AgentBlueprintProtocol.Compatibility => [exact?: 1, verify: 2],
    AgentBlueprintProtocol.Compatibility.Observed => [],
    AgentBlueprintProtocol.Error => [ceiling_keys: 0, codes: 0, declared?: 1],
    AgentBlueprintProtocol.Portability => [
      scan: 1,
      scan_authored: 1,
      scan_identifier: 1,
      scan_value: 1
    ],
    AgentBlueprintProtocol.BoundsAlgebra.Result => [],
    AgentBlueprintProtocol.Evidence.Signatures => [],
    AgentBlueprintProtocol => [
      canonical_bytes: 1,
      decode_blueprint: 1,
      decode_blueprint: 2,
      decode_deployment: 1,
      decode_deployment: 2,
      decode_federation_envelope: 1,
      decode_federation_envelope: 2,
      federation_mapping: 0,
      intersect: 1,
      negotiate: 2,
      reconcile: 3,
      verify_compatibility: 2
    ],
    AgentBlueprintProtocol.BoundsAlgebra.BoundSet => [names: 0, new: 1, to_map: 1],
    AgentBlueprintProtocol.Canonicalization => [encode: 1, encode: 2, verify: 1, verify: 2],
    AgentBlueprintProtocol.Signature => [
      attributes: 1,
      signing_input: 1,
      to_compact: 1,
      verify: 2,
      verify_attestation: 2
    ],
    AgentBlueprintProtocol.Digest => [
      equal?: 2,
      from_tagged: 1,
      hash: 2,
      of: 1,
      to_tagged: 1,
      verify_content: 3
    ],
    AgentBlueprintProtocol.Reconcile => [reconcile: 3],
    AgentBlueprintProtocol.ExtensionRegistry => [
      digest: 0,
      federation_schema: 0,
      registered_extensions: 0
    ],
    AgentBlueprintProtocol.Blueprint => [
      canonical_bytes: 1,
      content_digest: 1,
      decode: 1,
      decode: 2,
      digest_covered?: 1,
      digest_input: 1,
      from_value: 1,
      from_value: 2,
      to_value: 1,
      verify_content_digest: 1
    ],
    AgentBlueprintProtocol.Reconcile.Inputs => [],
    AgentBlueprintProtocol.Negotiation => [negotiate: 2],
    AgentBlueprintProtocol.Deployment.Observations => [],
    AgentBlueprintProtocol.Evidence => [build: 0, build: 1],
    AgentBlueprintProtocol.Federation.Context => [],
    AgentBlueprintProtocol.Evidence.Binding => [],
    AgentBlueprintProtocol.Schema => [
      ceiling: 0,
      complexity: 1,
      dialect: 0,
      equal?: 2,
      parse: 2,
      validate_instance: 3
    ],
    AgentBlueprintProtocol.Bounds => [coerce: 1, maximum: 0, new: 1],
    AgentBlueprintProtocol.Json => [decode: 1, decode: 2],
    AgentBlueprintProtocol.Conformance.Corpus => [classes: 0, floor: 0, load: 1, surfaces: 0],
    AgentBlueprintProtocol.Federation.Mapping.Row => [],
    AgentBlueprintProtocol.Negotiation.Outcome => [],
    AgentBlueprintProtocol.Signature.Attributes => [],
    AgentBlueprintProtocol.BoundsAlgebra.Sources => [],
    AgentBlueprintProtocol.Conformance.Report => [build: 2, to_bytes: 2],
    AgentBlueprintProtocol.Base64Url => [decode: 1, encode: 1],
    AgentBlueprintProtocol.Federation => [
      a2a_carrier_key: 0,
      canonical_bytes: 1,
      decode: 1,
      decode: 2,
      from_a2a_carrier: 1,
      from_a2a_state: 1,
      from_mcp_carrier: 1,
      from_mcp_state: 1,
      from_value: 1,
      mapping: 0,
      mcp_carrier_key: 0,
      terminal_commitment: 1,
      to_a2a_carrier: 1,
      to_a2a_state: 1,
      to_mcp_carrier: 1,
      to_mcp_state: 1,
      verify_commitment: 2
    ]
  }

  test "the documented public modules and functions equal the declared API" do
    modules = Application.spec(:agent_blueprint_protocol, :modules)
    sources = Enum.map(Path.wildcard("lib/**/*.ex"), &("/" <> &1))

    actual =
      for module <- modules,
          source = module.module_info(:compile)[:source] |> to_string(),
          String.ends_with?(String.replace(source, "\\", "/"), sources),
          {:docs_v1, _, _, _, doc, _, entries} = Code.fetch_docs(module),
          doc not in [false, :hidden],
          into: %{} do
        functions =
          for {{kind, name, arity}, _, _, function_doc, metadata} <- entries,
              kind in [:function, :macro],
              function_doc not in [false, :hidden],
              not String.starts_with?(Atom.to_string(name), "__"),
              collapsed <- (arity - Map.get(metadata, :defaults, 0))..arity,
              do: {name, collapsed}

        {module, Enum.sort(functions)}
      end

    assert actual == @public, "the documented public API changed"
  end
end
