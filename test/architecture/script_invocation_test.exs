defmodule AgentBlueprintProtocol.Architecture.ScriptInvocationTest do
  use ExUnit.Case, async: true

  # Scan argv literals as well as shell commands. Report locations only: source
  # lines and evaluated environment values must never enter failure diagnostics.
  @inline ~r/(?:^|[\s"',\[])(?:--eval|--execute|--print|-[Cc]ommand|-eval|-e|-c)(?=$|[\s"',\]=])|(?:\bnode(?:\.exe)?\b|process\.execPath)[\s"',\[]+-p(?=$|[\s"',\]])/m
  @toolchain ~r/["'`](?:[^"'`\r\n]*[\x2f\\])?(?:elixir|mix)(?:\.(?:bat|cmd))?["'`]/i
  # The byte-shared toolchain reader has two fixed installed-version probes.
  # These exact, credential-free commands are its only inline exceptions.
  @installed_probes [
    ~S/have=$(elixir -e 'IO.write(System.version() <> "-otp-" <> System.build_info()[:otp_release])') || { printf 'toolchain: %s version probe failed\n' "$tool" >&2; refused=1; continue; } ;;/,
    ~S/have=$(erl -noshell -noinput -eval '{ok, V} = file:read_file(filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"])), io:put_chars(string:trim(V)), halt().') || { printf 'toolchain: %s version probe failed\n' "$tool" >&2; refused=1; continue; } ;;/
  ]

  test "workflows and scripts pass filenames instead of inline program arguments" do
    offenders =
      for path <- paths(),
          {line, index} <- File.read!(path) |> String.split("\n") |> Enum.with_index(1),
          Regex.match?(@inline, line),
          not installed_probe?(path, line),
          do: "#{path}:#{index}"

    assert offenders == [], "inline program arguments at " <> Enum.join(offenders, ", ")
  end

  test "the shared installed-version probes are the only toolchain inline commands" do
    probes =
      "scripts/toolchain.sh"
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(&Regex.match?(@inline, &1))
      |> Enum.map(&String.trim/1)

    assert probes == @installed_probes
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

  # Windows cannot spawn npm's .cmd launcher as a native process. Elixir and
  # Node callers run npm's CLI script with the Node executable: repository
  # callers through scripts/npm.mjs, the shipped TypeScript gate with its own
  # copy of that lookup because it ships alone.
  @npm_by_name [
    ~r/System\.(?:cmd|find_executable)\(\s*"npm(?:\.cmd)?"/,
    ~r/\b(?:spawn|spawnSync|execFile|execFileSync|exec|execSync)\(\s*['"`]npm(?:\.cmd)?['"`]/
  ]
  @npm_lookup "node_modules/npm/bin/npm-cli.js"
  @npm_lookup_owners ["scripts/npm.mjs", "scripts/run_package_typescript_examples.mjs"]

  test "npm is launched as Node running npm's CLI script, never by name" do
    sources =
      for path <-
            Path.wildcard("{lib,scripts,test}/**/*.{ex,exs,js,mjs,cjs,ts}") --
              ["test/architecture/script_invocation_test.exs"],
          do: {path, File.read!(path)}

    by_name =
      for {path, source} <- sources,
          {line, index} <- source |> String.split("\n") |> Enum.with_index(1),
          Enum.any?(@npm_by_name, &Regex.match?(&1, line)),
          do: "#{path}:#{index}"

    assert by_name == [], "npm launched by name at " <> Enum.join(by_name, ", ")

    lookups = for {path, source} <- sources, source =~ @npm_lookup, do: path
    assert Enum.sort(lookups) == Enum.sort(@npm_lookup_owners)

    for launch <- [
          ~s|System.cmd("npm", ["pack"])|,
          ~s|System.find_executable("npm")|,
          ~s|System.cmd("npm.cmd", [])|,
          ~s|spawnSync('npm',['pack'])|,
          ~s|execFileSync("npm", args)|
        ] do
      assert Enum.any?(@npm_by_name, &Regex.match?(&1, launch)), launch
    end

    refute Enum.any?(@npm_by_name, &Regex.match?(&1, ~s|System.cmd("node", ["scripts/npm.mjs"])|))
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
    assert platforms =~ "elixir scripts/verify_release_packages.exs --local"

    published = File.read!(".github/workflows/publish.yml")
    assert published =~ "elixir scripts/verify_release_packages.exs --registry"
    refute published =~ "ref: v${{ inputs.version }}"
    refute published =~ "postpublish_examples.mjs"
  end

  test "release verification replays release tags through the installed packages" do
    verification = File.read!("scripts/verify_release_packages.exs")
    assert verification =~ ~s|Code.require_file("consumer_examples.exs", __DIR__)|
    assert verification =~ "--installed"
    assert verification =~ "check_compatibility_replay.exs"
    assert verification =~ "postpublish_smoke.mjs"

    # The shipped driver is only the package gates; the replay is the checkout's.
    driver = File.read!("scripts/consumer_examples.exs")
    refute driver =~ "check_compatibility_replay"
    refute driver =~ "postpublish_smoke"

    for path <- [
          ".github/workflows/ci.yml",
          ".github/workflows/publish.yml"
        ] do
      jobs = Regex.split(~r/^  [a-z][a-z0-9-]*:\n/m, File.read!(path))
      verifying = for job <- jobs, job =~ "elixir scripts/verify_release_packages.exs", do: job
      assert verifying != [], "#{path} no longer runs release package verification"
      refute Enum.any?(jobs, &(&1 =~ "elixir scripts/consumer_examples.exs"))

      for job <- verifying do
        assert job =~ "fetch-depth: 0"
      end
    end

    publish = File.read!(".github/workflows/publish.yml")
    assert publish =~ "needs: [verify, hex-publish]"
    assert publish =~ "ABP_VERSION: ${{ needs.verify.outputs.version }}"

    replay = File.read!("scripts/check_compatibility_replay.exs")
    assert replay =~ ~s|["tag", "-l", "v*"]|

    assert replay =~
             ~s|Version.compare(released["package_version"], manifest["package_version"]) != :gt|

    refute replay =~ ~s|"v" <> manifest["package_version"]|
  end

  defp installed_probe?("scripts/toolchain.sh", line), do: String.trim(line) in @installed_probes
  defp installed_probe?(_path, _line), do: false

  defp paths do
    Path.wildcard(".github/workflows/*.{yml,yaml}") ++
      Enum.filter(Path.wildcard("scripts/*"), &File.regular?/1)
  end
end
