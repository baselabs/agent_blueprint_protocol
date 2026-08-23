defmodule AgentBlueprintProtocol.Signature do
  @moduledoc """
  Detached JWS signature envelope: RFC 7515 compact serialization with the
  RFC 7797 `b64=false` unencoded, detached payload, Ed25519 signatures
  verified through `:crypto`. **Verify-only** — the package never signs,
  never accepts a private key on any function, and performs no key
  discovery or trust selection; hosts supply the trusted keys.

  What is signed is the RFC 7797 §3 input:

      ASCII(BASE64URL(JCS(protected_header))) || "." || JCS(signed_attributes)

  so a standard, `b64=false`-aware JOSE tooling stack can verify the same
  bytes (the ratified preimage form,
  byte-disjoint from the design's earlier sketch). **Producer contract:** the
  protected header segment must be the JCS serialization of the exact
  four-member header; a producer using any other member order produces a
  legitimately-signed JWS this verifier denies `:signature_not_verified`.
  This package is deliberately narrower than generic JOSE for determinism.

  The envelope shape (closed world, value-free denials):

      {"protected":        {"alg":"EdDSA","b64":false,"crit":["b64"],"kid":"…"},
       "signed_attributes":{"algorithm":"Ed25519","content_digest":"sha-256:…",
                            "created_at":"2026-08-20T00:00:00Z","key_id":"…",
                            "purpose":"blueprint"},
       "signature":        "<86-char unpadded base64url>"}

  `kid` must equal the signed `key_id` (key substitution prevention);
  `key_id` is dot-free so the unencoded payload can never contain `.`
  (RFC 7797 §5.2 forbids it in compact serializations); `created_at` is
  Z-form whole seconds. Attestations use the identical envelope with
  `purpose`/`content_digest` replaced by a registered `kind` and a
  `statement_digest`; the kind registry is empty until kinds become data,
  so every attestation denies `:attestation_malformed` today (fail-closed).

  Because `content_digest` and `purpose` are inside the signed bytes, a
  signature cannot be lifted onto a different artifact, digest, or
  purpose. Errors are value-free.
  Signature verification produces evidence only; it never authorizes an operation.
  """

  alias AgentBlueprintProtocol.{Base64Url, Canonicalization, Digest, Json}

  defmodule PublicKey do
    @moduledoc """
    A host-supplied Ed25519 public key, matched by the producer-chosen
    `key_id`. The package performs no discovery or trust selection.
    A public key is verification input that carries no authority.
    """

    @enforce_keys [:key_id, :algorithm, :key]
    defstruct [:key_id, :algorithm, :key]

    @type t :: %__MODULE__{key_id: binary(), algorithm: :ed25519, key: <<_::256>>}
  end

  defmodule Attributes do
    @moduledoc """
    The validated signed attributes of a signature entry, with
    `content_digest` parsed to a `Digest` value and `purpose` the closed
    purpose atom.
    Signed attributes are signature evidence that carries no authority.
    """

    @enforce_keys [:algorithm, :content_digest, :created_at, :key_id, :purpose]
    defstruct [:algorithm, :content_digest, :created_at, :key_id, :purpose]

    @type purpose :: :blueprint | :deployment | :federation_envelope

    @type t :: %__MODULE__{
            algorithm: binary(),
            content_digest: Digest.t(),
            created_at: binary(),
            key_id: binary(),
            purpose: purpose()
          }
  end

  @type reason ::
          :signature_algorithm_unsupported
          | :signature_key_unsupported
          | :signature_malformed
          | :signature_not_verified
          | :attestation_malformed

  @purposes %{
    "blueprint" => :blueprint,
    "deployment" => :deployment,
    "federation-envelope" => :federation_envelope
  }

  # The attestation kind registry: EMPTY by design — no kinds are
  # spec-named. Unknown kinds deny :attestation_malformed (fail-closed);
  # kinds become data when real consumers exist.
  @kinds %{}

  # RFC 3339 Z-form, whole seconds, no offset (deterministic JCS bytes; the
  # no-fraction rule also keeps the unencoded payload dot-and-dot-free).
  @created_at ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/

  @entry_members ["protected", "signature", "signed_attributes"]
  @header_members ["alg", "b64", "crit", "kid"]
  @signature_attr_members ["algorithm", "content_digest", "created_at", "key_id", "purpose"]
  @attestation_attr_members ["algorithm", "created_at", "key_id", "kind", "statement_digest"]

  @doc """
  The RFC 7797 `b64=false` signing input of a signature entry (the tagged
  algebra as decoded by `Json`): `BASE64URL(JCS(protected)) || "." ||
  JCS(signed_attributes)`. Envelope violations deny with their
  `verify/2` reason.
  """
  @spec signing_input(Json.value()) :: {:ok, binary()} | {:error, reason()}
  def signing_input(entry) do
    with {:ok, parts} <- parts(entry, :signature) do
      {:ok, parts.header_b64 <> "." <> parts.payload}
    end
  end

  @doc """
  The signed attributes of a signature entry as an `Attributes` value.
  **Shape-validated only** — no signature has been checked; only `verify/2`
  establishes the signature fact. Do not consume attributes from an
  envelope that has not verified.
  """
  @spec attributes(Json.value()) :: {:ok, Attributes.t()} | {:error, reason()}
  def attributes(entry) do
    with {:ok, parts} <- parts(entry, :signature) do
      {:ok, parts.attributes}
    end
  end

  @doc """
  Verify a signature entry against host-supplied trusted keys. Returns
  facts, never authorization: `{:ok, :verified}` when any key supplied for
  the entry's `key_id` verifies the envelope; `{:error,
  :signature_key_unsupported}` when no supplied key carries that id;
  `{:error, :signature_algorithm_unsupported}` when the header names a
  non-EdDSA algorithm or no matched key is usable Ed25519;
  `{:error, :signature_malformed}` for envelope violations;
  `{:error, :signature_not_verified}` when the bytes do not verify.
  """
  @spec verify(Json.value(), [PublicKey.t()]) :: {:ok, :verified} | {:error, reason()}
  def verify(entry, keys) when is_list(keys) do
    with {:ok, parts} <- parts(entry, :signature) do
      check(parts, parts.header_b64 <> "." <> parts.payload, keys)
    end
  end

  @doc """
  Verify an attestation entry (identical envelope; `kind` and
  `statement_digest` replace `purpose` and `content_digest`). The kind
  registry is empty, so a well-formed attestation denies
  `{:error, :attestation_malformed}` today — the fail-closed posture, not
  a defect. Shape errors use `:attestation_malformed`; algorithm denials
  (`alg`/`algorithm` not EdDSA/Ed25519) share the signature vocabulary by
  design — the envelope's algorithm posture is one concern. When the first
  kind registers, the single-clause match below fails loudly on the
  now-possible `{:ok, _}` and the identical `check/3` wiring used by
  `verify/2` is added deliberately; the envelope machinery (`parts/2`) is
  already shared.
  """
  @spec verify_attestation(Json.value(), [PublicKey.t()]) :: {:ok, :verified} | {:error, reason()}
  def verify_attestation(entry, _keys) do
    case parts(entry, :attestation) do
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The RFC 7515 detached compact serialization
  (`BASE64URL(JCS(protected)) .. BASE64URL(signature)`, empty payload
  segment per Appendix F) for standard-tooling cross-checks.
  """
  @spec to_compact(Json.value()) :: {:ok, binary()} | {:error, reason()}
  def to_compact(entry) do
    with {:ok, parts} <- parts(entry, :signature) do
      {:ok, parts.header_b64 <> "." <> "." <> Base64Url.encode(parts.signature)}
    end
  end

  # ---- shared engine ------------------------------------------------------------

  defp parts(entry, shape) do
    with {:ok, members} <- entry_members(entry, shape),
         {:ok, header} <- parse_header(members["protected"], shape),
         {:ok, attrs} <- parse_attrs(members["signed_attributes"], shape),
         :ok <- kid_matches(attrs, header, shape),
         {:ok, signature} <- parse_signature(members["signature"], shape),
         {:ok, header_b64, payload} <-
           canonical_input(members["protected"], members["signed_attributes"]) do
      attributes = if shape == :signature, do: attributes_struct(attrs), else: nil

      {:ok,
       %{
         header_b64: header_b64,
         payload: payload,
         signature: signature,
         key_id: elem(attrs["key_id"], 1),
         attributes: attributes
       }}
    else
      {:error, reason}
      when reason in [
             :signature_malformed,
             :attestation_malformed,
             :signature_algorithm_unsupported
           ] ->
        {:error, reason}

      # canonical_input's bare :error — a member value canonical
      # serialization rejects (e.g. invalid UTF-8 reaching a hand-built
      # entry; decoded entries are UTF-8-clean).
      :error ->
        {:error, malformed(shape)}
    end
  end

  defp entry_members({:object, members}, shape) do
    names = Enum.map(members, &elem(&1, 0))

    if length(names) == 3 and Enum.sort(names) == Enum.sort(@entry_members),
      do: {:ok, Map.new(members)},
      else: {:error, malformed(shape)}
  end

  defp entry_members(_not_an_object, shape), do: {:error, malformed(shape)}

  defp malformed(:signature), do: :signature_malformed
  defp malformed(:attestation), do: :attestation_malformed

  defp parse_header({:object, members}, shape) do
    names = Enum.map(members, &elem(&1, 0))

    if length(names) == 4 and Enum.sort(names) == Enum.sort(@header_members) do
      header = Map.new(members)

      with :ok <- alg_eddsa(header["alg"]),
           :ok <- exact_false(header["b64"]),
           :ok <- exact_crit(header["crit"]),
           {:ok, _kid} <- nonempty_string(header["kid"]) do
        {:ok, header}
      else
        {:error, :signature_algorithm_unsupported} = unsupported -> unsupported
        _other -> {:error, malformed(shape)}
      end
    else
      {:error, malformed(shape)}
    end
  end

  defp parse_header(_not_an_object, shape), do: {:error, malformed(shape)}

  defp alg_eddsa({:string, "EdDSA"}), do: :ok
  defp alg_eddsa({:string, _other}), do: {:error, :signature_algorithm_unsupported}
  defp alg_eddsa(_), do: :error

  defp exact_false({:boolean, false}), do: :ok
  defp exact_false(_), do: :error

  defp exact_crit({:array, [{:string, "b64"}]}), do: :ok
  defp exact_crit(_), do: :error

  defp nonempty_string({:string, s}) when s != "", do: {:ok, s}
  defp nonempty_string(_), do: :error

  defp parse_attrs({:object, members}, shape) do
    expected =
      if shape == :signature, do: @signature_attr_members, else: @attestation_attr_members

    names = Enum.map(members, &elem(&1, 0))

    if length(names) == 5 and Enum.sort(names) == Enum.sort(expected) do
      attrs = Map.new(members)

      with :ok <- algorithm_ed25519(attrs["algorithm"]),
           :ok <- tagged_digest(attrs["content_digest"] || attrs["statement_digest"]),
           :ok <- z_form_timestamp(attrs["created_at"]),
           :ok <- dot_free_key_id(attrs["key_id"]),
           :ok <- closed_member(attrs["purpose"] || attrs["kind"], shape) do
        {:ok, attrs}
      else
        {:error, :signature_algorithm_unsupported} = unsupported -> unsupported
        _other -> {:error, malformed(shape)}
      end
    else
      {:error, malformed(shape)}
    end
  end

  defp parse_attrs(_not_an_object, shape), do: {:error, malformed(shape)}

  defp algorithm_ed25519({:string, "Ed25519"}), do: :ok
  defp algorithm_ed25519({:string, _other}), do: {:error, :signature_algorithm_unsupported}
  defp algorithm_ed25519(_), do: :error

  defp tagged_digest({:string, tagged}) do
    case Digest.from_tagged(tagged) do
      {:ok, _digest} -> :ok
      {:error, _reason} -> :error
    end
  end

  defp tagged_digest(_), do: :error

  defp z_form_timestamp({:string, stamped}) do
    if Regex.match?(@created_at, stamped) and match?({:ok, _, _}, DateTime.from_iso8601(stamped)),
      do: :ok,
      else: :error
  end

  defp z_form_timestamp(_), do: :error

  defp dot_free_key_id({:string, key_id}) when key_id != "" do
    if String.contains?(key_id, "."), do: :error, else: :ok
  end

  defp dot_free_key_id(_), do: :error

  defp closed_member({:string, value}, :signature) do
    if Map.has_key?(@purposes, value), do: :ok, else: :error
  end

  defp closed_member({:string, value}, :attestation) do
    if Map.has_key?(@kinds, value), do: :ok, else: :error
  end

  defp closed_member(_, _), do: :error

  defp kid_matches(attrs, header, shape) do
    {:string, kid} = header["kid"]
    {:string, key_id} = attrs["key_id"]

    if kid == key_id, do: :ok, else: {:error, malformed(shape)}
  end

  defp parse_signature({:string, body}, shape) do
    case Base64Url.decode(body) do
      {:ok, <<_::512>> = signature} -> {:ok, signature}
      {:ok, _wrong_length} -> {:error, malformed(shape)}
      {:error, _reason} -> {:error, malformed(shape)}
    end
  end

  defp parse_signature(_, shape), do: {:error, malformed(shape)}

  defp canonical_input(header, attrs) do
    # RFC 7797 5.2: an unencoded payload containing "." can never appear in
    # a compact serialization. The dot-free key_id validation makes that
    # invariant hold by construction; every other member is dot-free from
    # its closed shape. (A belt re-check here would be an unreachable
    # branch — the coverage contract keeps guards live, not decorative.)
    with {:ok, header_json} <- wrap_encode(header),
         {:ok, attrs_json} <- wrap_encode(attrs) do
      {:ok, Base64Url.encode(header_json), attrs_json}
    end
  end

  defp wrap_encode(value) do
    case Canonicalization.encode(value) do
      {:ok, json} -> {:ok, json}
      {:error, _reason} -> :error
    end
  end

  defp attributes_struct(attrs) do
    {:string, purpose} = attrs["purpose"]

    %Attributes{
      algorithm: "Ed25519",
      content_digest: elem(Digest.from_tagged(elem(attrs["content_digest"], 1)), 1),
      created_at: elem(attrs["created_at"], 1),
      key_id: elem(attrs["key_id"], 1),
      purpose: @purposes[purpose]
    }
  end

  defp check(parts, input, keys) do
    candidates = for %PublicKey{key_id: id} = key <- keys, id == parts.key_id, do: key

    ed25519_keys =
      Enum.filter(candidates, fn
        %PublicKey{algorithm: :ed25519, key: <<encoding::binary-size(32)>>} ->
          usable_ed25519_key?(encoding)

        _not_usable_ed25519 ->
          false
      end)

    cond do
      candidates == [] ->
        {:error, :signature_key_unsupported}

      ed25519_keys == [] ->
        {:error, :signature_algorithm_unsupported}

      Enum.any?(ed25519_keys, fn key ->
        :crypto.verify(:eddsa, :none, input, parts.signature, [key.key, :ed25519])
      end) ->
        {:ok, :verified}

      true ->
        {:error, :signature_not_verified}
    end
  end

  # ---- small-order public-key rejection -------------------------------------------
  # Confirmed live on this OTP: :crypto.verify
  # ACCEPTS a small-order public key with an all-zero signature — a universal
  # forgery whenever such a key enters a trust set (a zeroed key is exactly
  # the "key failed to load" misconfiguration). A supplied key is usable
  # Ed25519 only if it decodes to a canonical on-curve point of the main
  # (large) subgroup. The test is the algebraic characterization of the
  # 8-torsion (as libsodium's ge25519_has_small_order computes it): x = 0,
  # or y = 0, or y*sqrt(-1) = +/- x. Field constants per RFC 8032 5.1;
  # the conformance suite recomputes d and sqrt(-1) from the curve
  # definition and asserts these literals.

  @ed_p 57_896_044_618_658_097_711_785_492_504_343_953_926_634_992_332_820_282_019_728_792_003_956_564_819_949
  @ed_d 37_095_705_934_669_439_343_138_083_508_754_565_189_542_113_879_843_219_016_388_785_533_085_940_283_555
  @ed_sqrt_m1 19_681_161_376_707_505_956_807_079_304_988_542_015_446_066_515_923_890_162_744_021_073_123_829_784_752

  defp usable_ed25519_key?(<<encoding::binary-size(32)>>) do
    <<y_raw::little-unsigned-256>> = encoding
    # RFC 8032 5.1.2: bit 255 carries the sign of x; the low 255 bits are y.
    sign_x = Bitwise.band(y_raw, Bitwise.bsl(1, 255)) != 0
    y = Bitwise.band(y_raw, Bitwise.bsl(1, 255) - 1)

    if y >= @ed_p do
      # Non-canonical y — not a valid encoding.
      false
    else
      yy = Integer.mod(y * y, @ed_p)
      denominator = Integer.mod(@ed_d * yy + 1, @ed_p)

      x2 = Integer.mod((y * y - 1) * mod_pow(denominator, @ed_p - 2), @ed_p)

      # p = 2^255 - 19 is 5 mod 8: the square root is z = a^((p+3)/8),
      # corrected by sqrt(-1) when z^2 = -a. (The a^((p+1)/4) shortcut is
      # INVALID for this p — a mistake this comment records so it never
      # returns.)
      z = mod_pow(x2, div(@ed_p + 3, 8))

      root =
        cond do
          Integer.mod(z * z - x2, @ed_p) == 0 -> z
          Integer.mod(z * z + x2, @ed_p) == 0 -> Integer.mod(z * @ed_sqrt_m1, @ed_p)
          true -> nil
        end

      case root do
        nil ->
          # (y^2 - 1)/(d*y^2 + 1) is not a square — not on the curve.
          false

        0 ->
          # root == 0 happens iff y ∈ {1, p-1} — the identity (order 1) and
          # the order-2 point. The sign-set encodings are non-canonical
          # (RFC 8032 5.1.2) and the sign-clear ones are canonical but
          # small-order; BOTH reject. (Found by the second-language
          # verifier's torsion battery: the previous `not sign_x` admitted the
          # sign-clear half — the exact forgery class this guard exists for.)
          false

        root ->
          not small_order?(canonical_x(root, sign_x), y)
      end
    end
  end

  defp canonical_x(root, sign_x) do
    root_odd = Bitwise.band(root, 1) == 1

    if sign_x == root_odd,
      do: root,
      else: @ed_p - root
  end

  defp small_order?(x, y) do
    y_sqrt_m1 = Integer.mod(y * @ed_sqrt_m1, @ed_p)

    x == 0 or y == 0 or y_sqrt_m1 == x or y_sqrt_m1 == @ed_p - x
  end

  defp mod_pow(base, exponent) do
    mod_pow_loop(base, exponent, 1)
  end

  defp mod_pow_loop(_base, 0, acc), do: acc

  defp mod_pow_loop(base, exponent, acc) do
    acc = if Bitwise.band(exponent, 1) == 1, do: Integer.mod(acc * base, @ed_p), else: acc
    mod_pow_loop(Integer.mod(base * base, @ed_p), Bitwise.bsr(exponent, 1), acc)
  end
end
