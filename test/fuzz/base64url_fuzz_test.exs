defmodule AgentBlueprintProtocol.Base64UrlFuzzTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentBlueprintProtocol.Base64Url

  property "arbitrary strings never raise; the result is always ok or a closed reason" do
    check all(input <- StreamData.string(:ascii), max_runs: 2000) do
      case Base64Url.decode(input) do
        {:ok, _bytes} -> :ok
        {:error, reason} -> assert reason in [:base64url_invalid, :base64url_padded]
      end
    end
  end

  property "arbitrary UTF-8 strings never raise either" do
    check all(input <- StreamData.string(:utf8), max_runs: 500) do
      case Base64Url.decode(input) do
        {:ok, _bytes} -> :ok
        {:error, reason} -> assert reason in [:base64url_invalid, :base64url_padded]
      end
    end
  end

  # The documented contract is totality over ALL binaries — raw byte inputs
  # (invalid UTF-8 included), not only printable strings.
  property "arbitrary raw binaries never raise" do
    check all(input <- StreamData.binary(), max_runs: 2000) do
      case Base64Url.decode(input) do
        {:ok, _bytes} -> :ok
        {:error, reason} -> assert reason in [:base64url_invalid, :base64url_padded]
      end
    end
  end
end
