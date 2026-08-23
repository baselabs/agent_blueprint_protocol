defmodule AgentBlueprintProtocol.PredicateTest do
  @moduledoc """
  The closed predicate algebra: grammar shape against declared ports, the
  node ceiling, and `evaluate/2`'s pinned contract (path addressing,
  error-dominant folds, mathematical-value comparisons).
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.Predicate

  @ports ["input", "config"]

  # ---- shape: the grammar -----------------------------------------------------

  test "every operator form validates green against its declared ports" do
    preds = [
      and_apply([leaf("input")]),
      or_leaf(leaf("config")),
      not_leaf(leaf("input")),
      cmp("eq", "input"),
      cmp("ne", "input"),
      cmp("lt", "input"),
      cmp("lte", "input"),
      cmp("gt", "input"),
      cmp("gte", "input"),
      in_pred("config"),
      presence("present", "input"),
      presence("absent", "config")
    ]

    for p <- preds do
      assert :ok = Predicate.validate(p, @ports)
    end
  end

  test "n-ary and/or nest and accept multiple args" do
    p = and_apply([or_leaf(leaf("input")), leaf("config"), not_leaf(leaf("input"))])
    assert :ok = Predicate.validate(p, @ports)
  end

  test "unknown operator denies :predicate_op_unknown (closed op set)" do
    assert {:error, :predicate_op_unknown} =
             Predicate.validate(leaf("input") |> put_op("xor"), @ports)

    assert {:error, :predicate_op_unknown} =
             Predicate.validate(cmp("eq", "input") |> put_op("=~"), @ports)
  end

  test "unknown member inside a predicate node denies :unknown_member" do
    p =
      {:object,
       [{"op", {:string, "and"}}, {"args", {:array, [leaf("input")]}}, {"extra", {:string, "x"}}]}

    assert {:error, :unknown_member} = Predicate.validate(p, @ports)
  end

  test "missing operand member denies :missing_required_field" do
    assert {:error, :missing_required_field} =
             Predicate.validate({:object, [{"op", {:string, "and"}}]}, @ports)

    assert {:error, :missing_required_field} =
             Predicate.validate(
               {:object, [{"op", {:string, "eq"}}, {"path", path("input")}]},
               @ports
             )
  end

  test "and/or with zero args and not with arity != 1 deny :invalid_cardinality" do
    assert {:error, :invalid_cardinality} =
             Predicate.validate(
               {:object, [{"op", {:string, "and"}}, {"args", {:array, []}}]},
               @ports
             )

    assert {:error, :invalid_cardinality} =
             Predicate.validate(not2(leaf("input"), leaf("config")), @ports)
  end

  test "path that is not a non-empty string array denies :invalid_type" do
    for bad <- [
          {:array, []},
          {:array, [{:integer, 0}]},
          {:string, "input"},
          :null
        ] do
      assert {:error, :invalid_type} =
               Predicate.validate(
                 {:object, [{"op", {:string, "eq"}}, {"path", bad}, {"value", {:integer, 1}}]},
                 @ports
               )
    end
  end

  test "path[0] naming no declared port denies :predicate_path_unresolved" do
    assert {:error, :predicate_path_unresolved} =
             Predicate.validate(cmp("eq", "elsewhere"), @ports)
  end

  test "values operand of in must be an array" do
    p = {:object, [{"op", {:string, "in"}}, {"path", path("input")}, {"values", {:string, "x"}}]}
    assert {:error, :invalid_type} = Predicate.validate(p, @ports)
  end

  test "node count over predicate_nodes (256) denies :predicate_nodes_exceeded" do
    # chain(n) is n `not` nodes over one comparison leaf = n + 1 nodes total.
    assert :ok = Predicate.validate(chain(255), @ports)
    assert {:error, :predicate_nodes_exceeded} = Predicate.validate(chain(256), @ports)
  end

  test "total and never-raising on malformed tagged shapes" do
    for bad <- [
          {:object, [{"op", 5}]},
          {:object, "and"},
          {:array, [leaf("input")]},
          {:string, "op"},
          {:integer, 3},
          {:object, [{"args", {:array, []}}, {"op", {:string, "not"}}]},
          {:object, nil}
        ] do
      assert {:error, _} = Predicate.validate(bad, @ports)
    end
  end

  # ---- evaluate ----------------------------------------------------------------

  @ports_value %{
    "input" =>
      {:object,
       [
         {"level", {:integer, 3}},
         {"name", {:string, "alpha"}},
         {"items", {:array, [{:string, "x"}, {:string, "y"}, {:string, "z"}]}},
         {"ratio", {:float, 1.0}},
         {"nested", {:object, [{"flag", {:boolean, true}}]}}
       ]},
    "config" => {:object, [{"mode", {:string, "dry_run"}}]}
  }

  test "eq addresses object members and array indices, compares by mathematical value" do
    assert {:ok, true} =
             Predicate.evaluate(eq_path(["input", "level"], {:integer, 3}), @ports_value)

    assert {:ok, true} =
             Predicate.evaluate(eq_path(["input", "ratio"], {:integer, 1}), @ports_value)

    assert {:ok, false} =
             Predicate.evaluate(eq_path(["input", "level"], {:integer, 4}), @ports_value)

    assert {:ok, true} =
             Predicate.evaluate(eq_path(["input", "items", "1"], {:string, "y"}), @ports_value)

    assert {:ok, true} =
             Predicate.evaluate(
               eq_path(["input", "nested", "flag"], {:boolean, true}),
               @ports_value
             )
  end

  test "ordering operators compare numbers mathematically and strings by byte order" do
    assert {:ok, true} =
             Predicate.evaluate(lt_path(["input", "level"], {:float, 3.5}), @ports_value)

    assert {:ok, true} =
             Predicate.evaluate(gte_path(["input", "level"], {:float, 3.0}), @ports_value)

    assert {:ok, false} =
             Predicate.evaluate(gt_path(["input", "level"], {:float, 3.0}), @ports_value)

    assert {:ok, true} =
             Predicate.evaluate(lt_path(["input", "name"], {:string, "beta"}), @ports_value)
  end

  test "ordering across mismatched kinds denies :predicate_path_unresolved" do
    assert {:error, :predicate_path_unresolved} =
             Predicate.evaluate(lt_path(["input", "level"], {:string, "3"}), @ports_value)

    assert {:error, :predicate_path_unresolved} =
             Predicate.evaluate(lt_path(["input", "name"], {:integer, 3}), @ports_value)
  end

  test "in uses kind-aware mathematical-value membership" do
    p =
      {:object,
       [
         {"op", {:string, "in"}},
         {"path", path_seg(["input", "level"])},
         {"values", {:array, [{:integer, 2}, {:float, 3.0}]}}
       ]}

    assert {:ok, true} = Predicate.evaluate(p, @ports_value)
  end

  test "present/absent treat an unresolvable path as a defined outcome, not an error" do
    assert {:ok, false} =
             Predicate.evaluate(presence("present", "input", ["missing"]), @ports_value)

    assert {:ok, true} =
             Predicate.evaluate(presence("absent", "input", ["missing"]), @ports_value)

    assert {:ok, true} = Predicate.evaluate(presence("present", "input", ["level"]), @ports_value)
    assert {:ok, false} = Predicate.evaluate(presence("absent", "config", ["mode"]), @ports_value)
  end

  test "an unresolvable path on a value operator denies :predicate_path_unresolved" do
    assert {:error, :predicate_path_unresolved} =
             Predicate.evaluate(eq_path(["input", "nope"], {:integer, 1}), @ports_value)

    assert {:error, :predicate_path_unresolved} =
             Predicate.evaluate(eq_path(["nowhere", "x"], {:integer, 1}), @ports_value)

    assert {:error, :predicate_path_unresolved} =
             Predicate.evaluate(eq_path(["input", "items", "9"], {:string, "x"}), @ports_value)
  end

  test "array index segments use canonical decimal form" do
    assert {:error, :predicate_path_unresolved} =
             Predicate.evaluate(eq_path(["input", "items", "01"], {:string, "y"}), @ports_value)

    assert {:error, :predicate_path_unresolved} =
             Predicate.evaluate(eq_path(["input", "items", "x"], {:string, "y"}), @ports_value)
  end

  test "error-dominant folds keep the verdict order-independent" do
    errored = eq_path(["input", "missing"], {:integer, 1})
    true_leaf = eq_path(["input", "level"], {:integer, 3})

    # or(true, error) must be an ERROR, never true — short-circuit-on-value
    # would make the verdict depend on operand order.
    assert {:error, :predicate_path_unresolved} =
             Predicate.evaluate(or_leaf(true_leaf, errored), @ports_value)

    assert {:error, :predicate_path_unresolved} =
             Predicate.evaluate(or_leaf(errored, true_leaf), @ports_value)

    # and(false, error) must be an ERROR, never false.
    false_leaf = eq_path(["input", "level"], {:integer, 4})

    assert {:error, :predicate_path_unresolved} =
             Predicate.evaluate(and2(false_leaf, errored), @ports_value)

    # not(error) is an error.
    assert {:error, :predicate_path_unresolved} =
             Predicate.evaluate(not_leaf(errored), @ports_value)
  end

  test "boolean folds over resolved operands are order-independent" do
    leaves = [
      eq_path(["input", "level"], {:integer, 3}),
      eq_path(["config", "mode"], {:string, "dry_run"}),
      eq_path(["input", "name"], {:string, "alpha"})
    ]

    for perm <- permutations(leaves) do
      assert {:ok, true} = Predicate.evaluate(and_apply(perm), @ports_value)
    end
  end

  test "evaluate on a shape-invalid predicate denies, never raises" do
    for bad <- [{:object, [{"op", {:string, "eq"}}]}, {:array, []}, {:string, "x"}, 5, :null] do
      assert {:error, _} = Predicate.evaluate(bad, @ports_value)
    end
  end

  # ---- hardened rims ---------------------------------------------------------

  test "malformed member lists deny :invalid_type, never raise" do
    assert {:error, :invalid_type} = Predicate.validate({:object, [:bad]}, @ports)
    assert {:error, :invalid_type} = Predicate.validate({:object, [5]}, @ports)
    # A non-binary member NAME (tuple element) hits the invalid_type branch.
    assert {:error, :invalid_type} =
             Predicate.validate({:object, [{5, {:string, "and"}}]}, @ports)
  end

  test "review F8: a missing root port is a defined outcome for present/absent" do
    absent = {:object, [{"op", {:string, "absent"}}, {"path", path("nowhere")}]}
    present = {:object, [{"op", {:string, "present"}}, {"path", path("nowhere")}]}

    eq =
      {:object, [{"op", {:string, "eq"}}, {"path", path("nowhere")}, {"value", {:integer, 1}}]}

    assert {:ok, true} = Predicate.evaluate(absent, @ports_value)
    assert {:ok, false} = Predicate.evaluate(present, @ports_value)
    assert {:error, :predicate_path_unresolved} = Predicate.evaluate(eq, @ports_value)
  end

  # ---- helpers -----------------------------------------------------------------

  defp leaf(port), do: cmp("eq", port)

  defp put_op({:object, members}, op) do
    {:object, List.keyreplace(members, "op", 0, {"op", {:string, op}})}
  end

  defp path(port), do: path_seg([port])
  defp path_seg(segs), do: {:array, Enum.map(segs, &{:string, &1})}

  defp cmp(op, port),
    do: {:object, [{"op", {:string, op}}, {"path", path(port)}, {"value", {:integer, 1}}]}

  defp in_pred(port),
    do:
      {:object,
       [{"op", {:string, "in"}}, {"path", path(port)}, {"values", {:array, [{:integer, 1}]}}]}

  defp and2(a, b), do: and_apply([a, b])
  defp and_apply(args), do: {:object, [{"op", {:string, "and"}}, {"args", {:array, args}}]}
  defp or_leaf(a), do: or_leaf(a, a)
  defp or_leaf(a, b), do: {:object, [{"op", {:string, "or"}}, {"args", {:array, [a, b]}}]}
  defp not_leaf(a), do: {:object, [{"op", {:string, "not"}}, {"args", {:array, [a]}}]}
  defp not2(a, b), do: {:object, [{"op", {:string, "not"}}, {"args", {:array, [a, b]}}]}

  defp eq_path(segs, value),
    do: {:object, [{"op", {:string, "eq"}}, {"path", path_seg(segs)}, {"value", value}]}

  defp lt_path(segs, value),
    do: {:object, [{"op", {:string, "lt"}}, {"path", path_seg(segs)}, {"value", value}]}

  defp lte_path(segs, value),
    do: {:object, [{"op", {:string, "lte"}}, {"path", path_seg(segs)}, {"value", value}]}

  defp gte_path(segs, value),
    do: {:object, [{"op", {:string, "gte"}}, {"path", path_seg(segs)}, {"value", value}]}

  defp gt_path(segs, value),
    do: {:object, [{"op", {:string, "gt"}}, {"path", path_seg(segs)}, {"value", value}]}

  defp presence(op, port), do: presence(op, port, [])

  defp presence(op, port, rest),
    do: {:object, [{"op", {:string, op}}, {"path", path_seg([port | rest])}]}

  # chain(n): n nested not-nodes over one leaf = n + 1 nodes.
  defp chain(1), do: not_leaf(leaf("input"))

  defp chain(n) when n > 1,
    do: {:object, [{"op", {:string, "not"}}, {"args", {:array, [chain(n - 1)]}}]}

  defp permutations([]), do: [[]]

  defp permutations(list) do
    for x <- list, rest <- permutations(list -- [x]), do: [x | rest]
  end

  # ---- branch sweep: live fallback clauses ------------------------------------------

  test "sweep: validate/2 non-list ports and evaluate/2 non-map ports deny" do
    assert {:error, :invalid_type} = Predicate.validate(leaf("input"), :ports)
    assert {:error, :invalid_type} = Predicate.evaluate(leaf("input"), [:ports])
  end

  test "sweep: malformed operand members hit their class fallbacks" do
    # op present but nil-value member shape (op_of's nil clause is the
    # missing case; a non-tuple op value hits invalid_type)
    assert {:error, :invalid_type} =
             Predicate.validate(
               {:object, [{"op", 5}, {"args", {:array, [leaf("input")]}}]},
               @ports
             )

    # non-binary member name
    assert {:error, :invalid_type} =
             Predicate.validate(
               {:object,
                [{5, nil}, {"op", {:string, "and"}}, {"args", {:array, [leaf("input")]}}]},
               @ports
             )

    # args not an array
    assert {:error, :invalid_type} =
             Predicate.validate(
               {:object, [{"op", {:string, "and"}}, {"args", 5}]},
               @ports
             )

    # values operand with a malformed element
    bad_values =
      {:object,
       [{"op", {:string, "in"}}, {"path", path("input")}, {"values", {:array, [{:integer, 1.5}]}}]}

    assert {:error, :invalid_type} = Predicate.validate(bad_values, @ports)

    # well_formed? misses: object with non-binary member name, non-list array
    assert {:error, :invalid_type} =
             Predicate.validate(
               {:object,
                [
                  {"op", {:string, "in"}},
                  {"path", path("input")},
                  {"values", {:array, [{:object, [{5, :null}]}]}}
                ]},
               @ports
             )
  end

  test "sweep: missing op member and rich in-values hit their branches" do
    # op absent entirely: op_of's nil clause (checked before anything else).
    assert {:error, :missing_required_field} =
             Predicate.validate({:object, [{"args", {:array, [leaf("input")]}}]}, @ports)

    # every tagged kind inside in-values exercises well_formed?'s positives.
    rich =
      {:object,
       [
         {"op", {:string, "in"}},
         {"path", path("input")},
         {"values",
          {:array,
           [
             :null,
             {:boolean, true},
             {:string, "s"},
             {:array, [{:float, 1.5}]},
             {:object, [{"k", {:integer, 2}}]}
           ]}}
       ]}

    assert :ok = Predicate.validate(rich, @ports)

    # a junk term inside values denies via well_formed?'s fallback.
    junk =
      {:object, [{"op", {:string, "in"}}, {"path", path("input")}, {"values", {:array, [5]}}]}

    assert {:error, :invalid_type} = Predicate.validate(junk, @ports)
  end

  test "sweep: not-fold, numeric orderings across tags, scalar descent, in on an unresolvable path" do
    assert {:ok, false} =
             Predicate.evaluate(
               not_leaf(eq_path(["input", "level"], {:integer, 3})),
               @ports_value
             )

    assert {:ok, true} =
             Predicate.evaluate(lt_path(["input", "items", "0"], {:string, "y"}), @ports_value)

    # int vs int, int vs float, float vs int, and the lte/gte edges.
    assert {:ok, true} =
             Predicate.evaluate(lt_path(["input", "level"], {:integer, 4}), @ports_value)

    assert {:ok, true} =
             Predicate.evaluate(lt_path(["input", "level"], {:float, 3.5}), @ports_value)

    assert {:ok, true} =
             Predicate.evaluate(lt_path(["input", "ratio"], {:integer, 2}), @ports_value)

    assert {:ok, true} =
             Predicate.evaluate(lt_path(["input", "ratio"], {:float, 2.0}), @ports_value)

    assert {:ok, true} =
             Predicate.evaluate(lte_path(["input", "level"], {:integer, 3}), @ports_value)

    # a path descending INTO a scalar denies unresolved.
    assert {:error, :predicate_path_unresolved} =
             Predicate.evaluate(
               eq_path(["input", "level", "deeper"], {:integer, 1}),
               @ports_value
             )

    in_bad =
      {:object,
       [
         {"op", {:string, "in"}},
         {"path", path_seg(["input", "missing"])},
         {"values", {:array, [{:integer, 1}]}}
       ]}

    assert {:error, :predicate_path_unresolved} = Predicate.evaluate(in_bad, @ports_value)
  end
end
