defmodule AgentBlueprintProtocol.Conformance.DigestTaggedTest do
  @moduledoc """
  Conformance corpus row `digest.tagged` (spec applicability floor):
  valid · invalid_encoding · digest_mismatch · tamper_meaningful_byte.
  The digest layer sees bytes + tags only — artifact and negotiation
  classes cannot reach it.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Canonicalization, Digest}

  @abc_body "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0"

  # Canonical JCS bytes as the covered content, the way the artifact layer
  # the artifact decode surface will feed this module: encode the tagged algebra, digest exactly
  # those bytes.
  defp covered do
    {:ok, bytes} =
      Canonicalization.encode(
        {:object, [{"release", {:integer, 1}}, {"name", {:string, "commerce/graph"}}]}
      )

    bytes
  end

  describe "class: valid" do
    test "canonical JCS bytes hash, tag, parse, and verify end to end" do
      bytes = covered()
      tagged = Digest.to_tagged(Digest.hash(:blueprint_content, bytes))

      assert {:ok, %Digest{algorithm: :sha256}} = Digest.from_tagged(tagged)
      assert Digest.verify_content(:blueprint_content, bytes, tagged) == :ok
    end

    test "the FIPS 180-4 known-answer vector carries through the wire form" do
      assert Digest.to_tagged(Digest.of("abc")) == "sha-256:" <> @abc_body
    end
  end

  describe "class: invalid_encoding" do
    test "unknown algorithm tags (inexact spellings included)" do
      assert Digest.from_tagged("SHA-256:" <> @abc_body) ==
               {:error, :digest_algorithm_unsupported}

      assert Digest.from_tagged("sha256:" <> @abc_body) == {:error, :digest_algorithm_unsupported}

      assert Digest.from_tagged("sha-512:" <> @abc_body) ==
               {:error, :digest_algorithm_unsupported}
    end

    test "malformed tagged strings" do
      assert Digest.from_tagged("not-a-tagged-digest") == {:error, :digest_encoding_invalid}
      assert Digest.from_tagged("sha-256:") == {:error, :digest_encoding_invalid}

      assert Digest.from_tagged("sha-256:" <> String.slice(@abc_body, 0, 42)) ==
               {:error, :digest_encoding_invalid}

      assert Digest.from_tagged("sha-256:" <> @abc_body <> "==") ==
               {:error, :digest_encoding_invalid}
    end
  end

  describe "class: digest_mismatch" do
    test "covered bytes mutated by one bit" do
      bytes = covered()
      tagged = Digest.to_tagged(Digest.hash(:blueprint_content, bytes))

      mutated = flip_bit(bytes, 0, 0)

      assert Digest.verify_content(:blueprint_content, mutated, tagged) ==
               {:error, :digest_mismatch}
    end

    test "a covered member's value changed (recomputed digest differs)" do
      {:ok, other} =
        Canonicalization.encode(
          {:object, [{"release", {:integer, 2}}, {"name", {:string, "commerce/graph"}}]}
        )

      tagged = Digest.to_tagged(Digest.hash(:blueprint_content, covered()))

      assert Digest.verify_content(:blueprint_content, other, tagged) ==
               {:error, :digest_mismatch}
    end

    test "cross-domain transplant of an honest digest" do
      bytes = covered()
      tagged = Digest.to_tagged(Digest.hash(:conformance_report, bytes))

      assert Digest.verify_content(:blueprint_content, bytes, tagged) ==
               {:error, :digest_mismatch}
    end
  end

  describe "class: tamper_meaningful_byte" do
    test "a mid-body character swapped for another alphabet character" do
      bytes = covered()
      tagged = Digest.to_tagged(Digest.hash(:blueprint_content, bytes))

      tampered = swap_mid_char(tagged)
      assert tampered != tagged

      assert Digest.verify_content(:blueprint_content, bytes, tampered) ==
               {:error, :digest_mismatch}
    end

    test "a body character swapped for a non-alphabet character" do
      tagged = "sha-256:" <> @abc_body
      tampered = swap_mid_char(tagged, ?.)
      assert Digest.from_tagged(tampered) == {:error, :digest_encoding_invalid}
    end
  end

  defp flip_bit(binary, index, bit) do
    <<head::binary-size(^index), byte, rest::binary>> = binary
    <<head::binary, Bitwise.bxor(byte, Bitwise.bsl(1, bit)), rest::binary>>
  end

  defp swap_mid_char(tagged, replacement \\ ?Z) do
    position = 10
    <<head::binary-size(^position), char, rest::binary>> = tagged
    replacement = if char == replacement, do: ?Y, else: replacement
    <<head::binary, replacement, rest::binary>>
  end
end
