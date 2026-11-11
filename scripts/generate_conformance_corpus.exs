# Generates the shipped conformance corpus (priv/conformance/**).
#
#   MIX_ENV=test mix run --no-start scripts/generate_conformance_corpus.exs
#
# Authoring tooling. Verdicts and expected CODES are hand-authored literals
# carried from the adversarially-pinned ExUnit lanes and their probes;
# only binary projections (digests, canonical bytes, signatures over authored
# inputs) are derived — deterministic math over authored inputs. The script
# REFUSES to write anything unless the assembled corpus loads and every case
# agrees in-process; the loader/runner/CLI are the verification surface.
#
# Fixtures (test/support, generation-time only): the full-registry goldens
# derive from BlueprintFixture/DeploymentFixture; committed corpus files
# stand alone once written.

Code.require_file("test/support/blueprint_fixture.exs", __DIR__ |> Path.join(".."))
Code.require_file("test/support/deployment_fixture.exs", __DIR__ |> Path.join(".."))
Code.require_file("test/support/federation_fixture.exs", __DIR__ |> Path.join(".."))
Code.require_file("test/support/ed25519_strict_fixture.exs", __DIR__ |> Path.join(".."))

alias AgentBlueprintProtocol.{
  Blueprint,
  BlueprintFixture,
  Canonicalization,
  DeploymentFixture,
  Digest,
  ExtensionRegistry,
  Federation,
  FederationFixture,
  Json,
  Signature
}

defmodule CorpusGen do
  @moduledoc false

  def b64(bytes), do: Base.url_encode64(bytes, padding: false)
  def sha(bytes), do: Base.url_encode64(:crypto.hash(:sha256, bytes), padding: false)

  def keypair(seed), do: :crypto.generate_key(:eddsa, :ed25519, :crypto.hash(:sha256, seed))

  def tagged_digest(domain, material),
    do: Digest.to_tagged(Digest.hash(domain, material))

  def to_tagged({:object, _} = tagged), do: tagged
  def to_tagged({:array, _} = tagged), do: tagged
  def to_tagged({:string, _} = tagged), do: tagged
  def to_tagged({:integer, _} = tagged), do: tagged
  def to_tagged({:float, _} = tagged), do: tagged
  def to_tagged({:boolean, _} = tagged), do: tagged
  def to_tagged(:null = tagged), do: tagged

  def to_tagged(value) do
    cond do
      is_map(value) ->
        {:object,
         value |> Enum.map(fn {k, v} -> {k, to_tagged(v)} end) |> Enum.sort_by(&elem(&1, 0))}

      is_list(value) ->
        {:array, Enum.map(value, &to_tagged/1)}

      is_integer(value) ->
        {:integer, value}

      is_boolean(value) ->
        {:boolean, value}

      is_binary(value) ->
        {:string, value}

      is_float(value) ->
        {:float, value}

      true ->
        :null
    end
  end

  def json_text!(value) do
    {:ok, text} = Canonicalization.encode(to_tagged(value))
    text
  end

  # --- signed constructs -----------------------------------------------------

  def signature_entry(seed, kid, digest_tagged, alg \\ "EdDSA", purpose \\ "deployment") do
    {pub, priv} = keypair(seed)

    header =
      {:object,
       [
         {"alg", {:string, alg}},
         {"b64", {:boolean, false}},
         {"crit", {:array, [{:string, "b64"}]}},
         {"kid", {:string, kid}}
       ]}

    attrs =
      {:object,
       [
         {"algorithm", {:string, "Ed25519"}},
         {"content_digest", {:string, digest_tagged}},
         {"created_at", {:string, "2026-08-23T00:00:00Z"}},
         {"key_id", {:string, kid}},
         {"purpose", {:string, purpose}}
       ]}

    {:ok, h} = Canonicalization.encode(header)
    {:ok, a} = Canonicalization.encode(attrs)
    si = AgentBlueprintProtocol.Base64Url.encode(h) <> "." <> a
    sig = :crypto.sign(:eddsa, :none, si, [priv, :ed25519])

    entry =
      {:object,
       [
         {"protected", header},
         {"signed_attributes", attrs},
         {"signature", {:string, AgentBlueprintProtocol.Base64Url.encode(sig)}}
       ]}

    {json_text!(entry), pub}
  end

  # An honestly signed federation terminal receipt over the covered body.
  def signed_receipt(seed, kid, alg \\ "EdDSA", purpose \\ "federation-envelope") do
    {pub, priv} = keypair(seed)
    shell = FederationFixture.value(terminal: true)

    {:ok, commitment} = Federation.terminal_commitment(%Federation{value: shell})

    with_commitment =
      put_path(
        shell,
        ["evidence_receipt", "terminal_commitment"],
        {:string, Digest.to_tagged(commitment)}
      )

    covered = drop_signature(with_commitment)
    {:ok, cj} = Canonicalization.encode(covered)
    digest = Digest.hash(:federation_envelope, cj)

    attrs =
      {:object,
       [
         {"algorithm", {:string, "Ed25519"}},
         {"content_digest", {:string, Digest.to_tagged(digest)}},
         {"created_at", {:string, "2026-08-23T00:00:00Z"}},
         {"key_id", {:string, kid}},
         {"purpose", {:string, purpose}}
       ]}

    header =
      {:object,
       [
         {"alg", {:string, alg}},
         {"b64", {:boolean, false}},
         {"crit", {:array, [{:string, "b64"}]}},
         {"kid", {:string, kid}}
       ]}

    {:ok, h} = Canonicalization.encode(header)
    {:ok, a} = Canonicalization.encode(attrs)
    si = AgentBlueprintProtocol.Base64Url.encode(h) <> "." <> a
    sig = :crypto.sign(:eddsa, :none, si, [priv, :ed25519])

    entry =
      {:object,
       [
         {"protected", header},
         {"signed_attributes", attrs},
         {"signature", {:string, AgentBlueprintProtocol.Base64Url.encode(sig)}}
       ]}

    signed = put_path(with_commitment, ["evidence_receipt", "signature"], entry)
    {json_text!(signed), pub, Digest.to_tagged(commitment)}
  end

  # An entry whose signature segment is not base64url (encoding failure).
  def bad_signature_entry(digest_tagged, bad_sig) do
    entry(
      {:object,
       [
         {"alg", {:string, "EdDSA"}},
         {"b64", {:boolean, false}},
         {"crit", {:array, [{:string, "b64"}]}},
         {"kid", {:string, "corpus-key"}}
       ]},
      digest_tagged,
      bad_sig
    )
  end

  # An entry whose protected header omits crit (the RFC 7797 constraint).
  def critless_entry(digest_tagged) do
    entry(
      {:object,
       [
         {"alg", {:string, "EdDSA"}},
         {"b64", {:boolean, false}},
         {"kid", {:string, "corpus-key"}}
       ]},
      digest_tagged,
      "AAA"
    )
  end

  defp entry(header, digest_tagged, sig) do
    {:object,
     [
       {"protected", header},
       {"signed_attributes",
        {:object,
         [
           {"algorithm", {:string, "Ed25519"}},
           {"content_digest", {:string, digest_tagged}},
           {"created_at", {:string, "2026-08-23T00:00:00Z"}},
           {"key_id", {:string, "corpus-key"}},
           {"purpose", {:string, "deployment"}}
         ]}},
       {"signature", {:string, sig}}
     ]}
    |> json_text!()
  end

  def put_path({:object, members}, [key | rest], value) do
    {:object,
     Enum.map(members, fn
       {^key, old} -> {key, put_path(old, rest, value)}
       other -> other
     end)}
  end

  def put_path(_old, [], value), do: value

  # The federation portability denial vehicle, verbatim from the pinned
  # federation_test construction: a secret-shaped kid AND key_id on the
  # receipt entry of the (unsigned) fixture envelope.
  def secret_kid_envelope do
    secret = String.duplicate("ab", 24)

    FederationFixture.value(terminal: true)
    |> put_path(["evidence_receipt", "signature", "protected", "kid"], {:string, secret})
    |> put_path(
      ["evidence_receipt", "signature", "signed_attributes", "key_id"],
      {:string, secret}
    )
    |> json_text!()
  end

  def drop_signature({:object, members}) do
    {:object,
     Enum.map(members, fn
       {"evidence_receipt", {:object, receipt}} ->
         {"evidence_receipt", {:object, Enum.reject(receipt, fn {n, _} -> n == "signature" end)}}

       other ->
         other
     end)}
  end

  # The SIGNED receipt machinery with a secret-shaped kid — the federation
  # portability denial vehicle (federation_test's construction, welded to the
  # honest-signing path so the envelope decodes).
  def secret_kid_envelope(seed, real_kid) do
    secret = String.duplicate("ab", 24)
    {_pub, priv} = keypair(seed)
    shell = FederationFixture.value(terminal: true)

    {:ok, commitment} = Federation.terminal_commitment(%Federation{value: shell})

    with_commitment =
      put_path(
        shell,
        ["evidence_receipt", "terminal_commitment"],
        {:string, Digest.to_tagged(commitment)}
      )

    covered = drop_signature(with_commitment)
    {:ok, cj} = Canonicalization.encode(covered)
    digest = Digest.hash(:federation_envelope, cj)

    attrs =
      {:object,
       [
         {"algorithm", {:string, "Ed25519"}},
         {"content_digest", {:string, Digest.to_tagged(digest)}},
         {"created_at", {:string, "2026-08-23T00:00:00Z"}},
         {"key_id", {:string, real_kid}},
         {"purpose", {:string, "federation-envelope"}}
       ]}

    header =
      {:object,
       [
         {"alg", {:string, "EdDSA"}},
         {"b64", {:boolean, false}},
         {"crit", {:array, [{:string, "b64"}]}},
         {"kid", {:string, secret}}
       ]}

    {:ok, h} = Canonicalization.encode(header)
    {:ok, a} = Canonicalization.encode(attrs)
    si = AgentBlueprintProtocol.Base64Url.encode(h) <> "." <> a
    sig = :crypto.sign(:eddsa, :none, si, [priv, :ed25519])

    entry =
      {:object,
       [
         {"protected", header},
         {"signed_attributes", attrs},
         {"signature", {:string, AgentBlueprintProtocol.Base64Url.encode(sig)}}
       ]}

    with_commitment
    |> put_path(["evidence_receipt", "signature"], entry)
    |> json_text!()
  end

  # Insert an unknown member at the CANONICAL (sorted) position so the bytes
  # stay canonical and the denial comes from the closed-world walk.
  def with_sorted_extra(value, name, v) do
    {:object, members} = value
    pair = {name, to_tagged(v)}
    {:object, Enum.sort_by([pair | members], &elem(&1, 0))}
  end

  def plain({:object, members}),
    do: members |> Enum.map(fn {k, v} -> {k, plain(v)} end) |> Map.new()

  def plain({:array, items}), do: Enum.map(items, &plain/1)
  def plain({:string, s}), do: s
  def plain({:integer, n}), do: n
  def plain({:float, n}), do: n
  def plain({:boolean, b}), do: b
  def plain(:null), do: nil

  def plain_value(value), do: plain(value)

  # A top-level string member's value from a tagged object.
  def member_string({:object, members}, name) do
    case List.keyfind(members, name, 0) do
      {^name, {:string, v}} -> v
      _ -> nil
    end
  end

  # Track-A goldens exercise EVERY registry member, evidence members
  # included: the with-signatures + empty-attestations form.
  def add_empty_attestations({:object, members}) do
    if Enum.any?(members, fn {n, _} -> n == "attestations" end) do
      {:object, members}
    else
      {:object, (members ++ [{"attestations", {:array, []}}]) |> Enum.sort_by(&elem(&1, 0))}
    end
  end
end

# --- the case table: every required cell of the 16x29 floor -------------------

sig_digest = CorpusGen.tagged_digest(:deployment_content, "corpus-signature")

{sig_entry_text, sig_pub} =
  CorpusGen.signature_entry("corpus-signature-valid", "corpus-key", sig_digest)

{wrong_entry_text, _} =
  CorpusGen.signature_entry(
    "corpus-signature-wrong",
    "corpus-key",
    CorpusGen.tagged_digest(:deployment_content, "other")
  )

{receipt_text, receipt_pub, commitment_tagged} =
  CorpusGen.signed_receipt("corpus-receipt", "remote-key")

{other_receipt_text, other_receipt_pub, _} =
  CorpusGen.signed_receipt("corpus-receipt-other", "remote-key")

golden_blueprint = BlueprintFixture.fixture_bytes([])
bi = fn hay, needle -> :binary.match(hay, needle) |> then(&elem(&1, 0)) end
golden_deployment = DeploymentFixture.fixture_bytes([])
golden_federation = FederationFixture.bytes(terminal: true)

# ---- json.decode (7) ----
json_cases = [
  %{
    "id" => "json-decode-valid",
    "surface" => "json.decode",
    "class" => "valid",
    "input" => %{"text" => ~s({"a":1,"b":[2,3.5,"x",true,false,null]})},
    "expected" => %{
      "verdict" => "valid",
      "value" => %{"a" => 1, "b" => [2, 3.5, "x", true, false, nil]}
    }
  },
  %{
    "id" => "json-decode-boundary-near",
    "surface" => "json.decode",
    "class" => "boundary_near",
    "input" => %{"text" => "[[[1]]]", "bounds" => %{"depth" => 4}},
    "expected" => %{"verdict" => "valid", "value" => [[[1]]]}
  },
  %{
    "id" => "json-decode-exact-bound",
    "surface" => "json.decode",
    "class" => "exact_bound",
    "input" => %{"text" => "[[[[1]]]]", "bounds" => %{"depth" => 4}},
    "expected" => %{"verdict" => "valid", "value" => [[[[1]]]]}
  },
  %{
    "id" => "json-decode-maximum-plus-one",
    "surface" => "json.decode",
    "class" => "maximum_plus_one",
    "input" => %{"text" => "[[[[[1]]]]]", "bounds" => %{"depth" => 4}},
    "expected" => %{"verdict" => "invalid", "code" => "ceiling:depth"}
  },
  %{
    "id" => "json-decode-invalid-encoding",
    "surface" => "json.decode",
    "class" => "invalid_encoding",
    "input" => %{"base64url" => CorpusGen.b64(<<?", 0xFF, ?">>)},
    "expected" => %{"verdict" => "invalid", "code" => "invalid_encoding"}
  },
  %{
    "id" => "json-decode-invalid-duplicate",
    "surface" => "json.decode",
    "class" => "invalid_duplicate",
    "input" => %{"text" => ~s({"a":1,"a":2})},
    "expected" => %{"verdict" => "invalid", "code" => "duplicate_member"}
  },
  %{
    "id" => "json-decode-invalid-type",
    "surface" => "json.decode",
    "class" => "invalid_type",
    "input" => %{"non_binary" => true},
    "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
  }
]

# ---- canonicalization.encode (6) ----
sort_doc = "{\"Ｚ\":1,\"\u{10000}\":2}"
sort_flip_index = :binary.match(sort_doc, "1") |> then(&elem(&1, 0))
sort_canonical = CorpusGen.json_text!(%{"Ｚ" => 1, "\u{10000}" => 2})

canonicalization_cases = [
  %{
    "id" => "canonicalization-encode-valid",
    "surface" => "canonicalization.encode",
    "class" => "valid",
    "input" => %{"text" => ~s([295147905179352830000,1e-7,5e-324,0])},
    "expected" => %{
      "verdict" => "valid",
      "encoded" => CorpusGen.json_text!([2.951_479_051_793_528_3e20, 1.0e-7, 5.0e-324, 0])
    }
  },
  %{
    "id" => "canonicalization-encode-boundary-near",
    "surface" => "canonicalization.encode",
    "class" => "boundary_near",
    "input" => %{"text" => sort_doc},
    "expected" => %{"verdict" => "valid", "encoded" => sort_canonical}
  },
  %{
    "id" => "canonicalization-encode-exact-bound",
    "surface" => "canonicalization.encode",
    "class" => "exact_bound",
    "input" => %{
      "text" => ~s({"a":1}),
      "bounds" => %{"bytes" => byte_size(CorpusGen.json_text!(%{"a" => 1}))}
    },
    "expected" => %{"verdict" => "valid", "encoded" => CorpusGen.json_text!(%{"a" => 1})}
  },
  %{
    "id" => "canonicalization-encode-maximum-plus-one",
    "surface" => "canonicalization.encode",
    "class" => "maximum_plus_one",
    "input" => %{
      "text" => ~s({"a":1}),
      "bounds" => %{"bytes" => byte_size(CorpusGen.json_text!(%{"a" => 1})) - 1}
    },
    "expected" => %{"verdict" => "invalid", "code" => "ceiling:bytes"}
  },
  %{
    "id" => "canonicalization-encode-invalid-encoding",
    "surface" => "canonicalization.encode",
    "class" => "invalid_encoding",
    "input" => %{"base64url" => CorpusGen.b64(<<?", 0xED, 0xA0, 0x80, ?">>)},
    "expected" => %{"verdict" => "invalid", "code" => "invalid_encoding"}
  },
  %{
    "id" => "canonicalization-encode-tamper-sort-order",
    "surface" => "canonicalization.encode",
    "class" => "tamper_meaningful_byte",
    "input" => %{"text" => String.replace(sort_doc, "1", "3")},
    "expected" => %{"verdict" => "valid", "encoded" => String.replace(sort_canonical, "1", "3")},
    "tamper" => %{
      "base_case" => "canonicalization-encode-boundary-near",
      "byte_index" => sort_flip_index,
      "xor" => 2
    }
  }
]

