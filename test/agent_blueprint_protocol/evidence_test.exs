defmodule AgentBlueprintProtocol.EvidenceTest do
  @moduledoc """
  The Evidence constructor's contract: the frozen host-owned field set,
  the seven-atom default, the union law over caller extras, and the typed
  rim denials (a forged constructor input never yields a record).
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Error, Evidence}

  @seven ~w(tenancy live_policy authority effect_ownership execution billing evaluation_truth)a

  test "build/0 defaults: not_verified is exactly the seven, in pinned order" do
    assert {:ok, %Evidence{not_verified: @seven, checks: [], clamps: []}} = Evidence.build()
  end

  test "build/1 unions caller extras after the seven, deduplicating" do
    assert {:ok, %Evidence{not_verified: listed}} =
             Evidence.build(not_verified: [:billing, :custom_surface, :custom_surface])

    assert listed == @seven ++ [:custom_surface]
  end

  test "build/1 accepts a map of attrs and sets the frozen fields" do
    check = %{surface: :digest, subject: ["blueprint"], verified: true, detail: nil}

    assert {:ok, %Evidence{protocol_revision: 1, checks: [^check]}} =
             Evidence.build(%{protocol_revision: 1, checks: [check]})
  end

  test "build/1 rim: struct inputs deny typed (never raise)" do
    assert {:error, %Error{code: :invalid_type, subject: ["evidence"]}} =
             Evidence.build(%URI{})

    assert {:error, %Error{code: :invalid_type, subject: ["evidence"]}} =
             Evidence.build(%Evidence{})
  end

  test "build/1 rim: junk field shapes deny typed with the field path" do
    for {forged, subject} <- [
          {[checks: :junk], ["checks"]},
          {[checks: [%{surface: :digest}]], ["checks", 0]},
          {[checks: [%{surface: "digest", subject: [], verified: true}]], ["checks", 0]},
          {[protocol_revision: "nope"], ["protocol_revision"]},
          {[protocol_revision: 0], ["protocol_revision"]},
          {[blueprint_digest: "sha-256:x"], ["blueprint_digest"]},
          {[deployment_digest: :junk], ["deployment_digest"]},
          {[effective_bounds: %{}], ["effective_bounds"]},
          {[clamps: :junk], ["clamps"]},
          {[clamps: [%{}]], ["clamps", 0]},
          {[optional_extensions_retained: [:ns]], ["optional_extensions_retained", 0]},
          {[optional_extensions_retained: :junk], ["optional_extensions_retained"]}
        ] do
      assert {:error, %Error{code: :invalid_type, subject: ^subject}} = Evidence.build(forged),
             "expected typed denial for #{inspect(subject)}"
    end
  end

  test "build/1 denies an unknown attr key without echoing it" do
    assert {:error, %Error{code: :unknown_member, subject: ["evidence"]}} =
             Evidence.build(%{forged_field: 1})
  end

  test "build/1 rim: a non-map, non-keyword input denies typed" do
    assert {:error, %Error{code: :invalid_type, subject: ["evidence"]}} = Evidence.build(:junk)
    assert {:error, %Error{code: :invalid_type, subject: ["evidence"]}} = Evidence.build(42)
  end

  test "build/1 rim: a list that is not a keyword list denies typed" do
    assert {:error, %Error{code: :invalid_type, subject: ["evidence"]}} =
             Evidence.build([{"not_verified", [:x]}])
  end

  test "build/1 rim: a non-list not_verified denies typed" do
    assert {:error, %Error{code: :invalid_type, subject: ["not_verified"]}} =
             Evidence.build(not_verified: :tenancy)
  end

  test "build/1 rim: a non-atom member denies typed naming its index" do
    assert {:error, %Error{code: :invalid_type, subject: ["not_verified", 1]}} =
             Evidence.build(not_verified: [:ok, "junk"])

    assert {:error, %Error{code: :invalid_type, subject: ["not_verified", 0]}} =
             Evidence.build(not_verified: [%{forged: true}])
  end
end
