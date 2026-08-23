defmodule AgentBlueprintProtocol.Schema do
  @moduledoc """
  Bounded JSON Schema 2020-12 dialect + instance validator.

  A closed 16-keyword subset — `type properties required items enum const
  minimum maximum minLength maxLength minItems maxItems additionalProperties
  oneOf $defs` plus document-local `$ref` — parsed from `Json`'s tagged
  algebra and evaluated as pure, zero-dep instance validation. Serves port
  payloads, `output_schema` assertions, and binding checks; evaluation and
  execution TRUTH stays host-owned. Semantics follow the 2020-12 core and
  validation specifications: assertions auto-pass instance types they do
  not target (core §7.6.1), missing keywords never fail (core §7.3), `oneOf`
  is exactly-one (core §10.2.1.3), boolean schemas are the substrate (core
  §4.3.2), numbers compare by mathematical value across the integer/float
  tags (core §4.2.2 — the tags do not survive the wire, so a non-Elixir
  verifier cannot and must not distinguish them), and string lengths count
  RFC 8259 characters (codepoints — not graphemes, not UTF-16 units).

  Everything outside the frozen subset denies `:schema_keyword_not_allowed`
  (fail-closed closed world: a regex-bearing or network-fetching schema is
  a DoS/SSRF surface in a portable artifact). Keyword recognition is
  POSITIONAL — only members of schema-position objects are keywords;
  `enum`/`const` values and `properties`/`$defs` member names are instance
  data.

  Resource posture: schema complexity is metered as
  `nodes + keywords + Σ(oneOf branches) + depth × 4` against the profile
  ceiling 512 (`:schema_complexity_exceeded`); evaluation memoizes
  (schema-node, instance-location) results — sound because assertion
  results are context-free in this annotation-free dialect — which bounds
  evaluation work to distinct pairs and closes the acyclic-`$ref`-DAG
  blowup; references resolve only to document-local JSON Pointers landing
  on schema positions, and any application-reachable reference cycle denies
  `:schema_ref_cycle` (core §9.4.1 — a dead `$defs` entry is never applied
  and may self-reference). `validate_instance/3` bounds no instance
  itself: termination and cost rely on the caller-side parse ceilings
  upstream (`Json`), the same posture as the decoder.

  Both `parse/2` and `validate_instance/3` are total and never raise on any
  input: malformed tagged shapes deny (`:invalid_type` instance-side,
  `:schema_keyword_value_invalid` schema-side), never crash. Errors are
  value-free; no wire string becomes an atom before a closed-set check.
  Schema validation is a structural fact — it never authorizes content.
  """

  alias AgentBlueprintProtocol.Json

  @dialect "https://json-schema.org/draft/2020-12/schema"
  @ceiling 512

  @type_names MapSet.new(["null", "boolean", "object", "array", "number", "string", "integer"])

  # Canonical evaluation order — the FIRST failure in this sequence is the
  # reported reason, independent of document member order. A fixed order is
  # what lets an independent verifier agree on multi-failure instances.
  # `$ref` leads because 2020-12 applies it alongside siblings, not instead.
  @keyword_order [
    "$ref",
    "type",
    "enum",
    "const",
    "minimum",
    "maximum",
    "minLength",
    "maxLength",
    "minItems",
    "maxItems",
    "required",
    "properties",
    "items",
    "additionalProperties",
    "oneOf"
  ]

  @schema_valued ["items", "additionalProperties"]
  @name_map_valued ["properties", "$defs"]

  @enforce_keys [:dialect, :root, :pointers, :complexity]
  defstruct [:dialect, :root, :pointers, :complexity]

  @typep pointers :: %{optional([binary()]) => Json.value()}

  @type t :: %__MODULE__{
          dialect: binary(),
          root: Json.value(),
          pointers: pointers(),
          complexity: non_neg_integer()
        }

  @type schema_reason ::
          :schema_dialect_unknown
          | :schema_keyword_not_allowed
          | :schema_keyword_value_invalid
          | :schema_complexity_exceeded
          | :schema_ref_unresolvable
          | :schema_ref_cycle
          | :schema_invalid_shape

  @type instance_reason :: :invalid_type | :invalid_constraint | :invalid_cardinality

  @doc """
  The single accepted dialect identifier — the 2020-12 dialect meta-schema
  URI (validation §5). 2020-12 is the only published dialect; the
  v1/2026 URI 404s.
  """
  @spec dialect() :: binary()
  def dialect, do: @dialect

  @doc "The profile complexity ceiling (declared profile maximum)."
  @spec ceiling() :: pos_integer()
  def ceiling, do: @ceiling

  @doc """
  Meter a schema document: `nodes + keywords + Σ(oneOf branch counts) +
  depth × 4`. Pure metering over the positional walk — unknown keywords
  count as keywords, their values as data; no validation is performed.
  """
  @spec complexity(Json.value()) :: non_neg_integer()
  def complexity(value) do
    # total like the other public calls: hand-built malformed tagged
    # values meter as 0 (they can never parse; decoder output is always
    # well-formed)
    if well_formed?(value) do
      {:ok, acc, _pointers, _edges} = walk(value, [], meter0(), %{}, [], :meter)
      meter_sum(acc)
    else
      0
    end
  end

  @doc """
  Parse a schema document (the tagged algebra value) under `dialect`.
  Validates the closed keyword subset, keyword-value syntax, document-local
  `$ref` resolution, application-edge acyclicity, and the complexity
  ceiling. Accepts only the exact 2020-12 dialect URI.
  """
  @spec parse(Json.value(), binary()) :: {:ok, t()} | {:error, schema_reason()}
  def parse(value, dialect) do
    with :ok <- check_dialect(dialect),
         :ok <- root_shape(value),
         :ok <- tagged_well_formed(value, :schema_keyword_value_invalid),
         {:ok, acc, pointers, edges} <- walk(value, [], meter0(), %{}, [], :validate),
         :ok <- resolve_edges(edges, pointers),
         :ok <- cycle_free?(pointers) do
      {:ok,
       %__MODULE__{
         dialect: @dialect,
         root: value,
         pointers: pointers,
         complexity: meter_sum(acc)
       }}
    end
  end

  @doc """
  Validate `instance` (a tagged algebra value) against `schema` under
  `dialect`. `schema` is the raw tagged document or a `parse/2` struct
  (structs are re-parsed, not trusted — the `Bounds.coerce` precedent).
  Total and never-raising on any input: malformed tagged values deny
  `:invalid_type`, malformed schemas deny a `:schema_*` reason.
  """
  @spec validate_instance(t() | Json.value(), Json.value(), binary()) ::
          :ok | {:error, instance_reason() | schema_reason()}
  def validate_instance(schema, instance, dialect) do
    with :ok <- check_dialect(dialect),
         {:ok, parsed} <- coerce(schema),
         :ok <- tagged_well_formed(instance, :invalid_type) do
      {result, _memo} = evaluate(parsed.root, instance, [], %{}, parsed.pointers)
      result
    end
  end

  ## Coercion + gates

  # A struct is re-parsed, not trusted (the Bounds.coerce precedent): a
  # directly-constructed %Schema{} with a forged pointers map or a
  # non-schema root would otherwise crash the evaluator. The metered
  # re-parse is sub-millisecond at the 512 ceiling.
  defp coerce(%__MODULE__{dialect: @dialect, root: root}), do: parse(root, @dialect)
  defp coerce(%__MODULE__{}), do: {:error, :schema_dialect_unknown}

  defp coerce(raw) do
    case parse(raw, @dialect) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_dialect(@dialect), do: :ok
  defp check_dialect(_other), do: {:error, :schema_dialect_unknown}

  defp root_shape({:object, _members}), do: :ok
  defp root_shape({:boolean, _}), do: :ok
  defp root_shape(_), do: {:error, :schema_invalid_shape}

  # The tagged-value well-formedness gate. The decoder guarantees every one
  # of these properties; hand-built terms do not, and the totality contract
  # turns each violation into the caller's `reason` instead of a crash.
  defp tagged_well_formed(value, reason) do
    if well_formed?(value), do: :ok, else: {:error, reason}
  end

  defp well_formed?(:null), do: true
  defp well_formed?({:boolean, b}), do: is_boolean(b)
  defp well_formed?({:integer, i}), do: is_integer(i)
  defp well_formed?({:float, f}), do: is_float(f)
  defp well_formed?({:string, s}), do: is_binary(s) and String.valid?(s)
  defp well_formed?({:array, items}), do: list_all?(items, &well_formed?/1)
  defp well_formed?({:object, members}), do: members_ok?(members, %{})
  defp well_formed?(_), do: false

  defp list_all?([], _fun), do: true
  defp list_all?([head | tail], fun), do: fun.(head) and list_all?(tail, fun)
  defp list_all?(_other, _fun), do: false

  defp members_ok?([], _seen), do: true

  defp members_ok?([{key, value} | tail], seen),
    do:
      is_binary(key) and String.valid?(key) and well_formed?(value) and
        not Map.has_key?(seen, key) and members_ok?(tail, Map.put(seen, key, true))

  defp members_ok?(_other, _seen), do: false

  ## Positional walk — keyword validation, metering, pointer map, ref edges

  defp meter0, do: %{nodes: 0, keywords: 0, branches: 0, depth: 0}

  defp meter_sum(%{nodes: n, keywords: k, branches: b, depth: d}), do: n + k + b + 4 * d

  # `path` is the pointer token list addressing this node from the root;
  # every schema-position node (objects AND booleans) lands in `pointers`,
  # and every `$ref` occurrence lands in `edges` as {source_path, tokens}.
  # Every metric component is monotone during the walk, so the fail-fast
  # ceiling check equals the final check.
  defp walk(term, path, acc, pointers, edges, mode) do
    acc = %{acc | nodes: acc.nodes + 1, depth: max(acc.depth, length(path) + 1)}

    case term do
      {:object, members} ->
        if mode == :validate and meter_sum(acc) > @ceiling do
          {:error, :schema_complexity_exceeded}
        else
          walk_members(members, path, acc, Map.put(pointers, path, term), edges, mode)
        end

      {:boolean, _} ->
        {:ok, acc, Map.put(pointers, path, term), edges}

      _scalar_or_malformed ->
        {:ok, acc, pointers, edges}
    end
  end

  defp walk_members([], _path, acc, pointers, edges, _mode), do: {:ok, acc, pointers, edges}

  defp walk_members([{key, value} | tail], path, acc, pointers, edges, mode) do
    acc = %{acc | keywords: acc.keywords + 1}

    with :ok <- allow_key(key, mode),
         :ok <- validate_value(key, value, mode),
         {:ok, acc, pointers, edges} <- descend(key, value, path, acc, pointers, edges, mode) do
      if mode == :validate and meter_sum(acc) > @ceiling do
        {:error, :schema_complexity_exceeded}
      else
        walk_members(tail, path, acc, pointers, edges, mode)
      end
    end
  end

  defp allow_key(key, :validate) when key in @keyword_order or key == "$defs", do: :ok
  defp allow_key(_key, :validate), do: {:error, :schema_keyword_not_allowed}
  defp allow_key(_key, :meter), do: :ok

  # Keyword-value syntax (design decision 10 — spec prose + meta-schema
  # floors, read first-hand). `:meter` mode accepts any shape and lets
  # `descend/7` fall through to data metering.
  defp validate_value("type", {:string, name}, :validate) do
    if MapSet.member?(@type_names, name), do: :ok, else: {:error, :schema_keyword_value_invalid}
  end

  defp validate_value("type", {:array, names}, :validate) do
    cond do
      not match_strings(names) ->
        {:error, :schema_keyword_value_invalid}

      names == [] ->
        {:error, :schema_keyword_value_invalid}

      names != Enum.uniq(names) ->
        {:error, :schema_keyword_value_invalid}

      not Enum.all?(names, fn {:string, name} -> MapSet.member?(@type_names, name) end) ->
        {:error, :schema_keyword_value_invalid}

      true ->
        :ok
    end
  end

  defp validate_value("enum", {:array, _elements}, :validate), do: :ok
  defp validate_value("const", _value, :validate), do: :ok

  defp validate_value(key, value, :validate) when key in ["minimum", "maximum"] do
    if number_tag?(value), do: :ok, else: {:error, :schema_keyword_value_invalid}
  end

  defp validate_value(key, value, :validate)
       when key in ["minLength", "maxLength", "minItems", "maxItems"] do
    case value do
      {:integer, n} when n >= 0 -> :ok
      {:float, f} when f >= 0 and f == trunc(f) -> :ok
      _ -> {:error, :schema_keyword_value_invalid}
    end
  end

  defp validate_value("required", {:array, names}, :validate) do
    cond do
      not match_strings(names) -> {:error, :schema_keyword_value_invalid}
      names != Enum.uniq(names) -> {:error, :schema_keyword_value_invalid}
      true -> :ok
    end
  end

  defp validate_value(key, {:object, _subs}, :validate) when key in @name_map_valued, do: :ok

  defp validate_value(key, value, :validate) when key in @schema_valued do
    if schema_shape?(value), do: :ok, else: {:error, :schema_keyword_value_invalid}
  end

  defp validate_value("oneOf", {:array, branches}, :validate) do
    if branches != [] and Enum.all?(branches, &schema_shape?/1),
      do: :ok,
      else: {:error, :schema_keyword_value_invalid}
  end

  defp validate_value("$ref", {:string, _ref}, :validate), do: :ok

  defp validate_value(_key, _value, :validate),
    do: {:error, :schema_keyword_value_invalid}

  defp validate_value(_key, _value, :meter), do: :ok

  defp schema_shape?({:object, _}), do: true
  defp schema_shape?({:boolean, _}), do: true
  defp schema_shape?(_), do: false

  defp match_strings([]), do: true
  defp match_strings([{:string, _} | tail]), do: match_strings(tail)
  defp match_strings(_), do: false

  defp number_tag?({:integer, _}), do: true
  defp number_tag?({:float, _}), do: true
  defp number_tag?(_), do: false

  # Descend into schema positions; data positions meter as plain nodes.
  defp descend("$ref", {:string, ref}, path, acc, pointers, edges, :validate) do
    case ref_tokens(ref) do
      {:ok, tokens} -> {:ok, acc, pointers, [{path, tokens} | edges]}
      :not_allowed -> {:error, :schema_keyword_not_allowed}
    end
  end

  defp descend("oneOf", {:array, branches}, path, acc, pointers, edges, mode) do
    # the branch array itself is a document node — count it
    acc = %{
      acc
      | branches: acc.branches + length(branches),
        nodes: acc.nodes + 1,
        depth: max(acc.depth, length(path) + 2)
    }

    walk_indexed(branches, 0, "oneOf", path, acc, pointers, edges, mode)
  end

  defp descend(key, {:object, subs}, path, acc, pointers, edges, mode)
       when key in @name_map_valued do
    # the name map itself is a document node — count it, then walk its
    # schema-position values
    acc = %{acc | nodes: acc.nodes + 1, depth: max(acc.depth, length(path) + 2)}
    walk_named(subs, key, path, acc, pointers, edges, mode)
  end

  defp descend(key, value, path, acc, pointers, edges, mode) when key in @schema_valued do
    if schema_shape?(value) do
      walk(value, path ++ [key], acc, pointers, edges, mode)
    else
      {:ok, meter_data(value, length(path) + 2, acc), pointers, edges}
    end
  end

  # Everything else (type/enum/const/number/required values, and meter-mode
  # leftovers) is data: nodes only, no keywords inside.
  defp descend(_key, value, path, acc, pointers, edges, _mode) do
    {:ok, meter_data(value, length(path) + 2, acc), pointers, edges}
  end

  defp walk_indexed([], _index, _key, _path, acc, pointers, edges, _mode),
    do: {:ok, acc, pointers, edges}

  defp walk_indexed([sub | tail], index, key, path, acc, pointers, edges, mode) do
    if schema_shape?(sub) do
      with {:ok, acc, pointers, edges} <-
             walk(sub, path ++ [key, Integer.to_string(index)], acc, pointers, edges, mode) do
        walk_indexed(tail, index + 1, key, path, acc, pointers, edges, mode)
      end
    else
      if mode == :validate do
        {:error, :schema_keyword_value_invalid}
      else
        walk_indexed(
          tail,
          index + 1,
          key,
          path,
          meter_data(sub, length(path) + 2, acc),
          pointers,
          edges,
          mode
        )
      end
    end
  end

  defp walk_named([], _key, _path, acc, pointers, edges, _mode), do: {:ok, acc, pointers, edges}

  defp walk_named([{name, sub} | tail], key, path, acc, pointers, edges, mode) do
    if schema_shape?(sub) do
      with {:ok, acc, pointers, edges} <-
             walk(sub, path ++ [key, name], acc, pointers, edges, mode) do
        walk_named(tail, key, path, acc, pointers, edges, mode)
      end
    else
      if mode == :validate do
        {:error, :schema_keyword_value_invalid}
      else
        walk_named(tail, key, path, meter_data(sub, length(path) + 2, acc), pointers, edges, mode)
      end
    end
  end

  defp meter_data(value, depth, acc) do
    acc = %{acc | nodes: acc.nodes + 1, depth: max(acc.depth, depth)}

    case value do
      {:array, items} ->
        Enum.reduce(items, acc, &meter_data(&1, depth + 1, &2))

      {:object, members} ->
        Enum.reduce(members, acc, fn {_k, v}, inner -> meter_data(v, depth + 1, inner) end)

      _other ->
        acc
    end
  end

  ## $ref pointers (RFC 6901: split on "/", then per-token ~1 → "/" before
  ## ~0 → "~", in ONE left-to-right pass; empty tokens address the
  ## empty-named member)

  defp ref_tokens("#"), do: {:ok, []}

  defp ref_tokens("#" <> rest) do
    if String.starts_with?(rest, "/") do
      tokens = tl(String.split(rest, "/"))

      case unescape_tokens(tokens, []) do
        {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
        :error -> :not_allowed
      end
    else
      # plain-name fragment or other non-pointer form
      :not_allowed
    end
  end

  # non-pointer strings — remote URIs, bare relative references — are the
  # dialect's not-allowed family
  defp ref_tokens(_non_pointer_string), do: :not_allowed

  defp unescape_tokens([], acc), do: {:ok, acc}

  defp unescape_tokens([token | tail], acc) do
    case unescape_token(token, []) do
      {:ok, decoded} -> unescape_tokens(tail, [decoded | acc])
      :error -> :error
    end
  end

  defp unescape_token(<<>>, acc), do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}
  defp unescape_token(<<?~, ?0, rest::binary>>, acc), do: unescape_token(rest, [?~ | acc])
  defp unescape_token(<<?~, ?1, rest::binary>>, acc), do: unescape_token(rest, [?/ | acc])

  # a "~" not followed by 0 or 1 is not an RFC 6901 escape
  defp unescape_token(<<?~, _rest::binary>>, _acc), do: :error
  defp unescape_token(<<char, rest::binary>>, acc), do: unescape_token(rest, [char | acc])

  ## Reference resolution + application-edge cycle check

  defp resolve_edges([], _pointers), do: :ok

  defp resolve_edges([{_path, tokens} | tail], pointers) do
    if Map.has_key?(pointers, tokens) do
      resolve_edges(tail, pointers)
    else
      {:error, :schema_ref_unresolvable}
    end
  end

  # Application edges are the positions evaluation follows: properties
  # values, items, additionalProperties, oneOf elements, and $ref targets.
  # $defs entries are a reserved location (core §8.2.4) and only become
  # reachable through a $ref — a dead self-referencing $defs entry parses.
  defp cycle_free?(pointers) do
    case dfs([], %{}, %{}, pointers) do
      {:ok, _visited} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp dfs(path, visiting, visited, pointers) do
    cond do
      Map.has_key?(visiting, path) ->
        {:error, :schema_ref_cycle}

      Map.has_key?(visited, path) ->
        {:ok, visited}

      true ->
        case visit_children(
               children(path, pointers),
               Map.put(visiting, path, true),
               visited,
               pointers
             ) do
          {:ok, visited} -> {:ok, Map.put(visited, path, true)}
          {:error, _reason} = error -> error
        end
    end
  end

  defp visit_children([], _visiting, visited, _pointers), do: {:ok, visited}

  defp visit_children([child | tail], visiting, visited, pointers) do
    case dfs(child, visiting, visited, pointers) do
      {:ok, visited} -> visit_children(tail, visiting, visited, pointers)
      {:error, _reason} = error -> error
    end
  end

  defp children(path, pointers) do
    case Map.fetch(pointers, path) do
      {:ok, {:object, members}} -> application_children(members, path)
      _other -> []
    end
  end

  defp application_children(members, path) do
    Enum.flat_map(members, fn
      {"properties", {:object, subs}} ->
        Enum.map(subs, fn {name, _sub} -> path ++ ["properties", name] end)

      {"items", _sub} ->
        [path ++ ["items"]]

      {"additionalProperties", _sub} ->
        [path ++ ["additionalProperties"]]

      {"oneOf", {:array, branches}} ->
        Enum.map(0..(length(branches) - 1)//1, &(path ++ ["oneOf", Integer.to_string(&1)]))

      {"$ref", {:string, ref}} ->
        # parse has already validated the ref form and its resolution
        {:ok, tokens} = ref_tokens(ref)
        [tokens]

      _member ->
        []
    end)
  end

  ## Evaluation — memoized on (schema term, instance location)

  defp evaluate({:boolean, true}, _instance, _loc, memo, _pointers), do: {:ok, memo}

  defp evaluate({:boolean, false}, _instance, _loc, memo, _pointers),
    do: {{:error, :invalid_type}, memo}

  defp evaluate({:object, _} = schema, instance, loc, memo, pointers) do
    key = {schema, loc}

    case memo do
      %{^key => result} ->
        {result, memo}

      _ ->
        case eval_keywords(schema, instance, loc, memo, pointers) do
          {:ok, memo2} ->
            {:ok, Map.put(memo2, key, :ok)}

          # errors are as deterministic as successes per (term, location) —
          # and the memo gained on the way down MUST survive the unwind:
          # dropping it re-walks shared subtrees once per distinct branch
          # (2^depth without it)
          {:error, reason, memo2} ->
            {{:error, reason}, Map.put(memo2, key, {:error, reason})}
        end
    end
  end

  defp eval_keywords(schema, instance, loc, memo, pointers) do
    Enum.reduce_while(@keyword_order, {:ok, memo}, fn keyword, acc ->
      eval_step(keyword, schema, instance, loc, acc, pointers)
    end)
  end

  defp eval_step(keyword, schema, instance, loc, {:ok, memo}, pointers) do
    case fetch(schema, keyword) do
      nil -> {:cont, {:ok, memo}}
      value -> eval_fetched(keyword, schema, value, instance, loc, memo, pointers)
    end
  end

  defp eval_fetched(keyword, schema, value, instance, loc, memo, pointers) do
    case eval_keyword(keyword, schema, value, instance, loc, memo, pointers) do
      {:ok, memo2} -> {:cont, {:ok, memo2}}
      {:error, reason, memo2} -> {:halt, {:error, reason, memo2}}
    end
  end

  defp fetch({:object, members}, key) do
    case List.keyfind(members, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp eval_keyword("$ref", _schema, {:string, ref}, instance, loc, memo, pointers) do
    {:ok, tokens} = ref_tokens(ref)

    case evaluate(Map.fetch!(pointers, tokens), instance, loc, memo, pointers) do
      {:ok, memo2} -> {:ok, memo2}
      {{:error, reason}, memo2} -> {:error, reason, memo2}
    end
  end

  defp eval_keyword("type", _schema, value, instance, _loc, memo, _pointers) do
    if Enum.any?(type_names(value), &type_matches?(&1, instance)) do
      {:ok, memo}
    else
      {:error, :invalid_type, memo}
    end
  end

  defp eval_keyword("enum", _schema, {:array, elements}, instance, _loc, memo, _pointers) do
    if Enum.any?(elements, &equal?(&1, instance)),
      do: {:ok, memo},
      else: {:error, :invalid_constraint, memo}
  end

  defp eval_keyword("const", _schema, value, instance, _loc, memo, _pointers) do
    if equal?(value, instance), do: {:ok, memo}, else: {:error, :invalid_constraint, memo}
  end

  defp eval_keyword("minimum", _schema, bound, instance, _loc, memo, _pointers) do
    limit = bound_number(bound)

    case instance do
      {:integer, n} -> if n >= limit, do: {:ok, memo}, else: {:error, :invalid_constraint, memo}
      {:float, f} -> if f >= limit, do: {:ok, memo}, else: {:error, :invalid_constraint, memo}
      _non_number -> {:ok, memo}
    end
  end

  defp eval_keyword("maximum", _schema, bound, instance, _loc, memo, _pointers) do
    limit = bound_number(bound)

    case instance do
      {:integer, n} -> if n <= limit, do: {:ok, memo}, else: {:error, :invalid_constraint, memo}
      {:float, f} -> if f <= limit, do: {:ok, memo}, else: {:error, :invalid_constraint, memo}
      _non_number -> {:ok, memo}
    end
  end

  defp eval_keyword("minLength", _schema, bound, instance, _loc, memo, _pointers) do
    limit = zero_fraction(bound)

    case instance do
      {:string, s} ->
        if length_string(s) >= limit, do: {:ok, memo}, else: {:error, :invalid_constraint, memo}

      _non_string ->
        {:ok, memo}
    end
  end

  defp eval_keyword("maxLength", _schema, bound, instance, _loc, memo, _pointers) do
    limit = zero_fraction(bound)

    case instance do
      {:string, s} ->
        if length_string(s) <= limit, do: {:ok, memo}, else: {:error, :invalid_constraint, memo}

      _non_string ->
        {:ok, memo}
    end
  end

  defp eval_keyword("minItems", _schema, bound, instance, _loc, memo, _pointers) do
    limit = zero_fraction(bound)

    case instance do
      {:array, items} ->
        if length(items) >= limit, do: {:ok, memo}, else: {:error, :invalid_cardinality, memo}

      _non_array ->
        {:ok, memo}
    end
  end

  defp eval_keyword("maxItems", _schema, bound, instance, _loc, memo, _pointers) do
    limit = zero_fraction(bound)

    case instance do
      {:array, items} ->
        if length(items) <= limit, do: {:ok, memo}, else: {:error, :invalid_cardinality, memo}

      _non_array ->
        {:ok, memo}
    end
  end

  defp eval_keyword("required", _schema, {:array, names}, instance, _loc, memo, _pointers) do
    case instance do
      {:object, members} ->
        if all_required?(names, members),
          do: {:ok, memo},
          else: {:error, :invalid_cardinality, memo}

      _non_object ->
        {:ok, memo}
    end
  end

  defp eval_keyword("properties", _schema, {:object, subs}, instance, loc, memo, pointers) do
    case instance do
      {:object, members} -> eval_present_properties(subs, members, loc, memo, pointers)
      _non_object -> {:ok, memo}
    end
  end

  defp eval_keyword("items", _schema, sub, instance, loc, memo, pointers) do
    case instance do
      {:array, items} -> eval_items(items, 0, sub, loc, memo, pointers)
      _non_array -> {:ok, memo}
    end
  end

  # Adjacency (core §10.3.2.3): additionalProperties sees only the sibling
  # `properties` member of the SAME schema object — never properties matched
  # inside oneOf branches or through $ref targets. `false` is the closure
  # itself and reports the closure class (an unexpected member), not the
  # boolean schema's type class; schema values propagate the child reason.
  defp eval_keyword("additionalProperties", schema, sub, instance, loc, memo, pointers) do
    case instance do
      {:object, members} -> eval_closure(schema, sub, members, loc, memo, pointers)
      _non_object -> {:ok, memo}
    end
  end

  defp eval_keyword("oneOf", _schema, {:array, branches}, instance, loc, memo, pointers) do
    case count_passes(branches, instance, loc, memo, pointers, 0) do
      {1, memo2} -> {:ok, memo2}
      {_other, memo2} -> {:error, :invalid_cardinality, memo2}
    end
  end

  defp all_required?(names, members) do
    Enum.all?(names, fn {:string, name} -> List.keymember?(members, name, 0) end)
  end

  defp eval_closure(schema, sub, members, loc, memo, pointers) do
    adjacent =
      case fetch(schema, "properties") do
        {:object, subs} -> Enum.map(subs, fn {name, _sub} -> name end)
        _absent -> []
      end

    additional = Enum.reject(members, fn {name, _v} -> name in adjacent end)

    case sub do
      {:boolean, true} -> {:ok, memo}
      {:boolean, false} when additional == [] -> {:ok, memo}
      {:boolean, false} -> {:error, :invalid_cardinality, memo}
      _schema_value -> eval_additional(additional, sub, loc, memo, pointers)
    end
  end

  defp eval_present_properties([], _members, _loc, memo, _pointers), do: {:ok, memo}

  defp eval_present_properties([{name, sub} | tail], members, loc, memo, pointers) do
    case List.keyfind(members, name, 0) do
      {^name, value} ->
        case evaluate(sub, value, [name | loc], memo, pointers) do
          {:ok, memo2} -> eval_present_properties(tail, members, loc, memo2, pointers)
          {{:error, reason}, memo2} -> {:error, reason, memo2}
        end

      nil ->
        eval_present_properties(tail, members, loc, memo, pointers)
    end
  end

  defp eval_items([], _index, _sub, _loc, memo, _pointers), do: {:ok, memo}

  defp eval_items([item | tail], index, sub, loc, memo, pointers) do
    case evaluate(sub, item, [index | loc], memo, pointers) do
      {:ok, memo2} -> eval_items(tail, index + 1, sub, loc, memo2, pointers)
      {{:error, reason}, memo2} -> {:error, reason, memo2}
    end
  end

  defp eval_additional([], _sub, _loc, memo, _pointers), do: {:ok, memo}

  defp eval_additional([{name, value} | tail], sub, loc, memo, pointers) do
    case evaluate(sub, value, [name | loc], memo, pointers) do
      {:ok, memo2} -> eval_additional(tail, sub, loc, memo2, pointers)
      {{:error, reason}, memo2} -> {:error, reason, memo2}
    end
  end

  # Branch results are memoized on (term, loc); counting stops at two —
  # exactly-one needs the full count only below two.
  defp count_passes([], _instance, _loc, memo, _pointers, count), do: {count, memo}

  defp count_passes([branch | tail], instance, loc, memo, pointers, count) when count < 2 do
    {result, memo2} = evaluate(branch, instance, loc, memo, pointers)
    count = if result == :ok, do: count + 1, else: count

    if count >= 2,
      do: {count, memo2},
      else: count_passes(tail, instance, loc, memo2, pointers, count)
  end

  defp type_names({:string, name}), do: [name]
  defp type_names({:array, names}), do: Enum.map(names, fn {:string, name} -> name end)

  defp type_matches?("null", :null), do: true
  defp type_matches?("boolean", {:boolean, _}), do: true
  defp type_matches?("object", {:object, _}), do: true
  defp type_matches?("array", {:array, _}), do: true
  defp type_matches?("string", {:string, _}), do: true
  defp type_matches?("number", {:integer, _}), do: true
  defp type_matches?("number", {:float, _}), do: true
  defp type_matches?("integer", {:integer, _}), do: true
  defp type_matches?("integer", {:float, f}), do: f == trunc(f)

  # no match: the instance's type is outside the keyword's name set — this
  # arm IS the failing type check
  defp type_matches?(_name, _instance), do: false

  # RFC 8259 characters = codepoints (validation §6.3.1/6.3.2). Never
  # `String.length/1` (graphemes — a combining sequence would undercount)
  # and never UTF-16 units (an astral character would double-count).
  defp length_string(s), do: count_codepoints(s, 0)

  defp count_codepoints(<<_::utf8, rest::binary>>, n), do: count_codepoints(rest, n + 1)
  defp count_codepoints(<<>>, n), do: n

  defp bound_number({:integer, n}), do: n
  defp bound_number({:float, f}), do: f

  defp zero_fraction({:integer, n}), do: n
  defp zero_fraction({:float, f}), do: trunc(f)

  ## Instance equality (core §4.2.2): numbers by mathematical value, strings
  ## codepoint-for-codepoint, objects order-blind, arrays order-sensitive.

  @doc """
  Structural equality of two tagged values per core §4.2.2: numbers compare
  by mathematical value across the integer/float tags, strings
  codepoint-for-codepoint, booleans and null by kind, arrays pairwise
  order-sensitive, objects order-blind with equal member counts. Mismatched
  kinds are unequal, never an error. Public so the artifact layers consume
  the one equality law rather than restating it.
  """
  @spec equal?(Json.value(), Json.value()) :: boolean()
  def equal?({:integer, a}, {:integer, b}), do: a == b
  def equal?({:integer, a}, {:float, b}), do: a == b
  def equal?({:float, a}, {:integer, b}), do: a == b
  def equal?({:float, a}, {:float, b}), do: a == b
  def equal?({:string, a}, {:string, b}), do: a == b
  def equal?(:null, :null), do: true
  def equal?({:boolean, a}, {:boolean, b}), do: a == b
  def equal?({:array, a}, {:array, b}), do: list_equal?(a, b)
  def equal?({:object, a}, {:object, b}), do: object_equal?(a, b)
  def equal?(_a, _b), do: false

  defp list_equal?([], []), do: true

  defp list_equal?([head_a | tail_a], [head_b | tail_b]),
    do: equal?(head_a, head_b) and list_equal?(tail_a, tail_b)

  defp list_equal?(_a, _b), do: false

  # Hand-built values may carry non-pair members; they are unequal, never a
  # crash (the newly-public equal?/2 owes totality on any input).
  defp pair?({key, _}) when is_binary(key), do: true
  defp pair?(_other), do: false

  defp object_equal?(a, b) do
    length(a) == length(b) and Enum.all?(a, &pair?/1) and Enum.all?(b, &pair?/1) and
      Enum.all?(a, fn {key, value} ->
        case List.keyfind(b, key, 0) do
          {^key, other} -> equal?(value, other)
          nil -> false
        end
      end)
  end
end
