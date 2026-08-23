defmodule AgentBlueprintProtocol.Conformance.JsonDecodeTest do
  @moduledoc """
  Conformance corpus row `json.decode`. Every negative class is an input the
  decoder MUST reject; the positive classes must decode. The full data-file
  corpus + loader live elsewhere — these cases pin the decode contract now.
  """
  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.Json

  describe "class: valid" do
    test "a well-formed document decodes to the tagged algebra" do
      assert Json.decode(~s({"a":1,"b":[2,3.5,"x"]})) ==
               {:ok,
                {:object,
                 [
                   {"a", {:integer, 1}},
                   {"b", {:array, [{:integer, 2}, {:float, 3.5}, {:string, "x"}]}}
                 ]}}
    end
  end

  describe "class: boundary_near / exact_bound / maximum_plus_one (depth)" do
    test "depth just under the ceiling decodes" do
      assert {:ok, _} = Json.decode("[[[1]]]", %{depth: 4})
    end

    test "depth exactly at the ceiling decodes" do
      assert {:ok, _} = Json.decode("[[[[1]]]]", %{depth: 4})
    end

    test "depth one past the ceiling is rejected" do
      assert Json.decode("[[[[[1]]]]]", %{depth: 4}) == {:error, {:ceiling, :depth}}
    end
  end

  describe "class: maximum_plus_one (every other parse ceiling)" do
    test "total input bytes" do
      assert Json.decode("[1,2,3]", %{bytes: 3}) == {:error, {:ceiling, :bytes}}
    end

    test "items in one array" do
      assert Json.decode("[1,2,3]", %{items: 2}) == {:error, {:ceiling, :items}}
      assert {:ok, _} = Json.decode("[1,2]", %{items: 2})
    end

    test "members in one object" do
      assert Json.decode(~s({"a":1,"b":2,"c":3}), %{members: 2}) == {:error, {:ceiling, :members}}
    end

    test "total value nodes, counted exactly including the root" do
      assert Json.decode("1", %{nodes: 1}) == {:ok, {:integer, 1}}
      assert Json.decode("[1]", %{nodes: 1}) == {:error, {:ceiling, :nodes}}
      assert {:ok, _} = Json.decode("[1]", %{nodes: 2})
      assert Json.decode("[1,[2,3]]", %{nodes: 2}) == {:error, {:ceiling, :nodes}}
    end

    test "string value byte length (nested and root)" do
      assert Json.decode(~s(["abcd"]), %{string: 3}) == {:error, {:ceiling, :string}}
      assert Json.decode(~s("abcd"), %{string: 3}) == {:error, {:ceiling, :string}}
      assert {:ok, _} = Json.decode(~s("abc"), %{string: 3})
    end

    test "object key byte length" do
      assert Json.decode(~s({"abcd":1}), %{key: 3}) == {:error, {:ceiling, :key}}
    end

    test "number lexeme byte length (integer and float paths)" do
      assert Json.decode("123456", %{number_lexeme: 3}) == {:error, {:ceiling, :number_lexeme}}
      assert Json.decode("1.234", %{number_lexeme: 3}) == {:error, {:ceiling, :number_lexeme}}
    end
  end

  describe "class: invalid_encoding" do
    test "a bad UTF-8 byte inside a string is rejected" do
      assert Json.decode(<<?", 0xFF, ?">>) == {:error, :invalid_encoding}
    end
  end

  describe "class: invalid_duplicate" do
    test "duplicate object members are rejected" do
      assert Json.decode(~s({"a":1,"a":2})) == {:error, :duplicate_member}
    end

    test "the divergence: stdlib :json silently collapses the duplicate this gate rejects" do
      # A decoder delegating to the stdlib would WRONGLY accept, keeping the first.
      assert :json.decode(~s({"a":1,"a":2})) == %{"a" => 1}
      assert Json.decode(~s({"a":1,"a":2})) == {:error, :duplicate_member}
    end
  end

  describe "class: exact_bound / maximum_plus_one — I-JSON integer window amendment" do
    test "the bound itself is integer-typed; one past it enters the window" do
      assert Json.decode("9007199254740991") == {:ok, {:integer, 9_007_199_254_740_991}}
      assert Json.decode("9007199254740992") == {:ok, {:float, 9.007_199_254_740_992e15}}
      assert Json.decode("-9007199254740992") == {:ok, {:float, -9.007_199_254_740_992e15}}
    end

    test "binary64 adjacency: silently-lossy lexemes deny, exactly-representable ones admit" do
      assert Json.decode("-9007199254740993") == {:error, :number_not_double_expressible}
      assert Json.decode("9007199254740993") == {:error, :number_not_double_expressible}
      assert Json.decode("9007199254740994") == {:ok, {:float, 9.007_199_254_740_994e15}}
    end
  end

  describe "class: invalid_constraint — window admissibility is the ES6 round-trip" do
    test "rounded-canonical spellings admit (RFC 8785 Appendix B window rows)" do
      assert Json.decode("295147905179352830000") == {:ok, {:float, 2.951_479_051_793_528_3e20}}
      assert Json.decode("999999999999999700000") == {:ok, {:float, 9.999_999_999_999_997e20}}
      assert Json.decode("999999999999999900000") == {:ok, {:float, 9.999_999_999_999_999e20}}
    end

    test "the exact-value (non-canonical) spelling of the same double denies" do
      assert Json.decode("295147905179352825856") == {:error, :number_not_double_expressible}
    end

    test "a lexeme whose bignum * 1.0 conversion mis-rounds still admits at the correct double" do
      # Provider-real fixture (node v24.18.0, 2026-08-21 live cross-check):
      # JSON.parse of this lexeme yields bits 440fefa841f21479, which
      # JSON.stringify reproduces byte-exact — a conforming round-trip.
      # String.to_integer/1 * 1.0 lands one ULP low (…1478) and denied it.
      <<expected::big-float-size(64)>> = <<0x440FEFA841F21479::big-integer-size(64)>>

      assert Json.decode("73639773945516200000") == {:ok, {:float, expected}}
    end

    test "pure digits at 1e21 and beyond deny — the canonical form is exponential" do
      assert Json.decode("1000000000000000000000") == {:error, :number_not_double_expressible}
    end
  end

  describe "class: boundary — lexeme ceiling fires before window adjudication" do
    test "63- and 64-byte digit lexemes pass the length guard and deny in the window" do
      assert Json.decode(String.duplicate("9", 63)) == {:error, :number_not_double_expressible}
      assert Json.decode(String.duplicate("9", 64)) == {:error, :number_not_double_expressible}
    end

    test "a 65-byte lexeme hits the ceiling, never the window rule" do
      assert Json.decode(String.duplicate("9", 65)) == {:error, {:ceiling, :number_lexeme}}
    end
  end

  describe "class: error atom — the interim :integer_magnitude reason is retired" do
    test "every window deny is :number_not_double_expressible, never :integer_magnitude" do
      for lexeme <-
            ~w(-9007199254740993 9007199254740993 295147905179352825856 1000000000000000000000) ++
              [String.duplicate("9", 63)] do
        assert Json.decode(lexeme) == {:error, :number_not_double_expressible}
        assert Json.decode(lexeme) != {:error, :integer_magnitude}
      end
    end
  end

  describe "aggregate — max-shape all-window document decodes in bounded time" do
    test "199,501 nodes of window numbers decode within seconds, not minutes" do
      # 9,500 inner arrays x 20 numbers = 190,000 number nodes + 9,500 array
      # element nodes + 1 root = 199,501 <= nodes max; ~4.2 MB <= bytes max;
      # 9,500 <= items max per array. Every number exercises the full window
      # rule (to_integer + float convert + ES6 serialize + byte compare).
      number = "295147905179352830000"
      inner = "[" <> Enum.map_join(1..20, ",", fn _ -> number end) <> "]"
      doc = "[" <> Enum.map_join(1..9_500, ",", fn _ -> inner end) <> "]"

      {usec, result} = :timer.tc(fn -> Json.decode(doc) end)

      assert {:ok, {:array, [{:array, [{:float, 2.951_479_051_793_528_3e20} | _]} | _]}} = result
      assert usec < 10_000_000
    end
  end
end
