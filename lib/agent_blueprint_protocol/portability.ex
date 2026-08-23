defmodule AgentBlueprintProtocol.Portability do
  @moduledoc """
  The never-portable structural guard: member-name and
  value-shape denylists over tagged values.

  Four walks, one position-aware contract — which mode applies is decided by
  the artifact layer, which knows what each position IS:

  - `scan/1` — member names AND string values at any depth, identifier
    exemption OFF. Extension bodies: host-supplied content where nothing
    earns the identifier tolerance.
  - `scan_authored/1` — member names AND values, identifier exemption ON.
    Authored JSON the protocol itself carries inside open positions
    (bounded-schema documents, predicate `value`/`values` operands): their
    member names are attacker-choosable (must be denylisted) but their
    VALUES legitimately contain long identifier-shaped strings (schema
    `enum` members, compared operation names).
  - `scan_identifier/1` — values only, exemption ON. The protocol's own
    identifier-convention positions (port names, operation families,
    logical operation names, assertion operand names).
  - `scan_value/1` — values only, exemption OFF. Every other string
    (toolchain, signature `key_id`, digests, timestamps).

  **Honest limit (necessary, not sufficient):** deciding whether an opaque
  string IS a tenant identifier, a database key, or an engine id is
  undecidable. The guard catches the named structural classes; the
  compensating controls are the closed-world core, the registered-extension
  schema requirement, and host-side review. Deny reason everywhere:
  `:forbidden_portable_value`.

  Value-shape classes:

  - PEM armour — a `-----BEGIN` prefix.
  - Compact JWS — three dot-separated non-empty base64url segments whose
    FINAL segment is ≥ `@min_signature_chars` (43) characters: a real
    detached JWS ends in a ≥ 32-byte signature, while dotted producer
    identities (`com.example.commerce`) end in short labels.
  - Absolute URI with a network authority — `scheme://authority…` with a
    non-empty authority (RFC 3986 scheme grammar).
  - Raw key material — a clean unpadded base64url string whose floor is
    SEPARATOR-AWARE: 24 decoded bytes (the 192-bit AES-128 hex class —
    hex never carries separators) when the string has no `-`/`_`, and the
    original 32-byte calibration when it does (real base64url keys carry
    separator characters; separator-bearing identifiers like kebab-case
    names in the 32-42-char window stay green). EXCEPT identifier-style
    strings (single case AND containing `_` or `-`; position-scoped, never
    a default) and hyphenated UUIDs (exempt by shape in every mode:
    the pinned honest-limit example — a 16-byte key re-spelled as a
    UUID is the accepted evasion class, already available at any length via
    word encodings).
  - Padded standard alphabets — self-identified by 1-6 `=` pad chars at 32+
    characters (24+ decoded bytes as base64; 20 as base32 — the fail-closed
    reading), or an unpadded ≥43-character standard-alphabet run (the
    base64url calibration; keeps dot-free slash paths under 43 green).
  - Colon-chunked hex fingerprints — 1-2 hex digits per `:` chunk, 24+
    CHUNKS (each chunk is one byte in the SSH-fingerprint / EUI form, so
    zero-stripped one-digit chunks count fully). The chunk grammar spares
    tagged content addresses (`sha256:…` — the prefix is not a hex chunk)
    and MAC addresses (6 chunks).

  Total and never-raising: malformed tagged shapes pass through unchecked
  (the layers below already denied them).
  The guard reports portability facts — it does not authorize or permit anything.
  The guard reports portability facts — it does not authorize or permit anything.
  """

  alias AgentBlueprintProtocol.Json

  # The 34-name member denylist, verbatim.
  # Stored NORMALIZED (snake + case-folded, kebab folded in at compare
  # time): the stored set carries every spelling's folded twin so camel,
  # kebab, and SCREAMING forms of one denied name converge — the
  # normalization lesson swept across the whole family.
  @denied_names_source [
    "secret",
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
    "accountId",
    "grantId",
    "primaryKey",
    "databaseUrl",
    "connectionString",
    "engineId",
    "billingAccount",
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

  @denied_names MapSet.new(
                  Enum.flat_map(@denied_names_source, fn name ->
                    normalized = name |> String.downcase() |> String.replace("-", "_")
                    folded = String.replace(normalized, "_", "")
                    if folded == normalized, do: [normalized], else: [normalized, folded]
                  end)
                )

  @pem_marker "-----BEGIN"
  @min_signature_chars 43
  # Raw-key floors, separator-aware: 24 decoded bytes separator-free (the
  # AES-128 hex class — hex never carries separators), 32 when the string
  # carries `-`/`_` (the base64url calibration — real keys carry
  # separator characters, and separator-bearing identifiers stay green
  # below it). Hyphenated UUIDs are exempt by SHAPE in every mode
  # (the pinned honest-limit example).
  @secret_entropy_bytes 24
  @separator_bearing_entropy_bytes 32
  @hex_chunk Regex.compile!("\\A[0-9a-fA-F]{1,2}\\z")
  @uuid_shape Regex.compile!(
                "\\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\z"
              )

  @b64url Regex.compile!("\\A[A-Za-z0-9_-]+\\z")
  # RFC 3986: scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ), then "://"
  # and a non-empty authority run up to the first path/query/fragment/space.
  # The scheme-less network-path reference (`//authority/path` — the same
  # host disclosure) matches anchored at string start only (the
  # scheme-requiring form would have let `//internal.svc/api`
  # through every scan mode).
  @network_uri Regex.compile!("[A-Za-z][A-Za-z0-9+.-]*:\\/\\/[^\\/\\s#?]+|\\A\\/\\/[^\\/\\s#?]+")
  @lower_identifier Regex.compile!("\\A[a-z0-9_-]+\\z")
  @upper_identifier Regex.compile!("\\A[A-Z0-9_-]+\\z")

  @type reason :: :forbidden_portable_value

  @doc "Names + values, identifier exemption OFF (extension bodies)."
  @spec scan(Json.value()) :: :ok | {:error, reason()}
  def scan(value), do: walk(value, true, false)

  @doc "Names + values, identifier exemption ON (authored JSON: schemas, predicate operands)."
  @spec scan_authored(Json.value()) :: :ok | {:error, reason()}
  def scan_authored(value), do: walk(value, true, true)

  @doc "Values only, identifier exemption ON (the protocol's identifier positions)."
  @spec scan_identifier(Json.value()) :: :ok | {:error, reason()}
  def scan_identifier(value), do: walk(value, false, true)

  @doc "Values only, exemption OFF (every other string position)."
  @spec scan_value(Json.value()) :: :ok | {:error, reason()}
  def scan_value(value), do: walk(value, false, false)

  # Names normalize kebab/SCREAMING/camel onto the stored forms before the
  # denylist compare (the normalized
  # comparison swept across the family: `tenant-id` is the same denied name as `tenant_id`
  # — a plain-ASCII completeness gap of the transcribed list, not a
  # homoglyph; homoglyph spellings remain the accepted residual of any
  # name list).
  defp denied_name?(name) do
    normalized = name |> String.downcase() |> String.replace("-", "_")
    MapSet.member?(@denied_names, normalized)
  end

  defp walk({:object, members}, names?, exempt?) when is_list(members) do
    member_ok? =
      if names?,
        do: Enum.all?(members, fn {name, _} -> not denied_name?(name) end),
        else: true

    if member_ok? and
         Enum.all?(members, fn {_name, value} -> walk(value, names?, exempt?) == :ok end) do
      :ok
    else
      {:error, :forbidden_portable_value}
    end
  end

  defp walk({:array, items}, names?, exempt?) when is_list(items),
    do:
      if(Enum.all?(items, &(walk(&1, names?, exempt?) == :ok)),
        do: :ok,
        else: {:error, :forbidden_portable_value}
      )

  defp walk({:string, s}, _names?, exempt?) when is_binary(s) do
    forbidden =
      if exempt? and identifier_style?(s),
        do: false,
        else: forbidden_value?(s)

    if forbidden, do: {:error, :forbidden_portable_value}, else: :ok
  end

  defp walk(_other, _names?, _exempt?), do: :ok

  # ---- value shapes ---------------------------------------------------------------

  defp forbidden_value?(s) do
    not uuid_shaped?(s) and structural_secret?(s)
  end

  defp uuid_shaped?(s), do: Regex.match?(@uuid_shape, s)

  defp structural_secret?(s) do
    String.contains?(s, @pem_marker) or compact_jws?(s) or
      Regex.match?(@network_uri, s) or raw_key_material?(s) or padded_standard_b64?(s) or
      colon_hex_fingerprint?(s)
  end

  # Standard-alphabet base64 with padding: 32+ decoded bytes of key-shaped
  # material that the base64url class structurally misses ("secret key →
  # any position RED" outranks the transcription's alphabet pin).
  # Standard-alphabet runs: PAD-IDENTIFIED forms (1-6 `=`) at 32+
  # characters, or unpadded runs at the 43-character calibration
  # (dot-free slash paths under 43 stay green).
  defp padded_standard_b64?(s) do
    Regex.match?(~r/\A[A-Za-z0-9+\/]{32,}={1,6}\z/, s) or
      Regex.match?(~r/\A[A-Za-z0-9+\/]{43,}\z/, s)
  end

  # Colon-chunked hex (SSH fingerprint / EUI form): 1-2 hex digits per
  # chunk, 24+ CHUNKS — each chunk is one byte, so one-digit (zero-stripped)
  # chunks count fully (both peers' finding: a digit-sum threshold let
  # zero-stripped keys under it). The chunk grammar spares tagged content
  # addresses ("sha256:…" — the prefix is not a hex chunk) and MACs.
  defp colon_hex_fingerprint?(s) do
    chunks = String.split(s, ":")

    length(chunks) >= 24 and Enum.all?(chunks, &Regex.match?(@hex_chunk, &1))
  end

  defp compact_jws?(s) do
    case String.split(s, ".") do
      [header, payload, signature] ->
        # RFC 7797 detached form carries an EMPTY payload segment;
        # the header is never empty, the signature
        # still carries the ≥32-byte weight.
        b64url?(header) and byte_size(header) > 0 and
          (payload == "" or b64url?(payload)) and
          b64url?(signature) and byte_size(signature) >= @min_signature_chars

      _not_three_segments ->
        false
    end
  end

  defp raw_key_material?(s) do
    b64url?(s) and decoded_bytes(s) >= entropy_floor(s)
  end

  defp entropy_floor(s) do
    if String.contains?(s, "-") or String.contains?(s, "_"),
      do: @separator_bearing_entropy_bytes,
      else: @secret_entropy_bytes
  end

  defp b64url?(s), do: Regex.match?(@b64url, s)

  # The identifier convention: one case, digits, and at least one `_` or
  # `-` separator (snake and kebab alike — the protocol's own segment
  # grammar admits both, and the [a-z0-9_-] class carries the same ≈1.6e-10
  # bound against random key material). Separator-free (hex, base32) is
  # never exempt. POSITION-SCOPED: an adversary who controls the ENCODING
  # can pack secret material into the class, so the exemption is the
  # artifact layer's call for positions whose convention it owns — never a
  # default.
  defp identifier_style?(s) do
    (String.contains?(s, "_") or String.contains?(s, "-")) and
      (Regex.match?(@lower_identifier, s) or Regex.match?(@upper_identifier, s))
  end

  # Unpadded base64url length: 4k → 3k bytes, 4k+2 → 3k+1, 4k+3 → 3k+2.
  defp decoded_bytes(s) do
    case rem(byte_size(s), 4) do
      0 -> div(byte_size(s) * 3, 4)
      2 -> div((byte_size(s) - 2) * 3, 4) + 1
      3 -> div((byte_size(s) - 3) * 3, 4) + 2
      1 -> 0
    end
  end
end
