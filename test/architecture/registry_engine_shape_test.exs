defmodule AgentBlueprintProtocol.Architecture.RegistryEngineShapeTest do
  @moduledoc """
  Dependency-direction gate for the generic registry engine (the engine-reuse spec): the
  engine knows TABLES, not DOMAINS. `registry.ex` may reference only the
  bytes-layer value algebra (`Json`, for the spec types) and the collection
  machinery — any reference to an artifact-layer or domain module (Blueprint,
  Portability, Predicate, Signature, Schema, Digest, Canonicalization) reds,
  because it would couple the Deployment table to Blueprint knowledge
  and break the "no second pipeline" acceptance invariant.

  Enforced at the BEAM level via `ArchitectureScan.beam_remote_calls/1`:
  aliases are expanded at compile time, so a renamed alias cannot hide the
  reference. The banned set is exact; the allowed set is two-directional.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.ArchitectureScan

  @beam "_build/test/lib/agent_blueprint_protocol/ebin/Elixir.AgentBlueprintProtocol.Registry.beam"

  # The artifact/domain layers the engine must never reach. The wire value
  # algebra (Json) is the one shared substrate both layers speak.
  @banned_modules [
    AgentBlueprintProtocol,
    AgentBlueprintProtocol.Blueprint,
    AgentBlueprintProtocol.Canonicalization,
    AgentBlueprintProtocol.Digest,
    AgentBlueprintProtocol.Portability,
    AgentBlueprintProtocol.Predicate,
    AgentBlueprintProtocol.Schema,
    AgentBlueprintProtocol.Signature
  ]

  @allowed_modules [
    Access,
    ArgumentError,
    Enum,
    Kernel,
    List,
    Map,
    MapSet,
    :elixir_erl_pass,
    :erlang,
    :maps
  ]

  test "registry.ex's beam never references a domain module" do
    census = ArchitectureScan.beam_remote_calls(@beam)

    used_modules = census |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    assert Enum.empty?(used_modules -- @allowed_modules),
           "registry.ex reached non-allowlisted modules: #{inspect(used_modules -- @allowed_modules)}"

    assert Enum.empty?(Enum.filter(used_modules, &(&1 in @banned_modules))),
           "the engine referenced a domain module — the table owns domain knowledge, never the engine"
  end
end
