Code.require_file("../scripts/consumer_examples.exs", __DIR__)

defmodule AgentBlueprintProtocol.ConsumerExamplesTest do
  use ExUnit.Case, async: true

  @driver ConsumerExamples

  test "registry versions are validated before any request" do
    for version <- ["", "1.2", "1.2.3/other", "1.2.3;command", "1.2.3\n"] do
      assert_raise RuntimeError, "expected a released version", fn ->
        apply(@driver, :version!, [version])
      end
    end

    assert apply(@driver, :version!, ["1.1.0-rc.2"]) == "1.1.0-rc.2"
  end

  test "Hex verification binds the entire archive to the API version and checksum" do
    bytes = File.read!("README.md")
    checksum = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
    release = %{"version" => "1.1.0-rc.2", "checksum" => checksum}
    assert apply(@driver, :verify_hex!, [bytes, release, "1.1.0-rc.2"]) == :ok

    for {candidate, metadata} <- [
          {bytes <> "changed", release},
          {bytes, %{release | "version" => "1.0.0"}},
          {bytes, Map.delete(release, "checksum")}
        ] do
      assert_raise RuntimeError, "Hex release checksum or version mismatch", fn ->
        apply(@driver, :verify_hex!, [candidate, metadata, "1.1.0-rc.2"])
      end
    end
  end

  test "npm integrity rejects changed bytes and missing or unsupported integrity" do
    bytes = File.read!("verifier/README.md")

    for algorithm <- [:sha256, :sha384, :sha512] do
      integrity =
        Atom.to_string(algorithm) <> "-" <> Base.encode64(:crypto.hash(algorithm, bytes))

      assert apply(@driver, :verify_npm!, [bytes, integrity]) == :ok

      assert_raise RuntimeError, "npm integrity mismatch", fn ->
        apply(@driver, :verify_npm!, [bytes <> "changed", integrity])
      end
    end

    for integrity <- [nil, "", "md5-value", "sha512-!"] do
      assert_raise RuntimeError, "npm integrity mismatch", fn ->
        apply(@driver, :verify_npm!, [bytes, integrity])
      end
    end
  end

  test "invalid usage fails before fetching or building packages" do
    assert_raise RuntimeError, ~r/usage:/, fn -> apply(@driver, :main, [[]]) end

    assert_raise RuntimeError, ~r/usage:/, fn ->
      apply(@driver, :main, [["--local", "one.tar"]])
    end
  end
end
