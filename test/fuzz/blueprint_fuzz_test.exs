defmodule AgentBlueprintProtocol.Fuzz.BlueprintTest do
  @moduledoc """
  Facade closure for `decode_blueprint/2`: arbitrary bytes under arbitrary
  tighten-only bounds return `{:ok, _} | {:error, _}` — never raise, never
  exit — inside a wall-clock budget.
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias AgentBlueprintProtocol

  property "arbitrary bytes never raise" do
    check all(input <- binary(), max_runs: 200) do
      started = System.monotonic_time()

      result = AgentBlueprintProtocol.decode_blueprint(input)

      elapsed_ms =
        System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)

      assert elapsed_ms < 1000

      case result do
        {:ok, %AgentBlueprintProtocol.Blueprint{}} -> assert is_binary(input)
        {:error, reason} -> assert is_atom(reason) or match?({:ceiling, _}, reason)
      end
    end
  end

  property "valid artifacts under tightened bounds still decode or deny cleanly" do
    check all(
            bytes <- member_of([AgentBlueprintProtocol.BlueprintFixture.fixture_bytes([])]),
            max_runs: 10
          ) do
      result = AgentBlueprintProtocol.decode_blueprint(bytes, %{bytes: 100})
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
