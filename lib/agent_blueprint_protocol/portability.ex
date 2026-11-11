defmodule AgentBlueprintProtocol.Portability do
  @moduledoc """
    This module scans tagged values for nonportable names and value shapes.

    Use it when checking content in open protocol fields for portability findings.

    This module does not authorize operations.

    ## Example

    ```elixir
    AgentBlueprintProtocol.Portability.scan({:object, [{"label", {:string, "example"}}]})
    ```
  """
  @moduledoc since: "1.0.0"

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
  @lower_identifier Regex.compile!("\\A[a-z0-9_-]+\\z")
  @upper_identifier Regex.compile!("\\A[A-Z0-9_-]+\\z")

  @max_depth AgentBlueprintProtocol.Bounds.maximum().depth

  @spec scan(Json.value()) :: :ok | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
    Scans a tagged value for portability findings.

    ## Example

        iex> AgentBlueprintProtocol.Portability.scan({:object, [{"label", {:string, "example"}}]})
        :ok
  """
  @doc since: "1.0.0"
  def scan(value), do: walk(value, true, false, 0)

  @spec scan_authored(Json.value()) :: :ok | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
    Scans authored tagged JSON for portability findings.

    ## Example

        iex> AgentBlueprintProtocol.Portability.scan_authored({:object, [{"label", {:string, "example"}}]})
        :ok
  """
  @doc since: "1.0.0"
  def scan_authored(value), do: walk(value, true, true, 0)

  @spec scan_identifier(Json.value()) :: :ok | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
    Scans identifier-position values for portability findings.

    ## Example

        iex> AgentBlueprintProtocol.Portability.scan_identifier({:string, "example-name"})
        :ok
  """
  @doc since: "1.0.0"
  def scan_identifier(value), do: walk(value, false, true, 0)

  @spec scan_value(Json.value()) :: :ok | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
    Scans tagged string values for portability findings.

    ## Example

        iex> AgentBlueprintProtocol.Portability.scan_value({:string, "example"})
        :ok
  """
  @doc since: "1.0.0"
  def scan_value(value), do: walk(value, false, false, 0)

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

  defp walk({tag, _}, _names?, _exempt?, depth)
       when tag in [:array, :object] and depth >= @max_depth,
       do: {:error, %AgentBlueprintProtocol.Error{code: {:ceiling, :depth}}}

  defp walk({:object, members}, names?, exempt?, depth) when is_list(members) do
    if member_pairs?(members),
      do: walk_object(members, names?, exempt?, depth),
      else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
  end

  defp walk({:array, items}, names?, exempt?, depth) when is_list(items) do
    walk_array(items, names?, exempt?, depth)
  end

  defp walk({:string, s}, _names?, exempt?, _depth) when is_binary(s) do
    forbidden = if exempt? and identifier_style?(s), do: false, else: forbidden_value?(s)

    if forbidden,
      do: {:error, %AgentBlueprintProtocol.Error{code: :forbidden_portable_value}},
      else: :ok
  end

  defp walk(_other, _names?, _exempt?, _depth), do: :ok

  defp walk_array([], _names?, _exempt?, _depth), do: :ok

  defp walk_array([value | rest], names?, exempt?, depth) do
    with :ok <- walk(value, names?, exempt?, depth + 1),
         do: walk_array(rest, names?, exempt?, depth)
  end

  defp walk_array(_, _, _, _), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp member_pairs?([]), do: true
  defp member_pairs?([{name, _} | rest]) when is_binary(name), do: member_pairs?(rest)
  defp member_pairs?(_), do: false

  defp walk_object(members, names?, exempt?, depth) do
    member_ok? =
      if names?, do: Enum.all?(members, fn {name, _} -> not denied_name?(name) end), else: true

    if member_ok? do
      Enum.find_value(members, :ok, fn {_name, value} ->
        pass_nil(walk(value, names?, exempt?, depth + 1))
      end)
    else
      {:error, %AgentBlueprintProtocol.Error{code: :forbidden_portable_value}}
    end
  end

  defp pass_nil(:ok), do: nil
  defp pass_nil({:error, _} = error), do: error

  # ---- value shapes ---------------------------------------------------------------

  defp forbidden_value?(s) do
    not uuid_shaped?(s) and structural_secret?(s)
  end

  defp uuid_shaped?(s), do: Regex.match?(@uuid_shape, s)

  defp structural_secret?(s) do
    String.contains?(s, @pem_marker) or compact_jws?(s) or
      network_uri?(s) or raw_key_material?(s) or padded_standard_b64?(s) or
      colon_hex_fingerprint?(s)
  end

  # Search delimiters once. The old unanchored scheme could begin at any
  # letter in the preceding scheme-character run, including after digits.
  # Backward walks cannot overlap: each delimiter breaks the next run.
  defp network_uri?(<<"//", first, _rest::binary>>)
       when first not in [?/, 9, 10, 11, 12, 13, 32, ?#, ??],
       do: true

  defp network_uri?(s), do: network_uri?(s, 0)

  defp network_uri?(s, offset) do
    case :binary.match(s, "://", scope: {offset, byte_size(s) - offset}) do
      {at, 3} ->
        (authority_start?(s, at + 3) and scheme_letter?(s, at - 1)) or
          network_uri?(s, at + 3)

      :nomatch ->
        false
    end
  end

  defp authority_start?(s, at) when at < byte_size(s),
    do: :binary.at(s, at) not in [?/, 9, 10, 11, 12, 13, 32, ?#, ??]

  defp authority_start?(_s, _at), do: false

  defp scheme_letter?(_s, at) when at < 0, do: false

  defp scheme_letter?(s, at) do
    case :binary.at(s, at) do
      c when c in ?A..?Z or c in ?a..?z -> true
      c when c in ?0..?9 or c in [?+, ?., ?-] -> scheme_letter?(s, at - 1)
      _ -> false
    end
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
