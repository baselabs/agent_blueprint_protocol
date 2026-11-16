defmodule AgentBlueprintProtocol.Architecture.ScriptInvocationTest do
  use ExUnit.Case, async: true

  # Scan argv literals as well as shell commands. Report locations only: source
  # lines and evaluated environment values must never enter failure diagnostics.
  @inline ~r/(?:^|[\s"',\[])(?:--eval|--execute|--print|-[Cc]ommand|-eval|-e|-c)(?=$|[\s"',\]=])|(?:\bnode(?:\.exe)?\b|process\.execPath)[\s"',\[]+-p(?=$|[\s"',\]])/m
  @toolchain ~r/["'`](?:[^"'`\r\n]*[\x2f\\])?(?:elixir|mix)(?:\.(?:bat|cmd))?["'`]/i

  test "workflows and scripts pass filenames instead of inline program arguments" do
    offenders =
      for path <- paths(),
          {line, index} <- File.read!(path) |> String.split("\n") |> Enum.with_index(1),
          Regex.match?(@inline, line),
          do: "#{path}:#{index}"

    assert offenders == [], "inline program arguments at " <> Enum.join(offenders, ", ")
  end

  test "Node scripts never launch the Elixir toolchain, directly or through a command helper" do
    offenders =
      for path <- Path.wildcard("scripts/*.{js,mjs,cjs,ts}"),
          source = File.read!(path),
          source =~ "child_process",
          {line, index} <- source |> String.split("\n") |> Enum.with_index(1),
          Regex.match?(@toolchain, line),
          do: "#{path}:#{index}"

    assert offenders == [], "Node Elixir toolchain invocation at " <> Enum.join(offenders, ", ")
  end

  test "the inline detector covers shell commands and argv arrays" do
    for command <- [
          ~s(elixir -e 'program'),
          ~s(node --input-type=module --eval='program'),
          ~s(mix run -e 'program'),
          ~s(erl -eval 'program'),
          ~s(python -c 'program'),
          ~s(node -p 'program'),
          ~s|command('elixir', ['-e', 'program'])|,
          ~s|System.cmd("node", ["--eval", source])|
        ] do
      assert Regex.match?(@inline, command)
    end

    refute Regex.match?(@inline, ~s(node scripts/gate.mjs --expected value))
    refute Regex.match?(@inline, ~s(git -C source status))
    refute Regex.match?(@inline, ~s(tar -xf package.tar -C target))
  end

  test "consumer examples use the same local package gate on all supported CI platforms" do
    ci = File.read!(".github/workflows/ci.yml")
    [_, platforms] = String.split(ci, "  platforms:\n", parts: 2)
    [platforms | _] = String.split(platforms, "  typescript-consumers:\n", parts: 2)
    assert platforms =~ "os: [ubuntu-24.04, macos-15, windows-2025]"
    assert platforms =~ "mix hex.build --output"
    assert platforms =~ "npm pack ./dist/package --ignore-scripts"
    assert platforms =~ "elixir scripts/consumer_examples.exs --local"

    postpublish = File.read!(".github/workflows/postpublish.yml")
    assert postpublish =~ "elixir scripts/consumer_examples.exs --registry"
    assert postpublish =~ "ref: v${{ inputs.version }}"
    refute postpublish =~ "postpublish_examples.mjs"
  end

  defp paths do
    Path.wildcard(".github/workflows/*.{yml,yaml}") ++
      Enum.filter(Path.wildcard("scripts/*"), &File.regular?/1)
  end
end