# ---- base64url.decode (3) ----
base64url_cases = [
  %{
    "id" => "base64url-decode-valid",
    "surface" => "base64url.decode",
    "class" => "valid",
    "input" => %{"base64url" => "-_8"},
    "expected" => %{"verdict" => "valid", "decoded" => CorpusGen.b64(<<0xFB, 0xFF>>)}
  },
  %{
    "id" => "base64url-decode-invalid-padded",
    "surface" => "base64url.decode",
    "class" => "invalid_encoding",
    "input" => %{"base64url" => "QQ=="},
    "expected" => %{"verdict" => "invalid", "code" => "base64url_padded"}
  },
  %{
    "id" => "base64url-decode-exact-bound",
    "surface" => "base64url.decode",
    "class" => "exact_bound",
    "input" => %{"base64url" => "QQQ"},
    "expected" => %{"verdict" => "valid", "decoded" => CorpusGen.b64(<<65, 4>>)}
  }
]

# ---- digest.tagged (4) ----
digest_cases = [
  %{
    "id" => "digest-tagged-valid",
    "surface" => "digest.tagged",
    "class" => "valid",
    "input" => %{"tagged" => CorpusGen.tagged_digest(:blueprint_content, "corpus")},
    "expected" => %{
      "verdict" => "valid",
      "tagged" => CorpusGen.tagged_digest(:blueprint_content, "corpus")
    }
  },
  %{
    "id" => "digest-tagged-invalid-encoding",
    "surface" => "digest.tagged",
    "class" => "invalid_encoding",
    "input" => %{"tagged" => "not-a-tagged-digest"},
    "expected" => %{"verdict" => "invalid", "code" => "digest_encoding_invalid"}
  },
  %{
    "id" => "digest-tagged-mismatch",
    "surface" => "digest.tagged",
    "class" => "digest_mismatch",
    "input" => %{
      "text" => "corpus",
      "domain" => "blueprint_content",
      "declared" => CorpusGen.tagged_digest(:deployment_content, "corpus")
    },
    "expected" => %{"verdict" => "invalid", "code" => "digest_mismatch"}
  },
  %{
    "id" => "digest-tagged-tamper-nibble",
    "surface" => "digest.tagged",
    "class" => "tamper_meaningful_byte",
    "input" => %{
      "text" => "corpur",
      "domain" => "blueprint_content",
      "declared" => CorpusGen.tagged_digest(:blueprint_content, "corpus")
    },
    "expected" => %{"verdict" => "invalid", "code" => "digest_mismatch"},
    "tamper" => %{
      "base_case" => "digest-tagged-mismatch",
      "byte_index" => 5,
      "xor" => 1,
      "target" => "input.text"
    }
  }
]

# ---- signature.verify (5) ----
sig_keys = [%{"key_id" => "corpus-key", "key" => CorpusGen.b64(sig_pub)}]

# Flip the entry's LAST byte to "A" — inside the b64 signature segment, a
# meaningful byte; the tamper block re-derives exactly this flip.
# The entry's canonical member order puts "signature" LAST; the marker's
# first match is the real one. Flip its first b64 char to "A".
sig_marker = ~s/"signature":"/
sig_flip_index = bi.(sig_entry_text, sig_marker) + byte_size(sig_marker)
sig_char = :binary.at(sig_entry_text, sig_flip_index)
sig_flip_xor = Bitwise.bxor(sig_char, ?A)

sig_tampered_text =
  binary_part(sig_entry_text, 0, sig_flip_index) <>
    "A" <>
    binary_part(
      sig_entry_text,
      sig_flip_index + 1,
      byte_size(sig_entry_text) - sig_flip_index - 1
    )

signature_cases = [
  %{
    "id" => "signature-verify-valid",
    "surface" => "signature.verify",
    "class" => "valid",
    "input" => %{"entry" => sig_entry_text, "keys" => sig_keys},
    "expected" => %{"verdict" => "valid", "verified" => true}
  },
  %{
    "id" => "signature-verify-invalid",
    "surface" => "signature.verify",
    "class" => "signature_invalid",
    "input" => %{"entry" => wrong_entry_text, "keys" => sig_keys},
    "expected" => %{"verdict" => "invalid", "code" => "signature_not_verified"}
  },
  %{
    "id" => "signature-verify-tamper-byte",
    "surface" => "signature.verify",
    "class" => "tamper_meaningful_byte",
    "input" => %{"entry" => sig_tampered_text, "keys" => sig_keys},
    "expected" => %{"verdict" => "invalid", "code" => "signature_not_verified"},
    "tamper" => %{
      "base_case" => "signature-verify-valid",
      "byte_index" => sig_flip_index,
      "xor" => sig_flip_xor,
      "target" => "input.entry"
    }
  },
  %{
    "id" => "signature-verify-invalid-encoding",
    "surface" => "signature.verify",
    "class" => "invalid_encoding",
    "input" => %{"entry" => CorpusGen.bad_signature_entry(sig_digest, "!!!"), "keys" => sig_keys},
    "expected" => %{"verdict" => "invalid", "code" => "signature_malformed"}
  },
  %{
    "id" => "signature-verify-invalid-constraint",
    "surface" => "signature.verify",
    "class" => "invalid_constraint",
    "input" => %{"entry" => CorpusGen.critless_entry(sig_digest), "keys" => sig_keys},
    "expected" => %{"verdict" => "invalid", "code" => "signature_malformed"}
  }
]

# ---- signature.verify: the strict Ed25519 rule (R canonical and not
# small-order, S < L) and a second honest key ----
#
# Every weak signature below rides the exact envelope of
# signature-verify-valid (same key, same signed attributes); only the
# 64 signature bytes change. The key holder of the corpus key builds
# R = P and S = k*a mod L (k = SHA-512(R || A || M) mod L); with R = the
# identity the cofactorless equation holds, so a backend that checks only
# the equation accepts it — asserted below, so the case can never go
# vacuous. The second-key valid case pins agreement on an honest key the
# point rule must accept (its key is one a mistyped curve constant
# misclassifies).
alias AgentBlueprintProtocol.Ed25519StrictFixture, as: StrictFixture

{:ok, sig_entry_value} = Json.decode(sig_entry_text)
{:ok, sig_signing_input} = Signature.signing_input(sig_entry_value)
sig_holder_seed = :crypto.hash(:sha256, "corpus-signature-valid")

{^sig_pub, _} = :crypto.generate_key(:eddsa, :ed25519, sig_holder_seed)

identity_forged =
  StrictFixture.key_holder_signature(sig_holder_seed, StrictFixture.identity(), sig_signing_input)

true = :crypto.verify(:eddsa, :none, sig_signing_input, identity_forged, [sig_pub, :ed25519])

weak_entry = fn signature ->
  CorpusGen.bad_signature_entry(sig_digest, AgentBlueprintProtocol.Base64Url.encode(signature))
end

weak_case = fn id, signature ->
  %{
    "id" => id,
    "surface" => "signature.verify",
    "class" => "signature_invalid",
    "input" => %{"entry" => weak_entry.(signature), "keys" => sig_keys},
    "expected" => %{"verdict" => "invalid", "code" => "signature_not_verified"}
  }
end

small_order_names = [
  "identity",
  "order-2",
  "order-4-sign-clear",
  "order-4-sign-set",
  "order-8-a",
  "order-8-b",
  "order-8-c",
  "order-8-d"
]

small_order_cases =
  Enum.zip_with(small_order_names, StrictFixture.small_order_encodings(), fn name, r ->
    true = StrictFixture.small_order?(r)

    weak_case.(
      "signature-verify-small-order-r-#{name}",
      StrictFixture.key_holder_signature(sig_holder_seed, r, sig_signing_input)
    )
  end)

non_canonical_names = [
  "y-equals-p",
  "y-equals-p-plus-1",
  "y-all-ones",
  "identity-sign-set",
  "order-2-sign-set"
]

non_canonical_cases =
  Enum.zip_with(non_canonical_names, StrictFixture.non_canonical_encodings(), fn name, r ->
    weak_case.(
      "signature-verify-non-canonical-r-#{name}",
      StrictFixture.key_holder_signature(sig_holder_seed, r, sig_signing_input)
    )
  end)

{:object, sig_entry_members} = sig_entry_value
{"signature", {:string, sig_b64}} = List.keyfind(sig_entry_members, "signature", 0)

{:ok, <<honest_r::binary-size(32), honest_s::little-unsigned-256>>} =
  AgentBlueprintProtocol.Base64Url.decode(sig_b64)

scalar_cases = [
  weak_case.(
    "signature-verify-s-equals-l",
    honest_r <> <<StrictFixture.l()::little-unsigned-256>>
  ),
  weak_case.(
    "signature-verify-s-plus-l",
    honest_r <> <<honest_s + StrictFixture.l()::little-unsigned-256>>
  )
]

{second_entry_text, second_pub} =
  CorpusGen.signature_entry("corpus-signature-valid-3", "corpus-key-3", sig_digest)

second_key_case = %{
  "id" => "signature-verify-valid-second-key",
  "surface" => "signature.verify",
  "class" => "valid",
  "input" => %{
    "entry" => second_entry_text,
    "keys" => [%{"key_id" => "corpus-key-3", "key" => CorpusGen.b64(second_pub)}]
  },
  "expected" => %{"verdict" => "valid", "verified" => true}
}

# S = L - 1 under the honest R passes the strict rule and fails only the
# equation: it pins the exact scalar bound from below (S = L pins it from
# above).
scalar_cases =
  scalar_cases ++
    [
      weak_case.(
        "signature-verify-s-equals-l-minus-1",
        honest_r <> <<StrictFixture.l() - 1::little-unsigned-256>>
      )
    ]

# ---- signature.verify: key facts, which come before the signature rule ----
#
# A matched key that is not usable Ed25519 (each small-order point, y = p,
# off the curve) denies signature_algorithm_unsupported whatever the
# signature; a key_id with no supplied key denies signature_key_unsupported.
# The identity key with R = [r]B, S = r passes the strict signature rule and
# the backend's equation ([S]B = R + [k]O), asserted below: only the key
# rule stands between it and a verified verdict.
key_case = fn id, class, keys, entry_text, code ->
  %{
    "id" => id,
    "surface" => "signature.verify",
    "class" => class,
    "input" => %{"entry" => entry_text, "keys" => keys},
    "expected" => %{"verdict" => "invalid", "code" => code}
  }
end

corpus_key = fn bytes -> %{"key_id" => "corpus-key", "key" => CorpusGen.b64(bytes)} end

small_order_key_cases =
  Enum.zip_with(small_order_names, StrictFixture.small_order_encodings(), fn name, key ->
    key_case.(
      "signature-verify-small-order-key-#{name}",
      "signature_invalid",
      [corpus_key.(key)],
      sig_entry_text,
      "signature_algorithm_unsupported"
    )
  end)

forgery_r = 123_456_789

identity_key_forgery =
  StrictFixture.encode_point(StrictFixture.scalar_mult(forgery_r, StrictFixture.base_point())) <>
    <<forgery_r::little-unsigned-256>>

true = StrictFixture.strict_signature?(identity_key_forgery)

true =
  :crypto.verify(:eddsa, :none, sig_signing_input, identity_key_forgery, [
    StrictFixture.identity(),
    :ed25519
  ])

off_curve_key =
  Base.decode16!("d7f0980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
    case: :lower
  )

key_cases =
  small_order_key_cases ++
    [
      key_case.(
        "signature-verify-identity-key-forgery",
        "signature_invalid",
        [corpus_key.(StrictFixture.identity())],
        weak_entry.(identity_key_forgery),
        "signature_algorithm_unsupported"
      ),
      key_case.(
        "signature-verify-zero-key-zero-signature",
        "signature_invalid",
        [corpus_key.(<<0::256>>)],
        weak_entry.(<<0::512>>),
        "signature_algorithm_unsupported"
      ),
      # Envelope parsing precedes the key facts: a small-order key with a
      # two-byte signature body is a malformed envelope, not a key fact.
      key_case.(
        "signature-verify-small-order-key-short-signature",
        "invalid_encoding",
        [corpus_key.(StrictFixture.identity())],
        CorpusGen.bad_signature_entry(sig_digest, "AAA"),
        "signature_malformed"
      ),
      key_case.(
        "signature-verify-non-canonical-key-y-equals-p",
        "signature_invalid",
        [corpus_key.(<<StrictFixture.p()::little-unsigned-256>>)],
        sig_entry_text,
        "signature_algorithm_unsupported"
      ),
      key_case.(
        "signature-verify-off-curve-key",
        "signature_invalid",
        [corpus_key.(off_curve_key)],
        sig_entry_text,
        "signature_algorithm_unsupported"
      ),
      key_case.(
        "signature-verify-short-key",
        "invalid_encoding",
        [corpus_key.(binary_part(sig_pub, 0, 31))],
        sig_entry_text,
        "invalid_type"
      ),
      key_case.(
        "signature-verify-unmatched-key-id",
        "signature_invalid",
        [%{"key_id" => "other-key", "key" => CorpusGen.b64(sig_pub)}],
        sig_entry_text,
        "signature_key_unsupported"
      ),
      %{
        "id" => "signature-verify-small-order-key-then-good-key",
        "surface" => "signature.verify",
        "class" => "valid",
        "input" => %{
          "entry" => sig_entry_text,
          "keys" => [corpus_key.(StrictFixture.identity()), corpus_key.(sig_pub)]
        },
        "expected" => %{"verdict" => "valid", "verified" => true}
      }
    ]

# Every signature.verify case whose signature decodes to 64 bytes pins the
# strict predicate's verdict, computed by the independent fixture rule, so
# the agreement sees each clause even where the backend rejects the bytes.
strict_expectation = fn case_obj ->
  with {:ok, {:object, members}} <- Json.decode(case_obj["input"]["entry"]),
       {"signature", {:string, body}} <- List.keyfind(members, "signature", 0),
       {:ok, <<_::512>> = signature} <- AgentBlueprintProtocol.Base64Url.decode(body) do
    put_in(case_obj, ["expected", "strict_signature"], StrictFixture.strict_signature?(signature))
  else
    _no_signature_bytes -> case_obj
  end
end

signature_cases =
  (signature_cases ++
     [second_key_case] ++ small_order_cases ++ non_canonical_cases ++ scalar_cases ++ key_cases)
  |> Enum.map(strict_expectation)

# ---- schema.validate_instance (5) ----
object_schema = %{"type" => "object", "additionalProperties" => false, "properties" => %{}}

big_schema = %{
  "type" => "object",
  "additionalProperties" => false,
  "properties" => Map.new(Enum.map(1..600, &{"p#{&1}", %{"type" => "integer"}}))
}

schema_cases = [
  %{
    "id" => "schema-validate-maximum-array",
    "surface" => "schema.validate_instance",
    "class" => "valid",
    "input" => %{"schema" => %{"items" => true}, "instance" => List.duplicate(nil, 10_000)},
    "expected" => %{"verdict" => "valid", "valid" => true}
  },
  %{
    "id" => "schema-validate-valid",
    "surface" => "schema.validate_instance",
    "class" => "valid",
    "input" => %{"schema" => object_schema, "instance" => %{}},
    "expected" => %{"verdict" => "valid", "valid" => true}
  },
  %{
    "id" => "schema-validate-invalid-type",
    "surface" => "schema.validate_instance",
    "class" => "invalid_type",
    "input" => %{"schema" => object_schema, "instance" => 5},
    "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
  },
  %{
    "id" => "schema-validate-invalid-constraint",
    "surface" => "schema.validate_instance",
    "class" => "invalid_constraint",
    "input" => %{"schema" => %{"type" => "integer", "minimum" => 10}, "instance" => 5},
    "expected" => %{"verdict" => "invalid", "code" => "invalid_constraint"}
  },
  %{
    "id" => "schema-validate-maximum-plus-one",
    "surface" => "schema.validate_instance",
    "class" => "maximum_plus_one",
    "input" => %{"schema" => big_schema, "instance" => %{}},
    "expected" => %{"verdict" => "invalid", "code" => "schema_complexity_exceeded"}
  },
  %{
    "id" => "schema-validate-invalid-cardinality",
    "surface" => "schema.validate_instance",
    "class" => "invalid_cardinality",
    "input" => %{"schema" => %{"type" => "array", "maxItems" => 2}, "instance" => [1, 2, 3]},
    "expected" => %{"verdict" => "invalid", "code" => "invalid_cardinality"}
  }
]

