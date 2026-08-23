defmodule AgentBlueprintProtocol.Bounds do
  @moduledoc """
  Parse ceilings for the bounded JSON decoder — resource-exhaustion guards,
  distinct from the eight operational ceilings an artifact declares.

  Every field is a positive integer. `maximum/0` is the immutable profile
  ceiling. `new/1` derives a *tighter* profile: an override may only lower a
  field, never raise it, so a portable input can never widen a host's parse
  limits.

  | field | meaning |
  |---|---|
  | `bytes` | maximum total input size |
  | `depth` | maximum structural nesting |
  | `members` | maximum members in one object |
  | `items` | maximum items in one array |
  | `nodes` | maximum total value nodes |
  | `string` | maximum byte length of one string value |
  | `key` | maximum byte length of one object key |
  | `number_lexeme` | maximum byte length of one number's source lexeme |
  Parse ceilings are decoder limits — the profile authorizes nothing.
  """

  @maxima [
    bytes: 5_000_000,
    depth: 64,
    members: 1_000,
    items: 10_000,
    nodes: 200_000,
    string: 100_000,
    key: 1_000,
    number_lexeme: 64
  ]

  @fields Keyword.keys(@maxima)

  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          bytes: pos_integer(),
          depth: pos_integer(),
          members: pos_integer(),
          items: pos_integer(),
          nodes: pos_integer(),
          string: pos_integer(),
          key: pos_integer(),
          number_lexeme: pos_integer()
        }

  @type error :: :unknown_bound | {:ceiling, atom()}

  @doc "The immutable profile maxima."
  @spec maximum() :: t()
  def maximum, do: struct!(__MODULE__, @maxima)

  @doc """
  A tighter profile from `overrides`. Each override key must be known and its
  value a positive integer no greater than the corresponding maximum
  (tighten-only). Omitted fields keep their maximum.
  """
  @spec new(map()) :: {:ok, t()} | {:error, error()}
  def new(overrides) when is_map(overrides) do
    with :ok <- validate_keys(overrides),
         :ok <- validate_values(overrides) do
      {:ok, struct!(maximum(), overrides)}
    end
  end

  @doc """
  Validate and normalize a `Bounds` struct, or build one from an overrides map.

  A struct is re-validated field-by-field, not trusted: a directly-constructed
  `%Bounds{}` carrying a super-maximum (or non-positive) ceiling is rejected, so
  the tighten-only invariant holds no matter how the struct was made.
  """
  @spec coerce(t() | map()) :: {:ok, t()} | {:error, error()}
  def coerce(%__MODULE__{} = bounds), do: bounds |> Map.from_struct() |> new()
  def coerce(overrides) when is_map(overrides), do: new(overrides)

  defp validate_keys(overrides) do
    case Map.keys(overrides) -- @fields do
      [] -> :ok
      _unknown -> {:error, :unknown_bound}
    end
  end

  defp validate_values(overrides) do
    Enum.reduce_while(overrides, :ok, fn {key, value}, :ok ->
      if is_integer(value) and value >= 1 and value <= Keyword.fetch!(@maxima, key) do
        {:cont, :ok}
      else
        {:halt, {:error, {:ceiling, key}}}
      end
    end)
  end
end
