defmodule AgentBlueprintProtocol.Conformance.CliLimitsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  alias AgentBlueprintProtocol.Conformance.Cli
  alias AgentBlueprintProtocol.ConformanceTest.Builder

  @moduletag :tmp_dir

  defp elixir_run(path) do
    error =
      capture_io(:stderr, fn ->
        output = capture_io(fn -> send(self(), {:status, Cli.run(["--corpus", path])}) end)
        send(self(), {:output, output})
      end)

    assert_received {:status, status}
    assert_received {:output, output}
    {status, output, error}
  end

  defp denied(path) do
    {2, "", error} = elixir_run(path)
    assert error =~ "corpus unreadable:"
    refute error =~ path

    {out, status} =
      System.cmd("node", ["verifier/cli.ts", "--corpus", path], stderr_to_stdout: true)

    assert status == 2
    assert out =~ "corpus unreadable:"
    refute out =~ path
  end

  @tag skip:
         if(match?({:win32, _}, :os.type()),
           do: "Windows symlink creation requires a privilege outside the contributor contract",
           else: false
         )
  test "both readers reject symlink files and directories", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "source"), "{}")
    File.ln_s!(Path.join(dir, "source"), Path.join(dir, "linked"))
    denied(dir)
    File.rm!(Path.join(dir, "linked"))
    File.mkdir!(Path.join(dir, "directory"))
    File.ln_s!(Path.join(dir, "directory"), Path.join(dir, "linked"))
    denied(dir)
  end

  test "both readers cap the aggregate bytes", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "one.json"), String.duplicate("x", 2_500_000))
    File.write!(Path.join(dir, "two.json"), String.duplicate("x", 2_500_001))
    denied(dir)
  end

  test "both readers cap entry count including empty files", %{tmp_dir: dir} do
    for i <- 1..1_001, do: File.write!(Path.join(dir, "example-#{i}.json"), "")
    denied(dir)
  end

  @tag skip:
         if(match?({:win32, _}, :os.type()),
           do: "POSIX FIFO creation is unavailable on Windows",
           else: false
         )
  test "both readers reject special files before reading", %{tmp_dir: dir} do
    {_, 0} = System.cmd("mkfifo", [Path.join(dir, "example.json")])
    denied(dir)
  end

  test "corpus certification is visible without changing report bytes", %{tmp_dir: dir} do
    map =
      Builder.build(Builder.minimal_cases())

    for {path, bytes} <- map do
      file = Path.join(dir, path)
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, bytes)
    end

    {_, _, uncertified} = elixir_run(dir)
    assert uncertified =~ "corpus digest does not match the release-certified corpus"
    {0, report, certified} = elixir_run("priv/conformance")
    assert certified =~ "corpus digest matches the release-certified corpus"

    for path <- [
          "./priv/conformance",
          "priv/conformance/",
          Path.expand("priv/conformance") <> "/"
        ] do
      {out, 0} =
        System.cmd("node", ["verifier/cli.ts", "--corpus", path], stderr_to_stdout: false)

      assert out == report
    end

    if match?({:unix, _}, :os.type()) do
      File.rename!(
        Path.join(dir, "cases/json-decode.json"),
        Path.join(dir, "cases\\json-decode.json")
      )

      {2, "", error} = elixir_run(dir)
      assert error =~ "corpus integrity failure:"
      {out, 2} = System.cmd("node", ["verifier/cli.ts", "--corpus", dir], stderr_to_stdout: true)
      assert out =~ "corpus integrity failure:"
    end
  end

  # The kit is built by the quality lane; the toolchain lanes run without it.
  @tag skip:
         if(File.exists?("dist/kit/cli.mjs"),
           do: false,
           else: "the npm kit is not built in this lane"
         )
  test "the installed entry reports help and version and preserves unknown-argument errors" do
    {help, 0} = System.cmd("node", ["dist/kit/cli.mjs", "--help"], stderr_to_stdout: true)
    assert help =~ "usage: agent-blueprint-protocol"

    for mode <- ["--corpus", "--prior-corpus", "--artifact", "--help", "--version", "Exit codes:"] do
      assert help =~ mode
    end

    {version, 0} = System.cmd("node", ["dist/kit/cli.mjs", "--version"], stderr_to_stdout: true)
    assert String.trim(version) == Mix.Project.config()[:version]
    {_, 2} = System.cmd("node", ["dist/kit/cli.mjs", "--unknown"], stderr_to_stdout: true)

    {"", 0} =
      System.cmd(
        "node",
        ["--input-type=module", "-e", "await import('./dist/verifier/run_corpus.js')"],
        stderr_to_stdout: true
      )
  end

  @tag skip:
         if(match?({:win32, _}, :os.type()),
           do: "POSIX permission-bit denial is unavailable on Windows",
           else: false
         )
  test "missing roots, unreadable directories, and unreadable files return exit 2", %{
    tmp_dir: dir
  } do
    {2, "", missing} = elixir_run(Path.join(dir, "absent"))
    assert missing =~ "corpus integrity failure:"
    File.write!(Path.join(dir, "example.json"), "{}")
    denied(Path.join(dir, "example.json"))
    File.chmod!(Path.join(dir, "example.json"), 0o000)

    try do
      denied(dir)
    after
      File.chmod!(Path.join(dir, "example.json"), 0o600)
    end

    File.mkdir!(Path.join(dir, "example"))
    File.chmod!(Path.join(dir, "example"), 0o000)

    try do
      denied(Path.join(dir, "example"))
    after
      File.chmod!(Path.join(dir, "example"), 0o700)
    end
  end
end
