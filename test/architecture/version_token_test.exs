defmodule AgentBlueprintProtocol.Architecture.VersionTokenTest do
  @moduledoc """
  Non-vacuity for the identifier gate's core predicate: it must flag release
  version tokens in every conventional position — leading, snake-boundary, and
  CamelCase-hump — not just terminal ones, while leaving embedded lowercase-`v`
  protocol names (IPv4-style) alone.
  """
  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.ArchitectureScan

  @carry_a_token ~w(
    V2 v1 V2Blueprint BlueprintV2 BlueprintV2Parser
    decode_v2 decode_v2beta schema_v1 blueprint_v2 blueprintV2
    Es6Number Http2Stream Tls12Socket Query2 Schema3Parser
    HTTP2Stream TLS12Socket ES6Number
  )

  @carry_no_token ~w(
    AgentBlueprintProtocol Blueprint reconcile base64url Ed25519
    crypto Ipv4 IPV4 IPv4 IPv6 revision Base64Url Ed25519Key Ipv4Route
  )

  test "every conventional version-token form is flagged" do
    for name <- @carry_a_token do
      assert ArchitectureScan.version_token?(name), "expected #{name} to be flagged"
    end
  end

  test "protocol names and clean identifiers are not flagged" do
    for name <- @carry_no_token do
      refute ArchitectureScan.version_token?(name), "did not expect #{name} to be flagged"
    end
  end
end
