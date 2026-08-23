defmodule AgentBlueprintProtocol.Canonicalization do
  @moduledoc """
  RFC 8785 JSON Canonicalization Scheme over the closed tagged algebra
  produced by `AgentBlueprintProtocol.Json`.

  This is the package's one and only encoder: object members are sorted by
  UTF-16 code unit (`sort_key/1`), strings use the §3.2.2.2 escape set, and
  floats serialize exactly as ECMAScript §7.1.12.1 (including the Note 2
  shortest round-trip rule) — digits from `:erlang.float_to_binary/2` with
  `[:short]`, notation re-formatted per ECMA-262. Output is UTF-8 with no
  whitespace between tokens.

  Fail-closed guards on the encode path (a value can reach the encoder
  without ever passing the decoder): invalid UTF-8 and lone surrogates deny
  with `:invalid_encoding`; duplicate object names deny with
  `:duplicate_member`; a directly-constructed tagged integer above the
  I-JSON bound `±(2^53−1)` denies with `:integer_magnitude` — decode can no
  longer produce one (the integer window float-tags above-bound lexemes), but a
  hand-built value still fails closed so the package never emits bytes an
  ECMAScript peer would serialize differently. The
  runtime cannot materialize NaN or ±Infinity floats (arithmetic raises,
  parsing and the external term format reject them), so no non-finite value
  can reach this module on a stock BEAM.

  `verify/2` enforces the interchange contract: bytes are canonical only if
  decode followed by re-encode reproduces them exactly; anything else
  (whitespace, member reordering, needless escapes, non-ES6 number lexemes)
  is `{:error, :non_canonical_bytes}`. Digests are computed over exactly
  these verified bytes by the digest layer.

  The decoder's integer window (the integer-window amendment, 2026-08-21) closes the
  former encode/verify asymmetry: a pure-digit lexeme above `±(2^53−1)`
  decodes as `{:float, f}` iff `number/1` reproduces it, so canonical
  pure-digit output for integral floats from 2^53 up to 10^21 (e.g.
  `9007199254740992`, `295147905179352830000` — RFC 8785 Appendix B) now
  round-trips through decode and `verify/2`. Above-bound lexemes that are
  not a double's canonical ES6 spelling deny decode with
  `:number_not_double_expressible`, which `verify/2` passes through.

  Errors are **value-free**: a reason names a category, never the offending
  bytes or values.
  Canonical bytes are a serialization fact — encoding never authorizes anything.
  """

  alias AgentBlueprintProtocol.{Bounds, Json}

  # I-JSON (RFC 7493) / RFC 8785 §3.1, mirrored from the decoder: a tagged
  # integer above it cannot round-trip a JS peer.
  @ijson_max 9_007_199_254_740_991
  # ECMA-262 §7.1.12.1: decimal notation covers 10^-6 <= x < 10^21, which in
  # terms of the decimal exponent n is -5 <= n <= 21.
  @decimal_high 21
  @decimal_low -5
  @short_escapes %{?\b => "b", ?\t => "t", ?\n => "n", ?\f => "f", ?\r => "r"}

  @doc """
  Encode `value` (the tagged algebra) to RFC 8785 canonical JSON under
  `bounds` (a `Bounds` struct or tighten-only overrides, defaulting to the
  profile maxima). The `bytes` ceiling bounds the OUTPUT size.
  """
  @spec encode(Json.value(), Bounds.t() | map()) :: {:ok, binary()} | {:error, reason()}
  def encode(value, bounds \\ Bounds.maximum()) do
    with {:ok, bounds} <- Bounds.coerce(bounds),
         {:ok, iodata} <- iodata(value) do
      binary = IO.iodata_to_binary(iodata)

      if byte_size(binary) > bounds.bytes,
        do: {:error, {:ceiling, :bytes}},
        else: {:ok, binary}
    end
  end

  @doc """
  The RFC 8785 §3.2.3 member sort key: `name` as big-endian UTF-16 code
  units. Erlang binary order over these keys is exactly the RFC's unsigned
  code-unit comparison, shorter-prefix-first. `name` must be valid UTF-8.
  """
  @spec sort_key(binary()) :: binary()
  def sort_key(name) when is_binary(name) do
    :unicode.characters_to_binary(name, :utf8, {:utf16, :big})
  end

  @doc """
  Serialize `float` per ECMA-262 §7.1.12.1 (Note 2 included): `-0.0` is
  `"0"`, integral values below 10^21 print as integers, `1e+21` and beyond
  (and below 10^-6) use exponential notation.
  """
  @spec number(float()) :: {:ok, binary()}
  def number(f) when is_float(f) do
    cond do
      f == 0 -> {:ok, "0"}
      f < 0 -> {:ok, "-" <> elem(number(-f), 1)}
      true -> {:ok, es6_digits(f)}
    end
  end

  @type reason ::
          :non_canonical_bytes
          | :integer_magnitude
          | Json.reason()

  @doc """
  Verify that `input` is already in canonical form: decode under `bounds`,
  re-encode, and require byte equality. Returns the decoded value on
  success, `{:error, :non_canonical_bytes}` on any mismatch, and passes
  decoder errors through unchanged (so every `Json` decode reason —
  `:number_not_double_expressible` included — can surface here).
  """
  @spec verify(binary(), Bounds.t() | map()) :: {:ok, Json.value()} | {:error, reason()}
  def verify(input, bounds \\ Bounds.maximum()) when is_binary(input) do
    with {:ok, value} <- Json.decode(input, bounds),
         {:ok, canonical} <- encode(value, bounds) do
      if canonical == input, do: {:ok, value}, else: {:error, :non_canonical_bytes}
    end
  end

  # ---- encode walk ------------------------------------------------------------

  defp iodata(:null), do: {:ok, "null"}
  defp iodata({:boolean, true}), do: {:ok, "true"}
  defp iodata({:boolean, false}), do: {:ok, "false"}

  defp iodata({:integer, n}) when is_integer(n) do
    if abs(n) > @ijson_max,
      do: {:error, :integer_magnitude},
      else: {:ok, Integer.to_string(n)}
  end

  defp iodata({:float, f}) when is_float(f), do: number(f)
  defp iodata({:string, s}) when is_binary(s), do: string_iodata(s)

  defp iodata({:array, items}) do
    with {:ok, inner} <- sequence(items, []) do
      {:ok, [?[, inner, ?]]}
    end
  end

  defp iodata({:object, members}) do
    with :ok <- check_names(members),
         {:ok, sorted} <- sort_members(members),
         :ok <- reject_adjacent_duplicates(sorted),
         {:ok, inner} <- member_sequence(sorted, []) do
      {:ok, [?{, inner, ?}]}
    end
  end

  defp sequence([], acc), do: {:ok, Enum.reverse(acc)}

  defp sequence([item | rest], acc) do
    with {:ok, element} <- iodata(item) do
      sequence(rest, [[maybe_comma(acc), element] | acc])
    end
  end

  defp member_sequence([], acc), do: {:ok, Enum.reverse(acc)}

  defp member_sequence([{name, value} | rest], acc) do
    with {:ok, key} <- string_iodata(name),
         {:ok, element} <- iodata(value) do
      member_sequence(rest, [[maybe_comma(acc), key, ?:, element] | acc])
    end
  end

  defp maybe_comma([]), do: []
  defp maybe_comma(_), do: ","

  # Every key must be valid UTF-8 BEFORE sort_key/1 runs: the conversion
  # returns an error tuple, not a binary, on invalid input.
  defp check_names(members) do
    if Enum.all?(members, fn {name, _} -> String.valid?(name) end),
      do: :ok,
      else: {:error, :invalid_encoding}
  end

  defp sort_members(members) do
    {:ok, Enum.sort_by(members, fn {name, _} -> sort_key(name) end)}
  end

  defp reject_adjacent_duplicates([{name, _} | [{name, _} | _rest]]),
    do: {:error, :duplicate_member}

  defp reject_adjacent_duplicates([_ | rest]), do: reject_adjacent_duplicates(rest)
  defp reject_adjacent_duplicates([]), do: :ok

  # ---- strings (RFC 8785 §3.2.2.2) --------------------------------------------

  defp string_iodata(s) do
    if String.valid?(s),
      do: {:ok, [?", escape(s), ?"]},
      else: {:error, :invalid_encoding}
  end

  defp escape(<<>>), do: []

  defp escape(<<?", rest::binary>>),
    do: ["\\\"" | escape(rest)]

  defp escape(<<?\\, rest::binary>>),
    do: ["\\\\" | escape(rest)]

  defp escape(<<c, rest::binary>>) when c in [?\b, ?\t, ?\n, ?\f, ?\r],
    do: ["\\" <> @short_escapes[c] | escape(rest)]

  defp escape(<<c, rest::binary>>) when c < 0x20,
    do: ["\\u" <> hex4(c) | escape(rest)]

  defp escape(<<c::utf8, rest::binary>>),
    do: [<<c::utf8>> | escape(rest)]

  defp hex4(c) do
    c
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(4, "0")
  end

  # ---- numbers (ECMA-262 §7.1.12.1) -------------------------------------------

  # f is finite, positive, non-zero. Erlang's [:short] supplies the shortest
  # round-tripping digit string; notation is re-derived from (digits, n)
  # where value = s * 10^(n - k), k = digit count, per ECMA-262.
  defp es6_digits(f) do
    {digits, n} = shortest(f)
    k = byte_size(digits)

    cond do
      k <= n and n <= @decimal_high ->
        digits <> String.duplicate("0", n - k)

      0 < n and n <= @decimal_high ->
        {head, tail} = String.split_at(digits, n)
        head <> "." <> tail

      @decimal_low <= n and n <= 0 ->
        "0." <> String.duplicate("0", -n) <> digits

      true ->
        exponential(digits, n)
    end
  end

  defp exponential(digits, n) do
    {first, rest} = String.split_at(digits, 1)
    mantissa = if rest == "", do: first, else: first <> "." <> rest
    exponent = n - 1
    sign = if exponent >= 0, do: "+", else: "-"
    mantissa <> "e" <> sign <> Integer.to_string(abs(exponent))
  end

  # Parse Erlang's [:short] output ("D.DDD" / "0.DDD" / "D.DDDe±EE") into
  # {digits without zero padding, n}. An unforeseen form crashes the pattern
  # match loudly rather than degrading silently.
  defp shortest(f) do
    bin = :erlang.float_to_binary(f, [:short])

    {mantissa, exp} =
      case String.split(bin, "e") do
        [m, e] -> {m, String.to_integer(e)}
        [m] -> {m, 0}
      end

    # No dot (an unforeseen [:short] form) is a loud MatchError, never a
    # silently degraded parse.
    [int_part, frac_part] = String.split(mantissa, ".")

    raw = int_part <> frac_part
    point = byte_size(int_part) + exp

    stripped = String.trim_leading(raw, "0")
    lead_zeros = byte_size(raw) - byte_size(stripped)
    digits = String.trim_trailing(stripped, "0")

    {digits, point - lead_zeros}
  end
end
