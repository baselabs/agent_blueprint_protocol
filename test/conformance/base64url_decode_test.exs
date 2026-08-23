defmodule AgentBlueprintProtocol.Conformance.Base64UrlDecodeTest do
  @moduledoc """
  Conformance corpus row `base64url.decode` (spec applicability floor):
  valid · invalid_encoding (padded, non-alphabet) · exact_bound. A pure
  codec — no artifact semantics reach it. Strictness follows RFC 4648 §3.2
  (padding omitted only when the referring spec says so — RFC 7515 §2 says
  so here), §3.3 (non-alphabet characters MUST be rejected), and §3.5 (a
  canonical encoding requires zero pad bits, or spellings alias).
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.Base64Url

  describe "class: valid" do
    test "each byte-length residue class (mod 3) decodes" do
      # 0 bytes -> "", 1 byte -> 2 chars, 2 bytes -> 3 chars, 3 bytes -> 4 chars
      assert Base64Url.decode("") == {:ok, ""}
      assert Base64Url.decode("QQ") == {:ok, "A"}
      assert Base64Url.decode("-_8") == {:ok, <<0xFB, 0xFF>>}
      assert Base64Url.decode("AAAA") == {:ok, <<0, 0, 0>>}
    end

    test "every alphabet character is accepted in each case form" do
      # The 64-character URL-safe alphabet exercising upper, lower, digit,
      # minus, and underscore: 12 bytes -> 16 chars, one per alphabet class mix.
      assert {:ok, decoded} = Base64Url.decode("ABCDEFGHIJKLMNOP")
      assert byte_size(decoded) == 12
      assert {:ok, _} = Base64Url.decode("qrstuvwxyz012345")
      assert {:ok, _} = Base64Url.decode("__--__--__--")
    end
  end

  describe "class: invalid_encoding (padded)" do
    test "trailing full and partial padding" do
      assert Base64Url.decode("QQ==") == {:error, :base64url_padded}
      assert Base64Url.decode("QQ=") == {:error, :base64url_padded}
      assert Base64Url.decode("TQ==") == {:error, :base64url_padded}
    end

    test "pad characters in any position" do
      assert Base64Url.decode("=QQ") == {:error, :base64url_padded}
      assert Base64Url.decode("Q=Q") == {:error, :base64url_padded}
    end
  end

  describe "class: invalid_encoding (non-alphabet)" do
    test "standard base64 alphabet characters are not base64url" do
      assert Base64Url.decode("A+B") == {:error, :base64url_invalid}
      assert Base64Url.decode("A/B") == {:error, :base64url_invalid}
    end

    test "whitespace and other non-alphabet bytes" do
      assert Base64Url.decode("A B") == {:error, :base64url_invalid}
      assert Base64Url.decode("A\nB") == {:error, :base64url_invalid}
      assert Base64Url.decode("A.B") == {:error, :base64url_invalid}
      assert Base64Url.decode("AéB") == {:error, :base64url_invalid}
    end
  end

  describe "class: exact_bound" do
    test "encoded lengths ≡ 0, 2, 3 (mod 4) are the valid shapes" do
      assert {:ok, _} = Base64Url.decode("QQQQ")
      assert {:ok, _} = Base64Url.decode("QQ")
      assert {:ok, _} = Base64Url.decode("QQQ")
    end

    test "encoded lengths ≡ 1 (mod 4) can never be a whole number of bytes" do
      assert Base64Url.decode("Q") == {:error, :base64url_invalid}
      assert Base64Url.decode("QQQQQ") == {:error, :base64url_invalid}
      assert Base64Url.decode("QQQQQQQQQ") == {:error, :base64url_invalid}
    end

    test "the pad-bit boundary of the last quantum" do
      # Both spellings decode to the same bytes under a tolerant decoder;
      # only the zero-pad-bit one is canonical and only it may be accepted.
      assert Base64Url.decode("QQQ") == {:ok, <<65, 4>>}
      assert Base64Url.decode("QRR") == {:error, :base64url_invalid}
    end
  end
end
