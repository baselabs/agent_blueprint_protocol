defmodule AgentBlueprintProtocol.SignatureTest do
  @moduledoc """
  Unit contract for the detached JWS envelope: RFC 7797 `b64=false` signing
  input over JCS bytes, the exact-shape protected header, the closed-world
  signed attributes (dot-free payload invariant included), and the
  verify-only fact vocabulary.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Base64Url, Canonicalization, Digest, Signature}

  # RFC 8032 §7.1 TEST 1 (read first-hand 2026-08-21).
  @seed Base.decode16!("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
          case: :lower
        )

  defp keys, do: [%Signature.PublicKey{key_id: "test-key", algorithm: :ed25519, key: pub()}]

  defp pub, do: elem(:crypto.generate_key(:eddsa, :ed25519, @seed), 0)
  defp priv, do: elem(:crypto.generate_key(:eddsa, :ed25519, @seed), 1)

  defp header(kid \\ "test-key") do
    {:object,
     [
       {"alg", {:string, "EdDSA"}},
       {"b64", {:boolean, false}},
       {"crit", {:array, [{:string, "b64"}]}},
       {"kid", {:string, kid}}
     ]}
  end

  defp attrs(opts \\ []) do
    {:object,
     [
       {"algorithm", {:string, "Ed25519"}},
       {"content_digest", {:string, Keyword.get(opts, :digest, honest_digest())}},
       {"created_at", {:string, "2026-08-20T00:00:00Z"}},
       {"key_id", {:string, Keyword.get(opts, :key_id, "test-key")}},
       {"purpose", {:string, Keyword.get(opts, :purpose, "blueprint")}}
     ]}
  end

  defp honest_digest,
    do: Digest.to_tagged(Digest.hash(:blueprint_content, ~s({"a":1})))

  # Independent construction of the RFC 7797 signing input (the KAT oracle:
  # built here from Canonicalization + Base64Url, not by the module).
  defp input_for(hdr, ats) do
    {:ok, h} = Canonicalization.encode(hdr)
    {:ok, a} = Canonicalization.encode(ats)
    Base64Url.encode(h) <> "." <> a
  end

  defp signed_entry(hdr \\ header(), ats \\ attrs(), signer \\ priv()) do
    sig = :crypto.sign(:eddsa, :none, input_for(hdr, ats), [signer, :ed25519])

    {:object,
     [
       {"protected", hdr},
       {"signed_attributes", ats},
       {"signature", {:string, Base64Url.encode(sig)}}
     ]}
  end

  describe "signing_input/1 (RFC 7797 b64=false over JCS bytes)" do
    test "matches the independently constructed input" do
      assert Signature.signing_input(signed_entry()) == {:ok, input_for(header(), attrs())}
    end

    test "the header segment is the JCS serialization of the four-member header" do
      {:ok, input} = Signature.signing_input(signed_entry())
      [segment, _payload] = String.split(input, ".", parts: 2)
      assert {:ok, hdr_json} = Canonicalization.encode(header())
      assert segment == Base64Url.encode(hdr_json)
    end
  end

  describe "header shape (exact, closed world)" do
    test "alg other than EdDSA denies :signature_algorithm_unsupported" do
      bad = put_member(header(), "alg", {:string, "HS256"})

      assert Signature.verify(signed_entry(bad), keys()) ==
               {:error, :signature_algorithm_unsupported}
    end

    test "alg missing or non-string denies :signature_malformed" do
      no_alg = drop_member(header(), "alg")

      assert Signature.signing_input(signed_entry(no_alg, attrs())) ==
               {:error, :signature_malformed}

      int_alg = put_member(header(), "alg", {:integer, 7})

      assert Signature.signing_input(signed_entry(int_alg, attrs())) ==
               {:error, :signature_malformed}
    end

    test "b64 not exactly false denies :signature_malformed" do
      bad = put_member(header(), "b64", {:boolean, true})
      assert Signature.signing_input(signed_entry(bad, attrs())) == {:error, :signature_malformed}
    end

    test "crit not exactly [\"b64\"] denies :signature_malformed" do
      extra = put_member(header(), "crit", {:array, [{:string, "b64"}, {:string, "foo"}]})

      assert Signature.signing_input(signed_entry(extra, attrs())) ==
               {:error, :signature_malformed}

      wrong_name = put_member(header(), "crit", {:array, [{:string, "exp"}]})

      assert Signature.signing_input(signed_entry(wrong_name, attrs())) ==
               {:error, :signature_malformed}

      none = drop_member(header(), "crit")

      assert Signature.signing_input(signed_entry(none, attrs())) ==
               {:error, :signature_malformed}
    end

    test "unknown header members deny :signature_malformed" do
      typ = add_member(header(), "typ", {:string, "JOSE"})
      assert Signature.signing_input(signed_entry(typ, attrs())) == {:error, :signature_malformed}
    end
  end

  describe "signed_attributes shape (exact, closed world)" do
    test "algorithm other than Ed25519 denies :signature_algorithm_unsupported" do
      bad = put_member(attrs(), "algorithm", {:string, "ES256"})

      assert Signature.signing_input(signed_entry(header(), bad)) ==
               {:error, :signature_algorithm_unsupported}
    end

    test "an unparsable content_digest denies :signature_malformed" do
      bad = put_member(attrs(), "content_digest", {:string, "sha256:not-a-digest"})

      assert Signature.signing_input(signed_entry(header(), bad)) ==
               {:error, :signature_malformed}
    end

    test "created_at must be Z-form, whole seconds, calendar-valid" do
      for bad <- ["2026-08-20T00:00:00.5Z", "2026-08-20T00:00:00+00:00", "2026-13-01T00:00:00Z"] do
        ats = put_member(attrs(), "created_at", {:string, bad})

        assert Signature.signing_input(signed_entry(header(), ats)) ==
                 {:error, :signature_malformed}
      end
    end

    test "key_id is nonempty and dot-free (RFC 7797 compact payload rule)" do
      for bad <- ["", "acme.prod.2026"] do
        ats = put_member(attrs(), "key_id", {:string, bad})
        hdr = header(bad)
        assert Signature.signing_input(signed_entry(hdr, ats)) == {:error, :signature_malformed}
      end
    end

    test "a key_id that is not valid UTF-8 denies through the encode guard" do
      # Nothing can sign unencodable bytes, so the entry carries a
      # syntactically valid placeholder signature; the denial fires at
      # canonical serialization, before any crypto.
      entry =
        {:object,
         [
           {"protected", header(<<0xFF>>)},
           {"signed_attributes", put_member(attrs(), "key_id", {:string, <<0xFF>>})},
           {"signature", {:string, String.duplicate("A", 86)}}
         ]}

      assert Signature.signing_input(entry) == {:error, :signature_malformed}
    end

    test "purpose outside the closed set denies :signature_malformed" do
      bad = put_member(attrs(), "purpose", {:string, "attestation"})

      assert Signature.signing_input(signed_entry(header(), bad)) ==
               {:error, :signature_malformed}
    end

    test "unknown or missing members deny :signature_malformed" do
      extra = add_member(attrs(), "nonce", {:string, "x"})

      assert Signature.signing_input(signed_entry(header(), extra)) ==
               {:error, :signature_malformed}

      missing = drop_member(attrs(), "purpose")

      assert Signature.signing_input(signed_entry(header(), missing)) ==
               {:error, :signature_malformed}
    end

    test "non-object and non-string members deny :signature_malformed" do
      placeholder = {:string, String.duplicate("A", 86)}

      assert Signature.signing_input({:string, "not-an-entry"}) == {:error, :signature_malformed}

      bad_protected =
        {:object,
         [
           {"protected", {:string, "not-an-object"}},
           {"signed_attributes", attrs()},
           {"signature", placeholder}
         ]}

      assert Signature.signing_input(bad_protected) == {:error, :signature_malformed}

      bad_attrs =
        {:object,
         [
           {"protected", header()},
           {"signed_attributes", {:array, []}},
           {"signature", placeholder}
         ]}

      assert Signature.signing_input(bad_attrs) == {:error, :signature_malformed}

      bad_signature =
        {:object,
         [
           {"protected", header()},
           {"signed_attributes", attrs()},
           {"signature", {:integer, 86}}
         ]}

      assert Signature.signing_input(bad_signature) == {:error, :signature_malformed}
    end

    test "non-string scalar members deny :signature_malformed" do
      for member <- ["algorithm", "content_digest", "created_at", "purpose"] do
        bad = put_member(attrs(), member, {:integer, 1})

        assert Signature.signing_input(signed_entry(header(), bad)) ==
                 {:error, :signature_malformed}
      end
    end
  end

  describe "kid / key_id anti-substitution" do
    test "a header kid that differs from the signed key_id denies :signature_malformed" do
      hdr = header("other-key")
      assert Signature.signing_input(signed_entry(hdr, attrs())) == {:error, :signature_malformed}
    end
  end

  describe "signature body" do
    test "non-alphabet, padded, and wrong-length bodies deny :signature_malformed" do
      for body <- ["!!not-b64!!", String.duplicate("A", 85), String.duplicate("A", 87), "A="] do
        entry =
          {:object,
           [
             {"protected", header()},
             {"signed_attributes", attrs()},
             {"signature", {:string, body}}
           ]}

        assert Signature.signing_input(entry) == {:error, :signature_malformed}
      end
    end
  end

  describe "verify/2 facts" do
    test "a small-order public key never verifies anything (universal forgery tripwire)" do
      # Confirmed live: :crypto.verify accepts
      # the all-zero (small-order) public key with an all-zero signature —
      # a universal forgery if such a key ever enters a trust set. The
      # zero key must be unusable Ed25519, and the forged envelope (all-zero
      # signature over OUR signing input) must never be :verified.
      zero_key = [%Signature.PublicKey{key_id: "test-key", algorithm: :ed25519, key: <<0::256>>}]

      forged =
        {:object,
         [
           {"protected", header()},
           {"signed_attributes", attrs()},
           {"signature", {:string, Base64Url.encode(<<0::512>>)}}
         ]}

      assert Signature.verify(forged, zero_key) == {:error, :signature_algorithm_unsupported}
    end

    test "degenerate and off-curve key encodings are unusable Ed25519" do
      # x = 0 with the sign bit set (non-canonical encoding, RFC 8032 5.1.2):
      y_one_sign =
        Base.decode16!("0100000000000000000000000000000000000000000000000000000000000080",
          case: :lower
        )

      # The identity point (x = 0, y = 1, sign clear) and the order-2 point
      # (x = 0, y = p-1, sign clear): canonical RFC 8032 encodings of
      # small-order points — root == 0 in usable_ed25519_key?. Found by the
      # the second-language mirror's torsion battery: the `not sign_x`
      # branch admitted BOTH (the sign-set half was the non-canonical
      # reject, the sign-clear half is the order-1/order-2 forgery class).
      y_one_clear =
        Base.decode16!("0100000000000000000000000000000000000000000000000000000000000000",
          case: :lower
        )

      y_p_minus_one =
        Base.decode16!("ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
          case: :lower
        )

      # y >= p (all-ones low 255 bits):
      y_ge_p =
        Base.decode16!("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          case: :lower
        )

      # Valid canonical y whose recovered x^2 is a non-square (TEST 1 key,
      # byte 1 XORed 0x55 — derived deterministically):
      off_curve =
        Base.decode16!("d7f0980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
          case: :lower
        )

      for bad_key <- [y_one_sign, y_one_clear, y_p_minus_one, y_ge_p, off_curve] do
        keys = [%Signature.PublicKey{key_id: "test-key", algorithm: :ed25519, key: bad_key}]

        assert Signature.verify(signed_entry(), keys) ==
                 {:error, :signature_algorithm_unsupported}
      end
    end

    test "an honest envelope verified under the supplied key" do
      assert Signature.verify(signed_entry(), keys()) == {:ok, :verified}
    end

    test "an unknown key_id reports the key fact, never verified" do
      stranger = [%Signature.PublicKey{key_id: "other", algorithm: :ed25519, key: pub()}]
      assert Signature.verify(signed_entry(), stranger) == {:error, :signature_key_unsupported}
    end

    test "a matched key that is not usable Ed25519 denies :signature_algorithm_unsupported" do
      wrong_alg = [%Signature.PublicKey{key_id: "test-key", algorithm: :ed448, key: pub()}]

      assert Signature.verify(signed_entry(), wrong_alg) ==
               {:error, :signature_algorithm_unsupported}
    end

    test "duplicate key_id: any candidate verifying is the fact" do
      {other_pub, other_priv} = :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<7>>, 32))

      rotated =
        keys() ++ [%Signature.PublicKey{key_id: "test-key", algorithm: :ed25519, key: other_pub}]

      assert Signature.verify(signed_entry(header(), attrs(), other_priv), rotated) ==
               {:ok, :verified}

      {third_pub, _third_priv} = :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<9>>, 32))
      none = [%Signature.PublicKey{key_id: "test-key", algorithm: :ed25519, key: third_pub}]

      # Signed by the TEST 1 key; only the unrelated third key is supplied.
      assert Signature.verify(signed_entry(), none) == {:error, :signature_not_verified}
    end

    test "purpose swapped after signing fails verification" do
      swapped =
        signed_entry(header(), attrs(purpose: "deployment"))
        |> put_nested("signed_attributes", "purpose", {:string, "blueprint"})

      assert Signature.verify(swapped, keys()) == {:error, :signature_not_verified}
    end

    test "content_digest re-bound to another body after signing fails verification" do
      rebound =
        signed_entry(
          header(),
          attrs(digest: Digest.to_tagged(Digest.hash(:blueprint_content, "{}")))
        )
        |> put_nested("signed_attributes", "content_digest", {:string, honest_digest()})

      assert Signature.verify(rebound, keys()) == {:error, :signature_not_verified}
    end
  end

  describe "attributes/1" do
    test "parses the signed attributes into the typed struct" do
      assert {:ok, %Signature.Attributes{} = parsed} = Signature.attributes(signed_entry())
      assert parsed.algorithm == "Ed25519"
      assert parsed.purpose == :blueprint
      assert parsed.key_id == "test-key"
      assert parsed.created_at == "2026-08-20T00:00:00Z"

      assert Digest.from_tagged(Digest.to_tagged(parsed.content_digest)) ==
               {:ok, parsed.content_digest}
    end
  end

  describe "to_compact/1 (RFC 7515 detached compact)" do
    test "renders three segments with an empty payload segment" do
      {:ok, compact} = Signature.to_compact(signed_entry())
      assert [segment, "", sig] = String.split(compact, ".")
      {:ok, hdr_json} = Canonicalization.encode(header())
      assert segment == Base64Url.encode(hdr_json)
      assert byte_size(sig) == 86
    end

    test "a standard reconstruction of the detached form verifies" do
      # The RFC 7515 App F recipient move: re-insert the payload and verify
      # with a stock crypto call over the compact's own bytes.
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

  describe "verify_attestation/2 (empty kind registry, fail-closed)" do
    test "any kind denies :attestation_malformed until kinds are registered" do
      ats =
        {:object,
         [
           {"algorithm", {:string, "Ed25519"}},
           {"statement_digest", {:string, honest_digest()}},
           {"created_at", {:string, "2026-08-20T00:00:00Z"}},
           {"key_id", {:string, "test-key"}},
           {"kind", {:string, "tool_binding"}}
         ]}

      entry = signed_entry(header(), ats)
      assert Signature.verify_attestation(entry, keys()) == {:error, :attestation_malformed}
    end

    test "attestation shape errors use the attestation vocabulary" do
      bad = add_member(header(), "typ", {:string, "JOSE"})
      entry = signed_entry(bad, attrs())
      assert Signature.verify_attestation(entry, keys()) == {:error, :attestation_malformed}
    end

    test "attestation algorithm denials share the signature vocabulary (pinned)" do
      bad_alg = put_member(header(), "alg", {:string, "HS256"})
      entry = signed_entry(bad_alg, attrs())

      assert Signature.verify_attestation(entry, keys()) ==
               {:error, :signature_algorithm_unsupported}
    end
  end

  # ---- tagged-algebra helpers ---------------------------------------------------

  defp put_member({:object, members}, name, value),
    do: {:object, Enum.map(members, fn {k, v} -> if k == name, do: {k, value}, else: {k, v} end)}

  defp add_member({:object, members}, name, value), do: {:object, members ++ [{name, value}]}

  defp drop_member({:object, members}, name), do: {:object, List.keydelete(members, name, 0)}

  defp put_nested(entry, object_name, member, value) do
    put_member(entry, object_name, put_member(member_of(entry, object_name), member, value))
  end

  defp member_of({:object, members}, name), do: List.keyfind(members, name, 0) |> elem(1)
end
