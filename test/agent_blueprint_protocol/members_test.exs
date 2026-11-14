defmodule AgentBlueprintProtocol.MembersTest do
  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Blueprint, Deployment, Error, Federation}

  doctest Blueprint
  doctest Deployment

  describe "Blueprint.members/1" do
    test "revision 1 returns the 18 Blueprint Core members in sorted order" do
      assert_members(Blueprint, "Blueprint Core", 18)
    end

    test "unsupported integer revisions return the protocol revision error" do
      assert_unsupported(Blueprint)
    end

    test "non-integer revisions return a typed invalid type error" do
      assert_invalid(Blueprint)
    end
  end

  describe "Deployment.members/1" do
    test "revision 1 returns the 19 Deployment Manifest members in sorted order" do
      assert_members(Deployment, "Deployment Manifest", 19)
    end

    test "unsupported integer revisions return the protocol revision error" do
      assert_unsupported(Deployment)
    end

    test "non-integer revisions return a typed invalid type error" do
      assert_invalid(Deployment)
    end
  end

  describe "Federation.members/1" do
    test "revision 1 returns the 23 Federation TaskEnvelope members in sorted order" do
      assert_members(Federation, "Federation TaskEnvelope", 23)
    end

    test "unsupported integer revisions return the protocol revision error" do
      assert_unsupported(Federation)
    end

    test "non-integer revisions return a typed invalid type error" do
      assert_invalid(Federation)
    end
  end

  test "TypeScript and Elixir expose identical member lists and refusals" do
    expected = for module <- [Blueprint, Deployment, Federation], do: elem(module.members(1), 1)
    node = System.find_executable("node") || raise "Node is required"
    {output, status} = System.cmd(node, ["test/typescript/members.mjs"], stderr_to_stdout: true)
    assert status == 0, output
    assert JSON.decode!(output) == expected
  end

  defp assert_members(module, title, count) do
    assert {:ok, members} = module.members(1)
    assert length(members) == count
    assert Enum.all?(members, &is_binary/1)
    assert members == Enum.sort(members)
    assert members == spec_members(title)
  end

  defp assert_unsupported(module) do
    for revision <- [-1, 0, 2, 100] do
      assert module.members(revision) ==
               {:error,
                %Error{code: :protocol_revision_unsupported, subject: ["protocol_revision"]}}
    end
  end

  defp assert_invalid(module) do
    for revision <- [nil, true, false, 1.0, "1", :one, [], %{}, {:integer, 1}, <<255>>] do
      assert module.members(revision) == {:error, %Error{code: :invalid_type}}
    end
  end

  # Read the same normative member-grammar sections as SpecMemberGrammarTest,
  # bounded by the next heading so nested tables cannot add root members.
  defp spec_members(title) do
    "spec/protocol.md"
    |> File.read!()
    |> String.split("### Member grammar: ")
    |> Enum.find(&String.starts_with?(&1, title))
    |> String.split("\n")
    |> Enum.take_while(&(!String.starts_with?(&1, ["### ", "## "])))
    |> Enum.flat_map(fn row ->
      case Regex.run(~r/^\| `([^`]+)` \| (?:1|0\.\.1) \|/, row) do
        [_, name] -> [name]
        nil -> []
      end
    end)
    |> Enum.sort()
  end
end
