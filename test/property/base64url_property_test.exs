defmodule AgentBlueprintProtocol.Base64UrlPropertyTest do
  @moduledoc """
  Properties of the strict base64url codec: total round-trip, agreement
  with the stdlib encoder on canonical output, and total rejection of
  padded or non-alphabet spellings (RFC 4648 §3.3/§3.5).
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentBlueprintProtocol.Base64Url

  property "decode of encode is the identity on every binary" do
    check all(data <- StreamData.binary()) do
      assert Base64Url.decode(Base64Url.encode(data)) == {:ok, data}
    end
  end

  property "encode agrees with the stdlib unpadded URL encoder" do
    check all(data <- StreamData.binary()) do
      assert Base64Url.encode(data) == Base.url_encode64(data, padding: false)
    end
  end

  property "encoded output is alphabet-only with the length class implied by the input" do
    check all(data <- StreamData.binary()) do
      encoded = Base64Url.encode(data)

      assert Regex.match?(~r/\A[A-Za-z0-9_-]*\z/, encoded)

      n = byte_size(data)
      expected_length = div(n, 3) * 4 + Enum.at([0, 2, 3], rem(n, 3))

      assert byte_size(encoded) == expected_length
    end
  end

  property "any string carrying a pad character is rejected as padded" do
    check all(
            prefix <- StreamData.string(:alphanumeric),
            suffix <- StreamData.string(:alphanumeric),
            pad <- StreamData.member_of(["=", "==", "==="])
          ) do
      assert Base64Url.decode(prefix <> pad <> suffix) == {:error, :base64url_padded}
    end
  end

  property "no two spellings of one encoding decode to the same bytes (anti-aliasing)" do
    alphabet = Enum.to_list(?A..?Z) ++ Enum.to_list(?a..?z) ++ Enum.to_list(?0..?9) ++ [?-, ?_]

    check all(
            data <- StreamData.binary(min_length: 1, max_length: 12),
            other <- StreamData.member_of(alphabet)
          ) do
      encoded = Base64Url.encode(data)
      last_index = byte_size(encoded) - 1
      <<head::binary-size(^last_index), last>> = encoded

      if other != last do
        # A tampered final character must either be rejected as non-canonical
        # or decode to DIFFERENT bytes — never alias the original spelling.
        refute Base64Url.decode(head <> <<other>>) == {:ok, data}
      end
    end
  end
end
