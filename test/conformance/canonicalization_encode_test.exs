defmodule AgentBlueprintProtocol.Conformance.CanonicalizationEncodeTest do
  @moduledoc """
  Conformance corpus row `canonicalization.encode`. Byte-exact vectors from
  RFC 8785 itself: the Appendix B number table (all 24 finite rows, floats
  built from the published IEEE 754 bit patterns), the §3.2.2
  escaping/numbers sample, the §3.2.3 sorting sample, and the
  probe-derived vectors. The 2 non-finite Appendix B rows (NaN, Infinity)
  cannot be constructed on the BEAM (see the design note) and are covered by
  that platform invariant instead.
  """
  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Canonicalization, Json}

  # RFC 8785 Appendix B, Table 1 — {IEEE 754 hex, JSON representation}
  @app_b_finite [
    {0x0000_0000_0000_0000, "0"},
    {0x8000_0000_0000_0000, "0"},
    {0x0000_0000_0000_0001, "5e-324"},
    {0x8000_0000_0000_0001, "-5e-324"},
    {0x7FEF_FFFF_FFFF_FFFF, "1.7976931348623157e+308"},
    {0xFFEF_FFFF_FFFF_FFFF, "-1.7976931348623157e+308"},
    {0x4340_0000_0000_0000, "9007199254740992"},
    {0xC340_0000_0000_0000, "-9007199254740992"},
    {0x4430_0000_0000_0000, "295147905179352830000"},
    {0x44B5_2D02_C7E1_4AF5, "9.999999999999997e+22"},
    {0x44B5_2D02_C7E1_4AF6, "1e+23"},
    {0x44B5_2D02_C7E1_4AF7, "1.0000000000000001e+23"},
    {0x444B_1AE4_D6E2_EF4E, "999999999999999700000"},
    {0x444B_1AE4_D6E2_EF4F, "999999999999999900000"},
    {0x444B_1AE4_D6E2_EF50, "1e+21"},
    {0x3EB0_C6F7_A0B5_ED8C, "9.999999999999997e-7"},
    {0x3EB0_C6F7_A0B5_ED8D, "0.000001"},
    {0x41B3_DE43_5555_5553, "333333333.3333332"},
    {0x41B3_DE43_5555_5554, "333333333.33333325"},
    {0x41B3_DE43_5555_5555, "333333333.3333333"},
    {0x41B3_DE43_5555_5556, "333333333.3333334"},
    {0x41B3_DE43_5555_5557, "333333333.33333343"},
    {0xBECB_F647_612F_3696, "-0.0000033333333333333333"},
    {0x4314_3FF3_C1CB_0959, "1424953923781206.2"}
  ]

  describe "class: valid — RFC 8785 Appendix B number table, byte-exact" do
    test "every finite row serializes exactly as published" do
      for {hex, expected} <- @app_b_finite do
        assert {:ok, float} = float_from_hex(hex)
        assert Canonicalization.number(float) == {:ok, expected}

        assert Canonicalization.encode({:object, [{"n", {:float, float}}]}) ==
                 {:ok, "{\"n\":" <> expected <> "}"}
      end
    end
  end

  describe "class: valid — ticket probe-derived vectors" do
    test "the exact divergences that motivated hand-written ES6 serialization" do
      assert Canonicalization.number(1.0) == {:ok, "1"}
      assert Canonicalization.number(1.0e22) == {:ok, "1e+22"}
      assert Canonicalization.number(-0.0) == {:ok, "0"}
      assert Canonicalization.number(5.0e-324) == {:ok, "5e-324"}

      assert Canonicalization.number(1.797_693_134_862_315_7e308) ==
               {:ok, "1.7976931348623157e+308"}
    end
  end

  describe "class: valid — RFC 8785 §3.2.2 sample (escaping + numbers)" do
    test "decode then encode reproduces the RFC's canonical line byte-exactly" do
      input = ~S"""
      {
        "numbers": [333333333.33333329, 1E30, 4.50,
                    2e-3, 0.000000000000000000000000001],
        "string": "\u20ac$\u000F\u000aA'\u0042\u0022\u005c\\\"\/",
        "literals": [null, true, false]
      }
      """

      expected =
        ~S({"literals":[null,true,false],"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],) <>
          ~S("string":"€$\u000f\nA'B\"\\\\\"/"})

      assert {:ok, value} = Json.decode(input)
      assert Canonicalization.encode(value) == {:ok, expected}

      # verify re-decodes the canonical bytes, so its value is in canonical
      # member order — the fixed-point chain, not input order.
      assert {:ok, decoded} = Json.decode(expected)
      assert Canonicalization.verify(expected) == {:ok, decoded}
      assert Canonicalization.encode(decoded) == {:ok, expected}
    end
  end

  describe "class: valid — RFC 8785 §3.2.3 sorting sample" do
    test "the seven-key object canonicalizes with UTF-16 code-unit order" do
      input = ~S"""
      {
        "\u20ac": "Euro Sign",
        "\r": "Carriage Return",
        "\ufb33": "Hebrew Letter Dalet With Dagesh",
        "1": "One",
        "\ud83d\ude00": "Emoji: Grinning Face",
        "\u0080": "Control",
        "\u00f6": "Latin Small Letter O With Diaeresis"
      }
      """

      # The RFC's published argument order, as data; JSON syntax is joined
      # mechanically below.
      ordered_members = [
        {"\\r", "Carriage Return"},
        {"1", "One"},
        {"\u0080", "Control"},
        {"\u00F6", "Latin Small Letter O With Diaeresis"},
        {"\u20AC", "Euro Sign"},
        {"\u{1F600}", "Emoji: Grinning Face"},
        {"\uFB33", "Hebrew Letter Dalet With Dagesh"}
      ]

      expected = "{" <> Enum.map_join(ordered_members, ",", &member/1) <> "}"

      assert {:ok, value} = Json.decode(input)
      assert Canonicalization.encode(value) == {:ok, expected}

      # Canonical member order from verify's re-decode, per the fixed-point
      # chain above.
      assert {:ok, decoded} = Json.decode(expected)
      assert Canonicalization.verify(expected) == {:ok, decoded}
      assert Canonicalization.encode(decoded) == {:ok, expected}
    end
  end

  describe "class: tamper_meaningful_byte — UTF-16 vs code-unit sort divergence" do
    test "U+10000 sorts BEFORE U+FF3A; a codepoint/UTF-8 sort emits the opposite" do
      # Insertion order is deliberately the stdlib (codepoint) order so the
      # test reds if anyone replaces the UTF-16 sort key with plain ordering.
      ff3a = "\uFF3A"
      supplementary = "\u{10000}"

      value =
        {:object, [{ff3a, {:integer, 1}}, {supplementary, {:integer, 2}}]}

      assert Canonicalization.encode(value) ==
               {:ok, "{\"" <> supplementary <> "\":2,\"" <> ff3a <> "\":1}"}
    end

    test "the BMP/supplementary boundary pins against surrogate-pair keys" do
      # U+E000 (private use, BMP high end) vs U+10000: UTF-16 0xE000 sorts
      # AFTER the D800..DFFF surrogate pair range, so U+10000 comes first.
      value = {:object, [{"\uE000", {:integer, 1}}, {"\u{10000}", {:integer, 2}}]}

      assert Canonicalization.encode(value) ==
               {:ok, "{\"\u{10000}\":2,\"\uE000\":1}"}
    end
  end

  describe "class: boundary_near — ES6 notation thresholds" do
    test "1e+21 / 1e20 and 1e-6 / 1e-7 straddle the notation switches" do
      assert Canonicalization.number(1.0e21) == {:ok, "1e+21"}
      assert Canonicalization.number(9.999_999_999_999_999e20) == {:ok, "999999999999999900000"}
      assert Canonicalization.number(1.0e-6) == {:ok, "0.000001"}
      assert Canonicalization.number(1.0e-7) == {:ok, "1e-7"}
    end
  end

  defp member({key, value}) do
    IO.iodata_to_binary([?", key, ?", ?:, ?", value, ?"])
  end

  defp float_from_hex(hex) do
    <<f::big-float-size(64)>> = <<hex::big-integer-size(64)>>
    {:ok, f}
  end
end