# ---- blueprint.decode (10) ----
# The signed variant: the evidence-member signatures array carries an
# honestly-signed envelope over the SAME content_digest (evidence members
# are digest-excluded, so the digest — and this case's expected digest —
# match the unsigned golden). Crypto verification is the signature surface
# and reconcile stage; decode proves the closed world admits the member.
signed_bp_value =
  BlueprintFixture.fixture_value(
    extra_members: [
      {"signatures",
       {:array,
        [
          BlueprintFixture.signature_entry(
            attrs:
              BlueprintFixture.signature_attrs(
                digest:
                  CorpusGen.member_string(BlueprintFixture.fixture_value([]), "content_digest")
              )
          )
        ]}}
    ]
  )

signed_blueprint = CorpusGen.json_text!(signed_bp_value)

# The extension-bearing variant: one REGISTERED optional namespace with a
# plain labeled body (no pinned schema — the body passes the generic
# value-shape heuristics; negotiation retains it on a supporting host).
extension_bp_value =
  BlueprintFixture.fixture_value(
    extensions:
      BlueprintFixture.extensions(
        optional: %{
          "com.example.vendor/labels" => {:object, [{"labels", {:array, [{:string, "pci"}]}}]}
        }
      )
  )

extension_blueprint = CorpusGen.json_text!(extension_bp_value)

pem = "-----" <> "BEGIN PRIVATE KEY-----\nMIIEvQ\n-----" <> "END PRIVATE KEY-----"
bp_forbidden_value = BlueprintFixture.fixture_value(toolchain: pem) |> CorpusGen.json_text!()

blueprint_cases = [
  %{
    "id" => "blueprint-decode-valid",
    "surface" => "blueprint.decode",
    "class" => "valid",
    "input" => %{"text" => golden_blueprint},
    "expected" => %{
      "verdict" => "valid",
      "digest" => CorpusGen.member_string(BlueprintFixture.fixture_value([]), "content_digest")
    }
  },
  %{
    "id" => "blueprint-decode-signed-valid",
    "surface" => "blueprint.decode",
    "class" => "valid",
    "input" => %{"text" => signed_blueprint},
    "expected" => %{
      "verdict" => "valid",
      "digest" => CorpusGen.member_string(BlueprintFixture.fixture_value([]), "content_digest")
    }
  },
  %{
    "id" => "blueprint-decode-extension-valid",
    "surface" => "blueprint.decode",
    "class" => "valid",
    "input" => %{"text" => extension_blueprint},
    "expected" => %{
      "verdict" => "valid",
      "digest" => CorpusGen.member_string(extension_bp_value, "content_digest")
    }
  },
  %{
    "id" => "blueprint-decode-unknown-member",
    "surface" => "blueprint.decode",
    "class" => "unknown_member",
    "input" => %{
      "text" =>
        BlueprintFixture.fixture_value(extra_members: [{"zz_extra", {:integer, 1}}])
        |> CorpusGen.json_text!()
    },
    "expected" => %{"verdict" => "invalid", "code" => "unknown_member"}
  },
  %{
    "id" => "blueprint-decode-invalid-type",
    "surface" => "blueprint.decode",
    "class" => "invalid_type",
    "input" => %{
      "text" =>
        BlueprintFixture.fixture_value(ceilings: {:string, "oops"}) |> CorpusGen.json_text!()
    },
    "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
  },
  %{
    "id" => "blueprint-decode-invalid-constraint",
    "surface" => "blueprint.decode",
    "class" => "invalid_constraint",
    "input" => %{
      "text" =>
        BlueprintFixture.fixture_value(blueprint_id: "UPPER/Case") |> CorpusGen.json_text!()
    },
    "expected" => %{"verdict" => "invalid", "code" => "invalid_constraint"}
  },
  %{
    "id" => "blueprint-decode-invalid-cardinality",
    "surface" => "blueprint.decode",
    "class" => "invalid_cardinality",
    "input" => %{
      "text" =>
        BlueprintFixture.fixture_value(
          input_ports: Enum.map(1..65, fn i -> BlueprintFixture.port("p#{i}") end)
        )
        |> CorpusGen.json_text!()
    },
    "expected" => %{"verdict" => "invalid", "code" => "invalid_cardinality"}
  },
  %{
    "id" => "blueprint-decode-maximum-plus-one",
    "surface" => "blueprint.decode",
    "class" => "maximum_plus_one",
    "input" => %{"text" => golden_blueprint, "bounds" => %{"bytes" => 10}},
    "expected" => %{"verdict" => "invalid", "code" => "ceiling:bytes"}
  },
  %{
    "id" => "blueprint-decode-forbidden-portable",
    "surface" => "blueprint.decode",
    "class" => "forbidden_portable_value",
    "input" => %{"text" => bp_forbidden_value},
    "expected" => %{"verdict" => "invalid", "code" => "forbidden_portable_value"}
  },
  %{
    "id" => "blueprint-decode-tamper-byte",
    "surface" => "blueprint.decode",
    "class" => "tamper_meaningful_byte",
    "input" => %{
      "text" => String.replace(golden_blueprint, "\"release_number\":1", "\"release_number\":2")
    },
    "expected" => %{"verdict" => "invalid", "code" => "digest_mismatch"},
    "tamper" => %{
      "base_case" => "blueprint-decode-valid",
      "byte_index" => bi.(golden_blueprint, "\"release_number\":1") + 17,
      "xor" => 3
    }
  }
]

# ---- deployment.decode (11) ----
dep_range = String.replace(golden_deployment, "\"0.1.0\"", "\"*\"")

other_ceilings =
  {:object,
   Enum.map(
     [
       {"max_attempts", 9},
       {"max_concurrency", 9},
       {"max_depth", 9},
       {"max_descendants", 9},
       {"max_elapsed_ms", 9},
       {"max_fan_out", 9},
       {"max_tokens", 9}
     ],
     fn {k, v} -> {k, {:integer, v}} end
   ) ++ [{"max_cost", {:object, [{"amount", {:integer, 9}}, {"currency", {:string, "USD"}}]}}]}

diverged_blueprint = BlueprintFixture.fixture_bytes(ceilings: other_ceilings)

deployment_cases = [
  %{
    "id" => "deployment-decode-valid",
    "surface" => "deployment.decode",
    "class" => "valid",
    "input" => %{"text" => golden_deployment},
    "expected" => %{
      "verdict" => "valid",
      "digest" =>
        CorpusGen.member_string(DeploymentFixture.fixture_value([]), "deployment_digest")
    }
  },
  %{
    "id" => "deployment-decode-unknown-member",
    "surface" => "deployment.decode",
    "class" => "unknown_member",
    "input" => %{
      "text" =>
        DeploymentFixture.fixture_value(extra_members: [{"zz_extra", {:integer, 1}}])
        |> CorpusGen.json_text!()
    },
    "expected" => %{"verdict" => "invalid", "code" => "unknown_member"}
  },
  %{
    "id" => "deployment-decode-invalid-type",
    "surface" => "deployment.decode",
    "class" => "invalid_type",
    "input" => %{
      "text" =>
        String.replace(golden_deployment, "\"agent_blueprint_protocol\"", "123", global: false)
    },
    "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
  },
  %{
    "id" => "deployment-decode-invalid-constraint",
    "surface" => "deployment.decode",
    "class" => "invalid_constraint",
    "input" => %{
      "text" =>
        DeploymentFixture.fixture_value(
          data_bindings: [
            DeploymentFixture.data_binding(
              as_of:
                {:object, [{"mode", {:string, "sometimes"}}, {"max_age_ms", {:integer, 1000}}]}
            )
          ]
        )
        |> CorpusGen.json_text!()
    },
    "expected" => %{"verdict" => "invalid", "code" => "invalid_constraint"}
  },
  %{
    "id" => "deployment-decode-invalid-cardinality",
    "surface" => "deployment.decode",
    "class" => "invalid_cardinality",
    "input" => %{
      "text" =>
        DeploymentFixture.fixture_value(
          tool_bindings:
            Enum.map(1..129, fn _ ->
              DeploymentFixture.tool_binding(operation: "example.demo.read_shape")
            end)
        )
        |> CorpusGen.json_text!()
    },
    "expected" => %{"verdict" => "invalid", "code" => "invalid_cardinality"}
  },
  %{
    "id" => "deployment-decode-maximum-plus-one",
    "surface" => "deployment.decode",
    "class" => "maximum_plus_one",
    "input" => %{"text" => golden_deployment, "bounds" => %{"bytes" => 10}},
    "expected" => %{"verdict" => "invalid", "code" => "ceiling:bytes"}
  },
  %{
    "id" => "deployment-decode-forbidden-portable",
    "surface" => "deployment.decode",
    "class" => "forbidden_portable_value",
    "input" => %{
      "text" =>
        DeploymentFixture.fixture_value(
          eligibility:
            DeploymentFixture.eligibility(owner: {:object, [{"tenant_id", {:string, "org-7"}}]})
        )
        |> CorpusGen.json_text!()
    },
    "expected" => %{"verdict" => "invalid", "code" => "forbidden_portable_value"}
  },
  %{
    "id" => "deployment-decode-tamper-byte",
    "surface" => "deployment.decode",
    "class" => "tamper_meaningful_byte",
    "input" => %{
      "text" => String.replace(golden_deployment, "\"0.1.0\"", "\"0.1.1\"", global: false)
    },
    "expected" => %{"verdict" => "invalid", "code" => "digest_mismatch"},
    "tamper" => %{
      "base_case" => "deployment-decode-valid",
      "byte_index" => bi.(golden_deployment, "\"0.1.0\"") + 5,
      "xor" => 1
    }
  },
  %{
    "id" => "deployment-decode-digest-mismatch",
    "surface" => "deployment.decode",
    "class" => "digest_mismatch",
    "input" => %{"text" => golden_deployment, "binding" => %{"blueprint" => diverged_blueprint}},
    "expected" => %{"verdict" => "invalid", "code" => "deployment_digest_mismatch"}
  },
  %{
    "id" => "deployment-decode-binding-stale",
    "surface" => "deployment.decode",
    "class" => "binding_stale",
    "input" => %{
      "text" => golden_deployment,
      "binding" => %{
        "blueprint" => diverged_blueprint,
        "now" => "2020-01-01T00:00:00Z",
        "max_attestation_age_ms" => 1
      }
    },
    "expected" => %{"verdict" => "invalid", "code" => "deployment_digest_mismatch"}
  },
  %{
    "id" => "deployment-decode-compat-range",
    "surface" => "deployment.decode",
    "class" => "compatibility_range_rejected",
    "input" => %{"text" => dep_range},
    "expected" => %{"verdict" => "invalid", "code" => "compatibility_identity_inexact"}
  }
]

# ---- shared negotiation fixtures ----
base_artifact = %{
  "protocol_revision" => 1,
  "content_digest" => "sha-256:x",
  "required_core_fields" => [],
  "extensions" => %{
    "critical" => %{"com.example/federation" => %{"issuer" => "org-a"}},
    "optional" => %{}
  }
}

fed_support = %{
  "revisions" => [1],
  "registry" => %{
    "com.example/federation" => %{"criticality" => "critical", "state" => "active"}
  },
  "schemas" => %{
    "com.example/federation" => CorpusGen.plain(ExtensionRegistry.federation_schema())
  }
}

# A host owns this example registration and holds its pinned schema document.
vendor_schema = %{
  "type" => "object",
  "additionalProperties" => false,
  "required" => ["value"],
  "properties" => %{"value" => %{"oneOf" => [%{"const" => "one"}, %{"const" => "two"}]}}
}

vendor_entry = %{
  "owner" => "ExampleVendor",
  "criticality" => "critical",
  "state" => "active",
  "schema_digest" =>
    CorpusGen.tagged_digest(:extension_schema, CorpusGen.json_text!(vendor_schema))
}

vendor_support = %{
  "revisions" => [1],
  "registry" => %{"com.example.vendor/record" => vendor_entry},
  "schemas" => %{
    "com.example/federation" => fed_support["schemas"]["com.example/federation"],
    "com.example.vendor/record" => vendor_schema
  }
}

legacy_entry = %{"owner" => "ExampleVendor", "criticality" => "optional", "state" => "deprecated"}
legacy_support = put_in(fed_support, ["registry", "com.example.vendor/legacy"], legacy_entry)

vendor_body = %{"value" => "one"}

vendor_artifact = fn body ->
  Map.put(base_artifact, "extensions", %{
    "critical" => %{
      "com.example/federation" => %{"issuer" => "org-a"},
      "com.example.vendor/record" => body
    },
    "optional" => %{}
  })
end

# ---- negotiation.negotiate (12) ----

negotiation_cases = [
  %{
    "id" => "negotiation-valid",
    "surface" => "negotiation.negotiate",
    "class" => "valid",
    "input" => %{"artifact" => base_artifact, "support" => fed_support},
    "expected" => %{
      "verdict" => "valid",
      "revision" => 1,
      "critical" => ["com.example/federation"]
    }
  },
  %{
    "id" => "negotiation-above-max",
    "surface" => "negotiation.negotiate",
    "class" => "revision_above_max",
    "input" => %{
      "artifact" => %{base_artifact | "protocol_revision" => 2},
      "support" => fed_support
    },
    "expected" => %{"verdict" => "invalid", "code" => "protocol_revision_unsupported"}
  },
  %{
    "id" => "negotiation-below-min",
    "surface" => "negotiation.negotiate",
    "class" => "revision_below_min",
    "input" => %{
      "artifact" => %{base_artifact | "protocol_revision" => 0},
      "support" => fed_support
    },
    "expected" => %{"verdict" => "invalid", "code" => "invalid_constraint"}
  },
  %{
    "id" => "negotiation-required-unsupported",
    "surface" => "negotiation.negotiate",
    "class" => "required_field_unsupported",
    "input" => %{
      "artifact" => %{base_artifact | "required_core_fields" => ["blueprint_id"]},
      "support" => fed_support
    },
    "expected" => %{"verdict" => "invalid", "code" => "required_core_field_unsupported"}
  },
  %{
    "id" => "negotiation-required-not-covered",
    "surface" => "negotiation.negotiate",
    "class" => "required_field_not_covered",
    "input" => %{
      "artifact" => %{base_artifact | "required_core_fields" => ["signatures"]},
      "support" => Map.put(fed_support, "core_fields", ["signatures"])
    },
    "expected" => %{"verdict" => "invalid", "code" => "required_core_field_not_digest_covered"}
  },
  %{
    "id" => "negotiation-unknown-critical",
    "surface" => "negotiation.negotiate",
    "class" => "extension_unknown_critical",
    "input" => %{
      "artifact" => %{
        base_artifact
        | "extensions" => %{"critical" => %{"com.example/absent" => %{}}, "optional" => %{}}
      },
      "support" => fed_support
    },
    "expected" => %{"verdict" => "invalid", "code" => "extension_unknown_critical"}
  },
  %{
    "id" => "negotiation-criticality-conflict",
    "surface" => "negotiation.negotiate",
    "class" => "extension_criticality_conflict",
    "input" => %{
      "artifact" => %{
        base_artifact
        | "extensions" => %{
            "critical" => %{"com.example/federation" => %{}},
            "optional" => %{"com.example/federation" => %{}}
          }
      },
      "support" => fed_support
    },
    "expected" => %{"verdict" => "invalid", "code" => "extension_criticality_conflict"}
  },
  %{
    "id" => "negotiation-vendor-record-valid",
    "surface" => "negotiation.negotiate",
    "class" => "valid",
    "input" => %{"artifact" => vendor_artifact.(vendor_body), "support" => vendor_support},
    "expected" => %{
      "verdict" => "valid",
      "revision" => 1,
      "critical" => ["com.example.vendor/record", "com.example/federation"],
      "notices" => ["extension_deprecated"]
    }
  },
  %{
    "id" => "negotiation-vendor-record-schema-absent",
    "surface" => "negotiation.negotiate",
    "class" => "extension_schema_unavailable",
    "input" => %{
      "artifact" => vendor_artifact.(vendor_body),
      "support" => %{vendor_support | "schemas" => %{}}
    },
    "expected" => %{"verdict" => "invalid", "code" => "extension_schema_unavailable"}
  },
  %{
    "id" => "negotiation-vendor-record-digest-mismatch",
    "surface" => "negotiation.negotiate",
    "class" => "invalid_constraint",
    "input" => %{
      "artifact" => vendor_artifact.(vendor_body),
      "support" => %{
        "revisions" => [1],
        "registry" => vendor_support["registry"],
        "schemas" => %{
          "com.example/federation" => fed_support["schemas"]["com.example/federation"],
          "com.example.vendor/record" => %{"type" => "object"}
        }
      }
    },
    "expected" => %{"verdict" => "invalid", "code" => "extension_schema_digest_mismatch"}
  },
  %{
    "id" => "negotiation-vendor-schema-cardinality",
    "surface" => "negotiation.negotiate",
    "class" => "invalid_cardinality",
    "input" => %{
      "artifact" => vendor_artifact.(%{"value" => "three"}),
      "support" => vendor_support
    },
    "expected" => %{"verdict" => "invalid", "code" => "invalid_cardinality"}
  },
  %{
    "id" => "negotiation-vendor-record-criticality-conflict",
    "surface" => "negotiation.negotiate",
    "class" => "extension_criticality_conflict",
    "input" => %{
      "artifact" =>
        Map.put(base_artifact, "extensions", %{
          "critical" => %{"com.example/federation" => %{"issuer" => "org-a"}},
          "optional" => %{"com.example.vendor/record" => vendor_body}
        }),
      "support" => vendor_support
    },
    "expected" => %{"verdict" => "invalid", "code" => "extension_criticality_conflict"}
  }
]

