defmodule AgentBlueprintProtocol.Registry do
  @moduledoc """
  The generic field-registry decode/validate engine: ONE
  table-driven walk, parameterized by the registry table an artifact layer
  supplies — `Blueprint` today, `Deployment` next. The engine knows tables,
  not domains: every domain judgment (bounded schemas, signature envelopes,
  predicates, extension forms, cross-field rules) arrives as data — checker
  functions carried in the table and defined in the owning artifact module —
  so the dependency direction is always artifact → engine.

  A table is a list of field specs (maps):

      %{
        name: "member_name",            # binary()
        required: true,                 # absence → :missing_required_field
        kind: kind(),                   # structural check below
        check: fn value -> :ok | {:error, reason()} end,   # optional, per-field
        root_hook: fn members -> :ok | {:error, reason()} end, # optional, cross-field
        min_items: 1,                   # array cardinality floor (kind arrays)
        max_items: 64,                  # array cardinality ceiling
        unique_by: "id"                 # array element uniqueness member name
      }

  Kinds: `:string` `:integer` `:float` `:boolean` `:number` (either number
  tag) `{:enum, MapSet.t()}` `{:array, element_spec}` `{:object,
  %{members: [spec()]}}` (closed world recursively) `:any` (any well-formed
  tagged value) `:custom` (the spec's `check` is the whole judgment). `:integer` is TAG-STRICT: a
  `{:float, f}` — including a zero-fraction window float — denies
  `:invalid_type`. This is the artifact layer's typing; the wire cannot carry
  the tag, so only this layer can see it (the artifact-typing relocation).

  **Failure precedence is pinned** so two implementations pick the same
  reason. Per object: member-list well-formedness (pairs, duplicates —
  hand-built values only; the decoder already denies these) → `:unknown_member`
  (document order) → `:missing_required_field` (table order) → `:invalid_type`
  (table order) → `:invalid_constraint` (table order: enum membership and
  `check` results that are not pass-through reasons of earlier stages) →
  `:invalid_cardinality` (table order: counts and uniqueness over raw keys) →
  nested recursion (children in document order; child reasons propagate) →
  `root_hook`s (table order). Array elements are recursed after cardinality,
  and uniqueness runs on raw member values so it never depends on element
  validity.

  Total and never-raising: malformed tagged shapes deny `:invalid_type`.
  The engine validates structure — validation never authorizes an operation.
  """

  alias AgentBlueprintProtocol.Json

  @type check :: (Json.value() -> :ok | {:error, reason()})
  @type root_hook :: (%{optional(binary()) => Json.value()} -> :ok | {:error, reason()})

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

  @type reason ::
          :unknown_member
          | :missing_required_field
          | :invalid_type
          | :invalid_constraint
          | :invalid_cardinality
          | term()

  @doc """
  Validate `value` against `table` under the pinned precedence. The root
  must be an object; every stage is fail-closed and value-free.
  """
  @spec validate([spec()], Json.value()) :: :ok | {:error, reason()}
  def validate(table, {:object, members}) when is_list(table) and is_list(members) do
    with :ok <- member_pairs_ok?(members),
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

  def validate(_table, _value), do: {:error, :invalid_type}

  # ---- object well-formedness (hand-built values) ----------------------------------

  defp member_pairs_ok?(members) do
    if Enum.all?(members, &match?({name, _} when is_binary(name), &1)),
      do: :ok,
      else: {:error, :invalid_type}
  end

  defp no_duplicate_members(members) do
    names = Enum.map(members, fn {name, _} -> name end)

    if length(names) == length(Enum.uniq(names)),
      do: :ok,
      else: {:error, :invalid_type}
  end

  # ---- stages ----------------------------------------------------------------------

  defp unknown_check(table, members) do
    names = MapSet.new(table, & &1.name)

    case Enum.find(members, fn {name, _} -> not MapSet.member?(names, name) end) do
      nil -> :ok
      _unknown -> {:error, :unknown_member}
    end
  end

  defp required_check(table, members) do
    present = MapSet.new(members, fn {name, _} -> name end)

    case Enum.find(table, &(&1.required and not MapSet.member?(present, &1.name))) do
      nil -> :ok
      _missing -> {:error, :missing_required_field}
    end
  end

  # Every table stage shares one walk: find the first spec (in table order,
  # or document order where a stage scans members) whose present value fails.
  defp stage(table, members, fun) when is_function(fun, 2) do
    table
    |> Enum.find_value(fn spec ->
      case List.keyfind(members, spec.name, 0) do
        nil -> nil
        {_name, value} -> fun.(spec, value)
      end
    end)
    |> case do
      nil -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp type_check(table, members),
    do: stage(table, members, fn spec, value -> spec_type(spec, value) end)

  defp spec_type(spec, value) do
    if kind_ok?(spec.kind, value), do: nil, else: {:error, :invalid_type}
  end

  defp constraint_check(table, members),
    do: stage(table, members, fn spec, value -> spec_constraint(spec, value) end)

  defp spec_constraint(%{kind: {:enum, allowed}}, {:string, s}) when is_binary(s) do
    if MapSet.member?(allowed, s), do: nil, else: {:error, :invalid_constraint}
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
        {:error, :invalid_cardinality}

      spec[:max_items] != nil and length(items) > spec.max_items ->
        {:error, :invalid_cardinality}

      duplicate_keys?(spec[:unique_by], items) ->
        {:error, :invalid_cardinality}

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
      {:ok, _present} -> check_result(hook.(member_map))
      :error -> nil
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
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case element_ok?(element_spec, item) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
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
    if kind_ok?(spec.kind, value), do: :ok, else: {:error, :invalid_type}
  end

  defp element_constraint(%{kind: {:enum, allowed}}, {:string, s}) when is_binary(s) do
    if MapSet.member?(allowed, s), do: :ok, else: {:error, :invalid_constraint}
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
  defp kind_ok?(:number, {:integer, _n}), do: true
  defp kind_ok?(:number, {:float, _f}), do: true
  defp kind_ok?(:any, value), do: well_formed?(value)
  defp kind_ok?(:custom, _value), do: true

  defp kind_ok?({:enum, _allowed}, {:string, s}) when is_binary(s), do: true
  defp kind_ok?({:array, _element_spec}, {:array, items}) when is_list(items), do: true

  defp kind_ok?({:object, %{members: _member_specs}}, {:object, members}) when is_list(members),
    do: true

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
