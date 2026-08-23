defmodule AgentBlueprintProtocol.Base64Url do
  @moduledoc """
  Strict unpadded base64url codec: the RFC 4648 §5 URL-safe alphabet with
  all trailing `=` omitted (RFC 7515 §2 permits omission on the wire; this
  protocol's wire form never carries padding, so padded input rejects).

  Decoding is total over binaries and rejects, in order:

    - any input carrying `=` anywhere — `:base64url_padded`;
    - any character outside the URL-safe alphabet — `:base64url_invalid`
      (RFC 4648 §3.3: non-alphabet characters MUST be rejected);
    - any spelling that is not the byte-exact encoding of its own decoded
      bytes — `:base64url_invalid`. This covers encoded lengths that are
      not a whole number of octets (≡ 1 mod 4) and, per RFC 4648 §3.5,
      non-canonical spellings whose pad bits are non-zero: those alias the
      same bytes under a different string, and accepting one would let two
      distinct digest bodies decode identically.

  Canonicality is enforced the same way
  `AgentBlueprintProtocol.Canonicalization.verify/2` enforces canonical
  JSON: decode, re-encode, require byte equality. The stdlib `Base` module
  supplies bit assembly only — probed on this OTP, `Base.url_decode64/2`
  alone accepts fully-padded input and non-zero pad bits, so every strict
  rejection above is this module's own guard.
  A pure codec — bytes in, bytes out; it never authorizes anything.
  """

  @alphabet ~r/\A[A-Za-z0-9_-]*\z/

  @type reason :: :base64url_invalid | :base64url_padded

  @doc """
  Encode `data` as unpadded base64url. The empty binary encodes to the
  empty string (RFC 7515 §2).
  """
  @spec encode(binary()) :: binary()
  def encode(data) when is_binary(data), do: Base.url_encode64(data, padding: false)

  @doc """
  Decode strict unpadded base64url. Never raises on binary input; errors
  are value-free.
  """
  @spec decode(binary()) :: {:ok, binary()} | {:error, reason()}
  def decode(input) when is_binary(input) do
    cond do
      String.contains?(input, "=") -> {:error, :base64url_padded}
      not Regex.match?(@alphabet, input) -> {:error, :base64url_invalid}
      true -> decode_canonical(input)
    end
  end

  defp decode_canonical(input) do
    case Base.url_decode64(input, padding: false) do
      {:ok, bytes} ->
        if encode(bytes) == input, do: {:ok, bytes}, else: {:error, :base64url_invalid}

      :error ->
        {:error, :base64url_invalid}
    end
  end
end