# Host registrations exercise the complete lifecycle in both negotiation surfaces.
host_registration_cases =
  for surface <- ["negotiation.negotiate", "extension.resolve"],
      position <- ["critical", "optional"],
      state <- ["active", "deprecated", "reserved", "retired"] do
    namespace = "com.example.vendor/record"
    entry = %{vendor_entry | "criticality" => position, "state" => state}

    input = %{
      "artifact" =>
        Map.put(base_artifact, "extensions", %{
          "critical" => if(position == "critical", do: %{namespace => vendor_body}, else: %{}),
          "optional" => if(position == "optional", do: %{namespace => vendor_body}, else: %{})
        }),
      "support" => %{
        "registry" => %{namespace => entry},
        "schemas" => %{namespace => vendor_schema}
      }
    }

    expected =
      case {position, state} do
        {"critical", "reserved"} ->
          %{"verdict" => "invalid", "code" => "extension_unknown_critical"}

        {"critical", "retired"} ->
          %{"verdict" => "invalid", "code" => "extension_retired"}

        _ ->
          %{
            "verdict" => "valid",
            "critical" => if(position == "critical", do: [namespace], else: []),
            "quarantined" => [],
            "notices" =>
              case state do
                "deprecated" -> ["extension_deprecated"]
                "reserved" -> ["extension_unknown_optional_retained"]
                "retired" -> ["extension_retired"]
                _ -> []
              end
          }
      end

    %{
      "id" => String.replace(surface, ".", "-") <> "-host-" <> position <> "-" <> state,
      "surface" => surface,
      "class" => if(expected["verdict"] == "valid", do: "valid", else: "invalid_constraint"),
      "input" => input,
      "expected" => expected
    }
  end

host_pin_cases =
  for surface <- ["negotiation.negotiate", "extension.resolve"],
      variant <- ["missing-pin", "mismatched-schema", "compiled-pin-override"] do
    namespace =
      if(variant == "compiled-pin-override",
        do: "io.github.baselabs/federation",
        else: "com.example.vendor/record"
      )

    entry =
      if(variant == "missing-pin",
        do: Map.put(vendor_entry, "schema_digest", nil),
        else: vendor_entry
      )

    document = if(variant == "mismatched-schema", do: %{"type" => "object"}, else: vendor_schema)

    %{
      "id" => String.replace(surface, ".", "-") <> "-host-" <> variant,
      "surface" => surface,
      "class" => "invalid_constraint",
      "input" => %{
        "artifact" =>
          Map.put(base_artifact, "extensions", %{
            "critical" => %{namespace => vendor_body},
            "optional" => %{}
          }),
        "support" => %{"registry" => %{namespace => entry}, "schemas" => %{namespace => document}}
      },
      "expected" => %{
        "verdict" => "invalid",
        "code" =>
          if(variant == "missing-pin",
            do: "extension_schema_unavailable",
            else: "extension_schema_digest_mismatch"
          )
      }
    }
  end

negotiation_cases = negotiation_cases ++ host_registration_cases ++ host_pin_cases

# ---- extension.resolve (7) ----
extension_cases = [
  %{
    "id" => "extension-resolve-valid",
    "surface" => "extension.resolve",
    "class" => "valid",
    "input" => %{"artifact" => base_artifact, "support" => fed_support},
    "expected" => %{"verdict" => "valid", "critical" => ["com.example/federation"]}
  },
  %{
    "id" => "extension-resolve-unknown-critical",
    "surface" => "extension.resolve",
    "class" => "extension_unknown_critical",
    "input" => %{
      "artifact" => %{
        base_artifact
        | "extensions" => %{"critical" => %{"com.example/absent" => %{}}, "optional" => %{}}
      },
      "support" => fed_support
    },
    "expected" => %{"verdict" => "invalid", "code" => "extension_unknown_critical"}
  },
  %{
    "id" => "extension-resolve-optional-roundtrip",
    "surface" => "extension.resolve",
    "class" => "extension_unknown_optional_roundtrip",
    "input" => %{
      "artifact" => %{
        base_artifact
        | "extensions" => %{
            "critical" => %{"com.example/federation" => %{"issuer" => "org-a"}},
            "optional" => %{"com.example/unknown" => %{"payload" => 1}}
          }
      },
      "support" => fed_support
    },
    "expected" => %{"verdict" => "valid", "quarantined" => ["com.example/unknown"]}
  },
  %{
    "id" => "extension-resolve-criticality-conflict",
    "surface" => "extension.resolve",
    "class" => "extension_criticality_conflict",
    "input" => %{
      "artifact" => %{
        base_artifact
        | "extensions" => %{
            "critical" => %{"com.example/federation" => %{}},
            "optional" => %{"com.example/federation" => %{}}
          }
      },
      "support" => fed_support
    },
    "expected" => %{"verdict" => "invalid", "code" => "extension_criticality_conflict"}
  },
  %{
    "id" => "extension-resolve-forbidden",
    "surface" => "extension.resolve",
    "class" => "forbidden_portable_value",
    "input" => %{
      "artifact" => %{
        base_artifact
        | "extensions" => %{
            "critical" => %{"com.example/federation" => %{"issuer" => "org-a"}},
            "optional" => %{"com.example/unknown" => %{"max_cost" => 5}}
          }
      },
      "support" => fed_support
    },
    "expected" => %{"verdict" => "invalid", "code" => "extension_payload_forbidden"}
  },
  %{
    "id" => "extension-resolve-invalid-constraint",
    "surface" => "extension.resolve",
    "class" => "invalid_constraint",
    "input" => %{
      "artifact" => base_artifact,
      "support" =>
        Map.put(fed_support, "schemas", %{"com.example/federation" => %{"type" => "array"}})
    },
    "expected" => %{"verdict" => "invalid", "code" => "extension_schema_digest_mismatch"}
  },
  %{
    "id" => "extension-resolve-vendor-deprecated-retained",
    "surface" => "extension.resolve",
    "class" => "extension_deprecated_retained",
    "input" => %{
      "artifact" =>
        Map.put(base_artifact, "extensions", %{
          "critical" => %{"com.example/federation" => %{"issuer" => "org-a"}},
          "optional" => %{"com.example.vendor/legacy" => %{"payload" => 1}}
        }),
      "support" => legacy_support
    },
    "expected" => %{
      "verdict" => "valid",
      "quarantined" => [],
      "notices" => ["extension_deprecated"]
    }
  }
]

# ---- bounds.new (4) ----
bounds_cases = [
  %{
    "id" => "bounds-new-valid",
    "surface" => "bounds.new",
    "class" => "valid",
    "input" => %{"bounds" => %{"depth" => 8}},
    "expected" => %{
      "verdict" => "valid",
      "bounds" => %{
        "bytes" => 5_000_000,
        "depth" => 8,
        "members" => 1_000,
        "items" => 10_000,
        "nodes" => 200_000,
        "string" => 100_000,
        "key" => 1_000,
        "number_lexeme" => 64
      }
    }
  },
  %{
    "id" => "bounds-new-exact-bound",
    "surface" => "bounds.new",
    "class" => "exact_bound",
    "input" => %{"bounds" => %{"depth" => 64}},
    "expected" => %{
      "verdict" => "valid",
      "bounds" => %{
        "bytes" => 5_000_000,
        "depth" => 64,
        "members" => 1_000,
        "items" => 10_000,
        "nodes" => 200_000,
        "string" => 100_000,
        "key" => 1_000,
        "number_lexeme" => 64
      }
    }
  },
  %{
    "id" => "bounds-new-maximum-plus-one",
    "surface" => "bounds.new",
    "class" => "maximum_plus_one",
    "input" => %{"bounds" => %{"depth" => 65}},
    "expected" => %{"verdict" => "invalid", "code" => "ceiling:depth"}
  },
  %{
    "id" => "bounds-new-invalid-type",
    "surface" => "bounds.new",
    "class" => "invalid_type",
    "input" => %{"bounds" => [1]},
    "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
  }
]

# ---- bounds_algebra.intersect (5) ----
narrow_bounds = %{
  "max_attempts" => 3,
  "max_concurrency" => 3,
  "max_cost" => %{"amount" => 3, "currency" => "USD"},
  "max_depth" => 3,
  "max_descendants" => 3,
  "max_elapsed_ms" => 3,
  "max_fan_out" => 3,
  "max_tokens" => 3,
  "classification_ceiling" => %{"ordinal" => "internal", "markers" => []},
  "authority_trait" => "local_policy",
  "approval_trait" => "none",
  "effect_impact_ceiling" => "ordinary",
  "disclosure_ceiling" => "none"
}

wide_operational =
  Map.merge(narrow_bounds, %{
    "max_attempts" => 9,
    "max_concurrency" => 9,
    "max_cost" => %{"amount" => 9, "currency" => "USD"},
    "max_depth" => 9,
    "max_descendants" => 9,
    "max_elapsed_ms" => 9,
    "max_fan_out" => 9,
    "max_tokens" => 9
  })

intersect_cases = [
  %{
    "id" => "intersect-valid",
    "surface" => "bounds_algebra.intersect",
    "class" => "valid",
    "input" => %{
      "blueprint" => narrow_bounds,
      "deployment" => narrow_bounds,
      "host" => narrow_bounds
    },
    "expected" => %{"verdict" => "valid", "clamp_count" => 0, "effective" => narrow_bounds}
  },
  %{
    "id" => "intersect-widening-operational",
    "surface" => "bounds_algebra.intersect",
    "class" => "bound_widening_operational",
    "input" => %{
      "blueprint" => wide_operational,
      "deployment" => narrow_bounds,
      "host" => narrow_bounds
    },
    "expected" => %{"verdict" => "valid", "clamp_count" => 8, "effective" => narrow_bounds}
  },
  %{
    "id" => "intersect-widening-protected",
    "surface" => "bounds_algebra.intersect",
    "class" => "bound_widening_protected",
    "input" => %{
      "blueprint" => narrow_bounds,
      "deployment" => narrow_bounds,
      "host" =>
        Map.put(narrow_bounds, "classification_ceiling", %{"ordinal" => "public", "markers" => []})
    },
    "expected" => %{"verdict" => "invalid", "code" => "protected_bound_clamp_denied"}
  },
  %{
    # The obligation meet finally varies across sources. The
    # blueprint holds the STRICTEST authority/approval/impact obligations;
    # a least-strict (min) meet would land on the loose host values, clamp,
    # and flip this valid case to a denial — the corpus now pins the
    # meet direction (the TS mirror was caught doing exactly
    # that, invisibly to the old all-equal cases).
    "id" => "intersect-obligation-strict-blueprint",
    "surface" => "bounds_algebra.intersect",
    "class" => "valid",
    "input" => %{
      "blueprint" =>
        Map.merge(narrow_bounds, %{
          "authority_trait" => "external_authority_required",
          "approval_trait" => "separated_human_required",
          "effect_impact_ceiling" => "authority"
        }),
      "deployment" => narrow_bounds,
      "host" => narrow_bounds
    },
    "expected" => %{
      "verdict" => "valid",
      "clamp_count" => 0,
      "effective" =>
        Map.merge(narrow_bounds, %{
          "authority_trait" => "external_authority_required",
          "approval_trait" => "separated_human_required",
          "effect_impact_ceiling" => "authority"
        })
    }
  },
  %{
    # The protected widening via an OBLIGATION bound (authority)
    # rather than a scope bound — the privilege-escalation direction.
    "id" => "intersect-obligation-widening-protected",
    "surface" => "bounds_algebra.intersect",
    "class" => "bound_widening_protected",
    "input" => %{
      "blueprint" => narrow_bounds,
      "deployment" => narrow_bounds,
      "host" => Map.put(narrow_bounds, "authority_trait", "external_authority_required")
    },
    "expected" => %{"verdict" => "invalid", "code" => "protected_bound_clamp_denied"}
  },
  %{
    "id" => "intersect-invalid-type",
    "surface" => "bounds_algebra.intersect",
    "class" => "invalid_type",
    "input" => %{
      "blueprint" => %{"no_such_bound" => 1},
      "deployment" => narrow_bounds,
      "host" => narrow_bounds
    },
    "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
  },
  %{
    "id" => "intersect-invalid-constraint",
    "surface" => "bounds_algebra.intersect",
    "class" => "invalid_constraint",
    "input" => %{
      "blueprint" => Map.delete(narrow_bounds, "max_attempts"),
      "deployment" => narrow_bounds,
      "host" => narrow_bounds
    },
    "expected" => %{"verdict" => "invalid", "code" => "missing_ceiling"}
  }
]

# ---- portability.scan (2) ----
portability_cases = [
  %{
    "id" => "portability-valid",
    "surface" => "portability.scan",
    "class" => "valid",
    "input" => %{"text" => ~s({"kind":"ordinary"})},
    "expected" => %{"verdict" => "valid", "clean" => true}
  },
  %{
    "id" => "portability-forbidden",
    "surface" => "portability.scan",
    "class" => "forbidden_portable_value",
    "input" => %{"text" => CorpusGen.json_text!(%{"api_key" => String.duplicate("A", 40)})},
    "expected" => %{"verdict" => "invalid", "code" => "forbidden_portable_value"}
  }
]

# ---- compatibility.verify (3) ----
{:object, golden_members} = DeploymentFixture.fixture_value([])

{"build_identities", {:array, [{:object, identity_members} | _]}} =
  List.keyfind(golden_members, "build_identities", 0)

compat_identity = Map.new(identity_members, fn {k, {:string, v}} -> {k, v} end)

compatibility_cases = [
  %{
    "id" => "compatibility-valid",
    "surface" => "compatibility.verify",
    "class" => "valid",
    "input" => %{"text" => golden_deployment, "observed" => %{"identities" => [compat_identity]}},
    "expected" => %{"verdict" => "valid", "verified" => true}
  },
  %{
    "id" => "compatibility-range-rejected",
    "surface" => "compatibility.verify",
    "class" => "compatibility_range_rejected",
    "input" => %{
      "text" => golden_deployment,
      "observed" => %{"identities" => [%{compat_identity | "version" => "~> 1"}]}
    },
    "expected" => %{"verdict" => "invalid", "code" => "compatibility_identity_inexact"}
  },
  %{
    "id" => "compatibility-entry-missing",
    "surface" => "compatibility.verify",
    "class" => "invalid_constraint",
    "input" => %{"text" => golden_deployment, "observed" => %{}},
    "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
  }
]

# ---- federation.decode (5) ----
fed_unknown =
  FederationFixture.value(terminal: true)
  |> CorpusGen.with_sorted_extra("zz_extra", 1)
  |> CorpusGen.json_text!()

federation_decode_cases = [
  %{
    "id" => "federation-decode-valid",
    "surface" => "federation.decode",
    "class" => "valid",
    "input" => %{"text" => golden_federation},
    "expected" => %{"verdict" => "valid", "canonical" => golden_federation}
  },
  %{
    "id" => "federation-decode-state-unmappable",
    "surface" => "federation.decode",
    "class" => "federation_state_unmappable",
    "input" => %{"from_a2a_state" => "TASK_STATE_UNSPECIFIED"},
    "expected" => %{"verdict" => "invalid", "code" => "federation_state_unmappable"}
  },
  %{
    "id" => "federation-decode-unknown-member",
    "surface" => "federation.decode",
    "class" => "unknown_member",
    "input" => %{"text" => fed_unknown},
    "expected" => %{"verdict" => "invalid", "code" => "unknown_member"}
  },
  %{
    "id" => "federation-decode-invalid-type",
    "surface" => "federation.decode",
    "class" => "invalid_type",
    "input" => %{"to_a2a_state" => "no-such-state"},
    "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
  },
  %{
    "id" => "federation-decode-forbidden-portable",
    "surface" => "federation.decode",
    "class" => "forbidden_portable_value",
    "input" => %{"text" => CorpusGen.secret_kid_envelope()},
    "expected" => %{"verdict" => "invalid", "code" => "forbidden_portable_value"}
  }
]

