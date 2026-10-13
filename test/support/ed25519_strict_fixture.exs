defmodule AgentBlueprintProtocol.Ed25519StrictFixture do
  @moduledoc """
  Test-side Ed25519 algebra for the strict signature rule (canonical R
  outside the small-order set, S below the group order L), derived here
  from the RFC 8032 curve definition, never copied from the package:

  - `key_holder_signature/3` builds the signature only the key holder can
    build, R = the identity and S = k*a mod L (k = SHA-512(R || A || M)
    mod L, a the clamped secret scalar). The cofactorless equation
    [S]B = R + [k]A holds for it, so a lenient backend accepts it.
  - `small_order_encodings/0` lists the eight canonical encodings of the
    8-torsion points; `small_order?/1` proves each one independently
    ([8]P is the identity, by affine Edwards addition).
  - `backend_verify_calls/1` counts the real `:crypto.verify/5` calls a
    function makes (a trace session on the calling process, observing,
    never replacing), so a test can show the rule rejects BEFORE the
    backend is consulted.
  """

  import Bitwise

  # RFC 8032 5.1: p = 2^255 - 19, d = -121665/121666, L = 2^252 + c.
  @p bsl(1, 255) - 19
  @l bsl(1, 252) + 27_742_317_777_372_353_535_851_937_790_883_648_493

  def p, do: @p
  def l, do: @l

  defp d, do: Integer.mod(-121_665 * inverse(121_666), @p)

  # p is 5 mod 8, so 2^((p-1)/4) is a square root of -1.
  defp sqrt_m1, do: pow(2, div(@p - 1, 4))

  @doc "The clamped secret scalar a of an RFC 8032 seed."
  def secret_scalar(seed) do
    <<low::binary-size(32), _prefix::binary>> = :crypto.hash(:sha512, seed)
    <<a::little-unsigned-256>> = low
    a |> band(bnot(7)) |> band(bsl(1, 255) - 1) |> bor(bsl(1, 254))
  end

  @doc "k = SHA-512(R || A || M) mod L, the RFC 8032 challenge scalar."
  def challenge(r, public, message) do
    <<k::little-unsigned-512>> = :crypto.hash(:sha512, r <> public <> message)
    rem(k, @l)
  end

  @doc """
  The key-holder signature over `message` with R the given encoding and
  S = k*a mod L. With R = the identity it satisfies the cofactorless
  equation under the holder's own (prime-order) key.
  """
  def key_holder_signature(seed, r, message) do
    {public, _} = :crypto.generate_key(:eddsa, :ed25519, seed)
    s = rem(challenge(r, public, message) * secret_scalar(seed), @l)
    r <> <<s::little-unsigned-256>>
  end

  def identity, do: <<1, 0::248>>

  @doc "The eight canonical encodings of the small-order (8-torsion) points."
  def small_order_encodings do
    Enum.map(
      [
        # order 1 (identity) and order 2 (y = p - 1)
        "0100000000000000000000000000000000000000000000000000000000000000",
        "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
        # order 4 (y = 0, x = +/- sqrt(-1))
        "0000000000000000000000000000000000000000000000000000000000000000",
        "0000000000000000000000000000000000000000000000000000000000000080",
        # order 8
        "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a",
        "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa",
        "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05",
        "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85"
      ],
      &Base.decode16!(&1, case: :lower)
    )
  end

  @doc """
  Non-canonical point encodings: y >= p (y = p, the identity's y + p, and
  all-ones), and x = 0 with the sign bit set (the identity and the order-2
  point; RFC 8032 5.1.3 rejects x = 0 with x_0 = 1).
  """
  def non_canonical_encodings do
    [
      <<@p::little-unsigned-256>>,
      <<@p + 1::little-unsigned-256>>,
      <<bsl(1, 255) - 1::little-unsigned-256>>,
      <<1, 0::240, 0x80>>,
      <<bor(@p - 1, bsl(1, 255))::little-unsigned-256>>
    ]
  end

  @doc "Independent proof that a canonical encoding decodes to a point with [8]P = O."
  def small_order?(encoding) do
    case decode(encoding) do
      {:ok, point} -> point |> double() |> double() |> double() == {0, 1}
      :error -> false
    end
  end

  defp decode(<<raw::little-unsigned-256>>) do
    sign = band(bsr(raw, 255), 1)
    y = band(raw, bsl(1, 255) - 1)
    x = recover_x(y)

    cond do
      y >= @p or x == nil -> :error
      x == 0 and sign == 1 -> :error
      band(x, 1) == sign -> {:ok, {x, y}}
      true -> {:ok, {@p - x, y}}
    end
  end

  # RFC 8032 5.1.3 steps 2-3: x^2 = (y^2 - 1)/(d y^2 + 1); nil when no root.
  defp recover_x(y) do
    x2 = Integer.mod((y * y - 1) * inverse(d() * y * y + 1), @p)
    z = pow(x2, div(@p + 3, 8))

    cond do
      Integer.mod(z * z - x2, @p) == 0 -> z
      Integer.mod(z * z + x2, @p) == 0 -> Integer.mod(z * sqrt_m1(), @p)
      true -> nil
    end
  end

  # Complete affine addition on -x^2 + y^2 = 1 + d x^2 y^2 (d non-square).
  defp double({x, y}) do
    t = d() * x * x * y * y

    {Integer.mod((x * y + y * x) * inverse(1 + t), @p),
     Integer.mod((y * y + x * x) * inverse(1 - t), @p)}
  end

  defp inverse(v), do: pow(Integer.mod(v, @p), @p - 2)

  defp pow(base, exponent), do: :crypto.mod_pow(base, exponent, @p) |> :binary.decode_unsigned()

  @doc """
  Run `fun` and count the real `:crypto.verify/5` calls it makes on the
  calling process. Returns `{result, calls}`.
  """
  def backend_verify_calls(fun) do
    {:module, :crypto} = Code.ensure_loaded(:crypto)
    caller = self()
    collector = spawn_link(fn -> collect(0) end)
    session = :trace.session_create(:strict_ed25519_backend_probe, collector, [])

    try do
      1 = :trace.function(session, {:crypto, :verify, 5}, true, [])
      1 = :trace.process(session, caller, true, [:call])
      result = fun.()
      ref = :trace.delivered(session, caller)

      receive do
        {:trace_delivered, ^caller, ^ref} -> :ok
      end

      send(collector, {:report, caller})

      receive do
        {:calls, calls} -> {result, calls}
      end
    after
      :trace.session_destroy(session)
    end
  end

  defp collect(calls) do
    receive do
      {:trace, _pid, :call, {:crypto, :verify, _args}} -> collect(calls + 1)
      {:report, to} -> send(to, {:calls, calls})
    end
  end
end
