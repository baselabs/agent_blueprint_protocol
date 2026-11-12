defmodule AgentBlueprintProtocol.BoundsAlgebra do
  @moduledoc """
    This module intersects Blueprint, Deployment, and host bound sets.

    Use it when an application needs effective bounds and records of any narrowing.

    This module does not authorize operations.

    ## Example

    ```elixir
    base = %{
      approval_trait: :none,
      authority_trait: :none,
      classification_ceiling: %{ordinal: :internal, markers: MapSet.new([])},
      disclosure_ceiling: :summary,
      effect_impact_ceiling: :ordinary,
      max_attempts: 3,
      max_concurrency: 2,
      max_cost: %{amount: 1000, currency: "USD"},
      max_depth: 8,
      max_descendants: 64,
      max_elapsed_ms: 60_000,
      max_fan_out: 4,
      max_tokens: 100_000
    }
    {:ok, bounds} = AgentBlueprintProtocol.BoundsAlgebra.BoundSet.new(base)
    sources = %AgentBlueprintProtocol.BoundsAlgebra.Sources{blueprint: bounds, deployment: bounds, host: bounds}
    match?({:ok, %AgentBlueprintProtocol.BoundsAlgebra.Result{}}, AgentBlueprintProtocol.BoundsAlgebra.intersect(sources))
    ```
  """
  @moduledoc since: "1.0.0"

  alias AgentBlueprintProtocol.{Blueprint, Deployment, Error}

  defmodule Bound do
    @moduledoc """
      This struct represents one named bound and its value.

      Use it when inspecting a bound in a validated bound set.

      This module does not authorize operations.

      ## Example

      ```elixir
      %AgentBlueprintProtocol.BoundsAlgebra.Bound{name: :max_tokens, class: :operational, unit: :token, value: 1000}
      ```
    """
    @moduledoc since: "1.0.0"

    defstruct [:name, :class, :unit, :value]

    @typedoc """
      The public data type for AgentBlueprintProtocol.BoundsAlgebra.Bound.
    """
    @type t :: %__MODULE__{
            name: atom(),
            class: :operational | :protected,
            unit: :count | :millisecond | :token | :money | :ordinal,
            value: term()
          }

    @spec narrower(t(), t()) :: boolean()
    @doc """
      Reports whether the first bound is strictly narrower than the second.

      ## Example

      ```elixir
      narrower = %AgentBlueprintProtocol.BoundsAlgebra.Bound{
        name: :max_tokens,
        class: :operational,
        unit: :token,
        value: 100
      }
      wider = %{narrower | value: 200}
      AgentBlueprintProtocol.BoundsAlgebra.Bound.narrower(narrower, wider)
      ```
    """
    @doc since: "1.0.0"
    def narrower(%__MODULE__{name: name, value: a}, %__MODULE__{name: name, value: b}),
      do: AgentBlueprintProtocol.BoundsAlgebra.narrower_value(name, a, b)

    def narrower(_, _), do: false
  end

  defmodule BoundSet do
    @moduledoc """
      This struct represents a set of named bounds.

      Use it when constructing or inspecting bound sources for intersection.

      This module does not authorize operations.

      ## Example

      ```elixir
      AgentBlueprintProtocol.BoundsAlgebra.BoundSet.new(%{max_tokens: 1000})
      ```
    """
    @moduledoc since: "1.0.0"

    defstruct [:bounds]

    @typedoc """
      The public data type for AgentBlueprintProtocol.BoundsAlgebra.BoundSet.
    """
    @type t :: %__MODULE__{bounds: %{optional(atom()) => Bound.t()}}

    @spec names() :: [atom()]
    @doc """
      Returns the names of the supported bounds.

      ## Example

      ```elixir
      AgentBlueprintProtocol.BoundsAlgebra.BoundSet.names()
      ```
    """
    @doc since: "1.0.0"
    def names, do: AgentBlueprintProtocol.BoundsAlgebra.names()

    @spec new(%{optional(atom()) => term()}) :: {:ok, t()} | {:error, Error.t()}
    @doc """
      Builds and validates a value from the supplied options.

      ## Example

      ```elixir
      AgentBlueprintProtocol.BoundsAlgebra.BoundSet.new(%{max_tokens: 1000})
      ```
    """
    @doc since: "1.0.0"
    def new(map) when is_map(map) and not is_struct(map) do
      map
      |> Enum.reduce_while({:ok, %{}}, fn {name, value}, {:ok, acc} ->
        case AgentBlueprintProtocol.BoundsAlgebra.build_bound(name, value) do
          {:ok, bound} -> {:cont, {:ok, Map.put(acc, name, bound)}}
          {:error, _} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, bounds} -> {:ok, %__MODULE__{bounds: bounds}}
        error -> error
      end
    end

    def new(_), do: {:error, %Error{code: :invalid_type, subject: ["bound_set"]}}

    @doc false
    @spec fetch(t(), atom()) :: {:ok, Bound.t()} | :error
    def fetch(%__MODULE__{bounds: bounds}, name) when is_map_key(bounds, name),
      do: {:ok, :erlang.map_get(name, bounds)}

    def fetch(_, _), do: :error

    @spec to_map(t()) :: {:ok, %{optional(atom()) => term()}} | {:error, Error.t()}
    @doc """
      Returns the raw values stored in a bound set.

      ## Example

      ```elixir
      {:ok, bounds} =
        AgentBlueprintProtocol.BoundsAlgebra.BoundSet.new(%{max_tokens: 1000})

      AgentBlueprintProtocol.BoundsAlgebra.BoundSet.to_map(bounds)
      ```
    """
    @doc since: "1.0.0"
    def to_map(%BoundSet{bounds: bounds}) when is_map(bounds) and not is_struct(bounds) do
      Enum.reduce_while(bounds, {:ok, %{}}, fn
        {name, %Bound{value: value}}, {:ok, acc} -> {:cont, {:ok, Map.put(acc, name, value)}}
        _, _ -> {:halt, {:error, %Error{code: :invalid_type, subject: ["bound_set"]}}}
      end)
    end

    def to_map(_), do: {:error, %Error{code: :invalid_type, subject: ["bound_set"]}}
  end

  defmodule Sources do
    @moduledoc """
      This struct carries the three bound sets used by an intersection.

      Use it when supplying Blueprint, Deployment, and host bounds to the algebra.

      This module does not authorize operations.

      ## Example

      ```elixir
      {:ok, bounds} = AgentBlueprintProtocol.BoundsAlgebra.BoundSet.new(%{max_tokens: 1000})
      sources = %AgentBlueprintProtocol.BoundsAlgebra.Sources{blueprint: bounds, deployment: bounds, host: bounds}
      ```
    """
    @moduledoc since: "1.0.0"

    defstruct [:blueprint, :deployment, :host, protected_clamp: :deny]

    @typedoc """
      The public data type for AgentBlueprintProtocol.BoundsAlgebra.Sources.
    """
    @type t :: %__MODULE__{
            blueprint: BoundSet.t(),
            deployment: BoundSet.t(),
            host: BoundSet.t(),
            protected_clamp: :deny | :acknowledge
          }
  end

  defmodule Result do
    @moduledoc """
      This struct contains the effective bound set and clamp records.

      Use it when consuming the result of a successful intersection.

      This module does not authorize operations.

      ## Example

      ```elixir
      result = %AgentBlueprintProtocol.BoundsAlgebra.Result{effective: %AgentBlueprintProtocol.BoundsAlgebra.BoundSet{bounds: %{}}, clamps: []}
      ```
    """
    @moduledoc since: "1.0.0"

    defstruct [:effective, :clamps]

    @typedoc """
      The public data type for AgentBlueprintProtocol.BoundsAlgebra.Result.
    """
    @type t :: %__MODULE__{
            effective: BoundSet.t(),
            clamps: [AgentBlueprintProtocol.BoundsAlgebra.ClampEvidence.t()]
          }
  end

  defmodule ClampEvidence do
    @moduledoc """
      This struct records one narrowing produced by a bound intersection.

      Use it when reviewing the effective value and source of a narrowed bound.

      This module does not authorize operations.

      ## Example

      ```elixir
      %AgentBlueprintProtocol.BoundsAlgebra.ClampEvidence{field: :max_tokens, class: :operational, unit: :token, requested: 2000, effective: 1000, source: :host, acknowledged: false}
      ```
    """
    @moduledoc since: "1.0.0"

    defstruct [:field, :class, :unit, :requested, :effective, :source, :acknowledged]

    @typedoc """
      The public data type for AgentBlueprintProtocol.BoundsAlgebra.ClampEvidence.
    """
    @type t :: %__MODULE__{
            field: atom(),
            class: :operational | :protected,
            unit: :count | :millisecond | :token | :money | :ordinal,
            requested: term(),
            effective: term(),
            source: :deployment | :host,
            acknowledged: boolean()
          }
  end

  # ---- the vocabulary table --------------------------------------------------

  @lattices %{
    classification: [:public, :internal, :confidential, :restricted],
    authority: [:none, :local_policy, :external_authority_required],
    approval: [:none, :human_required, :separated_human_required],
    impact: [:ordinary, :money, :authority, :secret],
    disclosure: [:none, :summary, :detail, :full]
  }

  @markers ~w(pci phi)a
  @currency ~r/\A[A-Z]{3}\z/

  # name => {class, unit, value-kind}
  @table %{
    max_attempts: {:operational, :count, :pos_integer},
    max_concurrency: {:operational, :count, :pos_integer},
    max_depth: {:operational, :count, :pos_integer},
    max_descendants: {:operational, :count, :pos_integer},
    max_elapsed_ms: {:operational, :millisecond, :pos_integer},
    max_fan_out: {:operational, :count, :pos_integer},
    max_tokens: {:operational, :token, :pos_integer},
    max_cost: {:operational, :money, :cost},
    classification_ceiling: {:protected, :ordinal, {:scope, :classification, :markers}},
    authority_trait: {:protected, :ordinal, {:obligation, :authority}},
    approval_trait: {:protected, :ordinal, {:obligation, :approval}},
    effect_impact_ceiling: {:protected, :ordinal, {:obligation, :impact}},
    disclosure_ceiling: {:protected, :ordinal, {:scope, :disclosure}}
  }

  @names Enum.sort(Map.keys(@table))

  # Missing-member precedence, pinned for the second-language verifier: sources in role
  # order (blueprint, deployment, host); per source the seven numerics
  # name-sorted, then max_cost, then the five protected name-sorted; the
  # first missing member fires.
  @missing_precedence [
    :max_attempts,
    :max_concurrency,
    :max_depth,
    :max_descendants,
    :max_elapsed_ms,
    :max_fan_out,
    :max_tokens,
    :max_cost,
    :approval_trait,
    :authority_trait,
    :classification_ceiling,
    :disclosure_ceiling,
    :effect_impact_ceiling
  ]

  @source_order [:blueprint, :deployment, :host]

  # ---- construction ------------------------------------------------------------

  @doc false
  @spec names() :: [atom()]
  def names, do: @names

  @doc false
  @spec build_bound(atom(), term()) :: {:ok, Bound.t()} | {:error, Error.t()}
  def build_bound(name, value) do
    case Map.fetch(@table, name) do
      {:ok, {class, unit, kind}} ->
        if value_ok?(kind, value) do
          {:ok, %Bound{name: name, class: class, unit: unit, value: value}}
        else
          {:error, %Error{code: :bound_value_invalid, subject: [to_string(name)]}}
        end

      :error ->
        # The subject is the containing surface, never the unknown name —
        # an attacker-supplied key must not ride the error channel, and a
        # non-atom/binary key must not crash to_string (the
        # unknown_member pattern).
        {:error, %Error{code: :bound_unknown, subject: ["bound_set"]}}
    end
  end

  # The parse profile's declared integer magnitude — the
  # algebra re-asserts it so a bypassed struct cannot smuggle a bignum.
  @integer_magnitude 9_007_199_254_740_991

  defp value_ok?(:pos_integer, v),
    do: is_integer(v) and v > 0 and v <= @integer_magnitude

  defp value_ok?(:cost, %{amount: amount, currency: currency} = value)
       when map_size(value) == 2 do
    is_integer(amount) and amount > 0 and amount <= @integer_magnitude and
      (is_binary(currency) and Regex.match?(@currency, currency))
  end

  defp value_ok?(:cost, _), do: false

  defp value_ok?({:scope, family, :markers}, %{ordinal: ordinal, markers: markers} = value)
       when map_size(value) == 2 and is_struct(markers, MapSet) do
    present = MapSet.to_list(markers)
    ordinal in @lattices[family] and Enum.all?(present, &(&1 in @markers))
  end

  defp value_ok?({:scope, _family, :markers}, _), do: false
  defp value_ok?({:scope, family}, v), do: v in @lattices[family]
  defp value_ok?({:obligation, family}, v), do: v in @lattices[family]

  # ---- the intersection --------------------------------------------------------

  @spec intersect(Sources.t()) :: {:ok, Result.t()} | {:error, Error.t()}
  @doc """
    Intersects the Blueprint, Deployment, and host bound sources.

    ## Example

    ```elixir
    base = %{
      approval_trait: :none,
      authority_trait: :none,
      classification_ceiling: %{ordinal: :internal, markers: MapSet.new([])},
      disclosure_ceiling: :summary,
      effect_impact_ceiling: :ordinary,
      max_attempts: 3,
      max_concurrency: 2,
      max_cost: %{amount: 1000, currency: "USD"},
      max_depth: 8,
      max_descendants: 64,
      max_elapsed_ms: 60_000,
      max_fan_out: 4,
      max_tokens: 100_000
    }

    {:ok, bounds} = AgentBlueprintProtocol.BoundsAlgebra.BoundSet.new(base)
    sources = %AgentBlueprintProtocol.BoundsAlgebra.Sources{
      blueprint: bounds,
      deployment: bounds,
      host: bounds
    }
    AgentBlueprintProtocol.BoundsAlgebra.intersect(sources)
    ```
  """
  @doc since: "1.0.0"
  def intersect(%Sources{} = sources) do
    with :ok <- posture_ok?(sources),
         :ok <- total?(sources),
         :ok <- cost_currencies_agree?(sources) do
      compose(sources)
    end
  end

  def intersect(_), do: {:error, %Error{code: :invalid_type, subject: ["sources"]}}

  defp posture_ok?(%Sources{protected_clamp: posture}) when posture in [:deny, :acknowledge],
    do: :ok

  defp posture_ok?(%Sources{}),
    do: {:error, %Error{code: :invalid_constraint, subject: ["protected_clamp"]}}

  # Per-source re-validation (a struct may bypass new/1) and totality under
  # the pinned precedence. Returns :ok or the first error.
  defp total?(sources) do
    @source_order
    |> Enum.find_value(fn role -> source_defect(Map.get(sources, role), role) end) ||
      :ok
  end

  defp source_defect(%BoundSet{bounds: bounds} = set, _role) when is_map(bounds) do
    present = MapSet.new(Map.keys(bounds))

    if present == MapSet.new(@names) do
      revalidate(set)
    else
      first_defect(set, present)
    end
  end

  defp source_defect(_not_a_set, role),
    do: {:error, %Error{code: :invalid_type, subject: [to_string(role)]}}

  # nil on success (so the outer find_value continues to the next source).
  defp revalidate(set) do
    names()
    |> Enum.find_value(&revalidate_one(set, &1))
  end

  defp revalidate_one(set, name) do
    case BoundSet.fetch(set, name) do
      {:ok, %Bound{value: value}} ->
        case build_bound(name, value) do
          {:ok, _} -> nil
          {:error, _} = error -> error
        end

      _ ->
        {:error, %Error{code: :invalid_type, subject: ["bound_set"]}}
    end
  end

  # Extra names deny first (a forged set is never more permissive than one
  # built through new/1 — the closed-vocabulary posture); then the pinned
  # precedence: a present member is re-validated in place; the first
  # missing member denies by family.
  defp first_defect(set, present) do
    if MapSet.size(MapSet.difference(present, MapSet.new(@names))) > 0 do
      {:error, %Error{code: :bound_unknown, subject: ["bound_set"]}}
    else
      precedence_defect(set, present)
    end
  end

  defp precedence_defect(set, present) do
    @missing_precedence
    |> Enum.find_value(fn name ->
      if name in present, do: revalidate_one(set, name), else: missing_code(name)
    end)
  end

  defp missing_code(name) do
    {class, _, _} = Map.fetch!(@table, name)
    code = if class == :operational, do: :missing_ceiling, else: :bound_source_missing
    {:error, %Error{code: code, subject: [to_string(name)]}}
  end

  defp cost_currencies_agree?(sources) do
    currencies =
      Enum.map(@source_order, fn role ->
        {:ok, bound} = BoundSet.fetch(Map.get(sources, role), :max_cost)
        bound.value.currency
      end)

    if Enum.uniq(currencies) == [hd(currencies)] do
      :ok
    else
      {:error, %Error{code: :bound_unit_mismatch, subject: ["max_cost"]}}
    end
  end

  defp compose(sources) do
    computed =
      Enum.reduce_while(names(), {:ok, %{}, []}, fn name, {:ok, bounds, clamps} ->
        compose_step(name, sources, bounds, clamps)
      end)

    case computed do
      {:ok, bounds, clamps} ->
        {:ok, %Result{effective: %BoundSet{bounds: bounds}, clamps: Enum.reverse(clamps)}}

      {:error, _} = error ->
        error
    end
  end

  defp compose_step(name, sources, bounds, clamps) do
    {class, unit, _kind} = Map.fetch!(@table, name)
    requested = value_of_set(sources.blueprint, name)
    effective = meet(name, sources)

    bound = %Bound{name: name, class: class, unit: unit, value: effective}

    if effective == requested do
      {:cont, {:ok, Map.put(bounds, name, bound), clamps}}
    else
      emit_clamp(name, sources, bound, requested, effective, bounds, clamps)
    end
  end

  defp emit_clamp(name, sources, bound, requested, effective, bounds, clamps) do
    {class, unit, _kind} = Map.fetch!(@table, name)

    evidence = %ClampEvidence{
      field: name,
      class: class,
      unit: unit,
      requested: requested,
      effective: effective,
      source: attribution(name, sources, effective),
      acknowledged: class == :protected and sources.protected_clamp == :acknowledge
    }

    if class == :protected and sources.protected_clamp == :deny do
      {:halt,
       {:error,
        %Error{
          code: :protected_bound_clamp_denied,
          subject: [to_string(name)]
        }}}
    else
      {:cont, {:ok, Map.put(bounds, name, bound), [evidence | clamps]}}
    end
  end

  defp meet(:max_cost, sources) do
    amounts = Enum.map(@source_order, &value_of_role(&1, sources, :max_cost).amount)
    %{amount: Enum.min(amounts), currency: value_of_role(:blueprint, sources, :max_cost).currency}
  end

  defp meet(name, sources) do
    {_, _, kind} = Map.fetch!(@table, name)
    values = Enum.map(@source_order, &value_of_role(&1, sources, name))

    case kind do
      :pos_integer ->
        Enum.min(values)

      {:scope, family, :markers} ->
        lattice = @lattices[family]

        %{
          ordinal: values |> Enum.map(& &1.ordinal) |> Enum.min_by(&index_of(lattice, &1)),
          markers: values |> Enum.map(& &1.markers) |> Enum.reduce(MapSet.new(), &MapSet.union/2)
        }

      {:scope, family} ->
        Enum.min_by(values, &index_of(@lattices[family], &1))

      {:obligation, family} ->
        Enum.max_by(values, &index_of(@lattices[family], &1))
    end
  end

  # The non-blueprint source whose value IS the effective; ties and
  # composites attribute :host (the live policy is the operative
  # constraint — pinned, deterministic).
  defp attribution(name, sources, effective) do
    cond do
      value_of_role(:host, sources, name) == effective -> :host
      value_of_role(:deployment, sources, name) == effective -> :deployment
      true -> :host
    end
  end

  defp value_of_role(role, sources, name) do
    {:ok, bound} = BoundSet.fetch(Map.get(sources, role), name)
    bound.value
  end

  defp value_of_set(set, name) do
    {:ok, bound} = BoundSet.fetch(set, name)
    bound.value
  end

  # ---- widens? -----------------------------------------------------------------

  @spec widens?(BoundSet.t(), BoundSet.t()) :: boolean()
  @doc """
    Reports whether one bound set is wider than another.

    ## Example

    ```elixir
    base = %{
      approval_trait: :none,
      authority_trait: :none,
      classification_ceiling: %{ordinal: :internal, markers: MapSet.new([])},
      disclosure_ceiling: :summary,
      effect_impact_ceiling: :ordinary,
      max_attempts: 3,
      max_concurrency: 2,
      max_cost: %{amount: 1000, currency: "USD"},
      max_depth: 8,
      max_descendants: 64,
      max_elapsed_ms: 60_000,
      max_fan_out: 4,
      max_tokens: 100_000
    }

    {:ok, bounds} = AgentBlueprintProtocol.BoundsAlgebra.BoundSet.new(base)
    AgentBlueprintProtocol.BoundsAlgebra.widens?(bounds, bounds)
    ```
  """
  @doc since: "1.0.0"
  def widens?(%BoundSet{bounds: a}, %BoundSet{bounds: b}) when is_map(a) and is_map(b) do
    Enum.any?(names(), fn name ->
      case {Map.fetch(a, name), Map.fetch(b, name)} do
        {{:ok, %Bound{value: left}}, {:ok, %Bound{value: right}}} ->
          widens_value(name, left, right)

        _incomplete ->
          true
      end
    end)
  end

  def widens?(_, _), do: true

  # Classification compares in the PRODUCT order the meet computes in
  # (ordinal ≤ AND markers ⊇ — the marker-retention rule; a marker dropped at
  # ANY ordinal is a widening, obligations are not tradeable against
  # scope). `a widens b` = ¬(a ⪯ b): fail-closed on every incomparable or
  # malformed pair. Total and never-raising on forged values.
  # The name always comes from names/0 iteration (a @table key) — unlike
  # narrower_value/3, which takes struct-forged names via Bound.narrower/2
  # and needs its :error arm.
  defp widens_value(name, a, b) do
    {:ok, {_, _, kind}} = Map.fetch(@table, name)
    widens_kind(kind, a, b)
  end

  defp widens_kind(:pos_integer, a, b) when is_integer(a) and is_integer(b), do: a > b
  defp widens_kind(:pos_integer, _, _), do: true

  defp widens_kind(:cost, %{amount: a_amount, currency: a_cur}, %{
         amount: b_amount,
         currency: b_cur
       })
       when is_integer(a_amount) and is_integer(b_amount),
       do: a_cur != b_cur or a_amount > b_amount

  defp widens_kind(:cost, _, _), do: true

  defp widens_kind({:scope, family, :markers}, %{ordinal: a_ord, markers: a_m}, %{
         ordinal: b_ord,
         markers: b_m
       }) do
    case {index_of(@lattices[family], a_ord), index_of(@lattices[family], b_ord)} do
      {ia, ib} when is_integer(ia) and is_integer(ib) ->
        ia > ib or not markers_subset?(b_m, a_m)

      _junk ->
        true
    end
  end

  defp widens_kind({:scope, _family, :markers}, _, _), do: true

  defp widens_kind({:scope, family}, a, b) do
    case {index_of(@lattices[family], a), index_of(@lattices[family], b)} do
      {ia, ib} when is_integer(ia) and is_integer(ib) -> ia > ib
      _junk -> true
    end
  end

  defp widens_kind({:obligation, family}, a, b) do
    case {index_of(@lattices[family], a), index_of(@lattices[family], b)} do
      {ia, ib} when is_integer(ia) and is_integer(ib) -> ia < ib
      _junk -> true
    end
  end

  # ---- narrower (per-bound) ------------------------------------------

  @doc false
  @spec narrower_value(atom(), term(), term()) :: boolean()
  def narrower_value(name, a, b) do
    case Map.fetch(@table, name) do
      {:ok, {_, _, kind}} -> narrower_kind(kind, a, b)
      :error -> false
    end
  end

  defp narrower_kind(:pos_integer, a, b) when is_integer(a) and is_integer(b), do: a < b
  defp narrower_kind(:pos_integer, _, _), do: false

  defp narrower_kind(:cost, %{amount: a_amount, currency: a_cur}, %{
         amount: b_amount,
         currency: b_cur
       })
       when is_integer(a_amount) and is_integer(b_amount),
       do: a_cur == b_cur and a_amount < b_amount

  defp narrower_kind(:cost, _, _), do: false

  defp narrower_kind({:scope, family, :markers}, %{ordinal: a_ord, markers: a_m}, %{
         ordinal: b_ord,
         markers: b_m
       }) do
    case {index_of(@lattices[family], a_ord), index_of(@lattices[family], b_ord)} do
      {ia, ib} when is_integer(ia) and is_integer(ib) ->
        (ia < ib and markers_subset?(b_m, a_m)) or
          (ia == ib and markers_strict_superset?(a_m, b_m))

      _junk ->
        false
    end
  end

  defp narrower_kind({:scope, _family, :markers}, _, _), do: false

  defp narrower_kind({:scope, family}, a, b) do
    case {index_of(@lattices[family], a), index_of(@lattices[family], b)} do
      {ia, ib} when is_integer(ia) and is_integer(ib) -> ia < ib
      _junk -> false
    end
  end

  defp narrower_kind({:obligation, family}, a, b) do
    case {index_of(@lattices[family], a), index_of(@lattices[family], b)} do
      {ia, ib} when is_integer(ia) and is_integer(ib) -> ia > ib
      _junk -> false
    end
  end

  defp markers_subset?(b, a) when is_struct(b, MapSet) and is_struct(a, MapSet),
    do: MapSet.subset?(b, a)

  defp markers_subset?(_, _), do: false

  defp markers_strict_superset?(a, b) when is_struct(a, MapSet) and is_struct(b, MapSet),
    do: MapSet.subset?(b, a) and not MapSet.equal?(a, b)

  defp markers_strict_superset?(_, _), do: false

  defp index_of(lattice, value), do: Enum.find_index(lattice, &(&1 == value))

  # ---- lifters --------------------------------------------------------------------

  @spec from_blueprint(Blueprint.t()) :: {:ok, BoundSet.t()} | {:error, Error.t()}
  @doc """
    Builds a bound set from a Blueprint.

    ## Example

    ```elixir
    dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
    {:ok, blueprint} =
      AgentBlueprintProtocol.Blueprint.decode(
        File.read!(Path.join(dependency_root, "examples/echo-blueprint.json"))
      )

    match?({:ok, %AgentBlueprintProtocol.BoundsAlgebra.BoundSet{}}, AgentBlueprintProtocol.BoundsAlgebra.from_blueprint(blueprint))
    ```
  """
  @doc since: "1.0.0"
  def from_blueprint(%Blueprint{value: {:object, members}}) when is_list(members) do
    with :ok <- value_shape({:object, members}),
         {:ok, bounds} <- lift_operational(member_of(members, "ceilings")) do
      derive_protected(members, bounds)
    end
  end

  def from_blueprint(_), do: {:error, %Error{code: :invalid_type, subject: ["blueprint"]}}

  @spec from_deployment(Deployment.t()) :: {:ok, BoundSet.t()} | {:error, Error.t()}
  @doc """
    Builds a bound set from a Deployment.

    ## Example

    ```elixir
    dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
    {:ok, deployment} =
      AgentBlueprintProtocol.Deployment.decode(
        File.read!(Path.join(dependency_root, "examples/echo-deployment.json"))
      )

    match?({:ok, %AgentBlueprintProtocol.BoundsAlgebra.BoundSet{}}, AgentBlueprintProtocol.BoundsAlgebra.from_deployment(deployment))
    ```
  """
  @doc since: "1.0.0"
  def from_deployment(%Deployment{value: {:object, members}}) when is_list(members) do
    with :ok <- value_shape({:object, members}) do
      lift_deployment_members(members)
    end
  end

  def from_deployment(_), do: {:error, %Error{code: :invalid_type, subject: ["deployment"]}}

  defp lift_deployment_members(members) do
    case member_of(members, "host_bounds") do
      nil ->
        {:ok, %BoundSet{bounds: %{}}}

      {:object, bound_members} when is_list(bound_members) ->
        with :ok <- closed_members?(bound_members, "host_bounds") do
          wrapped_lift(bound_members)
        end

      _malformed ->
        {:error, %Error{code: :invalid_type, subject: ["host_bounds"]}}
    end
  end

  defp value_shape(value) do
    case AgentBlueprintProtocol.Canonicalization.encode(value) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, %{reason | subject: ["bound_set"] ++ reason.subject}}
    end
  end

  defp lift_operational(nil), do: {:ok, %{}}

  defp lift_operational({:object, ceiling_members}) when is_list(ceiling_members) do
    with :ok <- closed_members?(ceiling_members, "ceilings") do
      lift_members(ceiling_members)
    end
  end

  defp lift_operational(_malformed),
    do: {:error, %Error{code: :invalid_type, subject: ["ceilings"]}}

  defp wrapped_lift(bound_members) do
    case lift_members(bound_members) do
      {:ok, bounds} -> {:ok, %BoundSet{bounds: bounds}}
      {:error, _} = error -> error
    end
  end

  # The lifted object is CLOSED and duplicate-free even on the hand-built
  # struct path (decode enforces both; protocol §9 "Reject duplicate
  # members" — first-wins List.keyfind must not become a silent hole).
  defp closed_members?(bound_members, subject) do
    member_names = Enum.map(bound_members, &elem(&1, 0))
    allowed = Enum.map(names(), &to_string/1)

    if Enum.uniq(member_names) == member_names and Enum.all?(member_names, &(&1 in allowed)) do
      :ok
    else
      {:error, %Error{code: :invalid_type, subject: [subject]}}
    end
  end

  defp lift_members(bound_members) do
    names()
    |> Enum.reduce_while({:ok, %{}}, fn name, {:ok, acc} ->
      case lift_one(name, bound_members) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, bound} -> {:cont, {:ok, Map.put(acc, name, bound)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, bounds} -> {:ok, bounds}
      error -> error
    end)
  end

  defp lift_one(:max_cost, members) do
    case member_of(members, "max_cost") do
      nil ->
        {:ok, nil}

      {:object, cost} ->
        with {:integer, amount} <- member_of(cost, "amount"),
             {:string, currency} <- member_of(cost, "currency") do
          build_bound(:max_cost, %{amount: amount, currency: currency})
        else
          _ -> {:error, %Error{code: :bound_value_invalid, subject: ["max_cost"]}}
        end

      _malformed ->
        {:error, %Error{code: :invalid_type, subject: ["max_cost"]}}
    end
  end

  defp lift_one(name, members) do
    {_, _, kind} = Map.fetch!(@table, name)

    case member_of(members, to_string(name)) do
      nil ->
        {:ok, nil}

      {:integer, value} when kind == :pos_integer ->
        build_bound(name, value)

      {:string, value} when kind != :pos_integer ->
        lift_ordinal(name, kind, value)

      _malformed ->
        {:error, %Error{code: :invalid_type, subject: [to_string(name)]}}
    end
  end

  defp lift_ordinal(name, kind, string) do
    lattice = lattice_of(kind)

    case lattice_atom(lattice, string) do
      {:ok, atom} ->
        if kind_match?(kind, :markers),
          do: build_bound(name, %{ordinal: atom, markers: MapSet.new([])}),
          else: build_bound(name, atom)

      :error ->
        {:error, %Error{code: :bound_value_invalid, subject: [to_string(name)]}}
    end
  end

  defp kind_match?({:scope, _family, marker_kind}, marker_kind), do: true
  defp kind_match?(_kind, _marker_kind), do: false

  defp lattice_of({:scope, family, :markers}), do: @lattices[family]
  defp lattice_of({:scope, family}), do: @lattices[family]
  defp lattice_of({:obligation, family}), do: @lattices[family]

  defp lattice_atom(lattice, string) do
    case Enum.find(lattice, &(to_string(&1) == string)) do
      nil -> :error
      atom -> {:ok, atom}
    end
  end

  # The derived protected envelope: classification is the WIDEST declared
  # across its five sites (absent when no site declares); approval and
  # authority are the STRICTEST claim across capabilities (empty → none);
  # impact is the strictest across capabilities and effect intents (empty →
  # ordinary); disclosure is the identity element :full.
  defp derive_protected(members, bounds) do
    derived = [
      derive_classification(members),
      derive_envelope(
        members,
        ["capability_requirements"],
        "approval_trait",
        :approval_trait,
        :approval,
        :none
      ),
      derive_envelope(
        members,
        ["capability_requirements"],
        "authority_trait",
        :authority_trait,
        :authority,
        :none
      ),
      derive_envelope(
        members,
        ["capability_requirements", "effect_intents"],
        "impact_class",
        :effect_impact_ceiling,
        :impact,
        :ordinary
      ),
      build_bound(:disclosure_ceiling, :full)
    ]

    derived
    |> Enum.reduce_while({:ok, bounds}, fn
      {:error, _} = error, _acc ->
        {:halt, error}

      :absent, {:ok, acc} ->
        {:cont, {:ok, acc}}

      {:ok, bound}, {:ok, acc} ->
        {:cont, {:ok, Map.put(acc, bound.name, bound)}}
    end)
    |> then(fn
      {:ok, final} -> {:ok, %BoundSet{bounds: final}}
      error -> error
    end)
  end

  defp derive_classification(members) do
    sites =
      ([member_string(members, "classification_ceiling"), contract_site(members)] ++
         array_strings(members, "input_ports", "classification_ceiling") ++
         array_strings(members, "output_ports", "classification_ceiling") ++
         array_strings(members, "capability_requirements", "classification_ceiling"))
      |> List.flatten()

    if sites == [] do
      :absent
    else
      widest_bound(sites, :classification, :classification_ceiling)
    end
  end

  defp derive_envelope(members, array_names, field, bound_name, family, empty_default) do
    strings = Enum.flat_map(array_names, &array_strings(members, &1, field))

    if strings == [] do
      build_bound(bound_name, empty_default)
    else
      strictest_bound(strings, family, bound_name)
    end
  end

  defp widest_bound(strings, family, bound_name) do
    lattice = @lattices[family]

    case all_atoms(strings, lattice, bound_name) do
      {:ok, atoms} ->
        widest = Enum.max_by(atoms, &index_of(lattice, &1))
        build_bound(bound_name, %{ordinal: widest, markers: MapSet.new([])})

      {:error, _} = error ->
        error
    end
  end

  defp strictest_bound(strings, family, bound_name) do
    lattice = @lattices[family]

    case all_atoms(strings, lattice, bound_name) do
      {:ok, atoms} ->
        build_bound(bound_name, Enum.max_by(atoms, &index_of(lattice, &1)))

      {:error, _} = error ->
        error
    end
  end

  defp all_atoms(strings, lattice, bound_name) do
    strings
    |> Enum.reduce_while({:ok, []}, fn string, {:ok, acc} ->
      case lattice_atom(lattice, string) do
        {:ok, atom} ->
          {:cont, {:ok, [atom | acc]}}

        :error ->
          {:halt, {:error, %Error{code: :bound_value_invalid, subject: [to_string(bound_name)]}}}
      end
    end)
    |> case do
      {:ok, atoms} -> {:ok, Enum.reverse(atoms)}
      error -> error
    end
  end

  defp member_string(members, name) do
    case member_of(members, name) do
      {:string, value} -> [value]
      _ -> []
    end
  end

  defp contract_site(members) do
    case member_of(members, "output_contract") do
      {:object, contract} -> member_string(contract, "classification_ceiling")
      _ -> []
    end
  end

  defp array_strings(members, array_name, field) do
    case member_of(members, array_name) do
      {:array, entries} when is_list(entries) ->
        Enum.flat_map(entries, fn
          {:object, entry} -> member_string(entry, field)
          _malformed -> []
        end)

      _ ->
        []
    end
  end

  # Callers pass member lists from the validated tagged value.
  defp member_of(members, name) when is_list(members) do
    case List.keyfind(members, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end
end
