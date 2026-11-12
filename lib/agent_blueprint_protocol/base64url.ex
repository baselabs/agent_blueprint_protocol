defmodule AgentBlueprintProtocol.Base64Url do
  @moduledoc """
    This module encodes and decodes strict unpadded base64url values.

    Use it when a protocol field contains URL-safe binary data.

    This module does not authorize operations.

    ## Example

    ```elixir
    encoded = AgentBlueprintProtocol.Base64Url.encode("sample")
    {:ok, "sample"} = AgentBlueprintProtocol.Base64Url.decode(encoded)
    ```
  """
  @moduledoc since: "1.0.0"

  @alphabet ~r/\A[A-Za-z0-9_-]*\z/

  @spec encode(binary()) :: binary() | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
    Encodes a binary as unpadded base64url.

    ## Example

        iex> AgentBlueprintProtocol.Base64Url.encode("abc")
        "YWJj"
  """
  @doc since: "1.0.0"
  def encode(data) when is_binary(data), do: Base.url_encode64(data, padding: false)

  def encode(_), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  @spec decode(binary()) :: {:ok, binary()} | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
    Decodes unpadded base64url text to binary bytes; rejects padding and invalid encodings.

    ## Example

        iex> AgentBlueprintProtocol.Base64Url.decode("YWJj")
        {:ok, "abc"}
  """
  @doc since: "1.0.0"
  def decode(input) when is_binary(input) do
    cond do
      String.contains?(input, "=") ->
        {:error, %AgentBlueprintProtocol.Error{code: :base64url_padded}}

      not Regex.match?(@alphabet, input) ->
        {:error, %AgentBlueprintProtocol.Error{code: :base64url_invalid}}

      true ->
        decode_canonical(input)
    end
  end

  def decode(_), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp decode_canonical(input) do
    case Base.url_decode64(input, padding: false) do
      {:ok, bytes} ->
        if encode(bytes) == input,
          do: {:ok, bytes},
          else: {:error, %AgentBlueprintProtocol.Error{code: :base64url_invalid}}

      :error ->
        {:error, %AgentBlueprintProtocol.Error{code: :base64url_invalid}}
    end
  end
end
