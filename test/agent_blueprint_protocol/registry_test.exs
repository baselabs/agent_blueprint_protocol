defmodule AgentBlueprintProtocol.RegistryTest do
  @moduledoc """
  The generic field-registry engine: closed-world walk, tag-strict kinds,
  cardinality, cross-field hooks, and the pinned failure precedence — proven
  on a SYNTHETIC table (the reuse invariant: the engine is
  table-parameterized, not Blueprint-shaped).
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.Registry

  defp toy_table do
    [
      %{
        name: "kind",
        required: true,
        kind: {:enum, MapSet.new(["alpha", "beta"])}
      },
      %{
        name: "count",
        required: true,
        kind: :integer
      },
      %{
        name: "ratio",
        required: false,
        kind: :number
      },
      %{
        name: "tags",
        required: false,
        kind: {:array, %{kind: :string}},
        min_items: 1
      },
      %{
        name: "items",
        required: true,
        kind:
          {:array, %{kind: {:object, %{members: [%{name: "id", required: true, kind: :string}]}}}},
        max_items: 3,
        unique_by: "id"
      },
      %{
        name: "payload",
        required: false,
        kind: :any
      },
      %{
        name: "sealed",
        required: false,
        kind: :custom,
        check: fn {:string, s} ->
          if(String.starts_with?(s, "ok:"), do: :ok, else: {:error, :sealed_invalid})
        end
      },
      %{
        name: "items",
        required: true,
        kind: {:array, %{kind: :any}},
        root_hook: fn members ->
          if Map.get(members, "kind") == {:string, "beta"} and length(items_of(members)) > 1 do
            {:error, :beta_single_item}
          else
            :ok
          end
        end
      }
    ]
  end

  defp items_of(members) do
    case Map.get(members, "items") do
      {:array, items} -> items
      _other -> []
    end
  end

  defp base_members do
    [
      {"kind", {:string, "alpha"}},
      {"count", {:integer, 2}},
      {"items", {:array, [{:object, [{"id", {:string, "one"}}]}]}}
    ]
  end

  test "a well-formed toy artifact validates green" do
    assert :ok = Registry.validate(toy_table(), {:object, base_members()})
  end

  test "unknown member denies :unknown_member" do
    assert {:error, :unknown_member} =
             Registry.validate(
               toy_table(),
               {:object, [{"mystery", {:integer, 1}} | base_members()]}
             )
  end

  test "missing required member denies :missing_required_field" do
    members = List.keydelete(base_members(), "count", 0)
    assert {:error, :missing_required_field} = Registry.validate(toy_table(), {:object, members})
  end

  test "tag-strict integer: a zero-fraction float denies :invalid_type" do
    members = List.keyreplace(base_members(), "count", 0, {"count", {:float, 2.0}})
    assert {:error, :invalid_type} = Registry.validate(toy_table(), {:object, members})

    members_int = List.keyreplace(base_members(), "count", 0, {"count", {:integer, 3}})
    assert :ok = Registry.validate(toy_table(), {:object, members_int})
  end

  test "enum boundary denies :invalid_constraint" do
    members = List.keyreplace(base_members(), "kind", 0, {"kind", {:string, "gamma"}})
    assert {:error, :invalid_constraint} = Registry.validate(toy_table(), {:object, members})
  end

  test "cardinality: max plus-one, min zero, and duplicates deny :invalid_cardinality" do
    four =
      {:array, Enum.map(["a", "b", "c", "d"], &{:object, [{"id", {:string, &1}}]})}

    members = List.keyreplace(base_members(), "items", 0, {"items", four})
    assert {:error, :invalid_cardinality} = Registry.validate(toy_table(), {:object, members})

    members = base_members() ++ [{"tags", {:array, []}}]
    assert {:error, :invalid_cardinality} = Registry.validate(toy_table(), {:object, members})

    dup = {:array, [{:object, [{"id", {:string, "one"}}]}, {:object, [{"id", {:string, "one"}}]}]}
    members = List.keyreplace(base_members(), "items", 0, {"items", dup})
    assert {:error, :invalid_cardinality} = Registry.validate(toy_table(), {:object, members})
  end

  test "nested object: unknown member inside an element denies :unknown_member" do
    item = {:object, [{"id", {:string, "one"}}, {"surprise", {:integer, 0}}]}
    members = List.keyreplace(base_members(), "items", 0, {"items", {:array, [item]}})
    assert {:error, :unknown_member} = Registry.validate(toy_table(), {:object, members})
  end

  test "custom kind passes its checker's reason through" do
    members = base_members() ++ [{"sealed", {:string, "bad:seal"}}]
    assert {:error, :sealed_invalid} = Registry.validate(toy_table(), {:object, members})

    members = base_members() ++ [{"sealed", {:string, "ok:seal"}}]
    assert :ok = Registry.validate(toy_table(), {:object, members})
  end

  test "root hooks see sibling members and run in table order" do
    members = List.keyreplace(base_members(), "kind", 0, {"kind", {:string, "beta"}})
    assert :ok = Registry.validate(toy_table(), {:object, members})

    two = {:array, [{:object, [{"id", {:string, "one"}}]}, {:object, [{"id", {:string, "two"}}]}]}
    members = List.keyreplace(base_members(), "items", 0, {"items", two})
    members = List.keyreplace(members, "kind", 0, {"kind", {:string, "beta"}})
    assert {:error, :beta_single_item} = Registry.validate(toy_table(), {:object, members})
  end

  test ":number accepts both number tags; :any accepts well-formed values" do
    members = base_members() ++ [{"ratio", {:float, 1.5}}, {"payload", {:object, [{"x", :null}]}}]
    assert :ok = Registry.validate(toy_table(), {:object, members})

    members = List.keyreplace(members, "ratio", 0, {"ratio", {:integer, 2}})
    assert :ok = Registry.validate(toy_table(), {:object, members})
  end

  test ":any denies malformed tagged values" do
    members = base_members() ++ [{"payload", {:integer, 1.5}}]
    assert {:error, :invalid_type} = Registry.validate(toy_table(), {:object, members})
  end

  test "a non-object root and malformed members deny :invalid_type" do
    assert {:error, :invalid_type} = Registry.validate(toy_table(), {:array, []})
    assert {:error, :invalid_type} = Registry.validate(toy_table(), {:string, "x"})
    # A malformed member VALUE denies :invalid_type at the type stage (with
    # every required member present so no earlier stage masks it).
    members = List.keyreplace(base_members(), "kind", 0, {"kind", 5})
    assert {:error, :invalid_type} = Registry.validate(toy_table(), {:object, members})
    # Hand-built duplicate members — the decoder rejects these, from_value
    # callers might not.
    dup = base_members() ++ [{"kind", {:string, "beta"}}]
    assert {:error, :invalid_type} = Registry.validate(toy_table(), {:object, dup})
  end

  test "array elements are fully validated: kind, enum membership, and custom checks" do
    table = [
      %{name: "names", required: false, kind: {:array, %{kind: :string}}},
      %{name: "codes", required: false, kind: {:array, %{kind: {:enum, MapSet.new(["a", "b"])}}}},
      %{
        name: "stamped",
        required: false,
        kind:
          {:array,
           %{
             kind: :custom,
             check: fn {:integer, n} -> if(n > 0, do: :ok, else: {:error, :stamp_invalid}) end
           }}
      }
    ]

    assert :ok = Registry.validate(table, {:object, [{"names", {:array, [{:string, "x"}]}}]})
    # Element type failure — not the array's.
    assert {:error, :invalid_type} =
             Registry.validate(table, {:object, [{"names", {:array, [5]}}]})

    # Element enum membership is a constraint, not a type.
    assert :ok = Registry.validate(table, {:object, [{"codes", {:array, [{:string, "a"}]}}]})

    assert {:error, :invalid_constraint} =
             Registry.validate(table, {:object, [{"codes", {:array, [{:string, "zz"}]}}]})

    assert :ok = Registry.validate(table, {:object, [{"stamped", {:array, [{:integer, 1}]}}]})

    assert {:error, :stamp_invalid} =
             Registry.validate(table, {:object, [{"stamped", {:array, [{:integer, 0}]}}]})
  end

  test "unique_by :value detects duplicate scalar elements" do
    table = [
      %{name: "triggers", required: false, kind: {:array, %{kind: :string}}, unique_by: :value}
    ]

    assert :ok =
             Registry.validate(
               table,
               {:object, [{"triggers", {:array, [{:string, "a"}, {:string, "b"}]}}]}
             )

    assert {:error, :invalid_cardinality} =
             Registry.validate(
               table,
               {:object, [{"triggers", {:array, [{:string, "a"}, {:string, "a"}]}}]}
             )
  end

  test "failure precedence: unknown beats missing beats type beats constraint beats cardinality" do
    # Unknown member present AND count missing AND a float ratio in integer
    # position AND a bad enum AND over-cardinality items: unknown wins.
    members = [
      {"mystery", {:integer, 1}},
      {"kind", {:string, "gamma"}},
      {"ratio", {:float, 9.007_199_254_740_992e15}},
      {"items", {:array, Enum.map(1..4, &{:object, [{"id", {:string, "x#{&1}"}}]})}}
    ]

    assert {:error, :unknown_member} = Registry.validate(toy_table(), {:object, members})

    # Same without the unknown member: missing wins over everything else.
    members = List.keydelete(members, "mystery", 0)
    assert {:error, :missing_required_field} = Registry.validate(toy_table(), {:object, members})
  end

  test "sweep: live fallback clauses" do
    # optional field carrying a root hook that is absent: hook skipped.
    table = [
      %{name: "opt", required: false, kind: :any, root_hook: fn _members -> {:error, :nope} end}
    ]

    assert :ok = Registry.validate(table, {:object, []})

    # unique_by over elements lacking the key and non-object elements.
    mixed = {:array, [{:object, [{"other", {:string, "x"}}]}, {:string, "raw"}]}
    table = [%{name: "items", required: false, kind: {:array, %{kind: :any}}, unique_by: "id"}]
    assert :ok = Registry.validate(table, {:object, [{"items", mixed}]})

    # float kind match and miss.
    table = [%{name: "ratio", required: false, kind: :float}]
    assert :ok = Registry.validate(table, {:object, [{"ratio", {:float, 1.5}}]})

    assert {:error, :invalid_type} =
             Registry.validate(table, {:object, [{"ratio", {:integer, 1}}]})

    # :any well-formedness branches: bad boolean, bad object member, junk atom.
    for bad <- [{:boolean, 5}, {:object, [{5, :null}]}, :junk] do
      table = [%{name: "payload", required: false, kind: :any}]
      assert {:error, :invalid_type} = Registry.validate(table, {:object, [{"payload", bad}]})
    end

    # :any positives: floats, arrays, objects.
    for good <- [{:float, 1.5}, {:array, [{:integer, 1}]}, {:object, [{"k", :null}]}] do
      table = [%{name: "payload", required: false, kind: :any}]
      assert :ok = Registry.validate(table, {:object, [{"payload", good}]})
    end
  end
end
