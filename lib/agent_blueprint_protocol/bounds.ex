defmodule AgentBlueprintProtocol.Bounds do
  @moduledoc """
  This module defines limits for JSON decoding and canonical encoding.

  Use it when an application needs tighter parse limits than the package profile.

  This module does not authorize operations.

  ## Example

  ```elixir
  {:ok, bounds} = AgentBlueprintProtocol.Bounds.new(%{bytes: 100_000})
  ```
  """
  @moduledoc since: "1.0.0"

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

  @typedoc """
  The public data type for AgentBlueprintProtocol.Bounds.
  """
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

  @spec maximum() :: t()
  @doc """
  Returns the maximum parse-limit profile.

  ## Example

      iex> is_struct(AgentBlueprintProtocol.Bounds.maximum(), AgentBlueprintProtocol.Bounds)
      true
  """
  @doc since: "1.0.0"
  def maximum, do: struct!(__MODULE__, @maxima)

  @spec new(map()) :: {:ok, t()} | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
  Builds and validates a value from the supplied options.

  ## Example

      iex> match?({:ok, %AgentBlueprintProtocol.Bounds{bytes: 100}}, AgentBlueprintProtocol.Bounds.new(%{bytes: 100}))
      true
  """
  @doc since: "1.0.0"
  def new(overrides) when is_map(overrides) do
    with :ok <- validate_keys(overrides),
         :ok <- validate_values(overrides) do
      {:ok, struct!(maximum(), overrides)}
    end
  end

  def new(_), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  @spec coerce(t() | map()) :: {:ok, t()} | {:error, AgentBlueprintProtocol.Error.t()}
  @doc """
  Validates and normalizes a parse-limit value.

  ## Example

      iex> match?({:ok, %AgentBlueprintProtocol.Bounds{bytes: 100}}, AgentBlueprintProtocol.Bounds.coerce(%{bytes: 100}))
      true
  """
  @doc since: "1.0.0"
  def coerce(%__MODULE__{} = bounds), do: bounds |> Map.from_struct() |> new()
  def coerce(overrides) when is_map(overrides), do: new(overrides)

  def coerce(_), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp validate_keys(overrides) do
    case Map.keys(overrides) -- @fields do
      [] -> :ok
      _unknown -> {:error, %AgentBlueprintProtocol.Error{code: :unknown_bound}}
    end
  end

  defp validate_values(overrides) do
    Enum.reduce_while(overrides, :ok, fn {key, value}, :ok ->
      if is_integer(value) and value >= 1 and value <= Keyword.fetch!(@maxima, key) do
        {:cont, :ok}
      else
        {:halt, {:error, %AgentBlueprintProtocol.Error{code: {:ceiling, key}}}}
      end
    end)
  end
end
