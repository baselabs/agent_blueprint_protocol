defmodule AgentBlueprintProtocol.Digest do
  @moduledoc """
    This module creates, parses, and compares tagged SHA-256 digests.

    Use it when computing or checking a digest over canonical bytes.

    This module does not authorize operations.

    ## Example

    ```elixir
    match?(
      "sha-256:" <> _,
      AgentBlueprintProtocol.Digest.to_tagged(
        AgentBlueprintProtocol.Digest.hash(:blueprint_content, "{}")
      )
    )
    ```
  """
  @moduledoc since: "1.0.0"

  alias AgentBlueprintProtocol.Base64Url

  @enforce_keys [:algorithm, :bytes]
  defstruct [:algorithm, :bytes]

  @typedoc """
    The digest algorithm identifier supported by this release.
  """
  @type algorithm :: :sha256

  @typedoc """
    A closed digest domain used to separate protocol digest inputs.
  """
  @type domain ::
          :blueprint_content
          | :deployment_content
          | :federation_envelope
          | :signature
          | :extension_schema
          | :extension_registry
          | :conformance_report
          | :corpus_index

  @typedoc """
    The public data type for AgentBlueprintProtocol.Digest.
  """
  @type t :: %__MODULE__{algorithm: algorithm(), bytes: <<_::256>>}

  @tags %{sha256: "sha-256"}
  @sizes %{sha256: 32}

  # protocol §5's normative separator table: constants with no version token,
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

  @spec of(iodata()) :: t() | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
    Creates a SHA-256 digest from the supplied bytes.

    ## Example

        iex> match?(%AgentBlueprintProtocol.Digest{algorithm: :sha256, bytes: <<_::256>>}, AgentBlueprintProtocol.Digest.of("abc"))
        true
  """
  @doc since: "1.0.0"
  def of(data) do
    if iodata?(data),
      do: %__MODULE__{algorithm: :sha256, bytes: :crypto.hash(:sha256, data)},
      else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
  end

  @spec hash(domain(), iodata()) :: t() | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
    Creates a domain-separated digest from the supplied bytes.

    ## Example

        iex> match?(%AgentBlueprintProtocol.Digest{algorithm: :sha256, bytes: <<_::256>>}, AgentBlueprintProtocol.Digest.hash(:blueprint_content, "{}"))
        true
  """
  @doc since: "1.0.0"
  def hash(domain, data) do
    case Map.fetch(@separators, domain) do
      {:ok, separator} -> of([separator, <<0>>, data])
      :error -> {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
    end
  end

  @spec to_tagged(t()) :: binary() | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
    Formats a digest as its tagged wire string.

    ## Example

        iex> digest = AgentBlueprintProtocol.Digest.hash(:blueprint_content, "{}")
        iex> String.starts_with?(AgentBlueprintProtocol.Digest.to_tagged(digest), "sha-256:")
        true
  """
  @doc since: "1.0.0"
  def to_tagged(%__MODULE__{algorithm: :sha256 = algorithm, bytes: <<_::256>> = bytes}),
    do: Map.fetch!(@tags, algorithm) <> ":" <> Base64Url.encode(bytes)

  def to_tagged(_), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  @spec from_tagged(binary()) :: {:ok, t()} | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
    Parses a tagged digest string.

    ## Example

        iex> match?({:ok, %AgentBlueprintProtocol.Digest{algorithm: :sha256}}, AgentBlueprintProtocol.Digest.from_tagged("sha-256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"))
        true
  """
  @doc since: "1.0.0"
  def from_tagged(input) when is_binary(input) do
    case String.split(input, ":", parts: 2) do
      [tag, body] ->
        with {:ok, algorithm} <- tag_lookup(tag),
             {:ok, bytes} <- body_lookup(algorithm, body) do
          {:ok, %__MODULE__{algorithm: algorithm, bytes: bytes}}
        end

      [_] ->
        {:error, %AgentBlueprintProtocol.Error{code: :digest_encoding_invalid}}
    end
  end

  def from_tagged(_), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  @spec equal?(t(), t()) :: boolean()
  @doc """
    Compares two values for equality under this module’s rules.

    ## Example

        iex> AgentBlueprintProtocol.Digest.equal?(AgentBlueprintProtocol.Digest.hash(:signature, "input"), AgentBlueprintProtocol.Digest.hash(:signature, "input"))
        true
  """
  @doc since: "1.0.0"
  def equal?(%__MODULE__{algorithm: a1, bytes: b1}, %__MODULE__{algorithm: a2, bytes: b2}) do
    binaries? = is_binary(b1) and is_binary(b2)
    binaries? and byte_size(b1) == byte_size(b2) and a1 == a2 and xor_zero?(b1, b2, 0)
  end

  def equal?(_, _), do: false

  @spec verify_content(domain(), binary(), binary()) ::
          :ok | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
    Checks a tagged digest against the supplied content and domain.

    ## Example

        iex> bytes = "{}"; tagged = AgentBlueprintProtocol.Digest.hash(:blueprint_content, bytes) |> AgentBlueprintProtocol.Digest.to_tagged(); AgentBlueprintProtocol.Digest.verify_content(:blueprint_content, bytes, tagged)
        :ok
  """
  @doc since: "1.0.0"
  def verify_content(domain, jcs_bytes, tagged)
      when is_map_key(@separators, domain) and is_binary(jcs_bytes) and is_binary(tagged) do
    with {:ok, declared} <- from_tagged(tagged) do
      if equal?(hash(domain, jcs_bytes), declared),
        do: :ok,
        else: {:error, %AgentBlueprintProtocol.Error{code: :digest_mismatch}}
    end
  end

  def verify_content(_, _, _), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp iodata?(data) when is_binary(data), do: true
  defp iodata?([]), do: true

  defp iodata?([head | tail]) when is_integer(head) and head >= 0 and head <= 255,
    do: iodata?(tail)

  defp iodata?([head | tail]), do: iodata?(head) and iodata?(tail)
  defp iodata?(_), do: false

  # ---- internals ----------------------------------------------------------------

  defp tag_lookup(tag) do
    case Enum.find(@tags, fn {_algorithm, spelled} -> spelled == tag end) do
      {algorithm, _spelled} -> {:ok, algorithm}
      nil -> {:error, %AgentBlueprintProtocol.Error{code: :digest_algorithm_unsupported}}
    end
  end

  defp body_lookup(algorithm, body) do
    expected_size = Map.fetch!(@sizes, algorithm)

    case Base64Url.decode(body) do
      {:ok, bytes} when byte_size(bytes) == expected_size ->
        {:ok, bytes}

      {:ok, _wrong_length} ->
        {:error, %AgentBlueprintProtocol.Error{code: :digest_encoding_invalid}}

      {:error, _body_reason} ->
        {:error, %AgentBlueprintProtocol.Error{code: :digest_encoding_invalid}}
    end
  end

  defp xor_zero?(<<a, rest_a::binary>>, <<b, rest_b::binary>>, acc),
    do: xor_zero?(rest_a, rest_b, Bitwise.bor(Bitwise.bxor(a, b), acc))

  defp xor_zero?(<<>>, <<>>, acc), do: acc == 0
end
