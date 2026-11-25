defmodule AgentBlueprintProtocol.Architecture.DecisionRecordsTest do
  use ExUnit.Case, async: true

  @record_slugs ~w(
    compiled-registry
    deny-default-clamps
    detached-jws-envelope
    federation-lanes
    no-versioning-rule
    non-authorizing-boundary
    two-consumer-amendment
    producer-surface
    product-extension-registration
    supported-otp-set
    release-identity-semantics
    conformance-product
    stability-policy
    three-platform-support
    typescript-library-surface
    verification-results
    artifact-portability
    normative-extraction
    runtime-boundary
    kit-cli
    federation-mapping-identity
    procedure-identity
  )

  test "tracked decision records have contiguous numbers, matching headings, and one status" do
    {listing, 0} = System.cmd("git", ["ls-files", "-z", "--", "docs/adr"])
    paths = listing |> String.split(<<0>>, trim: true) |> Enum.sort()

    expected =
      for {slug, number} <- Enum.with_index(@record_slugs, 1) do
        prefix = number |> Integer.to_string() |> String.pad_leading(4, "0")
        Path.join("docs/adr", "#{prefix}-#{slug}.md")
      end

    assert paths == expected

    for {path, number} <- Enum.with_index(paths, 1) do
      prefix = number |> Integer.to_string() |> String.pad_leading(4, "0")
      assert String.starts_with?(Path.basename(path), prefix <> "-"), path
      source = File.read!(path)
      assert Regex.match?(~r/\A# #{prefix}: [^\n]+\n\nStatus: [^\n]+\n/, source), path
      assert length(Regex.scan(~r/^Status:/m, source)) == 1, path
    end
  end

  test "public files use contributor and adopter language" do
    {listing, 0} = System.cmd("git", ["ls-files", "-z"])

    offenders =
      for path <- String.split(listing, <<0>>, trim: true),
          path != "AGENTS.md",
          not String.starts_with?(path, [".github/", "test/"]),
          File.regular?(path),
          source = File.read!(path),
          Regex.match?(~r/owner's Mac|build box|Sessions keep|Send infra/i, source),
          do: path

    assert offenders == [],
           "public files contain workshop language: #{Enum.join(offenders, ", ")}"
  end
end
