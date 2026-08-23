defmodule AgentBlueprintProtocol.Architecture.NonAuthorizingVocabularyTest do
  @moduledoc """
  Non-authorizing vocabulary gate: the shipped API carries no
  authorization-decision vocabulary in any executable identifier — no
  `authorize`/`authorization`/`authorized`, no `:unauthorized` in either
  polarity. The protocol returns facts, never permission.

  Only executable identifiers are scanned (module segments, function/macro names,
  atom literals). Documentation prose is excluded: the moduledoc legitimately
  describes the protocol as *non-authorizing*, and that must not trip the gate.
  """
  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.ArchitectureScan

  test "no shipped identifier carries authorization-decision vocabulary" do
    offenders =
      for path <- ArchitectureScan.source_files(),
          {kind, name} <- ArchitectureScan.identifiers(path),
          ArchitectureScan.authorization_token?(name),
          do: {path, kind, name}

    assert offenders == [],
           "authorization vocabulary found in identifiers (the API returns facts, never permission):\n" <>
             Enum.map_join(offenders, "\n", fn {p, k, n} -> "  #{p}: #{k} #{n}" end)
  end
end
