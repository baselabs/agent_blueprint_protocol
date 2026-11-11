defmodule AgentBlueprintProtocol.ScratchTest do
  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.Scratch
  alias AgentBlueprintProtocol.Test.CensusFormatter

  test "directory allocation is exclusive and validates every label" do
    Scratch.with_dir("allocation", fn root ->
      path = Scratch.dir!(root, "existing")
      assert File.dir?(path)
      assert_raise File.Error, fn -> Scratch.dir!(root, "existing") end
      File.ln_s!(path, Path.join(root, "linked"))
      assert_raise File.Error, fn -> Scratch.dir!(root, "linked") end

      for label <- [nil, "", "../escape", "UPPER", "bad_label", "valid\n"] do
        assert_raise ArgumentError, fn -> Scratch.dir!(label) end
        assert_raise ArgumentError, fn -> Scratch.dir!(root, label) end
      end
    end)
  end

  test "with_dir returns the callback value and removes its tree" do
    path =
      Scratch.with_dir("normal", fn path ->
        File.write!(Path.join(path, "child"), "bytes")
        path
      end)

    refute File.exists?(path)
  end

  test "with_dir removes its tree when the callback raises" do
    assert_raise RuntimeError, "callback failed", fn ->
      Scratch.with_dir("raising", fn path ->
        send(self(), {:scratch, path})
        raise "callback failed"
      end)
    end

    assert_received {:scratch, path}
    refute File.exists?(path)
  end

  test "replicas use the Git working file set and preserve modes and symlinks" do
    Scratch.with_dir("source", fn root ->
      Scratch.init_git!(root)
      File.write!(Path.join(root, ".gitignore"), "ignored\n/deps\n/_build/\n")
      File.write!(Path.join(root, "tracked"), "committed")
      File.write!(Path.join(root, "deleted"), "committed")
      git!(root, ["add", "--all"])
      git!(root, ["commit", "-m", "source"])
      File.write!(Path.join(root, "tracked"), "uncommitted edit")
      File.rm!(Path.join(root, "deleted"))
      File.write!(Path.join(root, "untracked file"), "allowed")
      File.chmod!(Path.join(root, "untracked file"), 0o755)
      File.write!(Path.join(root, "ignored"), "ignored")
      File.ln_s!("tracked", Path.join(root, "link"))
      File.ln_s!("absent", Path.join(root, "dangling"))
      File.mkdir!(Path.join(root, "deps"))
      File.mkdir_p!(Path.join(root, "_build/dev"))
      File.write!(Path.join(root, "_build/dev/cached"), "compiled")
      expected = files!(root) -- ["deleted"]

      replica =
        Scratch.with_replica("replica", [root: root, git: true], fn replica ->
          assert File.read!(Path.join(replica, "tracked")) == "uncommitted edit"
          assert File.read!(Path.join(replica, "untracked file")) == "allowed"

          assert Bitwise.band(File.stat!(Path.join(replica, "untracked file")).mode, 0o777) ==
                   0o755

          refute File.exists?(Path.join(replica, "ignored"))
          refute File.exists?(Path.join(replica, "deleted"))
          assert File.read_link!(Path.join(replica, "link")) == "tracked"
          assert File.read_link!(Path.join(replica, "dangling")) == "absent"
          assert File.read_link!(Path.join(replica, "deps")) == Path.join(root, "deps")
          assert File.read!(Path.join(replica, "_build/dev/cached")) == "compiled"

          listed =
            git!(replica, ["ls-files", "-z"])
            |> String.split(<<0>>, trim: true)
            |> Enum.sort()

          assert listed == Enum.sort(expected)
          assert git!(replica, ["status", "--porcelain"]) == ""
          replica
        end)

      refute File.exists?(replica)
    end)
  end

  test "replicas without Git still clean up when the callback raises" do
    Scratch.with_dir("raising-source", fn root ->
      Scratch.init_git!(root)

      assert_raise RuntimeError, "replica failed", fn ->
        Scratch.with_replica("raising-replica", [root: root], fn path ->
          refute File.exists?(Path.join(path, ".git"))
          send(self(), {:replica, path})
          raise "replica failed"
        end)
      end
    end)

    assert_received {:replica, path}
    refute File.exists?(path)
  end

  test "replica setup failures remove the allocated directory" do
    Scratch.with_dir("not-a-repository", fn root ->
      pattern = Path.join(Path.dirname(root), "abp-failed-replica-*")
      before = Path.wildcard(pattern)

      assert_raise MatchError, fn ->
        Scratch.with_replica("failed-replica", [root: root], fn _ -> flunk("must not run") end)
      end

      assert Path.wildcard(pattern) == before
    end)
  end

  test "the census writer owns a path in the test build directory" do
    expected = Path.join([File.cwd!(), "_build", "test", ".test_census"])
    assert CensusFormatter.path() == expected

    script =
      "Code.require_file(\"test/support/census_formatter.exs\"); " <>
        "IO.write(AgentBlueprintProtocol.Test.CensusFormatter.path())"

    assert {^expected, 0} =
             System.cmd(
               "mix",
               ["run", "--no-start", "--no-compile", "--no-deps-check", "--eval", script],
               env: [{"MIX_ENV", "dev"}],
               stderr_to_stdout: true
             )
  end

  defp files!(root) do
    git!(root, ["ls-files", "-z", "--cached", "--others", "--exclude-standard"])
    |> String.split(<<0>>, trim: true)
  end

  defp git!(root, args) do
    {output, 0} = System.cmd("git", args, cd: root, stderr_to_stdout: true)
    output
  end
end
