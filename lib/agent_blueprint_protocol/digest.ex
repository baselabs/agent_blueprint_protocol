defmodule AgentBlueprintProtocol.Digest do
  @moduledoc """
  Tagged content digests over RFC 8785 canonical bytes.

  The wire form is the self-identifying tagged string
  `"sha-256:<43-char unpadded base64url>"` — a consumer never guesses the
  algorithm or encoding from length. Preimages are domain-separated —
  `SHA-256(separator || <<0>> || jcs_bytes)` — under the registered
  separator for the hashing domain (base §8.2), so a digest transplanted
  across domains never verifies.

  **Canonicality is the caller's contract.** `hash/2` and `verify_content/3`
  treat the covered bytes as opaque: callers MUST pass canonical JCS bytes.
  The enforcement point is where received bytes enter the package — the
  artifact decode path verifies canonicality first (digests are
  computed only over exact received bytes). This module does not re-verify,
  so hashing never double-parses a document nor leaks the JSON reason set
  into this vocabulary.

  The algorithm set is closed (`:sha256`); algorithm succession is a data
  change plus a protocol revision, never a format change — an unknown tag
  denies `:digest_algorithm_unsupported` and any malformed body denies
  `:digest_encoding_invalid`, uniformly. SHA-256 conformance (FIPS 180-4
  known-answer vectors) is pinned in the conformance suite.
  A digest is an identity fact about bytes; it never authorizes anything.
  A digest is an identity fact about bytes; it never authorizes anything.
  """

  alias AgentBlueprintProtocol.Base64Url

  @enforce_keys [:algorithm, :bytes]
  defstruct [:algorithm, :bytes]

  @type algorithm :: :sha256

  @type domain ::
          :blueprint_content
          | :deployment_content
          | :federation_envelope
          | :signature
          | :extension_schema
          | :extension_registry
          | :conformance_report
          | :corpus_index

  @type t :: %__MODULE__{algorithm: algorithm(), bytes: <<_::256>>}

  @type reason :: :digest_algorithm_unsupported | :digest_encoding_invalid | :digest_mismatch

  @tags %{sha256: "sha-256"}
  @sizes %{sha256: 32}

  # Base §8.2's normative separator table: constants with no version token,
  # because protocol_revision is itself a covered member inside the bytes.
  @separators %{
    blueprint_content: "agent-blueprint-protocol/blueprint-content",
    deployment_content: "agent-blueprint-protocol/deployment-content",
    federation_envelope: "agent-blueprint-protocol/federation-envelope",
    signature: "agent-blueprint-protocol/signature",
    extension_schema: "agent-blueprint-protocol/extension-schema",
    extension_registry: "agent-blueprint-protocol/extension-registry",
    conformance_report: "agent-blueprint-protocol/conformance-report",
    corpus_index: "agent-blueprint-protocol/corpus-index"
  }

  @doc "SHA-256 of `data` as a tagged digest value."
  @spec of(iodata()) :: t()
  def of(data), do: %__MODULE__{algorithm: :sha256, bytes: :crypto.hash(:sha256, data)}

  @doc """
  Domain-separated digest over canonical JCS bytes: the base §8.2 preimage
  `separator || <<0>> || jcs_bytes` under the registered separator for
  `domain`. An unknown domain is an internal invariant and raises loudly.
  """
  @spec hash(domain(), iodata()) :: t()
  def hash(domain, data), do: of([Map.fetch!(@separators, domain), <<0>>, data])

  @doc ~S"""
  The wire form `"sha-256:<43-char unpadded base64url>"`. The clause matches
  the 256-bit `t()` byte shape, so a hand-built struct with wrong-size bytes
  fails loud (a `FunctionClauseError` invariant) rather than emitting a
  non-conforming wire string.
  """
  @spec to_tagged(t()) :: binary()
  def to_tagged(%__MODULE__{algorithm: algorithm, bytes: <<_::256>> = bytes}),
    do: Map.fetch!(@tags, algorithm) <> ":" <> Base64Url.encode(bytes)

  @doc """
  Parse a tagged digest string. A string with no colon is not a tagged
  digest (`:digest_encoding_invalid`). A tag segment that does not exactly
  match a registered algorithm tag denies `:digest_algorithm_unsupported` —
  case and hyphenation variants and the empty tag included. Every body
  defect denies `:digest_encoding_invalid` uniformly: wrong length (a
  sha-256 body decodes to exactly 32 bytes), non-alphabet characters,
  padding, non-canonical pad bits, extra colons.
  """
  @spec from_tagged(binary()) :: {:ok, t()} | {:error, reason()}
  def from_tagged(input) when is_binary(input) do
    case String.split(input, ":", parts: 2) do
      [tag, body] ->
        with {:ok, algorithm} <- tag_lookup(tag),
             {:ok, bytes} <- body_lookup(algorithm, body) do
          {:ok, %__MODULE__{algorithm: algorithm, bytes: bytes}}
        end

      [_] ->
        {:error, :digest_encoding_invalid}
    end
  end

  @doc """
  Constant-time equality over the digest bytes: the comparison accumulates
  the XOR of every byte pair and tests once at the end, so no early exit
  leaks the position of a difference. Length and algorithm equality are
  checked first and may short-circuit — both are public shape, carried in
  the tagged wire form itself. This is defense-in-depth: a digest is public
  once tagged; the guarantee matters where one side is not yet public.
  """
  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{algorithm: a1, bytes: b1}, %__MODULE__{algorithm: a2, bytes: b2}) do
    byte_size(b1) == byte_size(b2) and a1 == a2 and xor_zero?(b1, b2, 0)
  end

  @doc """
  Verify that `tagged` is the honest `hash(domain, jcs_bytes)`: parse first
  (a malformed tagged string denies with its `from_tagged/1` reason, before
  any comparison), then constant-time equality — a well-formed but
  divergent digest denies `:digest_mismatch`. `jcs_bytes` are the caller's
  canonical covered bytes (see the moduledoc contract).
  """
  @spec verify_content(domain(), binary(), binary()) :: :ok | {:error, reason()}
  def verify_content(domain, jcs_bytes, tagged)
      when is_binary(jcs_bytes) and is_binary(tagged) do
    with {:ok, declared} <- from_tagged(tagged) do
      if equal?(hash(domain, jcs_bytes), declared), do: :ok, else: {:error, :digest_mismatch}
    end
  end

  # ---- internals ----------------------------------------------------------------

  defp tag_lookup(tag) do
    case Enum.find(@tags, fn {_algorithm, spelled} -> spelled == tag end) do
      {algorithm, _spelled} -> {:ok, algorithm}
      nil -> {:error, :digest_algorithm_unsupported}
    end
  end

  defp body_lookup(algorithm, body) do
    expected_size = Map.fetch!(@sizes, algorithm)

    case Base64Url.decode(body) do
      {:ok, bytes} when byte_size(bytes) == expected_size -> {:ok, bytes}
      {:ok, _wrong_length} -> {:error, :digest_encoding_invalid}
      {:error, _body_reason} -> {:error, :digest_encoding_invalid}
    end
  end

  defp xor_zero?(<<a, rest_a::binary>>, <<b, rest_b::binary>>, acc),
    do: xor_zero?(rest_a, rest_b, Bitwise.bor(Bitwise.bxor(a, b), acc))

  defp xor_zero?(<<>>, <<>>, acc), do: acc == 0
end
