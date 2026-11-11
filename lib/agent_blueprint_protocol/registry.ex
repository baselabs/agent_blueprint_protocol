defmodule AgentBlueprintProtocol.Registry do
  @moduledoc false

  alias AgentBlueprintProtocol.Json

  @typedoc """
    A field validator that returns success or a typed protocol error.
  """
  @type check :: (Json.value() -> :ok | {:error, AgentBlueprintProtocol.Error.t()})
  @typedoc """
    A root validator that checks members in a tagged JSON object.
  """
  @type root_hook :: (%{optional(binary()) => Json.value()} ->
                        :ok | {:error, AgentBlueprintProtocol.Error.t()})

  @typedoc """
    The registry field kinds used by the internal validation table.
  """
  @type kind ::
          :string
          | :integer
          | :float
          | :boolean
          | :number
          | :any
          | :custom
          | {:enum, MapSet.t()}
          | {:array, spec()}
          | {:object, %{members: [spec()]}}

  @typedoc """
    A field definition used by the internal validation table.
  """
  @type spec :: %{
          optional(:name) => binary(),
          optional(:required) => boolean(),
          optional(:kind) => kind(),
          optional(:check) => check(),
          optional(:root_hook) => root_hook(),
          optional(:min_items) => non_neg_integer(),
          optional(:max_items) => pos_integer(),
          optional(:unique_by) => binary()
        }

  @typedoc """
    A typed error returned by a registry validator.
  """
  @type reason :: AgentBlueprintProtocol.Error.t()

  @doc false
  @spec validate([spec()], Json.value()) :: :ok | {:error, AgentBlueprintProtocol.Error.t()}
  def validate(table, {:object, members}) when is_list(table) and is_list(members) do
    with true <- table_ok?(table) or {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}},
         :ok <- member_pairs_ok?(members),
         :ok <- no_duplicate_members(members),
         :ok <- unknown_check(table, members),
         :ok <- required_check(table, members),
         :ok <- type_check(table, members),
         :ok <- constraint_check(table, members),
         :ok <- cardinality_check(table, members),
         :ok <- recursion_check(table, members) do
      hook_check(table, members)
    end
  end

  def validate(_table, _value), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp table_ok?([]), do: true

  defp table_ok?([%{name: name, required: required, kind: _} = spec | rest])
       when is_binary(name) and is_boolean(required) do
    (not Map.has_key?(spec, :check) or is_function(spec.check, 1)) and
      (not Map.has_key?(spec, :root_hook) or is_function(spec.root_hook, 1)) and
      kind_spec_ok?(spec.kind) and table_ok?(rest)
  end

  defp table_ok?(_), do: false

  defp kind_spec_ok?(kind)
       when kind in [:string, :integer, :float, :boolean, :number, :any, :custom], do: true

  defp kind_spec_ok?({:enum, %MapSet{map: map}}), do: is_map(map)
  defp kind_spec_ok?({:array, %{kind: kind}}), do: kind_spec_ok?(kind)
  defp kind_spec_ok?({:object, %{members: members}}), do: table_ok?(members)
  defp kind_spec_ok?(_), do: false

  defp proper_list?([]), do: true
  defp proper_list?([_ | rest]), do: proper_list?(rest)
  defp proper_list?(_), do: false

  # ---- object well-formedness (hand-built values) ----------------------------------

  defp member_pairs_ok?(members) do
    if pairs?(members),
      do: :ok,
      else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
  end

  defp pairs?([]), do: true
  defp pairs?([{name, _} | rest]) when is_binary(name), do: pairs?(rest)
  defp pairs?(_), do: false

  defp no_duplicate_members(members) do
    names = Enum.map(members, fn {name, _} -> name end)

    if length(names) == length(Enum.uniq(names)),
      do: :ok,
      else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
  end

  # ---- stages ----------------------------------------------------------------------

  defp unknown_check(table, members) do
    names = MapSet.new(table, & &1.name)

    case Enum.find(members, fn {name, _} -> not MapSet.member?(names, name) end) do
      nil -> :ok
      _unknown -> {:error, %AgentBlueprintProtocol.Error{code: :unknown_member}}
    end
  end

  defp required_check(table, members) do
    present = MapSet.new(members, fn {name, _} -> name end)

    case Enum.find(table, &(&1.required and not MapSet.member?(present, &1.name))) do
      nil ->
        :ok

      %{name: name} ->
        {:error, %AgentBlueprintProtocol.Error{code: :missing_required_field, subject: [name]}}
    end
  end

  # Every table stage shares one walk: find the first spec (in table order,
  # or document order where a stage scans members) whose present value fails.
  defp stage(table, members, fun) when is_function(fun, 2) do
    table
    |> Enum.find_value(fn spec ->
      case List.keyfind(members, spec.name, 0) do
        nil ->
          nil

        {_name, value} ->
          at_field(fun.(spec, value), spec.name)
      end
    end)
    |> case do
      nil -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp at_field({:error, error}, name), do: {:error, %{error | subject: [name | error.subject]}}
  defp at_field(other, _name), do: other

  defp type_check(table, members),
    do: stage(table, members, fn spec, value -> spec_type(spec, value) end)

  defp spec_type(spec, value) do
    if kind_ok?(spec.kind, value),
      do: nil,
      else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
  end

  defp constraint_check(table, members),
    do: stage(table, members, fn spec, value -> spec_constraint(spec, value) end)

  defp spec_constraint(%{kind: {:enum, allowed}}, {:string, s}) when is_binary(s) do
    if MapSet.member?(allowed, s),
      do: nil,
      else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}}
  end

  defp spec_constraint(%{check: check}, value) when is_function(check, 1),
    do: check_result(check.(value))

  defp spec_constraint(_spec, _value), do: nil

  defp check_result(:ok), do: nil
  defp check_result({:error, _reason} = error), do: error

  defp cardinality_check(table, members),
    do: stage(table, members, fn spec, value -> array_cardinality(spec, value) end)

  defp array_cardinality(spec, {:array, items}) when is_list(items) do
    cond do
      spec[:min_items] != nil and length(items) < spec.min_items ->
        {:error, %AgentBlueprintProtocol.Error{code: :invalid_cardinality}}

      spec[:max_items] != nil and length(items) > spec.max_items ->
        {:error, %AgentBlueprintProtocol.Error{code: :invalid_cardinality}}

      duplicate_keys?(spec[:unique_by], items) ->
        {:error, %AgentBlueprintProtocol.Error{code: :invalid_cardinality}}

      true ->
        nil
    end
  end

  defp array_cardinality(_spec, _not_an_array), do: nil

  defp recursion_check(table, members),
    do: stage(table, members, fn spec, value -> spec_recursion(spec, value) end)

  defp spec_recursion(spec, value), do: pass_nil(recurse(spec.kind, value))

  defp pass_nil(:ok), do: nil
  defp pass_nil({:error, _reason} = error), do: error

  defp hook_check(table, members) do
    member_map = Map.new(members)

    table
    |> Enum.find_value(fn spec -> hook_result(spec, member_map) end)
    |> case do
      nil -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp hook_result(%{root_hook: hook} = spec, member_map) when is_function(hook, 1) do
    case Map.fetch(member_map, spec.name) do
      {:ok, _present} ->
        case check_result(hook.(member_map)) do
          {:error, error} -> {:error, %{error | subject: [spec.name | error.subject]}}
          other -> other
        end

      :error ->
        nil
    end
  end

  defp hook_result(_spec, _member_map), do: nil

  # Uniqueness over raw values: object elements participate through the named
  # member (an element not yet recursed into still participates; a missing
  # key does not — its own recursion denies it); scalar elements participate
  # whole (`unique_by: :value`).
  defp duplicate_keys?(nil, _items), do: false

  defp duplicate_keys?(:value, items),
    do: length(items) != length(Enum.uniq(items))

  defp duplicate_keys?(key_name, items) do
    keys =
      Enum.flat_map(items, fn
        {:object, members} when is_list(members) ->
          case List.keyfind(members, key_name, 0) do
            {^key_name, value} -> [value]
            nil -> []
          end

        _not_an_object ->
          []
      end)

    length(keys) != length(Enum.uniq(keys))
  end

  # Array elements and nested objects recurse AFTER the parent's cardinality;
  # children are visited in document order and their reasons propagate. An
  # element gets the same judgment a table field gets: kind (type stage),
  # enum membership or `check` (constraint stage), then nested recursion.
  defp recurse({:array, element_spec}, {:array, items}) when is_list(items) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
      case element_ok?(element_spec, item) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, %{error | subject: [index | error.subject]}}}
      end
    end)
  end

  defp recurse({:object, %{members: member_specs}}, {:object, members}) when is_list(members),
    do: validate(member_specs, {:object, members})

  defp recurse(_leaf, _value), do: :ok

  defp element_ok?(spec, value) do
    with :ok <- element_type(spec, value),
         :ok <- element_constraint(spec, value) do
      recurse(spec.kind, value)
    end
  end

  defp element_type(spec, value) do
    if kind_ok?(spec.kind, value),
      do: :ok,
      else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
  end

  defp element_constraint(%{kind: {:enum, allowed}}, {:string, s}) when is_binary(s) do
    if MapSet.member?(allowed, s),
      do: :ok,
      else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_constraint}}
  end

  defp element_constraint(%{check: check}, value) when is_function(check, 1) do
    case check.(value) do
      :ok -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp element_constraint(_spec, _value), do: :ok

  # ---- kinds ------------------------------------------------------------------------

  defp kind_ok?(:string, {:string, s}) when is_binary(s), do: true
  defp kind_ok?(:integer, {:integer, n}) when is_integer(n), do: true
  defp kind_ok?(:float, {:float, f}) when is_float(f), do: true
  defp kind_ok?(:boolean, {:boolean, b}) when is_boolean(b), do: true
  defp kind_ok?(:number, {:integer, n}) when is_integer(n), do: true
  defp kind_ok?(:number, {:float, f}) when is_float(f), do: true
  defp kind_ok?(:any, value), do: well_formed?(value)
  defp kind_ok?(:custom, _value), do: true

  defp kind_ok?({:enum, _allowed}, {:string, s}) when is_binary(s), do: true

  defp kind_ok?({:array, _element_spec}, {:array, items}) when is_list(items),
    do: proper_list?(items)

  defp kind_ok?({:object, %{members: _member_specs}}, {:object, members}) when is_list(members),
    do: pairs?(members)

  defp kind_ok?(_kind, _value), do: false

  defp well_formed?(:null), do: true
  defp well_formed?({:boolean, b}), do: is_boolean(b)
  defp well_formed?({:integer, n}), do: is_integer(n)
  defp well_formed?({:float, f}), do: is_float(f)
  defp well_formed?({:string, s}), do: is_binary(s)
  defp well_formed?({:array, items}) when is_list(items), do: Enum.all?(items, &well_formed?/1)

  defp well_formed?({:object, members}) when is_list(members) do
    Enum.all?(members, fn
      {name, value} when is_binary(name) -> well_formed?(value)
      _other -> false
    end)
  end

  defp well_formed?(_other), do: false
end
