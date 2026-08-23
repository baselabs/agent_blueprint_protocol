defmodule AgentBlueprintProtocol.Conformance.SignatureVerifyTest do
  @moduledoc """
  Conformance corpus row `signature.verify` (spec applicability floor):
  valid · signature_invalid · tamper_meaningful_byte · invalid_encoding
  (header/payload) · invalid_constraint (crit/b64 violations). The
  verification surface sees JWS inputs only — bounds/federation/artifact
  classes cannot reach it. Also pins the RFC 8032 §7.1 TEST 1 known-answer
  vector (read first-hand 2026-08-21) the Ed25519 substrate must reproduce.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Base64Url, Canonicalization, Digest, Signature}

  # RFC 8032 §7.1 TEST 1.
  @seed Base.decode16!("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
          case: :lower
        )
  @rfc_pub Base.decode16!("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
             case: :lower
           )
  @rfc_sig_b64 "5VZDAMNgrHKQhuLMgG6CioSHfx645dl02HPgZSJJAVVfuIIVkKM7rMYeOXAc-bRr0lv18FlbviRlUUFDjnoQCw"

  defp pub, do: elem(:crypto.generate_key(:eddsa, :ed25519, @seed), 0)
  defp priv, do: elem(:crypto.generate_key(:eddsa, :ed25519, @seed), 1)
  defp keys, do: [%Signature.PublicKey{key_id: "prod-key", algorithm: :ed25519, key: pub()}]

  defp header do
    {:object,
     [
       {"alg", {:string, "EdDSA"}},
       {"b64", {:boolean, false}},
       {"crit", {:array, [{:string, "b64"}]}},
       {"kid", {:string, "prod-key"}}
     ]}
  end

  defp attrs do
    {:object,
     [
       {"algorithm", {:string, "Ed25519"}},
       {"content_digest", {:string, content_digest()}},
       {"created_at", {:string, "2026-08-20T00:00:00Z"}},
       {"key_id", {:string, "prod-key"}},
       {"purpose", {:string, "blueprint"}}
     ]}
  end

  defp content_digest, do: Digest.to_tagged(Digest.of("conformance"))

  defp input_for(hdr, ats) do
    {:ok, h} = Canonicalization.encode(hdr)
    {:ok, a} = Canonicalization.encode(ats)
    Base64Url.encode(h) <> "." <> a
  end

  defp signed_entry do
    sig = :crypto.sign(:eddsa, :none, input_for(header(), attrs()), [priv(), :ed25519])

    {:object,
     [
       {"protected", header()},
       {"signed_attributes", attrs()},
       {"signature", {:string, Base64Url.encode(sig)}}
     ]}
  end

  describe "known-answer: RFC 8032 §7.1 TEST 1 (substrate pin)" do
    test "the derived public key and the empty-message signature reproduce byte-exact" do
      assert pub() == @rfc_pub
      sig = :crypto.sign(:eddsa, :none, <<>>, [priv(), :ed25519])
      assert Base64Url.encode(sig) == @rfc_sig_b64
      assert :crypto.verify(:eddsa, :none, <<>>, sig, [pub(), :ed25519])
      refute :crypto.verify(:eddsa, :none, <<1>>, sig, [pub(), :ed25519])
    end
  end

  describe "class: valid" do
    test "an honest envelope verifies under its key" do
      assert Signature.verify(signed_entry(), keys()) == {:ok, :verified}
    end

    test "the compact rendering verifies under standard JOSE reconstruction" do
      {:ok, compact} = Signature.to_compact(signed_entry())
      [segment, "", sig_b64] = String.split(compact, ".")
      {:ok, attrs_json} = Canonicalization.encode(attrs())

      {:ok, sig_bytes} = Base64Url.decode(sig_b64)

      assert :crypto.verify(
               :eddsa,
               :none,
               segment <> "." <> attrs_json,
               sig_bytes,
               [pub(), :ed25519]
             )
    end
  end

  describe "class: signature_invalid" do
    test "a signature made over different bytes fails" do
      entry =
        {:object,
         [
           {"protected", header()},
           {"signed_attributes", attrs()},
           {"signature", {:string, @rfc_sig_b64}}
         ]}

      # The TEST 1 signature is over the empty message, not our input.
      assert Signature.verify(entry, keys()) == {:error, :signature_not_verified}
    end

    test "unknown key_id is a key fact, never verified" do
      stranger = [%Signature.PublicKey{key_id: "nobody", algorithm: :ed25519, key: pub()}]
      assert Signature.verify(signed_entry(), stranger) == {:error, :signature_key_unsupported}
    end
  end

  describe "class: tamper_meaningful_byte" do
    test "flipping a meaningful character of the signature body fails verification" do
      {:object, members} = signed_entry()
      {"signature", {:string, sig}} = List.keyfind(members, "signature", 0)
      position = 40
      original = :binary.at(sig, position)
      replacement = if original == ?A, do: ?B, else: ?A
      size = byte_size(sig)

      tampered =
        binary_part(sig, 0, position) <>
          <<replacement>> <> binary_part(sig, position + 1, size - position - 1)

      entry =
        {:object,
         [
           {"protected", header()},
           {"signed_attributes", attrs()},
           {"signature", {:string, tampered}}
         ]}

      assert Signature.verify(entry, keys()) == {:error, :signature_not_verified}
    end
  end

  describe "class: invalid_encoding (header/payload)" do
    test "non-string members where strings are required" do
      bad_header = put(header(), "kid", {:integer, 3})
      assert Signature.verify(with_header(bad_header), keys()) == {:error, :signature_malformed}

      bad_attrs = put(attrs(), "key_id", {:array, []})
      assert Signature.verify(with_attrs(bad_attrs), keys()) == {:error, :signature_malformed}
    end

    test "a non-b64url signature body" do
      entry =
        {:object,
         [
           {"protected", header()},
           {"signed_attributes", attrs()},
           {"signature", {:string, "not base64url !!"}}
         ]}

      assert Signature.verify(entry, keys()) == {:error, :signature_malformed}
    end
  end

  describe "class: invalid_constraint (crit/b64 violations)" do
    test "b64 true" do
      assert Signature.verify(with_header(put(header(), "b64", {:boolean, true})), keys()) ==
               {:error, :signature_malformed}
    end

    test "crit missing or extra" do
      drop = {:object, List.keydelete(elem(header(), 1), "crit", 0)}
      assert Signature.verify(with_header(drop), keys()) == {:error, :signature_malformed}

      extra = put(header(), "crit", {:array, [{:string, "b64"}, {:string, "exp"}]})
      assert Signature.verify(with_header(extra), keys()) == {:error, :signature_malformed}
    end

    test "kid does not match the signed key_id" do
      assert Signature.verify(with_header(put(header(), "kid", {:string, "other"})), keys()) ==
               {:error, :signature_malformed}
    end
  end

  # ---- helpers -------------------------------------------------------------------

  defp put({:object, members}, name, value),
    do: {:object, Enum.map(members, fn {k, v} -> if k == name, do: {k, value}, else: {k, v} end)}

  defp with_header(hdr) do
    {:object,
     [
       {"protected", hdr},
       {"signed_attributes", attrs()},
       {"signature",
        {:string,
         Base64Url.encode(
           :crypto.sign(:eddsa, :none, input_for(hdr, attrs()), [priv(), :ed25519])
         )}}
     ]}
  end

  defp with_attrs(ats) do
    {:object,
     [
       {"protected", header()},
       {"signed_attributes", ats},
       {"signature",
        {:string,
         Base64Url.encode(
           :crypto.sign(:eddsa, :none, input_for(header(), ats), [priv(), :ed25519])
         )}}
     ]}
  end
end