# ---- federation.verify_commitment (5) ----
receipt_keys = [%{"key_id" => "remote-key", "key" => CorpusGen.b64(receipt_pub)}]

verify_commitment_cases = [
  %{
    "id" => "commitment-valid",
    "surface" => "federation.verify_commitment",
    "class" => "valid",
    "input" => %{"envelope" => receipt_text, "context" => %{"keys" => receipt_keys}},
    "expected" => %{"verdict" => "valid", "task_identity" => "task-7f3a2c"}
  },
  %{
    "id" => "commitment-audience-mismatch",
    "surface" => "federation.verify_commitment",
    "class" => "audience_mismatch",
    "input" => %{
      "envelope" => receipt_text,
      "context" => %{"keys" => receipt_keys, "audience" => "someone-else"}
    },
    "expected" => %{"verdict" => "invalid", "code" => "audience_mismatch"}
  },
  %{
    "id" => "commitment-terminal-conflict",
    "surface" => "federation.verify_commitment",
    "class" => "federation_terminal_conflict",
    "input" => %{
      "envelope" => receipt_text,
      "context" => %{
        "keys" => receipt_keys,
        "prior_receipts" => [
          %{
            "task_identity" => "task-7f3a2c",
            "terminal_state" => "failed",
            "commitment" => CorpusGen.tagged_digest(:federation_envelope, "divergent")
          }
        ]
      }
    },
    "expected" => %{"verdict" => "invalid", "code" => "federation_terminal_conflict"}
  },
  %{
    "id" => "commitment-terminal-equivocation",
    "surface" => "federation.verify_commitment",
    "class" => "terminal_equivocation",
    "input" => %{
      "envelope" => receipt_text,
      "context" => %{
        "keys" => receipt_keys,
        "prior_receipts" => [
          %{
            "task_identity" => "task-7f3a2c",
            "terminal_state" => "completed",
            "commitment" => CorpusGen.tagged_digest(:federation_envelope, "divergent-same-state")
          }
        ]
      }
    },
    "expected" => %{"verdict" => "invalid", "code" => "federation_terminal_conflict"}
  },
  %{
    "id" => "commitment-signature-invalid",
    "surface" => "federation.verify_commitment",
    "class" => "signature_invalid",
    "input" => %{
      "envelope" => receipt_text,
      "context" => %{
        "keys" => [%{"key_id" => "remote-key", "key" => CorpusGen.b64(other_receipt_pub)}]
      }
    },
    "expected" => %{"verdict" => "invalid", "code" => "signature_not_verified"}
  }
]

# Malformed escapes exercise the shared decoder through every text surface.
unicode_escape_cases =
  for {name, text} <- [
        {"low-surrogate", ~S("\udc00")},
        {"member-surrogate", ~S({"a":"\udfff"})},
        {"key-surrogate", ~S({"\udc00":1})},
        {"high-surrogate", ~S("\ud800A")},
        {"nonhex-escape", ~S("\uZZZZ")}
      ],
      surface <- [
        "json.decode",
        "canonicalization.encode",
        "blueprint.decode",
        "deployment.decode",
        "federation.decode"
      ] do
    %{
      "id" => String.replace(surface, ".", "-") <> "-" <> name,
      "surface" => surface,
      "class" => "invalid_encoding",
      "input" => %{"text" => text},
      "expected" => %{"verdict" => "invalid", "code" => "invalid_syntax"}
    }
  end

prototype_names = ~w(constructor toString __proto__ hasOwnProperty)

predicate_operator_cases =
  for name <- prototype_names do
    assertion =
      BlueprintFixture.assertion(
        kind: "deterministic_predicate",
        predicate: {:object, [{"op", {:string, name}}]}
      )

    %{
      "id" => "blueprint-decode-unknown-operator-" <> name,
      "surface" => "blueprint.decode",
      "class" => "invalid_constraint",
      "input" => %{"text" => BlueprintFixture.fixture_bytes(assertions: [assertion])},
      "expected" => %{"verdict" => "invalid", "code" => "predicate_op_unknown"}
    }
  end

unknown_state_cases =
  for name <- prototype_names, transport <- ["a2a", "mcp"] do
    %{
      "id" => "federation-decode-unknown-" <> transport <> "-state-" <> name,
      "surface" => "federation.decode",
      "class" => "invalid_constraint",
      "input" => %{("from_" <> transport <> "_state") => name},
      "expected" => %{"verdict" => "invalid", "code" => "invalid_constraint"}
    }
  end

unknown_bound_cases =
  for name <- prototype_names do
    %{
      "id" => "bounds-new-unknown-member-" <> name,
      "surface" => "bounds.new",
      "class" => "invalid_type",
      "input" => %{"bounds" => %{name => 1}},
      "expected" => %{"verdict" => "invalid", "code" => "unknown_bound"}
    }
  end

unknown_algebra_cases =
  for name <- prototype_names do
    %{
      "id" => "intersect-unknown-member-" <> name,
      "surface" => "bounds_algebra.intersect",
      "class" => "invalid_type",
      "input" => %{"blueprint" => %{name => 1}, "deployment" => %{}, "host" => %{}},
      "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
    }
  end

uri_boundary_cases =
  for {name, text, denied} <- [
        {"letter-suffix", "1a://x", true},
        {"punctuation-prefix", "+a://x", true},
        {"relative-authority", "//example.com", true},
        {"colon-authority", "a://:x", true},
        {"no-break-space-authority", "a://\u00A0", true},
        {"ideographic-space-authority", "//\u3000", true},
        {"no-letter", "123+.-://x", false},
        {"no-scheme", "://x", false},
        {"empty-authority", "a://", false},
        {"fragment-authority", "a://#x", false},
        {"path-authority", "a:///x", false},
        {"repeated-delimiters", "a://#b://?c://", false}
      ] do
    expected =
      if denied,
        do: %{"verdict" => "invalid", "code" => "forbidden_portable_value"},
        else: %{"verdict" => "valid", "clean" => true}

    %{
      "id" => "portability-network-" <> name,
      "surface" => "portability.scan",
      "class" => if(denied, do: "forbidden_portable_value", else: "valid"),
      "input" => %{"text" => CorpusGen.json_text!(text)},
      "expected" => expected
    }
  end

# Dictionary keys retain their data meaning even when they share built-in names.
recovery_name_cases =
  for name <- prototype_names do
    {:ok, blueprint} =
      BlueprintFixture.fixture_bytes(
        capabilities: [BlueprintFixture.capability(family: name, kind: "mutation")]
      )
      |> Blueprint.decode()

    text =
      DeploymentFixture.fixture_bytes(
        blueprint: blueprint,
        tool_bindings: [DeploymentFixture.tool_binding(operation: name)],
        effect_owner: DeploymentFixture.effect_owner(recovery: "none")
      )

    %{
      "id" => "deployment-decode-mutation-name-" <> name,
      "surface" => "deployment.decode",
      "class" => "invalid_constraint",
      "input" => %{
        "text" => text,
        "binding" => %{
          "blueprint" =>
            BlueprintFixture.fixture_bytes(
              capabilities: [BlueprintFixture.capability(family: name, kind: "mutation")]
            )
        }
      },
      "expected" => %{"verdict" => "invalid", "code" => "no_authoritative_recovery"}
    }
  end

# Predicate grammar carries authored content through every boolean operand.
predicate_content_cases =
  for {name, predicate} <- [
        {"and-value",
         {:object,
          [
            {"op", {:string, "and"}},
            {"args",
             {:array,
              [
                {:object,
                 [
                   {"op", {:string, "eq"}},
                   {"path", BlueprintFixture.path(["request"])},
                   {"value", {:string, "https://example.com/token"}}
                 ]}
              ]}}
          ]}},
        {"or-values",
         {:object,
          [
            {"op", {:string, "or"}},
            {"args",
             {:array,
              [
                {:object,
                 [
                   {"op", {:string, "in"}},
                   {"path", BlueprintFixture.path(["request"])},
                   {"values", {:array, [{:string, "https://example.com/token"}]}}
                 ]}
              ]}}
          ]}},
        {"not-value",
         {:object,
          [
            {"op", {:string, "not"}},
            {"args",
             {:array,
              [
                {:object,
                 [
                   {"op", {:string, "eq"}},
                   {"path", BlueprintFixture.path(["request"])},
                   {"value", {:string, "https://example.com/token"}}
                 ]}
              ]}}
          ]}},
        {"path-segment",
         {:object,
          [
            {"op", {:string, "present"}},
            {"path", BlueprintFixture.path(["request", "https://example.com/token"])}
          ]}}
      ] do
    assertion = BlueprintFixture.assertion(kind: "deterministic_predicate", predicate: predicate)

    %{
      "id" => "blueprint-decode-predicate-" <> name,
      "surface" => "blueprint.decode",
      "class" => "forbidden_portable_value",
      "input" => %{"text" => BlueprintFixture.fixture_bytes(assertions: [assertion])},
      "expected" => %{"verdict" => "invalid", "code" => "forbidden_portable_value"}
    }
  end

signature_key_scan_cases =
  for {kind, fixture, attrs} <- [
        {"blueprint", BlueprintFixture, BlueprintFixture.signature_attrs()},
        {"deployment", DeploymentFixture, DeploymentFixture.signature_attrs()}
      ],
      position <- [0, 1] do
    entry = fn kid ->
      {:object, fields} = attrs
      attrs = {:object, List.keyreplace(fields, "key_id", 0, {"key_id", {:string, kid}})}

      BlueprintFixture.signature_entry(
        header: BlueprintFixture.signature_header(kid),
        attrs: attrs,
        signature: {:string, CorpusGen.b64(<<0::512>>)}
      )
    end

    entries = List.insert_at([entry.("example-key")], position, entry.("https://example/token"))
    value = fixture.fixture_value(extra_members: [{"signatures", {:array, entries}}])

    %{
      "id" => kind <> "-decode-signature-key-position-" <> Integer.to_string(position),
      "surface" => kind <> ".decode",
      "class" => "forbidden_portable_value",
      "input" => %{"text" => CorpusGen.json_text!(value)},
      "expected" => %{"verdict" => "invalid", "code" => "forbidden_portable_value"}
    }
  end

# New signing fixtures derive from one fixed, obviously test-only seed.
# Existing case signatures are preserved below; new fixtures regenerate from arithmetic.
fixture_label = "agent-blueprint-protocol/obviously-test-only-ed25519-fixture-seed"

{alias_entry, alias_pub} =
  CorpusGen.signature_entry(fixture_label, "example-signing-key", sig_digest, "Ed25519")

alias_keys = [%{"key_id" => "example-signing-key", "key" => CorpusGen.b64(alias_pub)}]

{eddsa_entry, ^alias_pub} =
  CorpusGen.signature_entry(fixture_label, "example-signing-key", sig_digest, "EdDSA")

algorithm_cases =
  for {label, text, expected} <-
        [
          {"eddsa", eddsa_entry, %{"verdict" => "valid", "verified" => true}},
          {"ed25519", alias_entry, %{"verdict" => "valid", "verified" => true}}
        ] ++
          for(
            alg <- ["ed25519", "EDDSA", "Ed448", "unknown"],
            do:
              {"unsupported-" <> alg,
               String.replace(alias_entry, "\"alg\":\"Ed25519\"", "\"alg\":\"#{alg}\""),
               %{"verdict" => "invalid", "code" => "signature_algorithm_unsupported"}}
          ) ++
          [
            {"header-substitution",
             String.replace(eddsa_entry, "\"alg\":\"EdDSA\"", "\"alg\":\"Ed25519\""),
             %{"verdict" => "invalid", "code" => "signature_not_verified"}},
            {"reverse-header-substitution",
             String.replace(alias_entry, "\"alg\":\"Ed25519\"", "\"alg\":\"EdDSA\""),
             %{"verdict" => "invalid", "code" => "signature_not_verified"}}
          ] do
    %{
      "id" => "signature-algorithm-" <> label,
      "surface" => "signature.verify",
      "class" => if(expected["verdict"] == "valid", do: "valid", else: "signature_invalid"),
      "input" => %{"entry" => text, "keys" => alias_keys},
      "expected" => expected
    }
    |> strict_expectation.()
  end

dotted_key_cases =
  for alg <- ["EdDSA", "Ed25519"],
      {label, kid} <- [
        {"named", "example.prod.2026"},
        {"period", "."},
        {"repeated", "example..key."}
      ] do
    {text, pub} = CorpusGen.signature_entry(fixture_label, kid, sig_digest, alg)
    keys = [%{"key_id" => kid, "key" => CorpusGen.b64(pub)}]

    %{
      "id" => "signature-dotted-key-" <> alg <> "-" <> label,
      "surface" => "signature.verify",
      "class" => "valid",
      "input" => %{"entry" => text, "keys" => keys},
      "expected" => %{"verdict" => "valid", "verified" => true}
    }
    |> strict_expectation.()
  end

{dotted_entry, dotted_pub} =
  CorpusGen.signature_entry(fixture_label, "example.prod.2026", sig_digest, "Ed25519")

dotted_denial_cases =
  for {label, text, keys, code} <- [
        {"empty", String.replace(dotted_entry, "example.prod.2026", ""), [],
         "signature_malformed"},
        {"non-string",
         String.replace(dotted_entry, ~s("key_id":"example.prod.2026"), ~s("key_id":7)), [],
         "signature_malformed"},
        {"mismatch",
         String.replace(dotted_entry, ~s("kid":"example.prod.2026"), ~s("kid":"other.key")), [],
         "signature_malformed"},
        {"missing-key", dotted_entry, [], "signature_key_unsupported"},
        {"changed-label", String.replace(dotted_entry, "example.prod.2026", "example.prod.2027"),
         [%{"key_id" => "example.prod.2027", "key" => CorpusGen.b64(dotted_pub)}],
         "signature_not_verified"}
      ] do
    %{
      "id" => "signature-dotted-key-" <> label,
      "surface" => "signature.verify",
      "class" => "signature_invalid",
      "input" => %{"entry" => text, "keys" => keys},
      "expected" => %{"verdict" => "invalid", "code" => code}
    }
    |> strict_expectation.()
  end

# Let T=(0,p-1), an order-two point, and a be the test seed's clamped scalar.
# A=[a]B (+T for a mixed key), R=[r]B (+T for mixed R), k=H(R||A||M) mod L,
# S=r+k*a mod L. The prime-order components cancel exactly. The residual
# torsion is T_R+[k]T_A: multiplying by 8 erases it, while the cofactorless
# equation rejects it unless it is zero. These points are NOT small-order.
{:ok, mixed_template} = Json.decode(alias_entry)
{:ok, mixed_message} = Signature.signing_input(mixed_template)
seed = :crypto.hash(:sha256, fixture_label)
a = StrictFixture.secret_scalar(seed)
b = StrictFixture.base_point()
t = {0, StrictFixture.p() - 1}
prime_a = StrictFixture.scalar_mult(a, b)

mixed_cases =
  for {label, mixed_key?, mixed_r?, parity, expected} <- [
        {"key", true, false, 1, false},
        {"r", false, true, nil, false},
        {"both-valid", true, true, 1, true},
        {"both-invalid", true, true, 0, false}
      ] do
    public_point = if mixed_key?, do: StrictFixture.add(prime_a, t), else: prime_a
    public = StrictFixture.encode_point(public_point)

    {r, r_point, k} =
      Enum.find_value(1..100, fn r ->
        prime_r = StrictFixture.scalar_mult(r, b)
        rp = if mixed_r?, do: StrictFixture.add(prime_r, t), else: prime_r
        k = StrictFixture.challenge(StrictFixture.encode_point(rp), public, mixed_message)
        if parity == nil or rem(k, 2) == parity, do: {r, rp, k}
      end)

    scalar = rem(r + k * a, StrictFixture.l())
    lhs = StrictFixture.scalar_mult(scalar, b)
    rhs = StrictFixture.add(r_point, StrictFixture.scalar_mult(k, public_point))
    true = StrictFixture.scalar_mult(8, lhs) == StrictFixture.scalar_mult(8, rhs)
    ^expected = lhs == rhs
    signature = StrictFixture.encode_point(r_point) <> <<scalar::little-unsigned-256>>
    true = StrictFixture.strict_point?(public)
    true = StrictFixture.strict_signature?(signature)
    ^expected = :crypto.verify(:eddsa, :none, mixed_message, signature, [public, :ed25519])
    entry = CorpusGen.put_path(mixed_template, ["signature"], {:string, CorpusGen.b64(signature)})

    %{
      "id" => "signature-mixed-order-" <> label,
      "surface" => "signature.verify",
      "class" => if(expected, do: "valid", else: "signature_invalid"),
      "input" => %{
        "entry" => CorpusGen.json_text!(entry),
        "keys" => [%{"key_id" => "example-signing-key", "key" => CorpusGen.b64(public)}]
      },
      "expected" =>
        if(expected,
          do: %{"verdict" => "valid", "verified" => true, "strict_signature" => true},
          else: %{
            "verdict" => "invalid",
            "code" => "signature_not_verified",
            "strict_signature" => true
          }
        )
    }
  end

