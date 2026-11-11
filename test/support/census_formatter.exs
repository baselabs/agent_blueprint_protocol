defmodule AgentBlueprintProtocol.Test.CensusFormatter do
  @moduledoc false
  # Records the registered-test count at suite end, excluding doctests.
  # Doctests are generated from documentation examples, so the source
  # macro census (test and property macros) cannot count them; every
  # other generated test still shifts this number away from the census.
  use GenServer

  @census_path Path.expand("../../.test_census", __DIR__)

  @impl true
  def init(_opts), do: {:ok, 0}

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{tags: tags}}, count) do
    {:noreply, if(Map.has_key?(tags, :doctest), do: count, else: count + 1)}
  end

  def handle_cast({:suite_finished, _times}, count) do
    File.write!(@census_path, Integer.to_string(count))
    {:noreply, count}
  end

  def handle_cast(_event, count), do: {:noreply, count}
end
