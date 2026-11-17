Code.require_file("../scripts/consumer_examples.exs", __DIR__)

defmodule AgentBlueprintProtocol.ConsumerExamplesTest do
  use ExUnit.Case, async: true

  test "registry versions are validated before any request" do
    for version <- ["", "1.2", "1.2.3/other", "1.2.3;command", "1.2.3\n"] do
      assert_raise RuntimeError, "expected a released version", fn ->
        ConsumerExamples.version!(version)
      end
    end

    assert ConsumerExamples.version!("9.8.7-rc.1") == "9.8.7-rc.1"
  end

  test "Hex verification binds the entire archive to the API version and checksum" do
    bytes = File.read!("README.md")
    checksum = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
    release = %{"version" => "9.8.7-rc.1", "checksum" => checksum}
    assert ConsumerExamples.verify_hex!(bytes, release, "9.8.7-rc.1") == :ok

    for {candidate, metadata} <- [
          {bytes <> "changed", release},
          {bytes, %{release | "version" => "1.0.0"}},
          {bytes, Map.delete(release, "checksum")}
        ] do
      assert_raise RuntimeError, "Hex release checksum or version mismatch", fn ->
        ConsumerExamples.verify_hex!(candidate, metadata, "9.8.7-rc.1")
      end
    end
  end

  test "npm integrity rejects changed bytes and missing or unsupported integrity" do
    bytes = File.read!("verifier/README.md")

    for algorithm <- [:sha256, :sha384, :sha512] do
      integrity =
        Atom.to_string(algorithm) <> "-" <> Base.encode64(:crypto.hash(algorithm, bytes))

      assert ConsumerExamples.verify_npm!(bytes, integrity) == :ok

      assert_raise RuntimeError, "npm integrity mismatch", fn ->
        ConsumerExamples.verify_npm!(bytes <> "changed", integrity)
      end
    end

    for integrity <- [nil, "", "md5-value", "sha512-!"] do
      assert_raise RuntimeError, "npm integrity mismatch", fn ->
        ConsumerExamples.verify_npm!(bytes, integrity)
      end
    end
  end

  # A Windows temp path's backslashes, like brackets and braces, are glob syntax.
  test "package documents are found under a root whose name is glob syntax" do
    AgentBlueprintProtocol.Scratch.with_dir("consumer-documents", fn scratch ->
      package = Path.join(scratch, "pkg[1]{a}\\x")

      for relative <- ~w(docs/livebooks/a.livemd documentation/b.md documentation/c.cheatmd) do
        File.mkdir_p!(Path.dirname(Path.join(package, relative)))
        File.write!(Path.join(package, relative), "")
      end

      assert ConsumerExamples.documents!(package, "docs/livebooks/*.livemd") ==
               [Path.join(package, "docs/livebooks/a.livemd")]

      assert ConsumerExamples.documents!(package, "documentation/*.{md,cheatmd}") == [
               Path.join(package, "documentation/b.md"),
               Path.join(package, "documentation/c.cheatmd")
             ]

      assert_raise RuntimeError, "package has no example documents", fn ->
        ConsumerExamples.documents!(package, "missing/*.md")
      end
    end)
  end

  test "invalid usage fails before fetching or building packages" do
    assert_raise RuntimeError, ~r/usage:/, fn -> ConsumerExamples.main([]) end

    assert_raise RuntimeError, ~r/usage:/, fn ->
      ConsumerExamples.main(["--local", "one.tar"])
    end
  end
end
