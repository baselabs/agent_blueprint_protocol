defmodule AgentBlueprintProtocol.BoundsAlgebraTest do
  @moduledoc """
  The bounds algebra (re-derived 2026-08-22): the 13-bound vocabulary's
  pointwise narrowest intersection over Blueprint/Deployment/host sources,
  the two clamp postures (deny-default, acknowledge-always-evidence), the
  per-family direction law, the marker-union rule, and the artifact lifters.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{
    Blueprint,
    BlueprintFixture,
    BoundsAlgebra,
    Deployment,
    DeploymentFixture,
    Error
  }

  alias BoundsAlgebra.{Bound, BoundSet, ClampEvidence, Result, Sources}

  import BlueprintFixture, only: [base_members: 1, capability: 1, port: 2]

  @base %{
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

  defp set(overrides \\ []) do
    {:ok, set} = BoundSet.new(Map.merge(@base, Map.new(overrides)))
    set
  end

  defp sources(opts \\ []) do
    %Sources{
      blueprint: Keyword.get(opts, :blueprint, set([])),
      deployment: Keyword.get(opts, :deployment, set([])),
      host: Keyword.get(opts, :host, set([]))
    }
    |> Map.put(:protected_clamp, Keyword.get(opts, :protected_clamp, :deny))
  end

  defp value(%Result{} = result, name) do
    {:ok, bound} = BoundSet.fetch(result.effective, name)
    bound.value
  end

  defp clamp_for(%Result{} = result, name),
    do: Enum.find(result.clamps, &(&1.field == name))

  # ---- green baseline ------------------------------------------------------

  test "a triple with no narrowing intersects green with no clamps" do
    assert {:ok, %Result{clamps: []}} = BoundsAlgebra.intersect(sources([]))
  end

  # ---- operational clamps --------------------------------------------------

  test "operational narrowing emits unacknowledged clamp evidence naming the field, values, and source" do
    assert {:ok, %Result{} = result} =
             BoundsAlgebra.intersect(sources(blueprint: set(max_tokens: 200_000)))

    assert %ClampEvidence{
             field: :max_tokens,
             class: :operational,
             unit: :token,
             requested: 200_000,
             effective: 100_000,
             source: :host,
             acknowledged: false
           } = clamp_for(result, :max_tokens)

    assert value(result, :max_tokens) == 100_000
  end

  test "attribution names the deployment when its value is the effective; a tie attributes :host" do
    assert {:ok, result} =
             BoundsAlgebra.intersect(
               sources(
                 blueprint: set(max_tokens: 100),
                 deployment: set(max_tokens: 50),
                 host: set(max_tokens: 200)
               )
             )

    assert %{source: :deployment} = clamp_for(result, :max_tokens)

    assert {:ok, tied} =
             BoundsAlgebra.intersect(
               sources(
                 blueprint: set(max_tokens: 100),
                 deployment: set(max_tokens: 50),
                 host: set(max_tokens: 50)
               )
             )

    assert %{source: :host} = clamp_for(tied, :max_tokens)
  end

  # ---- tripwire 2: protected deny carries the triple ------------------------

  test "a protected narrowing under the default posture denies carrying field/requested/effective" do
    denied = BoundsAlgebra.intersect(sources(blueprint: set(disclosure_ceiling: :detail)))

    assert {:error,
            %Error{
              code: :protected_bound_clamp_denied,
              subject: ["disclosure_ceiling"],
              detail: %ClampEvidence{
                field: :disclosure_ceiling,
                class: :protected,
                unit: :ordinal,
                requested: :detail,
                effective: :summary,
                acknowledged: false
              }
            }} = denied
  end

  # ---- tripwires 3a/3b: acknowledge posture, no silent path -----------------

  test "under :acknowledge the same narrowing clamps with acknowledged: true — no silent path" do
    assert {:ok, %Result{} = result} =
             BoundsAlgebra.intersect(
               sources(blueprint: set(disclosure_ceiling: :detail), protected_clamp: :acknowledge)
             )

    assert %ClampEvidence{acknowledged: true, requested: :detail, effective: :summary} =
             clamp_for(result, :disclosure_ceiling)

    # under :deny the same narrowing NEVER clamps — it denies (both directions)
    assert {:error, %Error{code: :protected_bound_clamp_denied}} =
             BoundsAlgebra.intersect(sources(blueprint: set(disclosure_ceiling: :detail)))
  end

  test "a marker-bearing host narrows the markerless lifted baseline (the deny-storm case)" do
    marker_host = set(classification_ceiling: %{ordinal: :internal, markers: MapSet.new([:pci])})

    assert {:error, %Error{code: :protected_bound_clamp_denied, detail: detail}} =
             BoundsAlgebra.intersect(sources(host: marker_host))

    assert %{field: :classification_ceiling, requested: %{ordinal: :internal, markers: empty}} =
             detail

    assert MapSet.size(empty) == 0

    assert {:ok, %Result{} = acknowledged} =
             BoundsAlgebra.intersect(sources(host: marker_host, protected_clamp: :acknowledge))

    assert %ClampEvidence{acknowledged: true, effective: %{markers: pci}} =
             clamp_for(acknowledged, :classification_ceiling)

    assert MapSet.equal?(pci, MapSet.new([:pci]))
  end

  # ---- tripwire 5: max_cost within one currency -----------------------------

  test "max_cost compares within one currency only; a cross-currency pair denies" do
    assert {:ok, result} =
             BoundsAlgebra.intersect(
               sources(
                 blueprint: set(max_cost: %{amount: 100, currency: "USD"}),
                 deployment: set(max_cost: %{amount: 50, currency: "USD"}),
                 host: set(max_cost: %{amount: 100, currency: "USD"})
               )
             )

    assert %{amount: 50, currency: "USD"} = value(result, :max_cost)
    assert %{source: :deployment} = clamp_for(result, :max_cost)

    for {bp, dep} <- [
          {%{amount: 100, currency: "USD"}, %{amount: 50, currency: "EUR"}},
          {%{amount: 100, currency: "EUR"}, %{amount: 50, currency: "USD"}}
        ] do
      assert {:error, %Error{code: :bound_unit_mismatch, detail: nil}} =
               BoundsAlgebra.intersect(
                 sources(blueprint: set(max_cost: bp), deployment: set(max_cost: dep))
               )
    end
  end

  # ---- tripwire 6: totality, by family, with pinned precedence ---------------

  test "a source missing an operational ceiling denies :missing_ceiling; a missing protected bound :bound_source_missing" do
    missing_ceiling = set([]) |> drop(:max_tokens)

    assert {:error, %Error{code: :missing_ceiling, subject: ["max_tokens"]}} =
             BoundsAlgebra.intersect(sources(host: missing_ceiling))

    missing_protected = set([]) |> drop(:disclosure_ceiling)

    assert {:error, %Error{code: :bound_source_missing, subject: ["disclosure_ceiling"]}} =
             BoundsAlgebra.intersect(sources(host: missing_protected))
  end

  test "a source missing members of both families reports the operational miss first; the blueprint source is examined first" do
    both = set([]) |> drop(:max_attempts) |> drop(:approval_trait)

    assert {:error, %Error{code: :missing_ceiling}} =
             BoundsAlgebra.intersect(sources(host: both))

    # blueprint's protected miss fires before deployment's operational miss
    assert {:error, %Error{code: :bound_source_missing}} =
             BoundsAlgebra.intersect(
               sources(
                 blueprint: set([]) |> drop(:approval_trait),
                 deployment: set([]) |> drop(:max_depth)
               )
             )
  end

  # ---- tripwire 7: the obligation-family direction law ----------------------

  test "a stricter host narrows a weaker declared obligation (deny); a wider host never clamps" do
    # empty-capability shape: declared envelope none, host separated
    assert {:error, %Error{code: :protected_bound_clamp_denied, detail: detail}} =
             BoundsAlgebra.intersect(
               sources(host: set(approval_trait: :separated_human_required))
             )

    assert %{field: :approval_trait, requested: :none, effective: :separated_human_required} =
             detail

    # the REVERSE: declared separated, host none — effective stays separated, no clamp
    assert {:ok, %Result{clamps: []}} =
             BoundsAlgebra.intersect(
               sources(
                 blueprint: set(approval_trait: :separated_human_required),
                 host: set(approval_trait: :none)
               )
             )
  end

  # ---- tripwire 8: the struct default is :deny ------------------------------

  test "Sources defaults to the :deny posture (the struct-defaults lesson)" do
    assert %Sources{protected_clamp: :deny} = %Sources{
             blueprint: set([]),
             deployment: set([]),
             host: set([])
           }

    assert {:error, %Error{code: :protected_bound_clamp_denied}} =
             BoundsAlgebra.intersect(%Sources{
               blueprint: set(disclosure_ceiling: :detail),
               deployment: set([]),
               host: set([])
             })
  end

  # ---- tripwire 9: construction validity ------------------------------------

  test "unknown names and off-lattice values deny at construction and again at intersect" do
    assert {:error, %Error{code: :bound_unknown, subject: ["bound_set"]}} =
             BoundSet.new(%{bogus: 1})

    for bad <- [
          %{max_depth: 0},
          %{max_depth: -1},
          %{max_depth: "8"},
          %{max_cost: %{amount: 0, currency: "USD"}},
          %{max_cost: %{amount: 5, currency: "usd"}},
          %{classification_ceiling: %{ordinal: :top_secret, markers: MapSet.new([])}},
          %{classification_ceiling: %{ordinal: :internal, markers: MapSet.new([:hipaa])}},
          %{approval_trait: :maybe},
          %{disclosure_ceiling: :everything}
        ] do
      assert {:error, %Error{code: :bound_value_invalid}} =
               BoundSet.new(Map.merge(@base, bad))
    end

    # a hand-built struct bypassing new/1 is re-checked at intersect
    {:ok, good} = BoundSet.new(@base)
    {:ok, depth} = BoundSet.fetch(good, :max_depth)
    escaped = %BoundSet{bounds: Map.put(good.bounds, :max_depth, %{depth | value: 0})}

    assert {:error, %Error{code: :bound_value_invalid}} =
             BoundsAlgebra.intersect(sources(host: escaped))
  end

  # ---- tripwire 10: the five-site classification envelope -------------------

  test "from_blueprint envelopes the WIDEST classification across all five declaration sites" do
    value =
      base_members(
        classification: "public",
        input_ports: [port("request", classification: "restricted")],
        capabilities: [
          capability(
            classification: "internal",
            approval: "human_required",
            authority: "local_policy"
          )
        ]
      )
      |> replace_member("output_contract", fn _ ->
        {:object,
         [
           {"port", {:string, "result"}},
           {"classification_ceiling", {:string, "confidential"}}
         ]}
      end)
      |> BlueprintFixture.with_digest()

    {:ok, blueprint} = Blueprint.from_value(value)
    {:ok, lifted} = BoundsAlgebra.from_blueprint(blueprint)

    assert {:ok, %{value: %{ordinal: :restricted}}} =
             BoundSet.fetch(lifted, :classification_ceiling)

    assert {:ok, %{value: :human_required}} = BoundSet.fetch(lifted, :approval_trait)
    assert {:ok, %{value: :local_policy}} = BoundSet.fetch(lifted, :authority_trait)

    # the understatement hole is closed: a host at internal now DENIES against
    # the artifact's own restricted declaration instead of passing silently
    assert {:error, %Error{code: :protected_bound_clamp_denied, detail: detail}} =
             BoundsAlgebra.intersect(sources(blueprint: lifted))

    assert %{requested: %{ordinal: :restricted}, effective: %{ordinal: :internal}} = detail
  end

  # ---- lifters --------------------------------------------------------------

  test "from_blueprint derives all thirteen; empty capability and effect arrays envelope the bottoms" do
    {:ok, blueprint} = Blueprint.from_value(BlueprintFixture.fixture_value([]))
    {:ok, lifted} = BoundsAlgebra.from_blueprint(blueprint)

    for name <- BoundSet.names() do
      assert {:ok, %Bound{}} = BoundSet.fetch(lifted, name)
    end

    assert {:ok, %{value: %{ordinal: :internal}}} =
             BoundSet.fetch(lifted, :classification_ceiling)

    assert {:ok, %{value: :full}} = BoundSet.fetch(lifted, :disclosure_ceiling)
    assert {:ok, %{value: :ordinary}} = BoundSet.fetch(lifted, :effect_impact_ceiling)

    empty =
      BlueprintFixture.fixture_value(capabilities: [], effects: [])
      |> Blueprint.from_value()
      |> then(&elem(&1, 1))

    assert {:ok, empty_lifted} = BoundsAlgebra.from_blueprint(empty)

    assert {:ok, %{value: :none}} = BoundSet.fetch(empty_lifted, :approval_trait)
    assert {:ok, %{value: :none}} = BoundSet.fetch(empty_lifted, :authority_trait)
    assert {:ok, %{value: :ordinary}} = BoundSet.fetch(empty_lifted, :effect_impact_ceiling)
    assert {:ok, %{value: :full}} = BoundSet.fetch(empty_lifted, :disclosure_ceiling)
  end

  test "from_deployment lifts host_bounds; a decoded Deployment is total" do
    {:ok, deployment} =
      DeploymentFixture.fixture_bytes([])
      |> Deployment.decode()

    assert {:ok, lifted} = BoundsAlgebra.from_deployment(deployment)

    assert {:ok, %{value: :summary}} = BoundSet.fetch(lifted, :disclosure_ceiling)

    assert {:ok, %{value: %{amount: 1000, currency: "USD"}}} =
             BoundSet.fetch(lifted, :max_cost)

    for name <- BoundSet.names() do
      assert {:ok, %Bound{}} = BoundSet.fetch(lifted, name)
    end
  end

  # ---- widens? and Bound.narrower/2 ----------------------------------------

  test "widens? reports a wider effective set and stays fail-closed on incomparable money" do
    wider =
      set(
        max_tokens: 200_000,
        classification_ceiling: %{ordinal: :restricted, markers: MapSet.new([])}
      )

    narrow =
      set(
        max_tokens: 100_000,
        classification_ceiling: %{ordinal: :internal, markers: MapSet.new([])}
      )

    assert BoundsAlgebra.widens?(wider, narrow)
    refute BoundsAlgebra.widens?(narrow, wider)
    refute BoundsAlgebra.widens?(narrow, narrow)

    usd = set(max_cost: %{amount: 100, currency: "USD"})
    eur = set(max_cost: %{amount: 50, currency: "EUR"})

    # incomparable currencies cannot be proven non-widening — fail closed
    assert BoundsAlgebra.widens?(usd, eur)
  end

  test "the classification product order — a dropped marker widens at ANY ordinal" do
    # narrower under the product order requires BOTH the ordinal AND marker
    # retention: {internal, {pci}} is not narrower than {restricted, {pci,phi}}
    # (it drops phi — obligations are not tradeable against scope)
    a = bound(:classification_ceiling, %{ordinal: :internal, markers: MapSet.new([:pci])})
    b = bound(:classification_ceiling, %{ordinal: :restricted, markers: MapSet.new([:pci, :phi])})
    refute Bound.narrower(a, b)

    # at set level on FULL sets, the PRODUCT order (review-round fold): each
    # drops an obligation the other retains — mutually widening, fail-closed
    a_set = set(classification_ceiling: %{ordinal: :internal, markers: MapSet.new([:pci])})

    b_set =
      set(classification_ceiling: %{ordinal: :restricted, markers: MapSet.new([:pci, :phi])})

    assert BoundsAlgebra.widens?(a_set, b_set)
    assert BoundsAlgebra.widens?(b_set, a_set)

    # retaining every obligation while narrowing the ordinal is not widening
    c_set =
      set(classification_ceiling: %{ordinal: :internal, markers: MapSet.new([:pci, :phi])})

    refute BoundsAlgebra.widens?(c_set, b_set)

    assert Bound.narrower(
             bound(:classification_ceiling, %{
               ordinal: :internal,
               markers: MapSet.new([:pci, :phi])
             }),
             b
           )

    # equal ordinals: the marker strict subset is the widening
    same_a = set(classification_ceiling: %{ordinal: :internal, markers: MapSet.new([:pci])})
    same_b = set(classification_ceiling: %{ordinal: :internal, markers: MapSet.new([])})

    assert BoundsAlgebra.widens?(same_b, same_a)
    refute BoundsAlgebra.widens?(same_a, same_b)

    assert Bound.narrower(
             bound(:classification_ceiling, %{ordinal: :internal, markers: MapSet.new([:pci])}),
             bound(:classification_ceiling, %{ordinal: :internal, markers: MapSet.new([])})
           )
  end

  test "Bound.narrower/2 encodes the direction per family and never raises across names" do
    assert Bound.narrower(
             bound(:approval_trait, :separated_human_required),
             bound(:approval_trait, :none)
           )

    refute Bound.narrower(
             bound(:approval_trait, :none),
             bound(:approval_trait, :separated_human_required)
           )

    assert Bound.narrower(
             bound(:classification_ceiling, %{ordinal: :public, markers: MapSet.new([])}),
             bound(:classification_ceiling, %{ordinal: :internal, markers: MapSet.new([])})
           )

    assert Bound.narrower(bound(:disclosure_ceiling, :none), bound(:disclosure_ceiling, :full))
    assert Bound.narrower(bound(:max_depth, 4), bound(:max_depth, 8))
    refute Bound.narrower(bound(:max_depth, 8), bound(:max_depth, 4))

    # cross-name comparison is not a lattice question — false, never a raise
    refute Bound.narrower(bound(:max_depth, 4), bound(:max_tokens, 2))
  end

  # ---- hardened-rim regressions (2026-08-22) -----------------------------------

  test "construction never raises on hostile keys and never echoes them" do
    # non-String.Chars keys previously RAISED (ArgumentError/Protocol.UndefinedError)
    for key <- [[:a], {:x, :y}, %{}, 999, "café-\u{1f48a}"] do
      assert {:error, %Error{code: :bound_unknown, subject: ["bound_set"]}} =
               BoundSet.new(%{key => 1})
    end

    # the subject is the containing surface, never the unknown name (the vocabulary
    # unknown_member pattern — an attacker string must not ride the channel)
    assert {:error, %Error{code: :bound_unknown, subject: ["bound_set"]}} =
             BoundSet.new(%{"<script>alert(1)</script>" => 1})
  end

  test "plain-map markers deny typed at construction and inside forged structs" do
    hostile = %{ordinal: :internal, markers: %{pci: true}}

    assert {:error, %Error{code: :bound_value_invalid}} =
             BoundSet.new(Map.merge(@base, %{classification_ceiling: hostile}))

    # the same value through a struct bypassing new/1: intersect DENIES, never raises
    {:ok, good} = BoundSet.new(@base)
    {:ok, bound} = BoundSet.fetch(good, :classification_ceiling)

    forged = %BoundSet{
      bounds: Map.put(good.bounds, :classification_ceiling, %{bound | value: hostile})
    }

    assert {:error, %Error{code: :bound_value_invalid}} =
             BoundsAlgebra.intersect(sources(host: forged))
  end

  test "a forged set carrying EXTRA names denies :bound_unknown at intersect" do
    {:ok, good} = BoundSet.new(@base)

    smuggled = %BoundSet{
      bounds:
        Map.put(good.bounds, :smuggled, %Bound{
          name: :smuggled,
          class: :operational,
          unit: :count,
          value: 1
        })
    }

    assert {:error, %Error{code: :bound_unknown, subject: ["bound_set"]}} =
             BoundsAlgebra.intersect(sources(host: smuggled))
  end

  test "the lifters never raise on malformed hand-built artifacts" do
    # malformed SHAPES read as absent (a typed error or a partial lift —
    # total, never a raise)
    for value <- [
          {:object, [{"input_ports", {:array, [{:object, "junk"}]}}]},
          {:object, [{"output_contract", {:object, "junk"}}]},
          {:object, [{"ceilings", {:string, "junk"}}]}
        ] do
      result = BoundsAlgebra.from_blueprint(%Blueprint{value: value})

      assert match?({:ok, %BoundSet{}}, result) or match?({:error, %Error{}}, result)
    end

    # off-lattice VALUES deny typed (the error constructor itself was the
    # crash site — to_string on a lattice list)
    for value <- [
          {:object, [{"classification_ceiling", {:string, "top_secret"}}]},
          {:object,
           [
             {"capability_requirements",
              {:array,
               [
                 {:object,
                  [
                    {"operation_family", {:string, "f"}},
                    {"approval_trait", {:string, "yolo"}} | []
                  ]}
               ]}}
           ]}
        ] do
      assert {:error, %Error{}} = BoundsAlgebra.from_blueprint(%Blueprint{value: value})
    end

    extra = [{"smuggled", {:integer, 1}} | dup_free_members()]
    duplicated = dup_free_members() ++ [List.first(dup_free_members())]

    for value <- [
          {:object, [{"host_bounds", {:object, extra}}]},
          {:object, [{"host_bounds", {:object, duplicated}}]}
        ] do
      assert {:error, %Error{}} = BoundsAlgebra.from_deployment(%Deployment{value: value})
    end
  end

  test "bound values above the documented integer magnitude deny" do
    assert {:error, %Error{code: :bound_value_invalid}} =
             BoundSet.new(Map.merge(@base, %{max_depth: 9_007_199_254_740_992}))

    assert {:ok, _} = BoundSet.new(Map.merge(@base, %{max_depth: 9_007_199_254_740_991}))
  end

  test "widens? and narrower/2 never raise on junk values (total predicates)" do
    junk_depth = %Bound{name: :max_depth, class: :operational, unit: :count, value: :weird}
    junk_str = %Bound{name: :max_depth, class: :operational, unit: :count, value: "8"}
    refute Bound.narrower(junk_depth, junk_str)

    {:ok, good} = BoundSet.new(@base)
    {:ok, cls} = BoundSet.fetch(good, :classification_ceiling)

    forged = %BoundSet{
      bounds:
        Map.put(good.bounds, :classification_ceiling, %{
          cls
          | value: %{ordinal: :internal, markers: %{}}
        })
    }

    # non-MapSet markers cannot be proven non-widening — fail closed, no raise
    assert BoundsAlgebra.widens?(forged, good)
  end

  # ---- the deny-typed rim, clause by clause (the rim's coverage debt) ------

  test "BoundSet.new/1 and fetch/2 deny typed on non-map input and absent names" do
    for junk <- [:junk, "map", nil, [{:max_depth, 8}]] do
      assert {:error, %Error{code: :invalid_type, subject: ["bound_set"]}} = BoundSet.new(junk)
    end

    {:ok, empty} = BoundSet.new(%{})

    assert :error = BoundSet.fetch(empty, :max_depth)
    assert :error = BoundSet.fetch(:junk, :max_depth)
    # fetch on a struct-forged set is already fail-closed (the is_map_key
    # guard's exception fails the guard, falling to the catch-all)
    assert :error = BoundSet.fetch(%BoundSet{}, :max_depth)

    # to_map/1 denies typed on forged shapes (the widens? guard-family sibling)
    assert {:error, %Error{code: :invalid_type, subject: ["bound_set"]}} =
             BoundSet.to_map(%BoundSet{})

    assert {:error, %Error{code: :invalid_type, subject: ["bound_set"]}} =
             BoundSet.to_map(:junk)
  end

  test "a cost bound of the wrong SHAPE denies :bound_value_invalid at construction" do
    for bad <- ["USD", %{amount: 1}, {1, "USD"}, 1000] do
      assert {:error, %Error{code: :bound_value_invalid, subject: ["max_cost"]}} =
               BoundSet.new(Map.merge(@base, %{max_cost: bad}))
    end
  end

  test "intersect/1 denies typed on a non-Sources argument, a junk posture, and a non-set source" do
    assert {:error, %Error{code: :invalid_type, subject: ["sources"]}} =
             BoundsAlgebra.intersect(:junk)

    assert {:error, %Error{code: :invalid_type, subject: ["sources"]}} =
             BoundsAlgebra.intersect(%{blueprint: set([])})

    assert {:error, %Error{code: :invalid_constraint, subject: ["protected_clamp"]}} =
             BoundsAlgebra.intersect(Map.put(sources([]), :protected_clamp, :bogus))

    for junk <- [:junk, %{}, %BoundSet{}] do
      assert {:error, %Error{code: :invalid_type, subject: ["blueprint"]}} =
               BoundsAlgebra.intersect(sources(blueprint: junk))
    end
  end

  test "widens?/2 fails closed on partial sets, non-set arguments, and forged values of every family" do
    {:ok, good} = BoundSet.new(@base)
    {:ok, partial} = BoundSet.new(%{max_depth: 5})

    assert BoundsAlgebra.widens?(partial, good)
    assert BoundsAlgebra.widens?(good, partial)
    assert BoundsAlgebra.widens?(:junk, good)
    assert BoundsAlgebra.widens?(good, nil)

    # a struct FORGED past the head (bounds not a map) must also fail closed —
    # the %BoundSet{} pattern alone does not establish bounds' type (a
    # forged struct raised BadMapError from either argument position)
    assert BoundsAlgebra.widens?(%BoundSet{bounds: nil}, good)
    assert BoundsAlgebra.widens?(good, %BoundSet{bounds: :junk})

    for {name, forged} <- [
          max_depth: "8",
          max_cost: "USD",
          max_cost: %{amount: "x", currency: "USD"},
          classification_ceiling: %{ordinal: :top_secret, markers: MapSet.new([])},
          classification_ceiling: :internal,
          disclosure_ceiling: :bogus,
          approval_trait: :bogus
        ] do
      assert BoundsAlgebra.widens?(forge(good, name, forged), good),
             "expected fail-closed widening for #{inspect(name)} = #{inspect(forged)}"
    end
  end

  test "Bound.narrower/2 is total and fail-closed on forged names and values of every family" do
    # an unknown name pair (equal names reach narrower_value/3, which has no
    # table entry for it) is false, never a raise
    refute Bound.narrower(forged_bound(:smuggled, 1), forged_bound(:smuggled, 2))

    assert Bound.narrower(
             forged_bound(:max_cost, %{amount: 5, currency: "USD"}),
             forged_bound(:max_cost, %{amount: 10, currency: "USD"})
           )

    refute Bound.narrower(
             forged_bound(:max_cost, %{amount: 5, currency: "USD"}),
             forged_bound(:max_cost, %{amount: 10, currency: "EUR"})
           )

    refute Bound.narrower(
             forged_bound(:max_cost, "USD"),
             forged_bound(:max_cost, %{amount: 10, currency: "USD"})
           )

    refute Bound.narrower(
             forged_bound(:classification_ceiling, %{
               ordinal: :top_secret,
               markers: MapSet.new([])
             }),
             forged_bound(:classification_ceiling, %{ordinal: :internal, markers: MapSet.new([])})
           )

    refute Bound.narrower(
             forged_bound(:classification_ceiling, :internal),
             forged_bound(:classification_ceiling, %{ordinal: :internal, markers: MapSet.new([])})
           )

    # equal ordinals with non-MapSet markers: neither the strict-superset nor
    # the subset arm can prove anything — false, never a raise
    refute Bound.narrower(
             forged_bound(:classification_ceiling, %{ordinal: :internal, markers: [:pci]}),
             forged_bound(:classification_ceiling, %{ordinal: :internal, markers: []})
           )

    refute Bound.narrower(
             forged_bound(:disclosure_ceiling, :bogus),
             forged_bound(:disclosure_ceiling, :summary)
           )

    refute Bound.narrower(
             forged_bound(:approval_trait, :bogus),
             forged_bound(:approval_trait, :none)
           )
  end

  test "the lifters deny typed on malformed argument shapes" do
    assert {:error, %Error{code: :invalid_type, subject: ["blueprint"]}} =
             BoundsAlgebra.from_blueprint(:junk)

    assert {:error, %Error{code: :invalid_type, subject: ["blueprint"]}} =
             BoundsAlgebra.from_blueprint(%Blueprint{value: {:array, []}})

    assert {:error, %Error{code: :invalid_type, subject: ["deployment"]}} =
             BoundsAlgebra.from_deployment(:junk)
  end

  test "from_deployment/1 reads a missing host_bounds as an empty lift and a malformed one as typed denial" do
    assert {:ok, %BoundSet{bounds: empty}} =
             BoundsAlgebra.from_deployment(%Deployment{
               value: {:object, [{"model_policy", {:object, []}}]}
             })

    assert empty == %{}

    assert {:error, %Error{code: :invalid_type, subject: ["host_bounds"]}} =
             BoundsAlgebra.from_deployment(%Deployment{
               value: {:object, [{"host_bounds", {:string, "junk"}}]}
             })
  end

  test "host_bounds member values lift, deny typed, or read absent according to shape" do
    # an absent max_cost member lifts nothing — a partial host_bounds is legal
    assert {:ok, lifted} =
             BoundsAlgebra.from_deployment(%Deployment{
               value: host_bounds([{"max_depth", {:integer, 8}}])
             })

    assert {:ok, %{value: 8}} = BoundSet.fetch(lifted, :max_depth)
    assert :error = BoundSet.fetch(lifted, :max_cost)

    # a present-but-malformed max_cost member denies :invalid_type
    assert {:error, %Error{code: :invalid_type, subject: ["max_cost"]}} =
             BoundsAlgebra.from_deployment(%Deployment{
               value: host_bounds([{"max_cost", {:integer, 5}}])
             })

    # a bad numeric VALUE passes the closed-member check, then denies at the
    # bound builder (the error must not be swallowed into a partial lift)
    assert {:error, %Error{code: :bound_value_invalid, subject: ["max_depth"]}} =
             BoundsAlgebra.from_deployment(%Deployment{
               value: host_bounds([{"max_depth", {:integer, 0}}])
             })

    # a protected name carrying an integer member (a string was expected)
    assert {:error, %Error{code: :invalid_type, subject: ["disclosure_ceiling"]}} =
             BoundsAlgebra.from_deployment(%Deployment{
               value: host_bounds([{"disclosure_ceiling", {:integer, 3}}])
             })

    # an off-lattice ordinal string denies :bound_value_invalid
    assert {:error, %Error{code: :bound_value_invalid, subject: ["disclosure_ceiling"]}} =
             BoundsAlgebra.from_deployment(%Deployment{
               value: host_bounds([{"disclosure_ceiling", {:string, "everything"}}])
             })
  end

  test "a ports array carrying non-object entries reads them as absent (never a raise)" do
    value = {:object, [{"input_ports", {:array, [{:string, "junk"}, {:object, []}]}}]}

    assert {:ok, %BoundSet{}} = BoundsAlgebra.from_blueprint(%Blueprint{value: value})
  end

  # ---- helpers --------------------------------------------------------------

  defp dup_free_members do
    [
      {"approval_trait", {:string, "none"}},
      {"authority_trait", {:string, "none"}},
      {"classification_ceiling", {:string, "internal"}},
      {"disclosure_ceiling", {:string, "summary"}},
      {"effect_impact_ceiling", {:string, "ordinary"}},
      {"max_attempts", {:integer, 3}},
      {"max_concurrency", {:integer, 2}},
      {"max_cost", {:object, [{"amount", {:integer, 1000}}, {"currency", {:string, "USD"}}]}},
      {"max_depth", {:integer, 8}},
      {"max_descendants", {:integer, 64}},
      {"max_elapsed_ms", {:integer, 60_000}},
      {"max_fan_out", {:integer, 4}},
      {"max_tokens", {:integer, 100_000}}
    ]
  end

  defp drop(%BoundSet{} = set, name) do
    {:ok, map} = BoundSet.to_map(set)
    {:ok, dropped} = BoundSet.new(Map.delete(map, name))
    dropped
  end

  defp bound(name, value) do
    {:ok, map} = BoundSet.new(Map.merge(@base, %{name => value}))
    {:ok, bound} = BoundSet.fetch(map, name)
    bound
  end

  defp forge(%BoundSet{} = set, name, value) do
    {:ok, bound} = BoundSet.fetch(set, name)
    %BoundSet{bounds: Map.put(set.bounds, name, %{bound | value: value})}
  end

  defp forged_bound(name, value),
    do: %Bound{name: name, class: :operational, unit: :count, value: value}

  defp host_bounds(members), do: {:object, [{"host_bounds", {:object, members}}]}

  defp replace_member(members, name, fun) do
    Enum.map(members, fn
      {^name, value} -> {name, fun.(value)}
      other -> other
    end)
  end
end
