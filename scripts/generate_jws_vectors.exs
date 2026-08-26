# Generates verifier/testdata/jose-vectors.json — the stored
# Stored detached-JWS vectors the TS verifier's standard-JOSE cross-check consumes
# ("the TS side verifies the stored JWS vectors with
# node:crypto's JWS-conformant path").
#
# Anchors, both provider-documented (never self-signed-only):
#   - RFC 8032 §7.1 TEST 1: seed → public key → signature over the empty
#     message, cross-checked against the RFC's published literals;
#   - detached-JWS entries in the exact fixture shapes, signed here
#     with the TEST 1 key, each verified through Signature.verify before
#     the file is written (a non-verifying vector set refuses to land —
#     the same posture as the corpus generator).
#
# Run: mix run --no-start scripts/generate_jws_vectors.exs

alias AgentBlueprintProtocol.{Base64Url, Canonicalization, Digest, Signature}

rfc_seed =
  Base.decode16!("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60", case: :lower)

rfc_pub =
  Base.decode16!("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", case: :lower)

rfc_sig =
  Base.decode16!(
    "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
    case: :lower
  )

{:ok, derived_pub} = :crypto.generate_key(:eddsa, :ed25519, rfc_seed) |> then(&{:ok, elem(&1, 0)})
{_, priv} = :crypto.generate_key(:eddsa, :ed25519, rfc_seed)

# KAT 1: the seed derives the RFC's published public key.
unless derived_pub == rfc_pub do
  IO.puts("REFUSING: RFC 8032 TEST 1 seed did not derive the published public key")
  System.halt(1)
end

# KAT 2: this OTP's Ed25519 reproduces the RFC's published signature over
# the RFC's TEST 1 message (the empty string).
kat_sig = :crypto.sign(:eddsa, :none, <<>>, [priv, :ed25519])

unless kat_sig == rfc_sig do
  IO.puts("REFUSING: RFC 8032 TEST 1 signature not reproduced")
  System.halt(1)
end

# ---- detached-JWS entries in the stored fixture shapes ------------------------

header =
  {:object,
   [
     {"alg", {:string, "EdDSA"}},
     {"b64", {:boolean, false}},
     {"crit", {:array, [{:string, "b64"}]}},
     {"kid", {:string, "test-key"}}
   ]}

digests = [
  {"blueprint", Digest.to_tagged(Digest.hash(:blueprint_content, ~s({"a":1})))},
  {"deployment", Digest.to_tagged(Digest.hash(:deployment_content, ~s({"b":2})))}
]

signing_input = fn hdr, ats ->
  {:ok, h} = Canonicalization.encode(hdr)
  {:ok, a} = Canonicalization.encode(ats)
  Base64Url.encode(h) <> "." <> a
end

entries =
  for {purpose, tagged} <- digests do
    attrs =
      {:object,
       [
         {"algorithm", {:string, "Ed25519"}},
         {"content_digest", {:string, tagged}},
         {"created_at", {:string, "2026-08-20T00:00:00Z"}},
         {"key_id", {:string, "test-key"}},
         {"purpose", {:string, purpose}}
       ]}

    signature =
      :crypto.sign(:eddsa, :none, signing_input.(header, attrs), [priv, :ed25519])

    entry =
      {:object,
       [
         {"protected", header},
         {"signed_attributes", attrs},
         {"signature", {:string, Base64Url.encode(signature)}}
       ]}

    {:ok, compact} = Signature.to_compact(entry)
    %{entry: entry, compact: compact}
  end

# Every entry must verify through the package's own verify path before the
# vector set may land.
trusted = [%Signature.PublicKey{key_id: "test-key", algorithm: :ed25519, key: rfc_pub}]

unless Enum.all?(entries, fn %{entry: entry} ->
         Signature.verify(entry, trusted) == {:ok, :verified}
       end) do
  IO.puts("REFUSING: an entry did not verify")
  System.halt(1)
end

document =
  {:object,
   [
     {"entries",
      {:array,
       Enum.map(entries, fn %{entry: entry, compact: compact} ->
         {:object, [{"compact", {:string, compact}}, {"entry", entry}]}
       end)}},
     {"format", {:string, "agent-blueprint-protocol-jose-vectors"}},
     {"public_key", {:string, Base64Url.encode(rfc_pub)}},
     {"rfc8032_test1",
      {:object,
       [
         {"message_hex", {:string, ""}},
         {"public_key_hex", {:string, Base.encode16(rfc_pub, case: :lower)}},
         {"seed_hex", {:string, Base.encode16(rfc_seed, case: :lower)}},
         {"signature_hex", {:string, Base.encode16(rfc_sig, case: :lower)}}
       ]}}
   ]}

{:ok, json} = Canonicalization.encode(document)

path = Path.join(["conformance", "verifier", "testdata", "jose-vectors.json"])
File.mkdir_p!(Path.dirname(path))
File.write!(path, json)
IO.puts("wrote #{path} (#{byte_size(json)} bytes, #{length(entries)} entries, KAT-verified)")
