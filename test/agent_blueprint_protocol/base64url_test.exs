defmodule AgentBlueprintProtocol.Base64UrlTest do
  @moduledoc """
  Unit contract for the strict unpadded base64url codec: RFC 4648 §5
  alphabet, RFC 7515 §2 padding omission, and RFC 4648 §3.5 canonical
  encoding (non-zero pad bits are a distinct spelling of the same bytes and
  must be rejected, or digest identity breaks).
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.Base64Url

  describe "encode/1 (unpadded, RFC 4648 §5 alphabet)" do
    test "empty octets encode to the empty string (RFC 7515 §2)" do
      assert Base64Url.encode(<<>>) == ""
    end

    test "one byte encodes to two characters" do
      assert Base64Url.encode("A") == "QQ"
    end

    test "two bytes encode to three characters" do
      assert Base64Url.encode(<<0xFB, 0xFF>>) == "-_8"
    end

    test "three bytes encode to four characters, no padding" do
      assert Base64Url.encode(<<0, 0, 0>>) == "AAAA"
    end

    test "matches the stdlib encoder on every length class" do
      for n <- 0..8 do
        data =
          if n == 0 do
            <<>>
          else
            for i <- 0..(n - 1)//1, into: <<>>, do: <<rem(i * 37, 256)>>
          end

        assert Base64Url.encode(data) == Base.url_encode64(data, padding: false)
      end
    end
  end

  describe "decode/1 valid" do
    test "every length class round-trips" do
      samples = ["", "A", <<0xFB, 0xFF>>, <<0, 0, 0>>, "canonical bytes", <<0xFF, 0, 0xFF>>]

      for data <- samples do
        assert Base64Url.decode(Base64Url.encode(data)) == {:ok, data}
      end
    end

    test "a three-character quantum with zero pad bits decodes" do
      assert Base64Url.decode("QQQ") == {:ok, <<65, 4>>}
    end
  end

  describe "decode/1 rejects padded input (:base64url_padded)" do
    test "full padding" do
      assert Base64Url.decode("QQ==") == {:error, :base64url_padded}
    end

    test "partial padding" do
      assert Base64Url.decode("QQ=") == {:error, :base64url_padded}
    end

    test "interior or leading pad characters are still padding" do
      assert Base64Url.decode("Q=Q") == {:error, :base64url_padded}
      assert Base64Url.decode("=QQ") == {:error, :base64url_padded}
    end
  end

  describe "decode/1 rejects malformed input (:base64url_invalid)" do
    test "non-alphabet characters, including the standard-alphabet + and /" do
      assert Base64Url.decode("A+B") == {:error, :base64url_invalid}
      assert Base64Url.decode("A/B") == {:error, :base64url_invalid}
      assert Base64Url.decode("A B") == {:error, :base64url_invalid}
      assert Base64Url.decode("A.B") == {:error, :base64url_invalid}
      assert Base64Url.decode("ünicode") == {:error, :base64url_invalid}
    end

    test "dangling single character (encoded length ≡ 1 mod 4)" do
      assert Base64Url.decode("Q") == {:error, :base64url_invalid}
      assert Base64Url.decode("QQQQQ") == {:error, :base64url_invalid}
    end

    test "non-zero pad bits are a non-canonical aliasing spelling (RFC 4648 §3.5)" do
      # "QR" and "QQ" decode to the same byte; both cannot be valid spellings.
      assert Base64Url.decode("QQ") == {:ok, "A"}
      assert Base64Url.decode("QR") == {:error, :base64url_invalid}
      assert Base64Url.decode("QRR") == {:error, :base64url_invalid}
    end
  end
end
