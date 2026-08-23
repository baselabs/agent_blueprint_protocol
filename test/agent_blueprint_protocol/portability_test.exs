defmodule AgentBlueprintProtocol.PortabilityTest do
  @moduledoc """
  The never-portable structural guard (the base protocol's never-portable clause): member-name and
  value-shape denylists over the open regions, value shapes over every other
  string. Necessary, not sufficient — the calibration pins (UUID green,
  identifier-style green, hex red) fix the red/green boundary.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.Portability

  # ---- member-name denylist (scan/1, any depth) ---------------------------------

  test "each denylisted member name denies at any depth, kebab and SCREAMING twins included" do
    names = [
      "secret",
      "tenant-id",
      "TENANT_ID",
      "Api-Key",
      "org-id",
      "secrets",
      "private_key",
      "privateKey",
      "api_key",
      "apiKey",
      "token",
      "password",
      "passphrase",
      "credential",
      "credentials",
      "tenant_id",
      "tenantId",
      "org_id",
      "orgId",
      "user_id",
      "userId",
      "account_id",
      "grant",
      "grant_id",
      "decision",
      "endpoint",
      "url",
      "uri",
      "href",
      "dsn",
      "connection_string",
      "database_url",
      "primary_key",
      "row_id",
      "billing_account",
      "engine",
      "engine_id",
      "provider_key"
    ]

    for name <- names do
      assert {:error, :forbidden_portable_value} =
               Portability.scan({:object, [{name, {:integer, 1}}]}),
             "name #{inspect(name)} must deny"
    end
  end

  test "denylisted names deny nested in arrays and objects at depth" do
    deep =
      {:object,
       [
         {"outer", {:array, [{:object, [{"inner", {:object, [{"engine_id", {:string, "x"}}]}}]}]}}
       ]}

    assert {:error, :forbidden_portable_value} = Portability.scan(deep)
  end

  test "benign member names pass" do
    assert :ok =
             Portability.scan(
               {:object, [{"max_depth", {:integer, 3}}, {"dataset", {:string, "orders"}}]}
             )
  end

  # ---- value shapes ---------------------------------------------------------------

  test "PEM armour denies" do
    pem =
      "-----" <>
        "BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASC\n-----" <>
        "END PRIVATE KEY-----"

    assert {:error, :forbidden_portable_value} =
             Portability.scan({:object, [{"note", {:string, pem}}]})

    assert {:error, :forbidden_portable_value} = Portability.scan_value({:string, pem})
  end

  test "compact-JWS shape denies, but a dotted producer identity does not" do
    jws =
      "eyJ0eXAiOiJKV1QiLA0KICJhbGciOiJIUzI1NiJ9." <>
        "eyJpc3MiOiJmb28iLCJleHAiOjEzMDA4MTkzODAsImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ." <>
        "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

    assert {:error, :forbidden_portable_value} = Portability.scan_value({:string, jws})

    # Three b64url segments, but the last is a producer label, not a
    # signature: the final-segment length discriminates.
    assert :ok = Portability.scan_value({:string, "com.example.commerce"})
    assert :ok = Portability.scan_value({:string, "com.example.tools.internal_platform"})
  end

  test "absolute URI with network authority denies; scheme-less forms pass" do
    assert {:error, :forbidden_portable_value} =
             Portability.scan_value({:string, "https://internal.acme.io/db"})

    assert {:error, :forbidden_portable_value} =
             Portability.scan_value({:string, "postgres://db-host.internal:5432/prod"})

    # The scheme-relative network-path reference carries the same host
    # disclosure — anchored at string start only,
    # so mid-string double slashes stay identifier-shaped.
    assert {:error, :forbidden_portable_value} =
             Portability.scan_value({:string, "//internal.svc/api"})

    assert {:error, :forbidden_portable_value} =
             Portability.scan_value({:string, "//db-host.internal:5432/prod"})

    assert :ok = Portability.scan_value({:string, "com.example.commerce/graph"})
    assert :ok = Portability.scan_value({:string, "2026-08-20T00:00:00Z"})
    assert :ok = Portability.scan_value({:string, "a//non-network//path"})

    assert :ok =
             Portability.scan_value(
               {:string, "sha-256:47DEQpj8HBS-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU"}
             )
  end

  test "clean b64url over 32 decoded bytes denies (the entropy threshold)" do
    # 67 mixed-case b64url chars = 50 decoded bytes (synthetic, two parts so
    # no scanner mistakes the fixture for a real key).
    material = "cGFzdGhldGljYWxseV9sb25nX" <> "3NlY3JldF9rZXlfbWF0ZXJpYWxIZEVGSU5JVEVMT05ORVNN"
    assert {:error, :forbidden_portable_value} = Portability.scan_value({:string, material})

    # 64-char hex (32 bytes) has no identifier separator and still denies.
    hex = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
    assert {:error, :forbidden_portable_value} = Portability.scan_value({:string, hex})
  end

  test "identifier-style strings: exempt in identifier mode, strict everywhere else" do
    # Single case, underscore-separated: the identifier convention — green
    # ONLY in the identifier position mode (an
    # adversary who controls the encoding can pack secret material into
    # [a-z0-9_], so the exemption is position-scoped, never a default).
    slug = "fetch_grounding_dataset_with_citations_and_full_sources_list"
    assert :ok = Portability.scan_identifier({:string, slug})
    assert {:error, :forbidden_portable_value} = Portability.scan_value({:string, slug})
    assert {:error, :forbidden_portable_value} = Portability.scan({:string, slug})

    # Mixed case WITH an underscore is outside every exemption.
    mixed = "Fetch_GroundingDataset_WithCitations_AndFullSourcesList"
    assert {:error, :forbidden_portable_value} = Portability.scan_value({:string, mixed})
    assert {:error, :forbidden_portable_value} = Portability.scan_identifier({:string, mixed})

    # A single-case 43+ char secret-shaped string denies in strict mode even
    # with underscores (the adversarial-encoding probe).
    packed = "a3f9c2b8d4e1f6a0b7c39d2e1f4a0b5c8d7e2f1a4b6c9d0"
    assert {:error, :forbidden_portable_value} = Portability.scan_value({:string, packed})
  end

  test "a hyphenated UUID stays green (the honest-limit calibration)" do
    assert :ok = Portability.scan_value({:string, "550e8400-e29b-41d4-a716-446655440000"})
  end

  test "value shapes apply to strings nested at any depth in scan/1" do
    deep =
      {:object,
       [
         {"fine", {:array, [{:object, [{"ok", {:string, "x"}}]}]}},
         {"also_fine", {:object, [{"hidden", {:string, "https://relay.internal/ingest"}}]}}
       ]}

    assert {:error, :forbidden_portable_value} = Portability.scan(deep)
  end

  # ---- scan_value does not check member names --------------------------------------

  test "scan_value checks strings only, never member names" do
    assert :ok = Portability.scan_value({:object, [{"tenant_id", {:integer, 4}}]})
  end

  test "a one-byte prefix does not defeat the URI or PEM classes" do
    assert {:error, :forbidden_portable_value} =
             Portability.scan_value({:string, " https://internal.example.com/db"})

    assert {:error, :forbidden_portable_value} =
             Portability.scan_value({:string, "note:https://relay.internal/x"})

    assert {:error, :forbidden_portable_value} =
             Portability.scan_value({:string, "id:-----BEGIN PRIVATE KEY-----"})
  end

  test "padded standard base64 keys and detached JWS forms deny" do
    padded = "cGFzdGhldGljYWxseV9sb25nX3NlY3JldF9rZXlfbWF0ZXJpYWw="
    assert {:error, :forbidden_portable_value} = Portability.scan_value({:string, padded})

    detached = "eyJhbGciOiJFZERTQSJ9..dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    assert {:error, :forbidden_portable_value} = Portability.scan_value({:string, detached})
  end

  test "camelCase denylist twins deny" do
    for name <- [
          "accountId",
          "grantId",
          "primaryKey",
          "databaseUrl",
          "connectionString",
          "engineId",
          "billingAccount"
        ] do
      assert {:error, :forbidden_portable_value} =
               Portability.scan({:object, [{name, {:integer, 1}}]}),
             name
    end
  end

  test "named encoding gaps: padded base32, colon-chunked hex, sub-threshold keys deny" do
    # base32 with 4-6 pad chars (the padded class capped at two).
    base32 = "ZY4R3ZJFJMM5CJLGEKV7R2JTCQZRQKTZ3ZXI2LMV2F4SCUXNZ4XA===="
    assert {:error, :forbidden_portable_value} = Portability.scan_value({:string, base32})

    # colon-chunked hex: SSH-fingerprint shape, 1-2 hex digits per chunk,
    # 24+ decoded bytes total.
    colon_hex =
      "9f:86:d0:81:88:4c:7d:65:9a:2f:ea:a0:c5:5a:d0:15:a3:bf:4f:1b:2b:0b:82:2c:d1:5d:6c:15:b0:f0:0a:08"

    assert {:error, :forbidden_portable_value} = Portability.scan_value({:string, colon_hex})

    # sub-threshold key: 32-char hex (24 decoded bytes) now denies.
    aes128_hex = "9f86d081884c7d659a2feaa0c55ad015"
    assert {:error, :forbidden_portable_value} = Portability.scan_value({:string, aes128_hex})
  end

  test "T1-review findings: zero-stripped chunks, kebab identifiers, and slash paths" do
    # Both peers' finding: one-digit (zero-stripped) chunks count fully —
    # the threshold is CHUNKS, not digit sum.
    assert {:error, :forbidden_portable_value} =
             Portability.scan_value({:string, Enum.join(List.duplicate("1", 24), ":")})

    assert {:error, :forbidden_portable_value} =
             Portability.scan_value(
               {:string, "f:86:d0:81:88:4c:7d:65:9a:2f:ea:a0:c5:5a:d0:15:a3:bf:4f:1b:2b:0b:82:2c"}
             )

    # Kebab-case identifiers in the 32-42-char window stay green in every
    # mode (the protocol's own segment grammar admits hyphens; the floor is
    # separator-aware) and are identifier-convention exempt at any length.
    kebab = "elixir-otp-27-agent-blueprint-build"
    assert :ok = Portability.scan_value({:string, kebab})
    assert :ok = Portability.scan_identifier({:string, kebab})

    long_kebab = "fetch-all-grounding-dataset-records-with-full-citation-lists"
    assert :ok = Portability.scan_identifier({:string, long_kebab})

    # A separator-bearing secret still denies at the 32-byte calibration.
    assert {:error, :forbidden_portable_value} =
             Portability.scan_value(
               {:string, "a3f9c2_b8d4e1_f6a0b7c_39d2e1f_4a0b5c8d7e2f1a4b6c9d0"}
             )

    # Dot-free slash paths under 43 chars stay green (the unpadded standard
    # run keeps the calibration).
    assert :ok = Portability.scan_value({:string, "lib/agent/blueprint/protocol/portability"})
  end

  test "the calibration pins survive the lower floor" do
    # The spec-pinned honest-limit example: a tenant UUID in free-form
    # content passes (named identifier shape, exempt in every mode).
    uuid = "550e8400-e29b-41d4-a716-446655440000"
    assert :ok = Portability.scan_value({:string, uuid})
    assert :ok = Portability.scan({:string, uuid})
    assert :ok = Portability.scan_identifier({:string, uuid})
    assert :ok = Portability.scan_authored({:string, uuid})

    # A MAC address (12 hex digits = 6 bytes) stays green under the floor.
    assert :ok = Portability.scan_value({:string, "9f:86:d0:81:88:4c"})

    # Content-address tags keep their green (the prefix is not hex-chunked).
    assert :ok =
             Portability.scan_value({:string, "sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b"})
  end

  test "total and never-raising on malformed tagged shapes" do
    for bad <- [5, :null, {:object, nil}, {:array, [3]}, {:string, :not_a_binary}, {"tuple", 1}] do
      assert :ok = Portability.scan_value(bad)
      assert :ok = Portability.scan(bad)
    end
  end
end
