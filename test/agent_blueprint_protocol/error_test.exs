defmodule AgentBlueprintProtocol.ErrorTest do
  @moduledoc """
  The Error record's declared-vocabulary surface: `codes/0`,
  `ceiling_keys/0`, and `declared?/1`'s totality (atoms, family keys,
  junk shapes all answer without raising). The two-directional
  closedness gate lives in the architecture lane.
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.Error

  test "declared?/1 answers for atoms, family keys, and junk shapes" do
    assert Error.declared?(:digest_mismatch)
    assert Error.declared?(:compatibility_entry_missing)
    refute Error.declared?(:totally_undeclared_code)
    assert Error.declared?({:ceiling, :bytes})
    refute Error.declared?({:ceiling, :not_a_limit_name})
    refute Error.declared?(%Error{})
    refute Error.declared?("digest_mismatch")
  end

  test "codes/0 and ceiling_keys/0 are unique atom lists" do
    codes = Error.codes()
    keys = Error.ceiling_keys()

    assert codes != [] and Enum.uniq(codes) == codes
    assert Enum.all?(codes, &is_atom/1)
    assert keys != [] and Enum.uniq(keys) == keys
    assert Enum.all?(keys, &is_atom/1)
  end
end