duplicate_signer_cases =
  for {kind, fixture} <- [{"blueprint", BlueprintFixture}, {"deployment", DeploymentFixture}] do
    entry = fixture.signature_entry()
    value = fixture.fixture_value(extra_members: [{"signatures", {:array, [entry, entry]}}])

    %{
      "id" => kind <> "-decode-duplicate-signers",
      "surface" => kind <> ".decode",
      "class" => "invalid_constraint",
      "input" => %{"text" => CorpusGen.json_text!(value)},
      "expected" => %{"verdict" => "invalid", "code" => "invalid_constraint"}
    }
  end

impact_case = %{
  "id" => "intersect-effect-impact-is-obligation",
  "surface" => "bounds_algebra.intersect",
  "class" => "valid",
  "input" => %{
    "blueprint" => Map.put(narrow_bounds, "effect_impact_ceiling", "secret"),
    "deployment" => narrow_bounds,
    "host" => narrow_bounds,
    "protected_clamp" => "deny"
  },
  "expected" => %{
    "verdict" => "valid",
    "clamp_count" => 0,
    "effective" => Map.put(narrow_bounds, "effect_impact_ceiling", "secret")
  }
}

# Both registered spellings carry identical schema pins. New producers use the controlled namespace.
namespace_cases =
  for namespace <- ["com.example/federation", "io.github.baselabs/federation"] do
    %{
      "id" =>
        "extension-federation-" <>
          if(namespace == "com.example/federation", do: "deprecated", else: "active"),
      "surface" => "extension.resolve",
      "class" => "valid",
      "input" => %{
        "artifact" =>
          Map.put(base_artifact, "extensions", %{
            "critical" => %{namespace => %{"issuer" => "org-a"}},
            "optional" => %{}
          }),
        "support" => %{
          "revisions" => [1],
          "schemas" => %{namespace => CorpusGen.plain(ExtensionRegistry.federation_schema())}
        }
      },
      "expected" => %{
        "verdict" => "valid",
        "critical" => [namespace],
        "notices" =>
          if(namespace == "com.example/federation", do: ["extension_deprecated"], else: [])
      }
    }
  end

{:ok, carrier_envelope} = Federation.from_value(FederationFixture.value(checkpoint: true))

carrier_cases =
  for {lane, encoder, member, current, legacy} <- [
        {"a2a", &Federation.to_a2a_carrier/1, "metadata", Federation.a2a_carrier_key(),
         "https://example.com/extensions/federation"},
        {"mcp", &Federation.to_mcp_carrier/1, "_meta", Federation.mcp_carrier_key(),
         "com.example/federation"}
      ],
      variant <- [:current, :legacy, :both] do
    {:ok, carrier} = encoder.(carrier_envelope)
    plain = CorpusGen.plain(carrier)
    body = plain[member][current]

    region =
      case variant do
        :current -> %{current => body}
        :legacy -> %{legacy => body}
        :both -> %{current => body, legacy => body}
      end

    %{
      "id" => "federation-carrier-" <> lane <> "-" <> Atom.to_string(variant),
      "surface" => "federation.decode",
      "class" => if(variant == :both, do: "invalid_constraint", else: "valid"),
      "input" => %{("from_" <> lane <> "_carrier") => Map.put(plain, member, region)},
      "expected" =>
        if(variant == :both,
          do: %{"verdict" => "invalid", "code" => "federation_mapping_conflict"},
          else: %{"verdict" => "valid", "decoded" => true}
        )
    }
  end

carrier_native_member_cases =
  for {lane, encoder, member, key} <- [
        {"a2a", &Federation.to_a2a_carrier/1, "metadata", Federation.a2a_carrier_key()},
        {"mcp", &Federation.to_mcp_carrier/1, "_meta", Federation.mcp_carrier_key()}
      ],
      native <- ["task_identity", "terminal_state", "recovery_handle", "checkpoint_status"] do
    {:ok, carrier} = encoder.(carrier_envelope)
    plain = CorpusGen.plain(carrier)
    body = Map.put(plain[member][key], native, "example-native")

    %{
      "id" => "federation-carrier-" <> lane <> "-body-" <> native,
      "surface" => "federation.decode",
      "class" => "invalid_constraint",
      "input" => %{("from_" <> lane <> "_carrier") => put_in(plain, [member, key], body)},
      "expected" => %{"verdict" => "invalid", "code" => "federation_mapping_conflict"}
    }
  end

all_cases =
  json_cases ++
    canonicalization_cases ++
    base64url_cases ++
    digest_cases ++
    signature_cases ++
    schema_cases ++
    blueprint_cases ++
    deployment_cases ++
    negotiation_cases ++
    extension_cases ++
    bounds_cases ++
    intersect_cases ++
    portability_cases ++
    compatibility_cases ++
    federation_decode_cases ++
    verify_commitment_cases ++
    unicode_escape_cases ++
    predicate_operator_cases ++
    unknown_state_cases ++
    unknown_bound_cases ++
    unknown_algebra_cases ++
    uri_boundary_cases ++
    recovery_name_cases ++
    predicate_content_cases ++
    signature_key_scan_cases ++
    algorithm_cases ++
    dotted_key_cases ++
    dotted_denial_cases ++
    mixed_cases ++
    duplicate_signer_cases ++
    [impact_case] ++
    namespace_cases ++
    carrier_cases ++
    carrier_native_member_cases

# Every artifact signature position accepts the same protected-header identifiers.
artifact_algorithm_cases =
  for {kind, fixture, digest_member} <- [
        {"blueprint", BlueprintFixture, "content_digest"},
        {"deployment", DeploymentFixture, "deployment_digest"}
      ],
      alg <- ["EdDSA", "Ed25519", "Ed448"] do
    value = fixture.fixture_value()
    digest = CorpusGen.member_string(value, digest_member)

    {text, _public} =
      CorpusGen.signature_entry(fixture_label, "example-signing-key", digest, alg, kind)

    {:ok, entry} = Json.decode(text)
    {:object, members} = value
    value = {:object, [{"signatures", {:array, [entry]}} | members]}

    %{
      "id" => kind <> "-decode-header-" <> alg,
      "surface" => kind <> ".decode",
      "class" => if(alg == "Ed448", do: "signature_invalid", else: "valid"),
      "input" => %{"text" => CorpusGen.json_text!(value)},
      "expected" =>
        if(alg == "Ed448",
          do: %{"verdict" => "invalid", "code" => "signature_algorithm_unsupported"},
          else: %{"verdict" => "valid", "digest" => digest}
        )
    }
  end

receipt_algorithm_cases =
  for alg <- ["EdDSA", "Ed25519", "Ed448"],
      surface <- ["federation.decode", "federation.verify_commitment"] do
    {text, public, _commitment} =
      CorpusGen.signed_receipt(fixture_label, "example-signing-key", alg)

    input =
      if(surface == "federation.decode",
        do: %{"text" => text},
        else: %{
          "envelope" => text,
          "context" => %{
            "keys" => [%{"key_id" => "example-signing-key", "key" => CorpusGen.b64(public)}],
            "created_after" => "2026-08-22T00:00:00Z",
            "created_before" => "2026-08-24T00:00:00Z"
          }
        }
      )

    %{
      "id" => String.replace(surface, ".", "-") <> "-header-" <> alg,
      "surface" => surface,
      "class" => if(alg == "Ed448", do: "signature_invalid", else: "valid"),
      "input" => input,
      "expected" =>
        cond do
          alg == "Ed448" -> %{"verdict" => "invalid", "code" => "invalid_constraint"}
          surface == "federation.decode" -> %{"verdict" => "valid", "canonical" => text}
          true -> %{"verdict" => "valid", "task_identity" => "task-7f3a2c"}
        end
    }
  end

all_cases = all_cases ++ artifact_algorithm_cases ++ receipt_algorithm_cases

# Byte error precedence and conformance input projection are shared across surfaces.
precedence_cases =
  for {label, text, bounds, code} <- [
        {"trailing-close", "[[[1]]]]", %{"depth" => 4}, "trailing_bytes"},
        {"truncated-depth", "[[[[[", %{"depth" => 4}, "invalid_syntax"},
        {"truncated-window-array", "[29514790517935283", %{}, "invalid_syntax"},
        {"truncated-window-object", "{\"x\":29514790517935283", %{}, "invalid_syntax"},
        {"invalid-window-delimiter", "[29514790517935283x]", %{}, "invalid_syntax"},
        {"truncated-overflow", "[1e999", %{}, "invalid_syntax"},
        {"window-before-tail", "[29514790517935283]]", %{}, "number_not_double_expressible"},
        {"root-tail-before-window", "29514790517935283]", %{}, "trailing_bytes"},
        {"root-tail-before-nodes", "1]", %{"nodes" => 1}, "trailing_bytes"}
      ],
      surface <- ["json.decode", "canonicalization.encode"] do
    %{
      "id" => String.replace(surface, ".", "-") <> "-precedence-" <> label,
      "surface" => surface,
      "class" => "invalid_encoding",
      "input" => %{"text" => text, "bounds" => bounds},
      "expected" => %{"verdict" => "invalid", "code" => code}
    }
  end

empty_base64_cases =
  for surface <- ["json.decode", "canonicalization.encode"] do
    %{
      "id" => String.replace(surface, ".", "-") <> "-empty-base64-input",
      "surface" => surface,
      "class" => "invalid_encoding",
      "input" => %{"base64url" => ""},
      "expected" => %{"verdict" => "invalid", "code" => "invalid_syntax"}
    }
  end

null_bounds_cases =
  for {surface, text, expected} <- [
        {"json.decode", "null", %{"verdict" => "valid", "value" => nil}},
        {"canonicalization.encode", "null", %{"verdict" => "valid", "encoded" => "null"}},
        {"blueprint.decode", golden_blueprint, hd(blueprint_cases)["expected"]},
        {"deployment.decode", golden_deployment, hd(deployment_cases)["expected"]},
        {"federation.decode", CorpusGen.json_text!(FederationFixture.value()),
         %{"verdict" => "valid", "canonical" => CorpusGen.json_text!(FederationFixture.value())}}
      ] do
    %{
      "id" => String.replace(surface, ".", "-") <> "-null-bounds",
      "surface" => surface,
      "class" => "valid",
      "input" => %{"text" => text, "bounds" => nil},
      "expected" => expected
    }
  end

input_projection_cases =
  for {surface, input, expected} <- [
        {"schema.validate_instance", %{"schema" => %{}, "instance" => nil},
         %{"verdict" => "valid", "valid" => true}},
        {"schema.validate_instance", %{"schema" => %{}, "instance" => 1, "dialect" => false},
         %{"verdict" => "invalid", "code" => "invalid_type"}},
        {"bounds.new", %{"bounds" => nil},
         %{
           "verdict" => "valid",
           "bounds" =>
             Map.new(Map.from_struct(AgentBlueprintProtocol.Bounds.maximum()), fn {k, v} ->
               {Atom.to_string(k), v}
             end)
         }}
      ] do
    %{
      "id" =>
        String.replace(surface, ".", "-") <>
          "-input-projection-" <> if(expected["verdict"] == "valid", do: "valid", else: "type"),
      "surface" => surface,
      "class" => if(expected["verdict"] == "valid", do: "valid", else: "invalid_type"),
      "input" => input,
      "expected" => expected
    }
  end

binding_type_cases =
  for {label, wrong} <- [
        {"null", nil},
        {"false", false},
        {"number", 0},
        {"string", ""},
        {"array", []}
      ] do
    %{
      "id" => "deployment-decode-binding-type-" <> label,
      "surface" => "deployment.decode",
      "class" => "invalid_type",
      "input" => %{"text" => golden_deployment, "binding" => wrong},
      "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
    }
  end

support_type_cases =
  for surface <- ["negotiation.negotiate", "extension.resolve"],
      field <- ["revisions", "core_fields", "registry", "schemas"],
      {label, wrong} <- [
        {"null", nil},
        {"false", false},
        {"number", 0},
        {"string", ""},
        {"collection", if(field in ["revisions", "core_fields"], do: %{}, else: [])}
      ] do
    %{
      "id" => String.replace(surface, ".", "-") <> "-support-type-" <> field <> "-" <> label,
      "surface" => surface,
      "class" => "invalid_type",
      "input" => %{"artifact" => base_artifact, "support" => %{field => wrong}},
      "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
    }
  end

marker_type_cases =
  for role <- ["blueprint", "deployment", "host"],
      {label, wrong} <- [
        {"null", nil},
        {"false", false},
        {"number", 0},
        {"string", ""},
        {"object", %{}}
      ] do
    source =
      Map.put(narrow_bounds, "classification_ceiling", %{
        "ordinal" => "internal",
        "markers" => wrong
      })

    %{
      "id" => "intersect-marker-type-" <> role <> "-" <> label,
      "surface" => "bounds_algebra.intersect",
      "class" => "invalid_constraint",
      "input" =>
        Map.put(
          %{"blueprint" => narrow_bounds, "deployment" => narrow_bounds, "host" => narrow_bounds},
          role,
          source
        ),
      "expected" => %{"verdict" => "invalid", "code" => "bound_value_invalid"}
    }
  end

notice_projection_cases =
  for surface <- ["negotiation.negotiate", "extension.resolve"] do
    %{
      "id" => String.replace(surface, ".", "-") <> "-deprecated-optional-notice",
      "surface" => surface,
      "class" => "valid",
      "input" => %{
        "artifact" =>
          Map.put(base_artifact, "extensions", %{
            "critical" => %{},
            "optional" => %{"com.example.vendor/legacy" => %{"label" => "archive"}}
          }),
        "support" => legacy_support
      },
      "expected" => %{"verdict" => "valid", "notices" => ["extension_deprecated"]}
    }
  end

negotiation_namespace_cases =
  Enum.map(namespace_cases, fn c ->
    %{
      c
      | "id" => String.replace(c["id"], "extension-", "negotiation-"),
        "surface" => "negotiation.negotiate"
    }
  end)

all_cases =
  all_cases ++
    precedence_cases ++
    empty_base64_cases ++
    null_bounds_cases ++
    input_projection_cases ++
    binding_type_cases ++
    support_type_cases ++
    marker_type_cases ++
    notice_projection_cases ++ negotiation_namespace_cases

receiving_type_cases =
  for base <- receipt_algorithm_cases,
      base["surface"] == "federation.verify_commitment",
      base["class"] == "valid",
      field <- ["created_after", "created_before"],
      {label, wrong} <- [{"false", false}, {"number", 0}, {"array", []}, {"object", %{}}] do
    input = put_in(base["input"], ["context", field], wrong)

    %{
      base
      | "id" => base["id"] <> "-" <> field <> "-" <> label,
        "class" => "invalid_type",
        "input" => input,
        "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
    }
  end

binding_age_type_cases =
  for {field, label, wrong} <-
        [{"now", "false", false}] ++
          for(
            {label, wrong} <- [{"false", false}, {"string", ""}, {"array", []}, {"object", %{}}],
            do: {"max_attestation_age_ms", label, wrong}
          ) do
    binding =
      Map.put(
        %{
          "blueprint" => golden_blueprint,
          "now" => "2026-08-21T00:00:00Z",
          "max_attestation_age_ms" => 86_400_000
        },
        field,
        wrong
      )

    %{
      "id" => "deployment-binding-type-" <> field <> "-" <> label,
      "surface" => "deployment.decode",
      "class" => "invalid_type",
      "input" => %{"text" => golden_deployment, "binding" => binding},
      "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
    }
  end

all_cases = all_cases ++ receiving_type_cases ++ binding_age_type_cases

source_precedence_cases =
  for base <- marker_type_cases,
      earlier =
        Enum.find(["blueprint", "deployment", "host"], fn role ->
          base["input"][role]["classification_ceiling"]["markers"] != []
        end),
      later <-
        (case earlier do
           "blueprint" -> ["deployment", "host"]
           "deployment" -> ["host"]
           "host" -> []
         end),
      {label, wrong} <- [
        {"null", nil},
        {"false", false},
        {"number", 0},
        {"string", ""},
        {"array", []}
      ] do
    %{
      base
      | "id" => base["id"] <> "-before-" <> later <> "-" <> label,
        "input" => Map.put(base["input"], later, wrong)
    }
  end

