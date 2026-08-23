defmodule AgentBlueprintProtocol.DigestTest do
  @moduledoc """
  Unit contract for the tagged content digest: FIPS 180-4 known-answer
  vectors (from the NIST example document this package's conformance row
  cites), the base-§8.2 domain-separated preimage formula re-derived
  independently, the tagged wire form, and constant-time equality.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Base64Url, Canonicalization, Digest}

  # NIST SHA-256 example values (csrc.nist.gov example-values, "SHA-256"
  # sample document), read first-hand 2026-08-21.
  @abc_hex "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  @abc_body "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0"
  @two_block_hex "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"

  describe "of/1 (raw SHA-256, FIPS 180-4 known-answer tests)" do
    test "one-block message sample" do
      assert Digest.of("abc").bytes == Base.decode16!(@abc_hex, case: :lower)
    end

    test "two-block message sample" do
      message = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
      assert Digest.of(message).bytes == Base.decode16!(@two_block_hex, case: :lower)
    end

    test "returns a sha-256-tagged 256-bit struct" do
      digest = Digest.of("abc")
      assert digest.algorithm == :sha256
      assert byte_size(digest.bytes) == 32
    end
  end

  describe "hash/2 (domain-separated preimage, base §8.2)" do
    test "the preimage formula is separator || <<0>> || bytes, re-derived here" do
      jcs = "{}"

      expected =
        :crypto.hash(
          :sha256,
          "agent-blueprint-protocol/blueprint-content" <> <<0>> <> jcs
        )

      assert Digest.hash(:blueprint_content, jcs).bytes == expected
    end

    test "every registered domain hashes under its own separator" do
      pairs = [
        blueprint_content: "agent-blueprint-protocol/blueprint-content",
        deployment_content: "agent-blueprint-protocol/deployment-content",
        federation_envelope: "agent-blueprint-protocol/federation-envelope",
        signature: "agent-blueprint-protocol/signature",
        conformance_report: "agent-blueprint-protocol/conformance-report",
        corpus_index: "agent-blueprint-protocol/corpus-index"
      ]

      for {domain, separator} <- pairs do
        assert Digest.hash(domain, "x").bytes ==
                 :crypto.hash(:sha256, separator <> <<0>> <> "x")
      end
    end
  end

  describe "to_tagged/1 (wire form: sha-256:<43-char unpadded b64url>)" do
    test "the NIST abc vector renders as the tagged literal" do
      assert Digest.to_tagged(Digest.of("abc")) == "sha-256:" <> @abc_body
    end

    test "the body is exactly 43 unpadded alphabet characters" do
      tagged = Digest.to_tagged(Digest.of("abc"))
      {tag, body} = String.split_at(tagged, 8)
      assert tag == "sha-256:"
      assert byte_size(body) == 43
      assert {:ok, _} = Base64Url.decode(body)
    end

    test "a hand-built struct with wrong-size bytes fails loud, never emits garbage" do
      assert_raise FunctionClauseError, fn ->
        Digest.to_tagged(%Digest{algorithm: :sha256, bytes: <<0>>})
      end
    end
  end

  describe "from_tagged/1" do
    test "round-trips a tagged digest" do
      digest = Digest.hash(:blueprint_content, ~s({"a":1}))
      assert Digest.from_tagged(Digest.to_tagged(digest)) == {:ok, digest}
    end

    test "unknown or inexact algorithm tags deny :digest_algorithm_unsupported" do
      assert Digest.from_tagged("SHA-256:" <> @abc_body) ==
               {:error, :digest_algorithm_unsupported}

      assert Digest.from_tagged("sha256:" <> @abc_body) == {:error, :digest_algorithm_unsupported}

      assert Digest.from_tagged("sha-512:" <> @abc_body) ==
               {:error, :digest_algorithm_unsupported}

      assert Digest.from_tagged(":" <> @abc_body) == {:error, :digest_algorithm_unsupported}
    end

    test "a string with no colon is not a tagged digest" do
      assert Digest.from_tagged(@abc_body) == {:error, :digest_encoding_invalid}
      assert Digest.from_tagged("sha-256") == {:error, :digest_encoding_invalid}
    end

    test "an empty body denies :digest_encoding_invalid" do
      assert Digest.from_tagged("sha-256:") == {:error, :digest_encoding_invalid}
    end

    test "wrong-length but codec-valid bodies deny :digest_encoding_invalid" do
      assert Digest.from_tagged("sha-256:" <> String.slice(@abc_body, 0, 42)) ==
               {:error, :digest_encoding_invalid}

      assert Digest.from_tagged("sha-256:" <> @abc_body <> "A") ==
               {:error, :digest_encoding_invalid}
    end

    test "a padded body collapses to :digest_encoding_invalid at the digest layer" do
      assert Digest.from_tagged("sha-256:" <> @abc_body <> "==") ==
               {:error, :digest_encoding_invalid}
    end

    test "extra colons are a body defect" do
      assert Digest.from_tagged("sha-256:AAA:BBB") == {:error, :digest_encoding_invalid}
    end
  end

  describe "equal?/2" do
    test "identical digests are equal, different digests are not" do
      a = Digest.of("abc")
      b = Digest.of("abc")
      c = Digest.of("abd")

      assert Digest.equal?(a, b)
      assert Digest.equal?(b, a)
      refute Digest.equal?(a, c)
      refute Digest.equal?(c, a)
    end

    test "agrees with structural equality" do
      assert Digest.equal?(Digest.of("x"), Digest.of("x")) ==
               (Digest.of("x") == Digest.of("x"))
    end
  end

  describe "verify_content/3" do
    test "honest bytes verify" do
      jcs = ~s({"covered":true})
      tagged = Digest.to_tagged(Digest.hash(:blueprint_content, jcs))
      assert Digest.verify_content(:blueprint_content, jcs, tagged) == :ok
    end

    test "a single-bit mutation of the covered bytes is a digest mismatch" do
      jcs = ~s({"covered":true})
      tagged = Digest.to_tagged(Digest.hash(:blueprint_content, jcs))

      for bit <- 0..7 do
        mutated = flip_bit(jcs, 0, bit)

        assert Digest.verify_content(:blueprint_content, mutated, tagged) ==
                 {:error, :digest_mismatch}
      end
    end

    test "a digest from another domain does not verify under this one" do
      jcs = ~s({"covered":true})
      tagged = Digest.to_tagged(Digest.hash(:deployment_content, jcs))
      assert Digest.verify_content(:blueprint_content, jcs, tagged) == {:error, :digest_mismatch}
    end

    test "parse errors surface before any comparison" do
      assert Digest.verify_content(:blueprint_content, "{}", "sha-512:" <> @abc_body) ==
               {:error, :digest_algorithm_unsupported}

      assert Digest.verify_content(:blueprint_content, "{}", "sha-256:") ==
               {:error, :digest_encoding_invalid}
    end

    test "covered bytes are opaque — the canonicality contract is the caller's" do
      # Pinned deliberately (derisk 2026-08-21): a non-canonical spelling of
      # the same value is denied by Canonicalization.verify/2, yet a digest
      # computed over exactly those bytes verifies against them. Digest hashes
      # what it is given, by contract; canonicality is enforced where received
      # bytes enter the package (the artifact decode path).
      # Anyone changing this opacity must change this test consciously.
      non_canonical = ~s({"b":2,"a":1})

      assert {:ok, _} = Canonicalization.verify(~s({"a":1,"b":2}))
      assert {:error, :non_canonical_bytes} = Canonicalization.verify(non_canonical)

      tagged = Digest.to_tagged(Digest.hash(:blueprint_content, non_canonical))
      assert Digest.verify_content(:blueprint_content, non_canonical, tagged) == :ok
    end
  end

  defp flip_bit(binary, byte_index, bit) do
    <<head::binary-size(^byte_index), byte, rest::binary>> = binary
    <<head::binary, Bitwise.bxor(byte, Bitwise.bsl(1, bit)), rest::binary>>
  end
end
