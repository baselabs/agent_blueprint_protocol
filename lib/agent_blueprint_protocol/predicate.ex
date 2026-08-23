defmodule AgentBlueprintProtocol.Predicate do
  @node_ceiling 256

  @moduledoc """
  The closed, portable boolean predicate algebra carried by
  `deterministic_predicate` evaluation assertions (base §6.6).

  Grammar (closed world — every node is an object with `op` plus exactly the
  operator's operand members):

      {"op": "and" | "or",  "args": [predicate, …]}      # n-ary, ≥ 1
      {"op": "not",         "args": [predicate]}
      {"op": "eq" | "ne" | "lt" | "lte" | "gt" | "gte",
       "path": [segment, …], "value": json}
      {"op": "in",          "path": [segment, …], "values": [json, …]}
      {"op": "present" | "absent", "path": [segment, …]}

  `validate/2` checks shape against the declared port names: `path[0]` must
  name a declared port (`:predicate_path_unresolved`), the node count is
  ceilinged at `#{@node_ceiling}` (`:predicate_nodes_exceeded`), unknown
  operators deny `:predicate_op_unknown`, and operand-shape failures use the
  package's class vocabulary (`:unknown_member`, `:missing_required_field`,
  `:invalid_type`, `:invalid_cardinality`). Check order inside one node is
  pinned so two implementations pick the same reason: `op` presence → `op`
  value/known → unknown member → missing operand → operand type/cardinality →
  `path[0]` → node ceiling (nodes are counted depth-first, on entry).

  `evaluate/2` validates first, then applies the predicate to a map of port
  name → tagged value. Path addressing: segment 0 is the port-name map key;
  later segments address object members by name and array elements by
  CANONICAL decimal index string (`"0"`, `"17"` — no leading zeros). For
  `present`/`absent` an unresolvable path is a defined outcome (`present` →
  false, `absent` → true); for every value operator it is
  `{:error, :predicate_path_unresolved}`. `eq`/`ne`/`in` use `Schema.equal?/2`
  (mathematical-value numbers, order-blind objects); `lt`/`lte`/`gt`/`gte`
  require both operands numbers (mathematical value) or both strings (byte
  order) — any other combination is `:predicate_path_unresolved` (the path
  did not resolve to a value the operator can order). The n-ary `and`/`or`
  folds are ERROR-DOMINANT: any errored operand makes the fold an error
  regardless of the other operands' booleans, which is what makes the verdict
  independent of operand order (a value short-circuit would not).
  Predicates are declarative data — evaluation never authorizes anything.
  """

  alias AgentBlueprintProtocol.{Json, Schema}

  @type reason ::
          :predicate_op_unknown
          | :predicate_path_unresolved
          | :predicate_nodes_exceeded
          | :unknown_member
          | :missing_required_field
          | :invalid_type
          | :invalid_cardinality

  @fold_ops ["and", "or"]
  @not_ops ["not"]
  @compare_ops ["eq", "ne", "lt", "lte", "gt", "gte"]
  @member_ops ["in"]
  @presence_ops ["present", "absent"]
  @arg_ops @fold_ops ++ @not_ops
  @path_ops @compare_ops ++ @member_ops ++ @presence_ops

  # operand name lists per operator — plain lists; the MapSet round-trip on
  # fixed literals trips dialyzer's opaque contract for no gain at this size.
  @operands %{
    "and" => ["args"],
    "or" => ["args"],
    "not" => ["args"],
    "eq" => ["path", "value"],
    "ne" => ["path", "value"],
    "lt" => ["path", "value"],
    "lte" => ["path", "value"],
    "gt" => ["path", "value"],
    "gte" => ["path", "value"],
    "in" => ["path", "values"],
    "present" => ["path"],
    "absent" => ["path"]
  }

  @doc """
  Validate a predicate's shape against `port_names`. Total and never-raising
  on any input: malformed tagged shapes deny `:invalid_type`.
  """
  @spec validate(Json.value(), [binary()] | :any_root) :: :ok | {:error, reason()}
  def validate(predicate, :any_root) do
    case shape(predicate, :any_root, 0) do
      {:ok, _nodes} -> :ok
      {:error, _reason} = error -> error
    end
  end

  def validate(predicate, port_names) when is_list(port_names) do
    case shape(predicate, MapSet.new(port_names), 0) do
      {:ok, _nodes} -> :ok
      {:error, _reason} = error -> error
    end
  end

  def validate(_predicate, _port_names), do: {:error, :invalid_type}

  @doc """
  Apply `predicate` to `ports` (port name → tagged value). Validates first,
  so a shape-invalid predicate denies instead of raising. Returns
  `{:ok, boolean()}` or the first error encountered under the pinned orders.
  """
  @spec evaluate(Json.value(), %{optional(binary()) => Json.value()}) ::
          {:ok, boolean()} | {:error, reason()}
  def evaluate(predicate, ports) when is_map(ports) do
    # Shape-only: the root check belongs to decode-time validation against
    # DECLARED ports. At evaluation, a root the host did not supply is an
    # unresolvable path — a defined outcome for present/absent, an error
    # for value operators.
    with :ok <- validate(predicate, :any_root) do
      apply_node(predicate, ports)
    end
  end

  def evaluate(_predicate, _ports), do: {:error, :invalid_type}

  # ---- shape walk ---------------------------------------------------------------

  defp shape({:object, members}, ports, count) when is_list(members) do
    with :ok <- count_ok(count + 1),
         :ok <- no_duplicate_members(members),
         {:ok, op} <- op_of(members),
         :ok <- closed_members(members, op),
         :ok <- operands_present(members, op) do
      operand_shapes(members, op, ports, count + 1)
    end
  end

  defp shape(_other, _ports, _count), do: {:error, :invalid_type}

  defp count_ok(count) when count > @node_ceiling, do: {:error, :predicate_nodes_exceeded}
  defp count_ok(_count), do: :ok

  # Hand-built objects can carry duplicate members the decoder would have
  # rejected, and non-pair elements the algebra never admits; deny both
  # here rather than let keyfind pick a winner or the walk raise.
  defp no_duplicate_members(members) do
    names =
      Enum.map(members, fn
        {name, _} when is_binary(name) -> name
        _not_a_pair -> :malformed
      end)

    if :malformed in names or length(names) != length(Enum.uniq(names)),
      do: {:error, :invalid_type},
      else: :ok
  end

  defp op_of(members) do
    case List.keyfind(members, "op", 0) do
      {"op", {:string, op}} when is_binary(op) -> {:ok, op}
      {"op", _other} -> {:error, :invalid_type}
      nil -> {:error, :missing_required_field}
    end
  end

  defp closed_members(members, op) do
    case Map.fetch(@operands, op) do
      :error -> {:error, :predicate_op_unknown}
      {:ok, operands} -> closed_member_check(members, ["op" | operands])
    end
  end

  defp closed_member_check(members, allowed) do
    # Non-binary names were denied by no_duplicate_members first; every
    # remaining name is binary.
    case Enum.find(members, fn {name, _} -> name not in allowed end) do
      nil -> :ok
      {_name, _} -> {:error, :unknown_member}
    end
  end

  defp operands_present(members, op) do
    required = Map.fetch!(@operands, op)

    case Enum.find(required, fn name -> List.keyfind(members, name, 0) == nil end) do
      nil -> :ok
      _missing -> {:error, :missing_required_field}
    end
  end

  defp operand_shapes(members, op, ports, count) when op in @arg_ops do
    with {:ok, items} <- array_member(members, "args"),
         :ok <- arity_check(op, length(items)) do
      arg_shapes(items, ports, count)
    end
  end

  defp operand_shapes(members, op, ports, count) when op in @path_ops do
    with :ok <- path_member(members, ports),
         :ok <- values_member_when_needed(op, members) do
      {:ok, count}
    end
  end

  defp arity_check(op, n) when op in @fold_ops and n >= 1, do: :ok
  defp arity_check(_not, 1), do: :ok
  defp arity_check(_op, _n), do: {:error, :invalid_cardinality}

  defp values_member_when_needed("in", members), do: values_member(members)
  defp values_member_when_needed(_op, _members), do: :ok

  defp arg_shapes(items, ports, count) do
    Enum.reduce_while(items, {:ok, count}, fn item, {:ok, acc} ->
      case shape(item, ports, acc) do
        {:ok, nodes} -> {:cont, {:ok, nodes}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp array_member(members, name) do
    case List.keyfind(members, name, 0) do
      {^name, {:array, items}} when is_list(items) -> {:ok, items}
      {^name, _other} -> {:error, :invalid_type}
    end
  end

  defp path_member(members, ports) do
    case List.keyfind(members, "path", 0) do
      {"path", {:array, segments}} when is_list(segments) ->
        path_segments(segments, ports)

      {"path", _other} ->
        {:error, :invalid_type}
    end
  end

  defp path_segments([], _ports), do: {:error, :invalid_type}

  defp path_segments(segments, ports) do
    if Enum.all?(segments, &match?({:string, s} when is_binary(s), &1)) do
      [{:string, root} | _] = segments

      root_ok?(ports, root)
    else
      {:error, :invalid_type}
    end
  end

  defp root_ok?(:any_root, _root), do: :ok

  defp root_ok?(ports, root) do
    if MapSet.member?(ports, root),
      do: :ok,
      else: {:error, :predicate_path_unresolved}
  end

  defp values_member(members) do
    case List.keyfind(members, "values", 0) do
      {"values", {:array, items}} when is_list(items) ->
        if Enum.all?(items, &well_formed?/1), do: :ok, else: {:error, :invalid_type}

      {"values", _other} ->
        {:error, :invalid_type}
    end
  end

  # `value`/`values` operands carry arbitrary tagged JSON; they must still be
  # well-formed tagged values or evaluate-time equality would crash.
  defp well_formed?(:null), do: true
  defp well_formed?({:boolean, b}), do: is_boolean(b)
  defp well_formed?({:integer, n}), do: is_integer(n)
  defp well_formed?({:float, f}), do: is_float(f)
  defp well_formed?({:string, s}), do: is_binary(s)

  defp well_formed?({:array, items}) when is_list(items),
    do: Enum.all?(items, &well_formed?/1)

  defp well_formed?({:object, members}) when is_list(members) do
    Enum.all?(members, fn
      {name, value} when is_binary(name) -> well_formed?(value)
      _other -> false
    end)
  end

  defp well_formed?(_other), do: false

  # ---- evaluation ----------------------------------------------------------------

  defp apply_node({:object, members}, ports) do
    {"op", {:string, op}} = List.keyfind(members, "op", 0)

    case op do
      op when op in @fold_ops -> fold(op, args_of(members), ports)
      "not" -> not_apply(args_of(members), ports)
      op when op in @compare_ops -> compare(op, members, ports)
      "in" -> member_of(members, ports)
      op when op in @presence_ops -> presence_apply(op, members, ports)
    end
  end

  defp args_of(members) do
    {"args", {:array, items}} = List.keyfind(members, "args", 0)
    items
  end

  # Error-dominant: the first error wins and booleans never override it —
  # stop on error, never on a boolean.
  defp fold(op, items, ports) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, booleans} ->
      case apply_node(item, ports) do
        {:ok, boolean} -> {:cont, {:ok, [boolean | booleans]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, booleans} ->
        combined = if(op == "and", do: Enum.all?(booleans), else: Enum.any?(booleans))
        {:ok, combined}

      {:error, _reason} = error ->
        error
    end
  end

  defp not_apply([arg], ports) do
    case apply_node(arg, ports) do
      {:ok, boolean} -> {:ok, not boolean}
      {:error, _reason} = error -> error
    end
  end

  defp compare(op, members, ports) do
    {"path", {:array, segments}} = List.keyfind(members, "path", 0)
    {"value", value} = List.keyfind(members, "value", 0)

    case resolve(segments, ports) do
      {:ok, actual} -> compare_values(op, actual, value)
      :unresolved -> {:error, :predicate_path_unresolved}
    end
  end

  defp compare_values(op, actual, value) when op in ["eq", "ne"] do
    equal = Schema.equal?(actual, value)
    {:ok, if(op == "eq", do: equal, else: not equal)}
  end

  defp compare_values(op, actual, value)
       when op in ["lt", "lte", "gt", "gte"] do
    case orderable_pair(actual, value) do
      {:ok, a, b} -> {:ok, order(op, a, b)}
      :mismatched_kinds -> {:error, :predicate_path_unresolved}
    end
  end

  # Orderable operands: both numbers (mathematical value, either tag) or both
  # strings (byte order). Anything else the operator cannot order.
  defp orderable_pair({:integer, a}, {:integer, b}), do: {:ok, a, b}
  defp orderable_pair({:integer, a}, {:float, b}), do: {:ok, a, b}
  defp orderable_pair({:float, a}, {:integer, b}), do: {:ok, a, b}
  defp orderable_pair({:float, a}, {:float, b}), do: {:ok, a, b}
  defp orderable_pair({:string, a}, {:string, b}), do: {:ok, a, b}
  defp orderable_pair(_actual, _value), do: :mismatched_kinds

  defp order("lt", a, b), do: a < b
  defp order("lte", a, b), do: a <= b
  defp order("gt", a, b), do: a > b
  defp order("gte", a, b), do: a >= b

  defp member_of(members, ports) do
    {"path", {:array, segments}} = List.keyfind(members, "path", 0)
    {"values", {:array, values}} = List.keyfind(members, "values", 0)

    case resolve(segments, ports) do
      {:ok, actual} -> {:ok, Enum.any?(values, &Schema.equal?(actual, &1))}
      :unresolved -> {:error, :predicate_path_unresolved}
    end
  end

  defp presence_apply(op, members, ports) do
    {"path", {:array, segments}} = List.keyfind(members, "path", 0)
    resolved = resolve(segments, ports) != :unresolved
    {:ok, if(op == "present", do: resolved, else: not resolved)}
  end

  # ---- path resolution -------------------------------------------------------------

  defp resolve([{:string, root} | rest], ports) do
    case Map.fetch(ports, root) do
      {:ok, value} -> resolve_rest(rest, value)
      :error -> :unresolved
    end
  end

  defp resolve_rest([], value), do: {:ok, value}

  defp resolve_rest([{:string, segment} | rest], {:object, members}) do
    case List.keyfind(members, segment, 0) do
      {^segment, value} -> resolve_rest(rest, value)
      nil -> :unresolved
    end
  end

  defp resolve_rest([{:string, segment} | rest], {:array, items}) do
    case canonical_index(segment) do
      {:ok, index} when index < length(items) -> resolve_rest(rest, Enum.at(items, index))
      _other -> :unresolved
    end
  end

  defp resolve_rest(_segments, _scalar), do: :unresolved

  # Canonical decimal only: "0", "17" — "01", "1x", "-1" do not address.
  defp canonical_index(segment) do
    case segment do
      "0" ->
        {:ok, 0}

      other when is_binary(other) ->
        if Regex.match?(~r/\A[1-9][0-9]*\z/, other),
          do: {:ok, String.to_integer(other)},
          else: :error
    end
  end
end
