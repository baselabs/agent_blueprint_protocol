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

alias AgentBlueprintProtocol.{
  Blueprint,
  BlueprintFixture,
  Canonicalization,
  Deployment,
  DeploymentFixture,
  Digest,
  ExtensionRegistry,
  Federation,
  FederationFixture,
  Json,
  Negotiation,
  Signature
}

alias AgentBlueprintProtocol.Conformance.{Corpus, Report, Runner}
alias AgentBlueprintProtocol.ConformanceTest.Builder

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

  def signature_entry(seed, kid, digest_tagged) do
    {pub, priv} = keypair(seed)

    header =
      {:object,
       [
         {"alg", {:string, "EdDSA"}},
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
         {"purpose", {:string, "deployment"}}
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
  def signed_receipt(seed, kid) do
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
         {"purpose", {:string, "federation-envelope"}}
       ]}

    header =
      {:object,
       [
         {"alg", {:string, "EdDSA"}},
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

  def put_path({:object, members}, [key | rest], value) do
    {:object,
     Enum.map(members, fn
       {^key, old} -> {key, put_path(old, rest, value)}
       other -> other
     end)}
  end

  def put_path(_old, [], value), do: value

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
sig_marker = ~s/"_signature":/
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

# ---- schema.validate_instance (5) ----
object_schema = %{"type" => "object", "additionalProperties" => false, "properties" => %{}}

big_schema = %{
  "type" => "object",
  "additionalProperties" => false,
  "properties" => Map.new(Enum.map(1..600, &{"p#{&1}", %{"type" => "integer"}}))
}

schema_cases = [
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

# ---- blueprint.decode (8) ----
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

# ---- negotiation.negotiate (7) ----
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
  }
]

# ---- extension.resolve (6) ----
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
    federation_decode_cases ++ verify_commitment_cases

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

  def main(all_cases, data) do
    map = AgentBlueprintProtocol.ConformanceTest.Builder.build(all_cases, %{}, data: data)

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

                with {:object, _} <- :nope do
                  :ok
                else
                  _ -> :ok
                end

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