all_cases = all_cases ++ source_precedence_cases

artifact_purpose_cases =
  for {kind, fixture, digest_member} <- [
        {"blueprint", BlueprintFixture, "content_digest"},
        {"deployment", DeploymentFixture, "deployment_digest"}
      ],
      alg <- ["EdDSA", "Ed25519"],
      purpose <- ["blueprint", "deployment", "federation-envelope", "unknown"],
      purpose != kind do
    value = fixture.fixture_value()
    digest = CorpusGen.member_string(value, digest_member)

    {text, _public} =
      CorpusGen.signature_entry(fixture_label, "example-signing-key", digest, alg, purpose)

    {:ok, entry} = Json.decode(text)
    {:object, members} = value
    value = {:object, [{"signatures", {:array, [entry]}} | members]}

    %{
      "id" => kind <> "-decode-purpose-" <> alg <> "-" <> purpose,
      "surface" => kind <> ".decode",
      "class" => "invalid_constraint",
      "input" => %{"text" => CorpusGen.json_text!(value)},
      "expected" => %{
        "verdict" => "invalid",
        "code" => if(purpose == "unknown", do: "signature_malformed", else: "invalid_constraint")
      }
    }
  end

receipt_purpose_cases =
  for alg <- ["EdDSA", "Ed25519"],
      purpose <- ["blueprint", "deployment", "unknown"],
      surface <- ["federation.decode", "federation.verify_commitment"] do
    {text, public, _commitment} =
      CorpusGen.signed_receipt(fixture_label, "example-signing-key", alg, purpose)

    valid? = surface == "federation.decode" and purpose != "unknown"

    %{
      "id" => String.replace(surface, ".", "-") <> "-purpose-" <> alg <> "-" <> purpose,
      "surface" => surface,
      "class" => if(valid?, do: "valid", else: "invalid_constraint"),
      "input" =>
        if(surface == "federation.decode",
          do: %{"text" => text},
          else: %{
            "envelope" => text,
            "context" => %{
              "keys" => [%{"key_id" => "example-signing-key", "key" => CorpusGen.b64(public)}]
            }
          }
        ),
      "expected" =>
        if(valid?,
          do: %{"verdict" => "valid", "canonical" => text},
          else: %{"verdict" => "invalid", "code" => "invalid_constraint"}
        )
    }
  end

closed_purpose_cases =
  for alg <- ["EdDSA", "Ed25519"] do
    {text, public} =
      CorpusGen.signature_entry(fixture_label, "example-signing-key", sig_digest, alg, "unknown")

    %{
      "id" => "signature-closed-purpose-" <> alg,
      "surface" => "signature.verify",
      "class" => "invalid_constraint",
      "input" => %{
        "entry" => text,
        "keys" => [%{"key_id" => "example-signing-key", "key" => CorpusGen.b64(public)}]
      },
      "expected" => %{"verdict" => "invalid", "code" => "signature_malformed"}
    }
  end

all_cases = all_cases ++ artifact_purpose_cases ++ receipt_purpose_cases ++ closed_purpose_cases

# The composed import and predicate surfaces use the same immutable fixture seed.
defmodule ImportCases do
  alias AgentBlueprintProtocol.{BlueprintFixture, DeploymentFixture, Digest}

  def redigest(map, domain, field) do
    input = Map.drop(map, [field, "signatures", "attestations"])
    Map.put(map, field, CorpusGen.tagged_digest(domain, CorpusGen.json_text!(input)))
  end

  def expectation(bp, dep, host) do
    check = fn surface, subject, verified, detail ->
      %{"surface" => surface, "subject" => [subject], "verified" => verified, "detail" => detail}
    end

    basic = fn surface ->
      for name <- ["blueprint", "deployment"], do: check.(surface, name, true, nil)
    end

    signatures =
      for {name, value} <- [{"blueprint", bp}, {"deployment", dep}] do
        entries = Map.get(value, "signatures", [])

        check.(
          "signatures",
          name,
          entries != [],
          if(entries == [],
            do: "no_signatures_present",
            else: %{"key_ids" => Enum.map(entries, & &1["signed_attributes"]["key_id"])}
          )
        )
      end

    bindings = dep["tool_bindings"]
    observations = Map.get(host, "observations", %{})

    staleness =
      bindings != [] and observations["now"] != nil and
        observations["max_attestation_age_ms"] != nil

    descriptors =
      bindings != [] and
        Enum.all?(
          bindings,
          &Map.has_key?(Map.get(observations, "observed", %{}), &1["logical_operation"])
        )

    gates = [{"binding_staleness", staleness}, {"binding_descriptors", descriptors}]
    skipped = for {name, false} <- gates, do: name

    bind_detail = %{
      "checked" =>
        ["release_binding", "binding_completeness", "effect_recovery"] ++
          for({name, true} <- gates, do: name),
      "not_verified" => skipped
    }

    effective =
      Map.put(dep["host_bounds"], "classification_ceiling", %{
        "ordinal" => "internal",
        "markers" => []
      })

    clamps =
      if dep["host_bounds"]["disclosure_ceiling"] == "full",
        do: [],
        else: [
          %{
            "field" => "disclosure_ceiling",
            "class" => "protected",
            "unit" => "ordinal",
            "requested" => "full",
            "effective" => "summary",
            "source" => "deployment",
            "acknowledged" => true
          }
        ]

    optional =
      for artifact <- [bp, dep], do: Map.keys(artifact["extensions"]["optional"]) |> Enum.sort()

    retained =
      optional |> List.flatten() |> Enum.reject(&(&1 == "com.example.z/y")) |> Enum.uniq()

    extension_checks =
      for namespaces <- optional,
          ns <- namespaces,
          do:
            check.(
              "extensions",
              ns,
              false,
              if(ns == "com.example.z/y", do: "quarantined", else: "retained")
            )

    checks =
      basic.("canonical") ++
        [
          check.("digest", "blueprint", true, bp["content_digest"]),
          check.("digest", "deployment", true, dep["deployment_digest"])
        ] ++
        basic.("negotiation") ++
        extension_checks ++
        basic.("structure") ++
        basic.("portability") ++
        signatures ++
        [
          check.("bind", "deployment", skipped == [], bind_detail),
          check.("bounds", "bounds", true, nil)
        ] ++ Enum.map(clamps, &check.("bounds", &1["field"], true, &1))

    unchecked =
      [
        "tenancy",
        "live_policy",
        "authority",
        "effect_ownership",
        "execution",
        "billing",
        "evaluation_truth",
        "signature_created_at",
        "lifecycle_state"
      ] ++ for(c <- checks, c["verified"] == false, do: c["surface"]) ++ skipped

    %{
      "verdict" => "valid",
      "evidence" => %{
        "protocol_revision" => 1,
        "blueprint_digest" => bp["content_digest"],
        "deployment_digest" => dep["deployment_digest"],
        "checks" => checks,
        "effective_bounds" => effective,
        "clamps" => clamps,
        "optional_extensions_retained" => retained,
        "not_verified" => Enum.uniq(unchecked)
      }
    }
  end

  def cases do
    bp = BlueprintFixture.fixture_value() |> CorpusGen.plain()
    dep = DeploymentFixture.fixture_value() |> CorpusGen.plain()

    dep =
      put_in(dep, ["host_bounds", "disclosure_ceiling"], "full")
      |> redigest(:deployment_content, "deployment_digest")

    host = %{
      "host_bounds" =>
        Map.put(dep["host_bounds"], "classification_ceiling", %{
          "ordinal" => "internal",
          "markers" => []
        }),
      "support" => %{},
      "keys" => [],
      "protected_clamp" => "deny",
      "observations" => %{}
    }

    row = fn id, class, b, d, h, expected ->
      %{
        "id" => "reconcile-" <> id,
        "surface" => "reconcile",
        "class" => class,
        "input" => %{
          "blueprint" => CorpusGen.json_text!(b),
          "deployment" => CorpusGen.json_text!(d),
          "inputs" => h
        },
        "expected" => expected
      }
    end

    deny = fn code, subject -> %{"verdict" => "invalid", "code" => code, "subject" => subject} end
    honest = fn b -> redigest(b, :blueprint_content, "content_digest") end

    stale_host =
      Map.put(host, "observations", %{
        "now" => "2026-08-21T00:00:00Z",
        "max_attestation_age_ms" => 1
      })

    partial_host =
      Map.put(host, "observations", %{"now" => "2026-08-20T00:00:00Z", "observed" => %{}})

    full_host =
      Map.put(host, "observations", %{
        "now" => "2026-08-20T00:00:00Z",
        "max_attestation_age_ms" => 1,
        "observed" =>
          Map.new(dep["tool_bindings"], &{&1["logical_operation"], &1["descriptor_digest"]})
      })

    clamped =
      put_in(dep, ["host_bounds", "disclosure_ceiling"], "summary")
      |> redigest(:deployment_content, "deployment_digest")

    optional =
      put_in(bp, ["extensions", "optional"], %{
        "com.example.vendor/legacy" => %{"label" => "example"}
      })
      |> honest.()

    optional_host =
      put_in(host, ["support", "registry"], %{
        "com.example.vendor/legacy" => %{
          "owner" => "ExampleVendor",
          "criticality" => "optional",
          "state" => "deprecated"
        }
      })

    optional_dep =
      put_in(dep, ["blueprint_release", "content_digest"], optional["content_digest"])
      |> redigest(:deployment_content, "deployment_digest")

    signed =
      for algorithm <- ["EdDSA", "Ed25519"] do
        {text, pub} =
          CorpusGen.signature_entry(
            "example conformance import seed",
            "example-import-key",
            bp["content_digest"],
            algorithm,
            "blueprint"
          )

        entry = :json.decode(text)
        b = Map.put(bp, "signatures", [entry])

        h =
          Map.put(host, "keys", [%{"key_id" => "example-import-key", "key" => CorpusGen.b64(pub)}])

        row.(String.downcase(algorithm), "valid", b, dep, h, expectation(b, dep, h))
      end

    bad_signature =
      signed
      |> hd()
      |> get_in(["input", "blueprint"])
      |> :json.decode()
      |> put_in(["signatures", Access.at(0), "signature"], CorpusGen.b64(<<0::512>>))

    signed_host = get_in(hd(signed), ["input", "inputs"])

    cases = [
      row.("unsigned", "valid", bp, dep, host, expectation(bp, dep, host)),
      row.(
        "partial-observations",
        "valid",
        bp,
        dep,
        partial_host,
        expectation(bp, dep, partial_host)
      ),
      row.("observed", "valid", bp, dep, full_host, expectation(bp, dep, full_host)),
      row.("root", "invalid_type", nil, dep, host, deny.("invalid_type", ["blueprint"])),
      row.(
        "digest",
        "digest_mismatch",
        put_in(bp, ["ceilings", "max_attempts"], 4),
        dep,
        host,
        deny.("digest_mismatch", ["blueprint"])
      ),
      row.(
        "revision",
        "revision_above_max",
        Map.put(bp, "protocol_revision", 2) |> honest.(),
        dep,
        host,
        deny.("protocol_revision_unsupported", ["blueprint", "protocol_revision"])
      ),
      row.(
        "structure",
        "unknown_member",
        Map.put(bp, "example", true) |> honest.(),
        dep,
        host,
        deny.("unknown_member", ["blueprint"])
      ),
      row.(
        "portability",
        "forbidden_portable_value",
        put_in(bp, ["extensions", "optional"], %{
          "com.example.unknown/data" => %{"api_key" => "example"}
        })
        |> honest.(),
        dep,
        host,
        deny.("forbidden_portable_value", ["blueprint"])
      ),
      row.(
        "signature",
        "signature_invalid",
        bad_signature,
        dep,
        signed_host,
        deny.("signature_not_verified", ["blueprint", "signatures", 0])
      ),
      row.(
        "binding",
        "binding_stale",
        bp,
        dep,
        stale_host,
        deny.("binding_attestation_stale", ["deployment"])
      ),
      row.(
        "protected-deny",
        "bound_widening_protected",
        bp,
        clamped,
        host,
        deny.("protected_bound_clamp_denied", ["disclosure_ceiling"])
      ),
      row.(
        "protected-acknowledge",
        "valid",
        bp,
        clamped,
        Map.put(host, "protected_clamp", "acknowledge"),
        expectation(bp, clamped, Map.put(host, "protected_clamp", "acknowledge"))
      ),
      row.(
        "deprecated-optional",
        "valid",
        optional,
        optional_dep,
        optional_host,
        expectation(optional, optional_dep, optional_host)
      )
    ]

    namespace = "com.example/federation"
    schema = AgentBlueprintProtocol.ExtensionRegistry.federation_schema() |> CorpusGen.plain()

    federated =
      put_in(bp, ["extensions", "critical"], %{
        namespace => %{
          "issuer" => "example.sender",
          "subject" => "example.agent",
          "audience" => "example.receiver"
        }
      })
      |> honest.()

    federated_dep =
      put_in(dep, ["blueprint_release", "content_digest"], federated["content_digest"])
      |> redigest(:deployment_content, "deployment_digest")

    federated_host = Map.put(host, "support", %{"schemas" => %{namespace => schema}})

    deprecated =
      row.(
        "deprecated-federation",
        "valid",
        federated,
        federated_dep,
        federated_host,
        expectation(federated, federated_dep, federated_host)
      )

    notice = %{
      "id" => "negotiation-import-deprecated-federation",
      "surface" => "negotiation.negotiate",
      "class" => "extension_deprecated_retained",
      "input" => %{"artifact" => federated, "support" => federated_host["support"]},
      "expected" => %{
        "verdict" => "valid",
        "revision" => 1,
        "critical" => [namespace],
        "quarantined" => [],
        "notices" => ["extension_deprecated"]
      }
    }

    unknown_optional =
      for side <- ["blueprint", "deployment", "both"] do
        b =
          if side in ["blueprint", "both"],
            do:
              put_in(bp, ["extensions", "optional"], %{"com.example.z/y" => %{"a" => 1}})
              |> honest.(),
            else: bp

        d =
          if side in ["deployment", "both"],
            do: put_in(dep, ["extensions", "optional"], %{"com.example.z/y" => %{"a" => 1}}),
            else: dep

        d =
          put_in(d, ["blueprint_release", "content_digest"], b["content_digest"])
          |> redigest(:deployment_content, "deployment_digest")

        [
          row.(
            "unknown-optional-" <> side,
            "extension_unknown_optional_roundtrip",
            b,
            d,
            host,
            expectation(b, d, host)
          )
          | for {name, artifact} <- [{"blueprint", b}, {"deployment", d}],
                side == "both" or name == side do
              %{
                "id" => "negotiation-unknown-optional-" <> side <> "-" <> name,
                "surface" => "negotiation.negotiate",
                "class" => "extension_unknown_optional_roundtrip",
                "input" => %{"artifact" => artifact, "support" => %{}},
                "expected" => %{
                  "verdict" => "valid",
                  "revision" => 1,
                  "critical" => [],
                  "quarantined" => ["com.example.z/y"],
                  "notices" => ["extension_unknown_optional_retained"]
                }
              }
            end
        ]
      end
      |> List.flatten()

    timestamps =
      for {name, now} <- [
            {"space", "2026-08-20 00:00:00Z"},
            {"fraction", "2026-08-20T00:00:00.1Z"},
            {"offset", "2026-08-20T00:00:00+00:00"},
            {"number", 1},
            {"boolean", true},
            {"object", %{}},
            {"impossible", "2026-02-31T00:00:00Z"},
            {"null", nil},
            {"valid", "2026-08-20T00:00:00Z"}
          ] do
        h = put_in(host, ["observations", "now"], now)
        valid = name in ["null", "valid"]

        row.(
          "now-" <> name,
          if(valid, do: "valid", else: "invalid_type"),
          bp,
          dep,
          h,
          if(valid, do: expectation(bp, dep, h), else: deny.("invalid_type", ["now"]))
        )
      end

    signature_cases =
      for side <- ["blueprint", "deployment"] do
        artifact = if side == "blueprint", do: bp, else: dep
        field = if side == "blueprint", do: "content_digest", else: "deployment_digest"

        {text, _} =
          CorpusGen.signature_entry(
            "example conformance import seed",
            "example-import-key",
            artifact[field],
            "EdDSA",
            side
          )

        entry = :json.decode(text)

        changes =
          for(
            alg <- ["Ed448", "none", "eddsa", "ES256"],
            do: {"alg-" <> alg, ["protected", "alg"], alg, "signature_algorithm_unsupported"}
          ) ++
            [
              {"purpose-unknown", ["signed_attributes", "purpose"], "unknown",
               "signature_malformed"},
              {"purpose-empty", ["signed_attributes", "purpose"], "", "signature_malformed"},
              {"algorithm", ["signed_attributes", "algorithm"], "Ed448",
               "signature_algorithm_unsupported"},
              {"created-text", ["signed_attributes", "created_at"], "yesterday",
               "signature_malformed"},
              {"created-offset", ["signed_attributes", "created_at"], "2026-08-20T00:00:00+00:00",
               "signature_malformed"},
              {"extra-attribute", ["signed_attributes", "extra"], true, "signature_malformed"},
              {"extra-header", ["protected", "extra"], true, "signature_malformed"},
              {"b64", ["protected", "b64"], true, "signature_malformed"},
              {"digest", ["signed_attributes", "content_digest"], "sha-256:bad",
               "signature_malformed"},
              {"kid-key-id-mismatch", ["signed_attributes", "key_id"], "example.forbidden",
               "signature_malformed"}
            ]

        malformed =
          for {name, path, value, code} <- changes do
            changed = Map.put(artifact, "signatures", [put_in(entry, path, value)])
            {b, d} = if side == "blueprint", do: {changed, dep}, else: {bp, changed}

            [
              row.(
                "signature-" <> side <> "-" <> name,
                "invalid_constraint",
                b,
                d,
                signed_host,
                deny.(
                  code,
                  [side, "signatures", 0] ++
                    if(name == "kid-key-id-mismatch", do: [], else: [hd(path)])
                )
              ),
              %{
                "id" => side <> "-decode-signature-" <> name,
                "surface" => side <> ".decode",
                "class" => "invalid_constraint",
                "input" => %{"text" => CorpusGen.json_text!(changed)},
                "expected" => %{"verdict" => "invalid", "code" => code}
              }
            ]
          end

        bad =
          Map.put(artifact, "signatures", [
            put_in(entry, ["signature"], CorpusGen.b64(<<0::512>>))
          ])

        {b, d} = if side == "blueprint", do: {bad, dep}, else: {bp, bad}

        dotted_key = "example.import.key"

        {dotted_text, dotted_pub} =
          CorpusGen.signature_entry(
            "example conformance import seed",
            dotted_key,
            artifact[field],
            "Ed25519",
            side
          )

        dotted_artifact = Map.put(artifact, "signatures", [:json.decode(dotted_text)])

        {dotted_bp, dotted_dep} =
          if side == "blueprint", do: {dotted_artifact, dep}, else: {bp, dotted_artifact}

        dotted_host =
          Map.put(host, "keys", [%{"key_id" => dotted_key, "key" => CorpusGen.b64(dotted_pub)}])

        malformed ++
          [
            row.(
              "signature-" <> side <> "-dotted-key-id",
              "valid",
              dotted_bp,
              dotted_dep,
              dotted_host,
              expectation(dotted_bp, dotted_dep, dotted_host)
            ),
            row.(
              "signature-" <> side <> "-invalid",
              "signature_invalid",
              b,
              d,
              signed_host,
              deny.("signature_not_verified", [side, "signatures", 0])
            )
          ]
      end
      |> List.flatten()

    retired_host =
      put_in(host, ["support", "registry"], %{
        "com.example.vendor/legacy" => %{"criticality" => "optional", "state" => "retired"}
      })

    retired_notice = %{
      "id" => "negotiation-retired-optional-notice",
      "surface" => "negotiation.negotiate",
      "class" => "extension_deprecated_retained",
      "input" => %{"artifact" => optional, "support" => retired_host["support"]},
      "expected" => %{
        "verdict" => "valid",
        "revision" => 1,
        "critical" => [],
        "quarantined" => [],
        "notices" => ["extension_retired"]
      }
    }

    cases ++
      signed ++
      [deprecated, notice, retired_notice] ++ unknown_optional ++ timestamps ++ signature_cases
  end
