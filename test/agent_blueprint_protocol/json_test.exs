defmodule AgentBlueprintProtocol.JsonTest do
  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.Json

  test "decodes scalars into the tagged algebra" do
    assert Json.decode("42") == {:ok, {:integer, 42}}
    assert Json.decode("-7") == {:ok, {:integer, -7}}
    assert Json.decode("0") == {:ok, {:integer, 0}}
    assert Json.decode("2.5") == {:ok, {:float, 2.5}}
    assert Json.decode("1e3") == {:ok, {:float, 1.0e3}}
    assert Json.decode("true") == {:ok, {:boolean, true}}
    assert Json.decode("false") == {:ok, {:boolean, false}}
    assert Json.decode("null") == {:ok, :null}
    assert Json.decode(~s("hi")) == {:ok, {:string, "hi"}}
  end

  test "decodes arrays preserving item order, including nesting" do
    assert Json.decode(~s([1, "a", true, null])) ==
             {:ok, {:array, [{:integer, 1}, {:string, "a"}, {:boolean, true}, :null]}}

    assert Json.decode("[[1],[2]]") ==
             {:ok, {:array, [{:array, [integer: 1]}, {:array, [integer: 2]}]}}
  end

  test "objects are order-preserving tagged pair lists with bare-binary keys" do
    assert Json.decode(~s({"b":1,"a":2})) ==
             {:ok, {:object, [{"b", {:integer, 1}}, {"a", {:integer, 2}}]}}

    assert Json.decode(~s({"outer":{"inner":[true]}})) ==
             {:ok, {:object, [{"outer", {:object, [{"inner", {:array, [boolean: true]}}]}}]}}
  end

  test "accepts trailing JSON whitespace, rejects trailing non-whitespace" do
    assert Json.decode("1 \n\t ") == {:ok, {:integer, 1}}
    assert Json.decode("1 x") == {:error, :trailing_bytes}
    assert Json.decode("{} []") == {:error, :trailing_bytes}
  end

  test "malformed input is a value-free syntax error, never a raise" do
    assert Json.decode("{") == {:error, :invalid_syntax}
    assert Json.decode("") == {:error, :invalid_syntax}
    assert Json.decode("nul") == {:error, :invalid_syntax}
    assert Json.decode("[1,]") == {:error, :invalid_syntax}
  end

  test "an overflowing float lexeme is a value-free invalid_number" do
    assert Json.decode("1e400") == {:error, :invalid_number}
  end

  test "propagates a bounds coercion error unchanged" do
    assert Json.decode("1", %{depth: 9999}) == {:error, {:ceiling, :depth}}
    assert Json.decode("1", %{bogus: 1}) == {:error, :unknown_bound}
  end

  test "accepts an explicit Bounds struct" do
    {:ok, bounds} = AgentBlueprintProtocol.Bounds.new(%{depth: 4})
    assert Json.decode("[1]", bounds) == {:ok, {:array, [integer: 1]}}
  end

  describe "non-binary input (the floor's json.decode × invalid_type cell)" do
    test "a non-binary input denies with a typed error, never raises" do
      assert Json.decode(123) == {:error, :invalid_type}
      assert Json.decode(nil) == {:error, :invalid_type}
      assert Json.decode(:atom, %{}) == {:error, :invalid_type}
    end
  end
end
