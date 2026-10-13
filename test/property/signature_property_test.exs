defmodule AgentBlueprintProtocol.SignaturePropertyTest do
  @moduledoc """
  Properties of the detached JWS envelope: generated keypairs sign (in the
  test, never in the package) and verify, any meaningful tamper denies,
  signing input construction is deterministic, and the compact rendering is
  always three segments with an empty payload.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentBlueprintProtocol.{Base64Url, Canonicalization, Digest, Signature}
  alias AgentBlueprintProtocol.Ed25519StrictFixture, as: StrictFixture

  property "for generated keys and attributes, the envelope verifies" do
    check all(
            seed <- StreamData.binary(length: 32),
            key_id <- dot_free_id(),
            purpose <- StreamData.member_of(["blueprint", "deployment", "federation-envelope"]),
            digest_input <- StreamData.binary(min_length: 0, max_length: 64)
          ) do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519, seed)
      entry = signed_entry(priv, key_id, purpose, digest_input)

      assert Signature.verify(entry, [
               %Signature.PublicKey{key_id: key_id, algorithm: :ed25519, key: pub}
             ]) == {:ok, :verified}
    end
  end

  property "any single-bit flip of the signature bytes denies" do
    check all(
            seed <- StreamData.binary(length: 32),
            bit <- StreamData.integer(0..511)
          ) do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519, seed)
      entry = signed_entry(priv, "prop-key", "blueprint", "x")
      flipped = flip_first_member_byte(entry, bit)

      assert Signature.verify(flipped, [
               %Signature.PublicKey{key_id: "prop-key", algorithm: :ed25519, key: pub}
             ]) == {:error, :signature_not_verified}
    end
  end

  property "for generated keys and messages, the verdict matches the backend's" do
    check all(
            seed <- StreamData.binary(length: 32),
            digest_input <- StreamData.binary(max_length: 64),
            replacement <-
              StreamData.one_of([StreamData.constant(:honest), StreamData.binary(length: 64)])
          ) do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519, seed)
      honest = signed_entry(priv, "prop-key", "blueprint", digest_input)
      {:ok, input} = Signature.signing_input(honest)

      sig =
        if replacement == :honest,
          do: :crypto.sign(:eddsa, :none, input, [priv, :ed25519]),
          else: replacement

      backend = :crypto.verify(:eddsa, :none, input, sig, [pub, :ed25519])
      verdict = Signature.verify(with_signature(honest, sig), prop_keys(pub))

      assert verdict == if(backend, do: {:ok, :verified}, else: {:error, :signature_not_verified})
      if replacement == :honest, do: assert(verdict == {:ok, :verified})
    end
  end

  property "a small-order or non-canonical R is always rejected, whatever S" do
    check all(
            seed <- StreamData.binary(length: 32),
            digest_input <- StreamData.binary(max_length: 64),
            r <- weak_r(),
            s_kind <-
              StreamData.frequency([
                {3, StreamData.constant(:key_holder)},
                {1, StreamData.constant(:honest)},
                {1, StreamData.constant(:random)}
              ])
          ) do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519, seed)
      honest = signed_entry(priv, "prop-key", "blueprint", digest_input)
      {:ok, input} = Signature.signing_input(honest)

      sig =
        case s_kind do
          :key_holder ->
            StrictFixture.key_holder_signature(seed, r, input)

          :honest ->
            <<_r::binary-size(32), s::binary-size(32)>> =
              :crypto.sign(:eddsa, :none, input, [priv, :ed25519])

            r <> s

          :random ->
            <<s::little-unsigned-256>> = :crypto.hash(:sha256, seed <> digest_input)
            r <> <<rem(s, StrictFixture.l())::little-unsigned-256>>
        end

      assert Signature.verify(with_signature(honest, sig), prop_keys(pub)) ==
               {:error, :signature_not_verified}
    end
  end

  property "S >= L is always rejected, even with the honest R" do
    check all(
            seed <- StreamData.binary(length: 32),
            offset <- StreamData.binary(length: 32)
          ) do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519, seed)
      honest = signed_entry(priv, "prop-key", "blueprint", "s")
      {:ok, input} = Signature.signing_input(honest)

      <<r::binary-size(32), _s::binary-size(32)>> =
        :crypto.sign(:eddsa, :none, input, [priv, :ed25519])

      l = StrictFixture.l()
      <<o::little-unsigned-256>> = offset
      s = l + rem(o, Bitwise.bsl(1, 256) - l)

      assert Signature.verify(
               with_signature(honest, r <> <<s::little-unsigned-256>>),
               prop_keys(pub)
             ) ==
               {:error, :signature_not_verified}
    end
  end

  property "signing input is deterministic and byte-stable" do
    check all(
            seed <- StreamData.binary(length: 32),
            digest_input <- StreamData.binary(max_length: 32)
          ) do
      {_pub, priv} = :crypto.generate_key(:eddsa, :ed25519, seed)
      entry = signed_entry(priv, "prop-key", "deployment", digest_input)

      assert Signature.signing_input(entry) == Signature.signing_input(entry)

      assert :crypto.sign(:eddsa, :none, elem(Signature.signing_input(entry), 1), [priv, :ed25519]) ==
               :crypto.sign(:eddsa, :none, elem(Signature.signing_input(entry), 1), [
                 priv,
                 :ed25519
               ])
    end
  end

  property "the compact rendering is always three segments with an empty payload" do
    check all(seed <- StreamData.binary(length: 32)) do
      {_pub, priv} = :crypto.generate_key(:eddsa, :ed25519, seed)
      {:ok, compact} = Signature.to_compact(signed_entry(priv, "prop-key", "blueprint", "y"))

      assert [segment, "", sig] = String.split(compact, ".")
      assert segment != "" and byte_size(sig) == 86
    end
  end

  # ---- fixtures ---------------------------------------------------------------

  defp header(key_id) do
    {:object,
     [
       {"alg", {:string, "EdDSA"}},
       {"b64", {:boolean, false}},
       {"crit", {:array, [{:string, "b64"}]}},
       {"kid", {:string, key_id}}
     ]}
  end

  defp attrs(key_id, purpose, digest_input) do
    {:object,
     [
       {"algorithm", {:string, "Ed25519"}},
       {"content_digest", {:string, Digest.to_tagged(Digest.of(digest_input))}},
       {"created_at", {:string, "2026-08-20T00:00:00Z"}},
       {"key_id", {:string, key_id}},
       {"purpose", {:string, purpose}}
     ]}
  end

  defp signed_entry(priv, key_id, purpose, digest_input) do
    hdr = header(key_id)
    ats = attrs(key_id, purpose, digest_input)
    {:ok, h} = Canonicalization.encode(hdr)
    {:ok, a} = Canonicalization.encode(ats)
    sig = :crypto.sign(:eddsa, :none, Base64Url.encode(h) <> "." <> a, [priv, :ed25519])

    {:object,
     [
       {"protected", hdr},
       {"signed_attributes", ats},
       {"signature", {:string, Base64Url.encode(sig)}}
     ]}
  end

  defp prop_keys(pub),
    do: [%Signature.PublicKey{key_id: "prop-key", algorithm: :ed25519, key: pub}]

  defp with_signature({:object, members}, sig) do
    {:object,
     Enum.map(members, fn
       {"signature", _} -> {"signature", {:string, Base64Url.encode(sig)}}
       other -> other
     end)}
  end

  # The eight small-order encodings, the listed non-canonical encodings,
  # and every y >= p (p..2^255-1, 19 values) under either sign bit. The
  # identity is weighted up: with the key-holder S it is the one weak R
  # the backend alone accepts, so the property must draw it often.
  defp weak_r do
    StreamData.frequency([
      {2, StreamData.constant(StrictFixture.identity())},
      {3, StreamData.member_of(StrictFixture.small_order_encodings())},
      {2, StreamData.member_of(StrictFixture.non_canonical_encodings())},
      {2,
       StreamData.bind(StreamData.tuple({StreamData.integer(0..18), StreamData.boolean()}), fn
         {offset, sign} ->
           y = StrictFixture.p() + offset
           y = if sign, do: Bitwise.bor(y, Bitwise.bsl(1, 255)), else: y
           StreamData.constant(<<y::little-unsigned-256>>)
       end)}
    ])
  end

  defp flip_first_member_byte({:object, members}, bit) do
    byte_index = div(bit, 8)
    bit_offset = rem(bit, 8)

    members =
      Enum.map(members, fn
        {"signature", {:string, b64}} ->
          {:ok, <<bytes::binary-size(64)>>} = Base64Url.decode(b64)
          <<head::binary-size(^byte_index), byte, rest::binary>> = bytes
          flipped = <<head::binary, Bitwise.bxor(byte, Bitwise.bsl(1, bit_offset)), rest::binary>>
          {"signature", {:string, Base64Url.encode(flipped)}}

        other ->
          other
      end)

    {:object, members}
  end

  defp dot_free_id do
    StreamData.map(
      StreamData.list_of(StreamData.member_of(?a..?z), min_length: 4, max_length: 12),
      fn chars ->
        Enum.map_join(chars, &<<&1>>)
      end
    )
  end
end
