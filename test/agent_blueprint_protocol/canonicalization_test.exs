defmodule AgentBlueprintProtocol.CanonicalizationTest do
  @moduledoc """
  Unit contract of `AgentBlueprintProtocol.Canonicalization` over the tagged
  value algebra: escaping, sorting, the encode-path fail-closed guards, and
  the output byte ceiling. RFC-level byte-exact vectors live in the
  conformance suite.
  """
  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Bounds, Canonicalization}

  @ijson_max 9_007_199_254_740_991

  describe "encode/2 scalars and containers" do
    test "literals" do
      assert Canonicalization.encode(:null) == {:ok, "null"}
      assert Canonicalization.encode({:boolean, true}) == {:ok, "true"}
      assert Canonicalization.encode({:boolean, false}) == {:ok, "false"}
    end

    test "integers as plain decimal digits, negatives signed, no exponent" do
      assert Canonicalization.encode({:integer, 0}) == {:ok, "0"}
      assert Canonicalization.encode({:integer, 7}) == {:ok, "7"}
      assert Canonicalization.encode({:integer, -42}) == {:ok, "-42"}

      assert Canonicalization.encode({:integer, @ijson_max}) ==
               {:ok, Integer.to_string(@ijson_max)}
    end

    test "a constructed integer above the I-JSON magnitude bound is denied" do
      over = @ijson_max + 1

      assert Canonicalization.encode({:integer, over}) == {:error, :integer_magnitude}
      assert Canonicalization.encode({:integer, -over}) == {:error, :integer_magnitude}
    end

    test "arrays keep item order; no whitespace between tokens" do
      assert Canonicalization.encode({:array, [{:integer, 1}, {:string, "a"}, :null]}) ==
               {:ok, ~s([1,"a",null])}

      assert Canonicalization.encode({:array, []}) == {:ok, "[]"}
      assert Canonicalization.encode({:object, []}) == {:ok, "{}"}
    end

    test "object members are emitted in UTF-16 sort-key order" do
      value = {:object, [{"b", {:integer, 1}}, {"a", {:integer, 2}}]}
      assert Canonicalization.encode(value) == {:ok, ~s({"a":2,"b":1})}
    end
  end

  describe "encode/2 string escaping (RFC 8785 §3.2.2.2)" do
    test "the five short escapes" do
      assert Canonicalization.encode({:string, "\b\t\n\f\r"}) == {:ok, ~s("\\b\\t\\n\\f\\r")}
    end

    test "other control characters become lowercase \\u00xx" do
      assert Canonicalization.encode({:string, <<0x00>>}) == {:ok, ~s("\\u0000")}
      assert Canonicalization.encode({:string, <<0x0F>>}) == {:ok, ~s("\\u000f")}
      assert Canonicalization.encode({:string, <<0x1F>>}) == {:ok, ~s("\\u001f")}
    end

    test "quote and backslash escape; slash, DEL, and non-ASCII stay literal" do
      assert Canonicalization.encode({:string, "\""}) == {:ok, <<?", ?\\, ?\", ?">>}

      assert Canonicalization.encode({:string, "\\"}) == {:ok, <<?", ?\\, ?\\, ?">>}
      assert Canonicalization.encode({:string, "/"}) == {:ok, ~s("/")}

      assert Canonicalization.encode({:string, <<0x7F>>}) == {:ok, <<?", 0x7F, ?">>}
      assert Canonicalization.encode({:string, "ö"}) == {:ok, <<?", "ö"::binary, ?">>}
    end

    test "invalid UTF-8 and lone surrogates deny on the encode path" do
      assert Canonicalization.encode({:string, <<0xFF, 0xFE>>}) == {:error, :invalid_encoding}

      assert Canonicalization.encode({:string, <<0xED, 0xA0, 0x80>>}) ==
               {:error, :invalid_encoding}

      assert Canonicalization.encode({:object, [{<<0xED, 0xA0, 0x80>>, :null}]}) ==
               {:error, :invalid_encoding}
    end
  end

  describe "sort_key/1" do
    test "UTF-16BE code units, no BOM" do
      assert Canonicalization.sort_key("a") == <<0x00, 0x61>>
      assert Canonicalization.sort_key("") == <<>>
      # U+1F600 as a surrogate pair, big-endian
      assert Canonicalization.sort_key("😀") == <<0xD8, 0x3D, 0xDE, 0x00>>
    end
  end

  describe "number/1 (ECMA-262 §7.1.12.1)" do
    test "integral floats lose the fraction; negative zero is zero" do
      assert Canonicalization.number(1.0) == {:ok, "1"}
      assert Canonicalization.number(100.0) == {:ok, "100"}
      assert Canonicalization.number(-0.0) == {:ok, "0"}
      assert Canonicalization.number(0.0) == {:ok, "0"}
    end

    test "decimal vs exponential notation thresholds" do
      assert Canonicalization.number(4.5) == {:ok, "4.5"}
      assert Canonicalization.number(0.002) == {:ok, "0.002"}
      assert Canonicalization.number(1.0e-6) == {:ok, "0.000001"}
      assert Canonicalization.number(1.0e-7) == {:ok, "1e-7"}
      assert Canonicalization.number(1.0e22) == {:ok, "1e+22"}
    end
  end

  describe "duplicate members on the encode path" do
    test "a constructed object with duplicate names denies" do
      value = {:object, [{"a", {:integer, 1}}, {"a", {:integer, 2}}]}
      assert Canonicalization.encode(value) == {:error, :duplicate_member}
    end

    test "duplicates nested inside arrays deny as well" do
      value = {:array, [{:object, [{"a", :null}, {"a", :null}]}]}
      assert Canonicalization.encode(value) == {:error, :duplicate_member}
    end
  end

  describe "encode/2 bounds" do
    test "output exactly at the bytes ceiling passes; one more denies" do
      # ~s({"a":1}) is 7 bytes
      assert Canonicalization.encode({:object, [{"a", {:integer, 1}}]}, %{bytes: 7}) ==
               {:ok, ~s({"a":1})}

      assert Canonicalization.encode({:object, [{"a", {:integer, 1}}]}, %{bytes: 6}) ==
               {:error, {:ceiling, :bytes}}
    end

    test "bounds coercion errors pass through" do
      assert Canonicalization.encode(:null, %{bogus: 1}) == {:error, :unknown_bound}
      assert Canonicalization.encode(:null, %{bytes: 9_999_999}) == {:error, {:ceiling, :bytes}}
    end

    test "accepts an explicit Bounds struct" do
      {:ok, bounds} = Bounds.new(%{})
      assert Canonicalization.encode({:integer, 1}, bounds) == {:ok, "1"}
    end
  end

  describe "verify/2" do
    test "canonical bytes return the decoded value" do
      assert Canonicalization.verify(~s({"a":1})) ==
               {:ok, {:object, [{"a", {:integer, 1}}]}}

      assert Canonicalization.verify("1") == {:ok, {:integer, 1}}
      assert Canonicalization.verify("[1,2]") == {:ok, {:array, [integer: 1, integer: 2]}}
    end

    test "non-canonical bytes deny with :non_canonical_bytes" do
      assert Canonicalization.verify("{ \"a\" : 1 }") == {:error, :non_canonical_bytes}
      assert Canonicalization.verify(~s({"b":2,"a":1})) == {:error, :non_canonical_bytes}
      assert Canonicalization.verify(~s({"a":4.50})) == {:error, :non_canonical_bytes}
      assert Canonicalization.verify(~s({"a":1E30})) == {:error, :non_canonical_bytes}
      assert Canonicalization.verify(~s({"\\u0041":1})) == {:error, :non_canonical_bytes}
      assert Canonicalization.verify(" 1 ") == {:error, :non_canonical_bytes}
    end

    test "decode errors pass through unchanged" do
      assert Canonicalization.verify("{") == {:error, :invalid_syntax}
      assert Canonicalization.verify(~s({"a":1,"a":2})) == {:error, :duplicate_member}
      assert Canonicalization.verify("[1] x") == {:error, :trailing_bytes}
    end

    test "former false-reject class: pure digits above the I-JSON bound round-trip" do
      assert Canonicalization.verify(~s({"n":9007199254740992})) ==
               {:ok, {:object, [{"n", {:float, 9.007_199_254_740_992e15}}]}}

      assert Canonicalization.verify("295147905179352830000") ==
               {:ok, {:float, 2.951_479_051_793_528_3e20}}
    end

    test "window deny rows pass the decode error through verify unchanged" do
      assert Canonicalization.verify(~s({"n":9007199254740993})) ==
               {:error, :number_not_double_expressible}
    end

    test "bounds thread through decode and encode" do
      assert Canonicalization.verify(~s({"a":1}), %{bytes: 6}) == {:error, {:ceiling, :bytes}}
    end
  end
end
