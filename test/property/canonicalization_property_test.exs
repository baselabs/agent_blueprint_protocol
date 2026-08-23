defmodule AgentBlueprintProtocol.CanonicalizationPropertyTest do
  @moduledoc """
  Properties of canonical bytes. The fixed-point property is TOTAL over the
  closed algebra (integer-window amendment, 2026-08-21): the decoder's integer window
  admits a pure-digit lexeme above 2^53−1 iff it is that double's own ES6
  serialization, so every canonical byte string decodes and re-encodes
  byte-exactly — the float generator includes the formerly excluded window.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentBlueprintProtocol.{Canonicalization, Json}

  @ijson_max 9_007_199_254_740_991

  property "canonicalization is stable under member permutation at every depth" do
    check all(value <- json_value()) do
      {:ok, canonical} = Canonicalization.encode(value)
      assert {:ok, canonical} == Canonicalization.encode(shuffle_members(value))
    end
  end

  property "encode of a decode is a byte fixed point on decodable canonical forms" do
    check all(value <- json_value()) do
      {:ok, bytes} = Canonicalization.encode(value)

      assert {:ok, decoded} = Json.decode(bytes)
      assert Canonicalization.encode(decoded) == {:ok, bytes}
      assert Canonicalization.verify(bytes) == {:ok, decoded}
    end
  end

  property "whitespace-inserted canonical bytes fail verify" do
    check all(value <- json_value()) do
      {:ok, bytes} = Canonicalization.encode(value)

      assert Canonicalization.verify(" " <> bytes) == {:error, :non_canonical_bytes}
      assert Canonicalization.verify(bytes <> " ") == {:error, :non_canonical_bytes}
      assert Canonicalization.verify(" " <> bytes <> " ") == {:error, :non_canonical_bytes}
    end
  end

  property "decode admits every window double at its own canonical digits" do
    # Guards the Float.parse reliance mechanically: the true double is built
    # FROM BITS, so the oracle chain contains no decimal->float conversion.
    # If Float.parse ever regresses (an OTP change), decode returns a wrong
    # value or denies and this property reds — the reliance does not rest on
    # prose. (Also reds if the window converts via `String.to_integer * 1.0`:
    # that path mis-rounds ~1% of window doubles; probed 2026-08-21,
    # 1,937/200,000 bit-constructed samples.)
    check all(f <- window_double(), max_runs: 300) do
      assert {:ok, digits} = Canonicalization.number(f)
      assert Json.decode(digits) == {:ok, {:float, f}}
    end
  end

  # ---- generators ------------------------------------------------------------

  defp json_value do
    StreamData.tree(leaf(), fn child ->
      one_of([
        map(list_of(child, max_length: 4), &{:array, &1}),
        object(child)
      ])
    end)
  end

  defp leaf do
    one_of([
      constant(:null),
      map(boolean(), &{:boolean, &1}),
      map(integer(-@ijson_max..@ijson_max), &{:integer, &1}),
      map(one_of([float(), window_float()]), &{:float, &1}),
      map(safe_string(), &{:string, &1})
    ])
  end

  # Integral floats in ±[2^53, 1e21) — the integer window whose ES6 form is pure
  # digits, both signs. Guaranteed-present so the un-capped fixed point is
  # exercised on the formerly excluded class every run; random float/0 alone
  # rarely lands there.
  defp window_float do
    magnitude = integer((@ijson_max + 1)..999_999_999_999_999_999_999)
    one_of([map(magnitude, &(&1 * 1.0)), map(magnitude, &(-&1 * 1.0))])
  end

  # A window double built from raw IEEE 754 bits: exponent 53..68 puts the
  # value in [2^53, 2^69) — above the I-JSON bound, integral, and below
  # 1e21, so its canonical ES6 form is pure digits. Bit construction keeps
  # the generated value independent of every decimal parser.
  defp window_double do
    mantissa_max = Integer.pow(2, 52) - 1

    gen all(sign <- member_of([0, 1]), exp <- integer(53..68), m <- integer(0..mantissa_max)) do
      <<f::big-float-size(64)>> = <<sign::1, exp + 1023::11, m::52>>
      f
    end
  end

  defp object(child) do
    {safe_string(), child}
    |> tuple()
    |> list_of(max_length: 4)
    |> map(fn pairs -> {:object, Enum.uniq_by(pairs, &elem(&1, 0))} end)
  end

  defp safe_string do
    # Printable Unicode (never surrogates) makes member permutation
    # sort-sensitive: UTF-16 vs codepoint order diverges above the BMP.
    string(:printable, max_length: 8)
  end

  # Recursively permute every object's members; array order untouched.
  defp shuffle_members({:object, members}) do
    {:object, Enum.shuffle(Enum.map(members, fn {k, v} -> {k, shuffle_members(v)} end))}
  end

  defp shuffle_members({:array, items}) do
    {:array, Enum.map(items, &shuffle_members/1)}
  end

  defp shuffle_members(scalar), do: scalar
end
