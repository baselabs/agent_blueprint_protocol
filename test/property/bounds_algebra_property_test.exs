defmodule AgentBlueprintProtocol.Property.BoundsAlgebraTest do
  @moduledoc """
  Bounds-algebra properties: the intersection's algebra laws
  (idempotent, commutative under source permutation, associative through
  the pinned fold encoding), the universal non-widening law, the clamp
  emission law, `Bound.narrower/2` per-lattice totality and direction, and
  the marker-union law the pci-dropped mutation targets.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentBlueprintProtocol.BoundsAlgebra
  alias BoundsAlgebra.{Bound, BoundSet, Sources}

  @classification ~w(public internal confidential restricted)a
  @authority ~w(none local_policy external_authority_required)a
  @approval ~w(none human_required separated_human_required)a
  @impact ~w(ordinary money authority secret)a
  @disclosure ~w(none summary detail full)a

  @scope_families ~w(classification_ceiling disclosure_ceiling)a
  @obligation_families ~w(approval_trait authority_trait effect_impact_ceiling)a

  # ---- generators -----------------------------------------------------------

  defp marker_set do
    gen all(pci? <- boolean(), phi? <- boolean()) do
      MapSet.new(for {flag, name} <- [{pci?, :pci}, {phi?, :phi}], flag, do: name)
    end
  end

  defp classification_value do
    gen all(ordinal <- member_of(@classification), markers <- marker_set()) do
      %{ordinal: ordinal, markers: markers}
    end
  end

  defp bound_map(currency \\ "USD") do
    gen all(
          max_attempts <- integer(1..1_000_000),
          max_concurrency <- integer(1..1_000_000),
          max_depth <- integer(1..1_000_000),
          max_descendants <- integer(1..1_000_000),
          max_elapsed_ms <- integer(1..1_000_000),
          max_fan_out <- integer(1..1_000_000),
          max_tokens <- integer(1..1_000_000),
          cost_amount <- integer(1..1_000_000),
          approval <- member_of(@approval),
          authority <- member_of(@authority),
          classification <- classification_value(),
          impact <- member_of(@impact),
          disclosure <- member_of(@disclosure)
        ) do
      %{
        max_attempts: max_attempts,
        max_concurrency: max_concurrency,
        max_depth: max_depth,
        max_descendants: max_descendants,
        max_elapsed_ms: max_elapsed_ms,
        max_fan_out: max_fan_out,
        max_tokens: max_tokens,
        max_cost: %{amount: cost_amount, currency: currency},
        approval_trait: approval,
        authority_trait: authority,
        classification_ceiling: classification,
        effect_impact_ceiling: impact,
        disclosure_ceiling: disclosure
      }
      |> BoundSet.new()
      |> ok!()
    end
  end

  defp triple(currency \\ "USD") do
    gen all(
          blueprint <- bound_map(currency),
          deployment <- bound_map(currency),
          host <- bound_map(currency)
        ) do
      {blueprint, deployment, host}
    end
  end

  defp ok!({:ok, value}), do: value

  defp intersect_ack(blueprint, deployment, host) do
    BoundsAlgebra.intersect(%Sources{
      blueprint: blueprint,
      deployment: deployment,
      host: host,
      protected_clamp: :acknowledge
    })
  end

  defp value_of(set, name) do
    {:ok, bound} = BoundSet.fetch(set, name)
    bound.value
  end

  defp with_cost(set, cost) do
    {:ok, map} = BoundSet.to_map(set)
    {:ok, updated} = BoundSet.new(Map.put(map, :max_cost, cost))
    updated
  end

  # ---- the universal non-widening law ----------------------------------------

  property "effective never widens any source — widens? is false against all three" do
    check all({bp, dep, host} <- triple()) do
      {:ok, result} = intersect_ack(bp, dep, host)

      refute BoundsAlgebra.widens?(result.effective, host)
      refute BoundsAlgebra.widens?(result.effective, dep)
      refute BoundsAlgebra.widens?(result.effective, bp)
    end
  end

  # ---- the algebra laws -----------------------------------------------------

  property "idempotent: re-intersecting the effective as all three sources is a fixpoint" do
    check all({bp, dep, host} <- triple()) do
      {:ok, result} = intersect_ack(bp, dep, host)
      {:ok, again} = intersect_ack(result.effective, result.effective, result.effective)

      assert again.effective == result.effective
      assert again.clamps == []
    end
  end

  property "commutative: the effective value is invariant under source permutation" do
    check all({bp, dep, host} <- triple()) do
      {:ok, result} = intersect_ack(bp, dep, host)

      for perm <- [
            {dep, bp, host},
            {host, dep, bp},
            {bp, host, dep},
            {dep, host, bp},
            {host, bp, dep}
          ] do
        {a, b, c} = perm
        {:ok, other} = intersect_ack(a, b, c)
        assert other.effective == result.effective
      end
    end
  end

  property "associative through the pinned fold encoding; the mismatch deny is order-free" do
    check all({a, b, c} <- triple()) do
      left = fold_meet(fold_meet(a, b), c)
      right = fold_meet(a, fold_meet(b, c))
      {:ok, direct} = intersect_ack(a, b, c)

      assert left == right
      assert left == direct.effective
    end

    # a cross-currency pair denies the triple in every source position
    check all(same <- bound_map("USD")) do
      usd_set = with_cost(same, %{amount: 100, currency: "USD"})
      eur_set = with_cost(same, %{amount: 50, currency: "EUR"})

      for {a, b, c} <- [
            {usd_set, eur_set, same},
            {same, usd_set, eur_set},
            {eur_set, same, usd_set}
          ] do
        assert {:error, _} = intersect_ack(a, b, c)
      end

      assert {:error, _} = intersect_ack(usd_set, eur_set, eur_set)
      assert {:ok, _} = intersect_ack(usd_set, same, same)
    end
  end

  # ---- clamp emission -------------------------------------------------------

  property "a clamp is emitted iff effective differs from requested; protected clamps carry acknowledged: true" do
    check all({bp, dep, host} <- triple()) do
      {:ok, result} = intersect_ack(bp, dep, host)

      for name <- BoundSet.names() do
        {:ok, %{class: class}} = BoundSet.fetch(result.effective, name)
        clamp = Enum.find(result.clamps, &(&1.field == name))
        differs = value_of(result.effective, name) != value_of(bp, name)

        assert clamp != nil == differs

        if differs do
          assert clamp.acknowledged == (class == :protected)
          assert clamp.requested == value_of(bp, name)
          assert clamp.effective == value_of(result.effective, name)
        end
      end
    end
  end

  # ---- narrower/2 totality per lattice --------------------------------------

  property "Bound.narrower/2 is function-total on every lattice and direction-true per family" do
    lattices = %{
      classification_ceiling: @classification,
      authority_trait: @authority,
      approval_trait: @approval,
      effect_impact_ceiling: @impact,
      disclosure_ceiling: @disclosure
    }

    for {name, lattice} <- lattices do
      check all(i <- integer(0..(length(lattice) - 1)), j <- integer(0..(length(lattice) - 1))) do
        a = ordinal_bound(name, Enum.at(lattice, i))
        b = ordinal_bound(name, Enum.at(lattice, j))
        assert is_boolean(Bound.narrower(a, b))

        cond do
          i == j -> refute Bound.narrower(a, b)
          name in @obligation_families -> assert Bound.narrower(a, b) == i > j
          name in @scope_families -> assert Bound.narrower(a, b) == i < j
        end
      end
    end
  end

  property "classification narrows only in the product order — ordinal AND marker retention" do
    check all(
            lo <- member_of(@classification),
            hi <- member_of(@classification -- [lo]),
            a_markers <- marker_set(),
            b_markers <- marker_set()
          ) do
      lo_bound = bound_of(:classification_ceiling, lo, a_markers)
      hi_bound = bound_of(:classification_ceiling, hi, b_markers)

      # narrower(a, b) = a below on the ordinal AND a retains every marker
      # b carries (strict superset at equal ordinals) — the ordinal retention
      # rule; a dropped marker disqualifies narrowing at ANY ordinal
      retains = MapSet.subset?(b_markers, a_markers)
      expected = index_of(lo) < index_of(hi) and retains
      assert Bound.narrower(lo_bound, hi_bound) == expected

      same_a = bound_of(:classification_ceiling, lo, a_markers)
      same_b = bound_of(:classification_ceiling, lo, b_markers)

      strict_superset = MapSet.subset?(b_markers, a_markers) and a_markers != b_markers
      assert Bound.narrower(same_a, same_b) == strict_superset
    end
  end

  # ---- the marker-union law (the pci-dropped mutation's target) -------------

  property "effective classification markers are the union of the three sources' markers" do
    check all({bp, dep, host} <- triple()) do
      {:ok, result} = intersect_ack(bp, dep, host)

      union =
        [bp, dep, host]
        |> Enum.map(&value_of(&1, :classification_ceiling))
        |> Enum.map(& &1.markers)
        |> Enum.reduce(MapSet.new(), &MapSet.union/2)

      assert MapSet.equal?(value_of(result.effective, :classification_ceiling).markers, union)
    end
  end

  # ---- max_cost ------------------------------------------------------------

  property "within one currency the effective cost is the minimum amount and keeps the currency" do
    check all({bp, dep, host} <- triple("USD")) do
      {:ok, result} = intersect_ack(bp, dep, host)

      amounts =
        [bp, dep, host] |> Enum.map(&value_of(&1, :max_cost)) |> Enum.map(& &1.amount)

      assert value_of(result.effective, :max_cost) == %{
               amount: Enum.min(amounts),
               currency: "USD"
             }
    end
  end

  # ---- helpers --------------------------------------------------------------

  defp fold_meet(a, b) do
    {:ok, result} = intersect_ack(a, b, b)
    result.effective
  end

  defp bound_of(:classification_ceiling, ordinal, markers) do
    %Bound{
      name: :classification_ceiling,
      class: :protected,
      unit: :ordinal,
      value: %{ordinal: ordinal, markers: markers}
    }
  end

  defp bound_of(name, ordinal) do
    %Bound{name: name, class: :protected, unit: :ordinal, value: ordinal}
  end

  defp ordinal_bound(:classification_ceiling, ordinal),
    do: bound_of(:classification_ceiling, ordinal, MapSet.new([]))

  defp ordinal_bound(name, ordinal), do: bound_of(name, ordinal)

  defp index_of(ordinal), do: Enum.find_index(@classification, &(&1 == ordinal))
end
