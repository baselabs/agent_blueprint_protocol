defmodule AgentBlueprintProtocol.Json do
  @moduledoc """
  This module decodes bounded JSON into an order-preserving tagged value.

  Use it when decoding protocol JSON before passing the value to another module.

  This module does not authorize operations.

  ## Example

  ```elixir
  {:ok, value} = AgentBlueprintProtocol.Json.decode(~s({"ready":true}))
  ```
  """
  @moduledoc since: "1.0.0"

  alias AgentBlueprintProtocol.{Bounds, Canonicalization}

  # I-JSON (RFC 7493) / RFC 8785 §3.1: every integer must round-trip a JS peer.
  @ijson_max 9_007_199_254_740_991

  @typedoc """
  A JSON value represented as a tagged scalar, array, or ordered object.
  """
  @type value ::
          :null
          | {:boolean, boolean()}
          | {:integer, integer()}
          | {:float, float()}
          | {:string, binary()}
          | {:array, [value()]}
          | {:object, [{binary(), value()}]}

  @spec decode(binary(), Bounds.t() | map()) ::
          {:ok, value()} | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
  Decodes bounded JSON into an order-preserving tagged value.

  ## Example

      iex> match?({:ok, {:object, [{"ready", {:boolean, true}}]}}, AgentBlueprintProtocol.Json.decode(~S({"ready":true})))
      true
      iex> match?({:ok, {:object, [{"ready", {:boolean, true}}]}}, AgentBlueprintProtocol.Json.decode(~S({"ready":true}), %{bytes: 32}))
      true
  """
  @doc since: "1.0.0"
  def decode(input, bounds \\ Bounds.maximum())

  def decode(input, bounds) when is_binary(input) do
    with {:ok, bounds} <- Bounds.coerce(bounds),
         :ok <- check_bytes(input, bounds) do
      # counters: index 1 = live depth, index 2 = monotonic node count.
      counters = :counters.new(2, [:atomics])

      try do
        {value, :root, rest} = :json.decode(input, :root, decoders(bounds, counters))

        if blank?(rest) do
          finalize_root(value, bounds, counters)
        else
          {:error, %AgentBlueprintProtocol.Error{code: :trailing_bytes}}
        end
      catch
        # Ceiling, duplicate, and number violations we raise from container
        # callbacks or `finalize_root`. (`:json` swallows a throw from a scalar
        # decoder, so number checks run at the value sinks, never in the hook.)
        :throw, {:abp_error, reason} ->
          {:error, %AgentBlueprintProtocol.Error{code: reason}}

        # OTP 27–29 decode errors: unexpected_end, invalid_byte, and
        # unexpected_sequence (malformed Unicode escapes). Classify using the
        # whole input without returning the byte or sequence. Other errors,
        # including callback invariant failures, must still escape loudly.
        :error, :unexpected_end ->
          {:error, %AgentBlueprintProtocol.Error{code: classify_parse_error(input)}}

        :error, {:invalid_byte, _byte} ->
          {:error, %AgentBlueprintProtocol.Error{code: classify_parse_error(input)}}

        :error, {:unexpected_sequence, _bytes} ->
          {:error, %AgentBlueprintProtocol.Error{code: classify_parse_error(input)}}
      end
    end
  end

  # The API type boundary: a non-binary input is the decoder's one
  # invalid_type surface (the corpus floor's json.decode cell) — typed
  # denial, never a FunctionClauseError raise.
  def decode(_input, _bounds), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp decoders(bounds, counters) do
    %{
      null: :null,
      # Scalars return their raw lexeme; numbers are validated and parsed at the
      # value sinks (`:json` discards a throw raised inside these hooks).
      integer: &{:integer, &1},
      float: &{:float, &1},
      string: &{:string, &1},
      array_start: fn _acc ->
        enter(counters, bounds)
        {0, []}
      end,
      array_push: fn value, {n, items} ->
        guard(n + 1, bounds.items, :items)
        bump_nodes(counters, bounds)
        {n + 1, [sink(value, bounds) | items]}
      end,
      array_finish: fn {_n, items}, old ->
        leave(counters)
        {{:array, :lists.reverse(items)}, old}
      end,
      object_start: fn _acc ->
        enter(counters, bounds)
        {0, []}
      end,
      object_push: fn {:string, key}, value, {n, members} ->
        guard(n + 1, bounds.members, :members)
        guard(byte_size(key), bounds.key, :key)
        bump_nodes(counters, bounds)
        {n + 1, [{key, sink(value, bounds)} | members]}
      end,
      object_finish: fn {_n, members}, old ->
        leave(counters)
        members = :lists.reverse(members)
        reject_duplicates(members)
        {{:object, members}, old}
      end
    }
  end

  # A value settling into its container (or the root): tag bare booleans, parse
  # and bound numbers, bound string length.
  defp sink(value, bounds) do
    value
    |> tag_scalar()
    |> resolve_number(bounds)
    |> check_string_size(bounds)
  end

  defp finalize_root(value, bounds, counters) do
    # The root value is a node too — count it so `nodes` is an exact bound.
    bump_nodes(counters, bounds)
    {:ok, sink(value, bounds)}
  end

  defp resolve_number({:integer, lexeme}, bounds) when is_binary(lexeme) do
    guard(byte_size(lexeme), bounds.number_lexeme, :number_lexeme)
    integer = String.to_integer(lexeme)

    if abs(integer) > @ijson_max do
      # Integer window: admit iff the double's own canonical ES6 form IS
      # the lexeme — byte-exact round-trip through the one serializer. The
      # double must be the CORRECTLY-ROUNDED one an ECMAScript peer parses
      # from these digits: `Float.parse` (e.g. "73639773945516200000" ->
      # bits …1479, node-verified), while `integer * 1.0` lands one ULP low
      # for some large magnitudes and would falsely deny lexemes a peer
      # round-trips. Total over decoder-visible pure-digit lexemes.
      {float, ""} = Float.parse(lexeme)

      case Canonicalization.number(float) do
        {:ok, ^lexeme} -> {:float, float}
        _ -> throw({:abp_error, :number_not_double_expressible})
      end
    else
      {:integer, integer}
    end
  end

  defp resolve_number({:float, lexeme}, bounds) when is_binary(lexeme) do
    guard(byte_size(lexeme), bounds.number_lexeme, :number_lexeme)

    case Float.parse(lexeme) do
      {float, ""} -> {:float, float}
      _ -> throw({:abp_error, :invalid_number})
    end
  end

  defp resolve_number(value, _bounds), do: value

  defp check_string_size({:string, s} = value, bounds) do
    guard(byte_size(s), bounds.string, :string)
    value
  end

  defp check_string_size(value, _bounds), do: value

  defp check_bytes(input, bounds) do
    if byte_size(input) > bounds.bytes,
      do: {:error, %AgentBlueprintProtocol.Error{code: {:ceiling, :bytes}}},
      else: :ok
  end

  defp enter(counters, bounds) do
    guard(:counters.get(counters, 1) + 1, bounds.depth, :depth)
    :counters.add(counters, 1, 1)
  end

  defp leave(counters), do: :counters.sub(counters, 1, 1)

  defp bump_nodes(counters, bounds) do
    guard(:counters.get(counters, 2) + 1, bounds.nodes, :nodes)
    :counters.add(counters, 2, 1)
  end

  defp guard(observed, ceiling, name) when observed > ceiling,
    do: throw({:abp_error, {:ceiling, name}})

  defp guard(_observed, _ceiling, _name), do: :ok

  defp reject_duplicates(members) do
    keys = Enum.map(members, fn {key, _value} -> key end)
    if keys != Enum.uniq(keys), do: throw({:abp_error, :duplicate_member})
  end

  defp tag_scalar(true), do: {:boolean, true}
  defp tag_scalar(false), do: {:boolean, false}
  defp tag_scalar(other), do: other

  defp classify_parse_error(input) do
    if String.valid?(input), do: :invalid_syntax, else: :invalid_encoding
  end

  defp blank?(<<>>), do: true
  defp blank?(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r], do: blank?(rest)
  defp blank?(_rest), do: false
end
