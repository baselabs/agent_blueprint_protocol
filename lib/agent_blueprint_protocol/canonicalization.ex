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
  is `{:error, %AgentBlueprintProtocol.Error{code: :non_canonical_bytes}}`. Digests are computed over exactly
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
  profile maxima). Every structural ceiling applies to hand-built values,
  including container size, string and key lengths, node count, and depth;
  the `bytes` ceiling bounds the output size. Producers cannot emit artifacts
  that verifiers refuse to decode.
  """
  @spec encode(Json.value(), Bounds.t() | map()) ::
          {:ok, binary()} | {:error, AgentBlueprintProtocol.Error.t()}
  def encode(value, bounds \\ Bounds.maximum()) do
    with {:ok, bounds} <- Bounds.coerce(bounds),
         {:ok, _nodes} <- shape(value, bounds, 0, 0),
         {:ok, iodata} <- iodata(value) do
      binary = IO.iodata_to_binary(iodata)

      if byte_size(binary) > bounds.bytes,
        do: {:error, %AgentBlueprintProtocol.Error{code: {:ceiling, :bytes}}},
        else: {:ok, binary}
    end
  end

  @doc false
  @spec sort_key(binary()) :: binary() | {:error, AgentBlueprintProtocol.Error.t()}
  def sort_key(name) when is_binary(name) do
    if String.valid?(name),
      do: :unicode.characters_to_binary(name, :utf8, {:utf16, :big}),
      else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_encoding}}
  end

  def sort_key(_), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  @doc false
  @spec number(float()) :: {:ok, binary()} | {:error, AgentBlueprintProtocol.Error.t()}
  def number(f) when is_float(f) do
    cond do
      f == 0 -> {:ok, "0"}
      f < 0 -> {:ok, "-" <> elem(number(-f), 1)}
      true -> {:ok, es6_digits(f)}
    end
  end

  def number(_), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  @doc """
  Verify that `input` is already in canonical form: decode under `bounds`,
  re-encode, and require byte equality. Returns the decoded value on
  success, `{:error, %AgentBlueprintProtocol.Error{code: :non_canonical_bytes}}` on any mismatch, and passes
  decoder errors through unchanged (so every `Json` decode reason —
  `:number_not_double_expressible` included — can surface here).
  """
  @spec verify(binary(), Bounds.t() | map()) ::
          {:ok, Json.value()} | {:error, AgentBlueprintProtocol.Error.t()}
  def verify(input, bounds \\ Bounds.maximum())

  def verify(input, bounds) when is_binary(input) do
    with {:ok, value} <- Json.decode(input, bounds),
         {:ok, canonical} <- encode(value, bounds) do
      if canonical == input,
        do: {:ok, value},
        else: {:error, %AgentBlueprintProtocol.Error{code: :non_canonical_bytes}}
    end
  end

  def verify(_, _), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  # ---- encode walk ------------------------------------------------------------

  defp shape(_value, bounds, _depth, nodes) when nodes >= bounds.nodes,
    do: {:error, %AgentBlueprintProtocol.Error{code: {:ceiling, :nodes}}}

  defp shape({tag, values}, bounds, depth, nodes)
       when tag in [:array, :object] and is_list(values) do
    limit = if tag == :array, do: bounds.items, else: bounds.members
    field = if tag == :array, do: :items, else: :members

    if depth >= bounds.depth do
      {:error, %AgentBlueprintProtocol.Error{code: {:ceiling, :depth}}}
    else
      with :ok <- container_size(values, limit, field),
           do: shape_children(values, tag, bounds, depth + 1, nodes + 1)
    end
  end

  defp shape({:string, value}, bounds, _depth, nodes) when is_binary(value) do
    cond do
      byte_size(value) > bounds.bytes ->
        {:error, %AgentBlueprintProtocol.Error{code: {:ceiling, :bytes}}}

      byte_size(value) > bounds.string ->
        {:error, %AgentBlueprintProtocol.Error{code: {:ceiling, :string}}}

      true ->
        {:ok, nodes + 1}
    end
  end

  defp shape(:null, _bounds, _depth, nodes), do: {:ok, nodes + 1}

  defp shape({:boolean, value}, _bounds, _depth, nodes) when is_boolean(value),
    do: {:ok, nodes + 1}

  defp shape({:integer, value}, _bounds, _depth, nodes) when is_integer(value),
    do: {:ok, nodes + 1}

  defp shape({:float, value}, _bounds, _depth, nodes) when is_float(value), do: {:ok, nodes + 1}
  defp shape(_, _, _, _), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp container_size([], _remaining, _field), do: :ok

  defp container_size([_ | _], 0, field),
    do: {:error, %AgentBlueprintProtocol.Error{code: {:ceiling, field}}}

  defp container_size([_ | rest], remaining, field),
    do: container_size(rest, remaining - 1, field)

  defp container_size(_, _, _), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp shape_children([], _tag, _bounds, _depth, nodes), do: {:ok, nodes}

  defp shape_children([value | rest], :array, bounds, depth, nodes) do
    with {:ok, next} <- shape(value, bounds, depth, nodes),
         do: shape_children(rest, :array, bounds, depth, next)
  end

  defp shape_children([{name, value} | rest], :object, bounds, depth, nodes)
       when is_binary(name) do
    if byte_size(name) > bounds.key do
      {:error, %AgentBlueprintProtocol.Error{code: {:ceiling, :key}}}
    else
      with {:ok, next} <- shape(value, bounds, depth, nodes),
           do: shape_children(rest, :object, bounds, depth, next)
    end
  end

  defp shape_children(_, _, _, _, _),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp iodata(:null), do: {:ok, "null"}
  defp iodata({:boolean, true}), do: {:ok, "true"}
  defp iodata({:boolean, false}), do: {:ok, "false"}

  defp iodata({:integer, n}) when is_integer(n) do
    if abs(n) > @ijson_max,
      do: {:error, %AgentBlueprintProtocol.Error{code: :integer_magnitude}},
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
      else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_encoding}}
  end

  defp sort_members(members) do
    {:ok, Enum.sort_by(members, fn {name, _} -> sort_key(name) end)}
  end

  defp reject_adjacent_duplicates([{name, _} | [{name, _} | _rest]]),
    do: {:error, %AgentBlueprintProtocol.Error{code: :duplicate_member}}

  defp reject_adjacent_duplicates([_ | rest]), do: reject_adjacent_duplicates(rest)
  defp reject_adjacent_duplicates([]), do: :ok

  # ---- strings (RFC 8785 §3.2.2.2) --------------------------------------------

  defp string_iodata(s) do
    if String.valid?(s),
      do: {:ok, [?", escape(s), ?"]},
      else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_encoding}}
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