end

predicate_cases =
  for {name, predicate, expected, class} <-
        [
          {"and", %{"op" => "and", "args" => [%{"op" => "present", "path" => ["request"]}]},
           %{"value" => true}, "valid"},
          {"or",
           %{"op" => "or", "args" => [%{"op" => "absent", "path" => ["request", "missing"]}]},
           %{"value" => true}, "valid"},
          {"not", %{"op" => "not", "args" => [%{"op" => "present", "path" => ["request"]}]},
           %{"value" => false}, "valid"},
          {"in", %{"op" => "in", "path" => ["request", "count"], "values" => [1, 2, 3]},
           %{"value" => true}, "valid"},
          {"present", %{"op" => "present", "path" => ["request"]}, %{"value" => true}, "valid"},
          {"absent", %{"op" => "absent", "path" => ["request", "missing"]}, %{"value" => true},
           "valid"},
          {"arity", %{"op" => "not", "args" => []}, %{"code" => "invalid_cardinality"},
           "invalid_cardinality"},
          {"type", true, %{"code" => "invalid_type"}, "invalid_type"},
          {"unknown", %{"op" => "unknown"}, %{"code" => "predicate_op_unknown"},
           "invalid_constraint"},
          {"exact",
           %{
             "op" => "and",
             "args" => List.duplicate(%{"op" => "present", "path" => ["request"]}, 255)
           }, %{"value" => true}, "exact_bound"},
          {"overflow",
           %{
             "op" => "and",
             "args" => List.duplicate(%{"op" => "present", "path" => ["request"]}, 256)
           }, %{"code" => "predicate_nodes_exceeded"}, "maximum_plus_one"}
        ] ++
          for(
            op <- ["eq", "ne", "lt", "lte", "gt", "gte"],
            do:
              {op, %{"op" => op, "path" => ["request", "count"], "value" => 2},
               %{"value" => op in ["eq", "lte", "gte"]}, "valid"}
          ) ++
          for(
            op <- ["__proto__", "constructor", "toString", "hasOwnProperty"],
            do: {op, %{"op" => op}, %{"code" => "predicate_op_unknown"}, "invalid_constraint"}
          ) do
    verdict = if Map.has_key?(expected, "code"), do: "invalid", else: "valid"

    %{
      "id" => "predicate-" <> name,
      "surface" => "predicate",
      "class" => class,
      "input" => %{
        "mode" => "evaluate",
        "predicate" => predicate,
        "port_names" => ["request"],
        "ports" => %{"request" => %{"count" => 2}}
      },
      "expected" => Map.put(expected, "verdict", verdict)
    }
  end

unicode_case_ids =
  for suffix <- ["Ｚ", "𐀀"] do
    %{
      "id" => "json-decode-order-" <> suffix,
      "surface" => "json.decode",
      "class" => "valid",
      "input" => %{"text" => "null"},
      "expected" => %{"verdict" => "valid", "value" => nil}
    }
  end

absent_root_cases =
  for op <- ~w(present absent eq ne lt lte gt gte in and or not) do
    predicate =
      cond do
        op in ~w(and or not) ->
          %{"op" => op, "args" => [%{"op" => "present", "path" => ["request"]}]}

        op == "in" ->
          %{"op" => op, "path" => ["request"], "values" => [1]}

        op in ~w(present absent) ->
          %{"op" => op, "path" => ["request"]}

        true ->
          %{"op" => op, "path" => ["request"], "value" => 1}
      end

    valid = op in ~w(present absent and or not)

    %{
      "id" => "predicate-absent-root-" <> op,
      "surface" => "predicate",
      "class" => if(valid, do: "valid", else: "invalid_constraint"),
      "input" => %{
        "mode" => "evaluate",
        "port_names" => ["request"],
        "ports" => %{},
        "predicate" => predicate
      },
      "expected" =>
        if(valid,
          do: %{"verdict" => "valid", "value" => op in ~w(absent not)},
          else: %{"verdict" => "invalid", "code" => "predicate_path_unresolved"}
        )
    }
  end

large_number_cases =
  for {text, value, name} <- [
        {"1e300", 1.0e300, "exponent"},
        {"1.7976931348623157e308", 1.7976931348623157e308, "maximum"},
        {"100000000000000000000", 1.0e20, "decimal"},
        {"9007199254740992", 9_007_199_254_740_992.0, "unsafe"}
      ],
      nested <- [false, true] do
    %{
      "id" => "json-decode-large-" <> name <> if(nested, do: "-nested", else: ""),
      "surface" => "json.decode",
      "class" => "valid",
      "input" => %{"text" => if(nested, do: "{\"values\":[" <> text <> "]}", else: text)},
      "expected" => %{
        "verdict" => "valid",
        "value" => if(nested, do: %{"values" => [value]}, else: value)
      }
    }
  end

all_cases =
  all_cases ++
    ImportCases.cases() ++
    predicate_cases ++ unicode_case_ids ++ absent_root_cases ++ large_number_cases

# --- vectors + schemas (hash-bound non-case data) ----------------------------

# Track-A goldens exercise EVERY registry member, evidence members
# included: the with-signatures + empty-attestations form (decodes green).
golden_blueprint_value = CorpusGen.add_empty_attestations(BlueprintFixture.with_signatures([]))
golden_deployment_value = CorpusGen.add_empty_attestations(DeploymentFixture.with_signatures([]))

data = %{
  "schemas/object.schema.json" => object_schema,
  "vectors/blueprint-golden.json" => CorpusGen.plain_value(golden_blueprint_value),
  "vectors/deployment-golden.json" => CorpusGen.plain_value(golden_deployment_value),
  "vectors/rfc8785-numbers.json" => %{
    "rows" => [
      %{"input" => "295147905179352830000", "canonical" => "295147905179352830000"},
      %{"input" => "1e-7", "canonical" => "1e-7"},
      %{"input" => "5e-324", "canonical" => "5e-324"},
      %{"input" => "0", "canonical" => "0"}
    ]
  }
}

defmodule Plain do
  def plain({:object, members}),
    do: members |> Enum.map(fn {k, v} -> {k, plain(v)} end) |> Map.new()

  def plain({:array, items}), do: Enum.map(items, &plain/1)
  def plain({:string, s}), do: s
  def plain({:integer, n}), do: n
  def plain({:float, n}), do: n
  def plain({:boolean, b}), do: b
  def plain(:null), do: nil
end

defmodule GenMain do
  # Re-run a single case's dispatch through the runner machinery to surface
  # the actual result next to the expectation.
  def dispatch_debug(c) do
    {actual, _agree} = AgentBlueprintProtocol.Conformance.Runner.execute(c, %{}, %{})
    project(actual)
  end

  defp project({:error, %AgentBlueprintProtocol.Error{code: {:ceiling, k}}}), do: "ceiling:#{k}"
  defp project({:error, %AgentBlueprintProtocol.Error{code: c}}), do: c
  defp project({:error, {:ceiling, k}}), do: "ceiling:#{k}"
  defp project({:error, c}) when is_atom(c), do: c
  defp project({:ok, m}) when is_map(m), do: {:ok, m}
  defp project(other), do: other

  # The goldens' fixture signatures (kid example-demo-signing-key /
  # example-demo-deploy-key, over the digest-UNCOVERED `signatures`
  # member) historically used random test keys. New signatures use the fixed
  # test-only seed in BlueprintFixture.signing_keypair/0. Preserve tokens per case, so adding cases to a file does not
  # replace an existing case's signature. Non-case files retain the same
  # whole-file comparison.
  @fixture_signature ~r/(example-demo-(?:signing|deploy)-key\\?"\},\\?"signature\\?":\\?")[A-Za-z0-9_-]{86}/

  def preserve_fixture_signatures(map, dir) do
    Enum.reduce(map, map, fn
      {"index.json", _bytes}, acc ->
        acc

      {path, bytes}, acc ->
        case File.read(Path.join(dir, path)) do
          {:ok, committed} when committed != bytes ->
            preserved = preserve_case_signatures(bytes, committed)

            if preserved != bytes,
              do:
                AgentBlueprintProtocol.ConformanceTest.Builder.resync_file(acc, path, preserved),
              else: acc

          _unchanged_or_new ->
            acc
        end
    end)
  end

  defp preserve_case_signatures(bytes, committed) do
    with {:ok, prior_value} <- AgentBlueprintProtocol.Json.decode(committed),
         {:ok, fresh_value} <- AgentBlueprintProtocol.Json.decode(bytes),
         %{"cases" => previous} <- CorpusGen.plain(prior_value),
         %{"cases" => fresh} = body <- CorpusGen.plain(fresh_value) do
      by_id = Map.new(previous, &{&1["id"], &1})

      cases =
        Enum.map(fresh, fn current ->
          prior = Map.get(by_id, current["id"])

          if prior && mask(CorpusGen.json_text!(prior)) == mask(CorpusGen.json_text!(current)),
            do: prior,
            else: current
        end)

      CorpusGen.json_text!(Map.put(body, "cases", cases))
    else
      _ -> if mask(committed) == mask(bytes), do: committed, else: bytes
    end
  end

  defp mask(bytes), do: Regex.replace(@fixture_signature, bytes, "\\1<fixture-signature>")

  def main(all_cases, data) do
    map =
      AgentBlueprintProtocol.ConformanceTest.Builder.build(all_cases, %{}, data: data)
      |> preserve_fixture_signatures("priv/conformance")

    with {:ok, corpus} <- AgentBlueprintProtocol.Conformance.Corpus.load(map) do
      results = AgentBlueprintProtocol.Conformance.Runner.run(corpus)
      report = AgentBlueprintProtocol.Conformance.Report.build(corpus, results)

      disagreements =
        results
        |> Enum.flat_map(&elem(&1, 1))
        |> Enum.reject(& &1.agree)
        |> Enum.map(& &1.case_id)

      if System.get_env("CORPUS_DEBUG") do
        IO.puts("DEBUG: loaded ok, checking tampers individually")
      end

      if disagreements != [] do
        IO.puts("REFUSING TO WRITE — disagreeing cases (actual vs expected):")
        by_id = all_cases |> Map.new(&{&1["id"], &1})

        Enum.each(disagreements, fn id ->
          c = Map.fetch!(by_id, id)
          actual = dispatch_debug(c)

          IO.puts(
            "  - #{id}: got #{inspect(actual, limit: 6)} expected #{inspect(c["expected"], limit: 6)}"
          )
        end)

        System.halt(2)
      end

      if not report.agreement do
        IO.puts("REFUSING TO WRITE — report does not agree: #{inspect(Map.from_struct(report))}")
        System.halt(2)
      end

      dir = "priv/conformance"
      File.rm_rf!(dir)
      File.mkdir_p!(dir)

      count =
        Enum.reduce(map, 0, fn {path, bytes}, n ->
          target = Path.join(dir, path)
          File.mkdir_p!(Path.dirname(target))
          File.write!(target, bytes)
          n + 1
        end)

      IO.puts("wrote #{count} files, #{length(all_cases)} cases, digest #{corpus.identity}")
    else
      {:error, error} ->
        IO.puts(
          "REFUSING TO WRITE — corpus does not load: #{inspect(error.code)} #{inspect(error.subject)}"
        )

        if error.code == :corpus_case_invalid and error.subject == ["cases", "tamper"] do
          # Report each tamper pair's derivation so the bad one is obvious.
          by_id = all_cases |> Map.new(&{&1["id"], &1})

          Enum.each(all_cases, fn c ->
            case c["tamper"] do
              nil ->
                :ok

              t ->
                base = Map.get(by_id, t["base_case"])
                bi = t["byte_index"]
                bx = t["xor"]

                key =
                  case t["target"] do
                    "input.entry" -> "entry"
                    "input.base64url" -> "base64url"
                    "input.text" -> "text"
                    _ -> "text"
                  end

                base_bytes =
                  case base && base["input"][key] do
                    b when is_binary(b) -> {:ok, b}
                    _ -> :error
                  end

                case base_bytes do
                  {:ok, bb} ->
                    <<pre::binary-size(^bi), byte, post::binary>> = bb
                    derived = pre <> <<Bitwise.bxor(byte, bx)>> <> post
                    actual = c["input"][key]

                    if derived != actual,
                      do:
                        IO.puts(
                          "  TAMPER MISMATCH #{c["id"]}: derived #{inspect(derived)} vs stored #{inspect(actual)}"
                        )

                  :error ->
                    IO.puts(
                      "  TAMPER BASE-MISSING-KEY #{c["id"]}/#{key} (base #{t["base_case"]})"
                    )
                end
            end
          end)
        end

        System.halt(2)
    end
  end
end

if System.get_env("CORPUS_DUMP_CASE") do
  c = Enum.find(all_cases, &(&1["id"] == System.get_env("CORPUS_DUMP_CASE")))

  IO.puts(
    "DUMP execute: " <>
      inspect(AgentBlueprintProtocol.Conformance.Runner.execute(c, %{}, %{}) |> elem(0), limit: 4)
  )

  IO.puts(
    "DUMP direct-decode: " <>
      inspect(AgentBlueprintProtocol.Federation.decode(c["input"]["text"]), limit: 6)
  )
else
  GenMain.main(all_cases, data)
end
