defmodule AgentBlueprintProtocol.Architecture.IdentifierNamingTest do
  @moduledoc """
  Identifier-naming gate: no version token appears in any shipped identifier —
  module segment, function/macro name, atom, or path segment. The Hex semver in
  `mix.exs` (`@version`, dependency requirements) is a string literal, not an
  identifier, and is the sole permitted place for a version number; this gate
  only scans the `lib/` and `priv/` shipped surface.
  """
  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.ArchitectureScan

  test "no shipped module/function/atom carries a version token" do
    offenders =
      for path <- ArchitectureScan.source_files(),
          {kind, name} <- ArchitectureScan.identifiers(path),
          {:error, :implementation_version_identifier} <- [
            ArchitectureScan.check_durable_identifier(%{path: path, kind: kind, name: name})
          ],
          do: {path, kind, name}

    assert offenders == [],
           "version tokens found in identifiers (forbidden in shipped names):\n" <>
             Enum.map_join(offenders, "\n", fn {p, k, n} -> "  #{p}: #{k} #{n}" end)
  end

  test "no shipped path segment carries a version token" do
    offenders =
      for seg <- ArchitectureScan.path_segments(),
          {:error, :implementation_version_identifier} <- [
            ArchitectureScan.check_durable_identifier(%{path: seg, kind: :path, name: seg})
          ],
          do: seg

    assert offenders == [],
           "version tokens found in shipped paths (forbidden in shipped names): #{inspect(offenders)}"
  end

  test "the package source identity is observed from the real package metadata" do
    assert ArchitectureScan.package_source_ref_observations() == [
             %{
               path: "mix.exs",
               kind: :package_source_ref,
               name: ~S(source_ref: "v#{@version}")
             }
           ]

    assert Enum.all?(
             ArchitectureScan.package_source_ref_observations(),
             &(ArchitectureScan.check_durable_identifier(&1) == :ok)
           )
  end
end
