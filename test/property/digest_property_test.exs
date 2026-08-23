defmodule AgentBlueprintProtocol.DigestPropertyTest do
  @moduledoc """
  Properties of the tagged digest: wire-form round-trip and shape,
  determinism, single-bit sensitivity of the covered bytes, domain
  separation, and equivalence of constant-time `equal?/2` with structural
  equality.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentBlueprintProtocol.{Base64Url, Digest}

  property "to_tagged and from_tagged round-trip on every binary" do
    check all(data <- StreamData.binary()) do
      digest = Digest.of(data)

      assert Digest.from_tagged(Digest.to_tagged(digest)) == {:ok, digest}
    end
  end

  property "the tagged wire form is exactly sha-256: + 43 alphabet characters" do
    check all(data <- StreamData.binary()) do
      tagged = Digest.to_tagged(Digest.of(data))
      {tag, body} = String.split_at(tagged, 8)

      assert tag == "sha-256:"
      assert byte_size(body) == 43
      assert {:ok, <<_::256>>} = Base64Url.decode(body)
    end
  end

  property "hashing is deterministic" do
    check all(
            domain <- StreamData.member_of(domains()),
            data <- StreamData.binary()
          ) do
      assert Digest.hash(domain, data) == Digest.hash(domain, data)
    end
  end

  property "any single-bit flip of the covered bytes changes the digest" do
    check all(
            data <- StreamData.binary(min_length: 1, max_length: 64),
            bit <- StreamData.integer(0..511)
          ) do
      bit = rem(bit, bit_size(data))
      byte_index = div(bit, 8)
      bit_offset = rem(bit, 8)

      <<head::binary-size(^byte_index), byte, rest::binary>> = data
      flipped = <<head::binary, Bitwise.bxor(byte, Bitwise.bsl(1, bit_offset)), rest::binary>>

      assert Digest.hash(:blueprint_content, flipped) !=
               Digest.hash(:blueprint_content, data)
    end
  end

  property "distinct domains never produce the same digest for the same bytes" do
    check all(data <- StreamData.binary()) do
      assert Digest.hash(:blueprint_content, data) != Digest.hash(:deployment_content, data)
      assert Digest.hash(:signature, data) != Digest.hash(:conformance_report, data)
    end
  end

  property "equal?/2 agrees with structural equality in both directions" do
    check all(
            a <- StreamData.binary(),
            b <- StreamData.binary()
          ) do
      digest_a = Digest.of(a)
      digest_b = Digest.of(b)

      assert Digest.equal?(digest_a, digest_b) == (digest_a == digest_b)
      assert Digest.equal?(digest_b, digest_a) == Digest.equal?(digest_a, digest_b)
    end
  end

  property "from_tagged never raises on arbitrary strings and reports closed reasons" do
    check all(input <- StreamData.string(:ascii), max_runs: 1000) do
      case Digest.from_tagged(input) do
        {:ok, %Digest{algorithm: :sha256, bytes: <<_::256>>}} ->
          assert String.starts_with?(input, "sha-256:")

        {:error, reason}
        when reason in [:digest_algorithm_unsupported, :digest_encoding_invalid] ->
          :ok
      end
    end
  end

  property "from_tagged never raises on arbitrary raw binaries either" do
    check all(input <- StreamData.binary(), max_runs: 1000) do
      case Digest.from_tagged(input) do
        {:ok, %Digest{algorithm: :sha256, bytes: <<_::256>>}} ->
          :ok

        {:error, reason} ->
          assert reason in [:digest_algorithm_unsupported, :digest_encoding_invalid]
      end
    end
  end

  defp domains do
    [
      :blueprint_content,
      :deployment_content,
      :federation_envelope,
      :signature,
      :conformance_report,
      :corpus_index
    ]
  end
end
