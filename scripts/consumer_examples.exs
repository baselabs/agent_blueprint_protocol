# Load the extracted package's Elixir gates in-process: Node cannot spawn Windows
# .bat files, and program source must never cross a shell argument boundary.
Code.require_file("../test/support/scratch.exs", __DIR__)

defmodule ConsumerExamples do
  @moduledoc false
  alias AgentBlueprintProtocol.Scratch

  def main(["--registry", version]) do
    version = version!(version)

    Scratch.with_dir("consumer-examples", fn scratch ->
      release =
        fetch_json!("https://hex.pm/api/packages/agent_blueprint_protocol/releases/#{version}")

      hex = fetch!("https://repo.hex.pm/tarballs/agent_blueprint_protocol-#{version}.tar")
      verify_hex!(hex, release, version)

      npm =
        fetch_json!("https://registry.npmjs.org/@agent-blueprint-protocol%2fverifier/#{version}")

      unless npm["name"] == "@agent-blueprint-protocol/verifier" and npm["version"] == version,
        do: raise("npm package name or version mismatch")

      packed = fetch!(npm["dist"]["tarball"])
      verify_npm!(packed, npm["dist"]["integrity"])
      IO.puts("consumer examples: registry checksums verified")

      archive = Path.join(scratch, "package.tar")
      tarball = Path.join(scratch, "verifier.tgz")
      File.write!(archive, hex)
      File.write!(tarball, packed)
      run!(archive, tarball, scratch)
    end)
  end

  def main(["--local", archive, tarball]) do
    archive = Path.expand(archive)
    tarball = Path.expand(tarball)
    Scratch.with_dir("consumer-examples", &run!(archive, tarball, &1))
  end

  def main(_args),
    do:
      raise(
        "usage: elixir scripts/consumer_examples.exs --registry VERSION | --local HEX.tar NPM.tgz"
      )

  def version!(version) do
    if is_binary(version) and Regex.match?(~r/\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\z/, version),
      do: version,
      else: raise("expected a released version")
  end

  def verify_hex!(bytes, release, version) do
    checksum = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

    unless release["version"] == version and release["checksum"] == checksum,
      do: raise("Hex release checksum or version mismatch")

    :ok
  end

  def verify_npm!(bytes, integrity) do
    valid =
      with true <- is_binary(integrity),
           [algorithm, digest] <- String.split(integrity, "-", parts: 2),
           {:ok, algorithm} <-
             Map.fetch(
               %{"sha256" => :sha256, "sha384" => :sha384, "sha512" => :sha512},
               algorithm
             ),
           {:ok, expected} <- Base.decode64(digest) do
        :crypto.hash(algorithm, bytes) == expected
      else
        _ -> false
      end

    unless valid, do: raise("npm integrity mismatch")
    :ok
  end

  defp run!(archive, tarball, scratch) do
    package = Path.join(scratch, "hex")
    installed = Path.join(scratch, "npm")
    File.mkdir!(package)
    File.mkdir!(installed)

    {:ok, entries} = :erl_tar.extract(String.to_charlist(archive), [:memory])
    {_, contents} = List.keyfind(entries, ~c"contents.tar.gz", 0)

    :ok =
      :erl_tar.extract({:binary, contents}, [:compressed, {:cwd, String.to_charlist(package)}])

    :ok =
      :erl_tar.extract(String.to_charlist(tarball), [
        :compressed,
        {:cwd, String.to_charlist(installed)}
      ])

    replay!(package, tarball, installed, scratch)

    # These are always the package's own gates and documents, never the checkout's.
    # Their child consumers use System.cmd, which supports Windows batch launch;
    # only filenames and fixed task arguments cross that boundary.
    Code.require_file(Path.join(package, "scripts/extract_livebooks.exs"))
    Code.require_file(Path.join(package, "scripts/package_examples.exs"))
    notebooks = documents!(package, "docs/livebooks/*.livemd")
    guides = documents!(package, "documentation/*.{md,cheatmd}")
    apply(PackageLivebooks, :run, [archive, notebooks])
    apply(PackageExamples, :run, [archive, :doctests, []])
    apply(PackageExamples, :run, [archive, :snippets, [Path.join(package, "README.md") | guides]])

    # Node is a native executable on Windows. npm's CLI is launched by that
    # executable inside the published TypeScript gate, never through npm.cmd.
    # Keep the caller's cwd for version-manager shims; the gate isolates its
    # consumer in its own scratch directory using process.execPath.
    node = if match?({:win32, _}, :os.type()), do: "node.exe", else: "node"

    {_, status} =
      System.cmd(
        node,
        [
          Path.join(package, "scripts/run_package_typescript_examples.mjs"),
          tarball,
          Path.join(installed, "package/README.md"),
          Path.join(package, "documentation/typescript.md")
        ],
        into: IO.stream(),
        stderr_to_stdout: true
      )

    if status != 0, do: raise("package TypeScript examples failed")
    IO.puts("consumer examples: installed compatibility replay and all four package gates passed")
  end

  def replay!(package, tarball, installed, scratch) do
    repository = File.cwd!()
    node = if match?({:win32, _}, :os.type()), do: "node.exe", else: "node"

    command!(
      node,
      [Path.join(__DIR__, "postpublish_smoke.mjs"), "--local", tarball, installed],
      []
    )

    kit = Path.join(installed, "node_modules/@agent-blueprint-protocol/verifier/dist/kit/cli.mjs")
    consumers = Path.join(scratch, "consumers")
    File.mkdir!(consumers)
    consumer = Path.join(consumers, "replay")
    File.mkdir!(consumer)

    try do
      File.write!(Path.join(consumer, "mix.exs"), """
      defmodule CompatibilityConsumer.MixProject do
        use Mix.Project
        def project, do: [app: :compatibility_consumer, version: "0.0.0", deps: [{:agent_blueprint_protocol, path: #{inspect(package)}, env: :prod}]]
        def application, do: [extra_applications: [:crypto]]
      end
      """)

      options = [
        cd: consumer,
        env: [{"MIX_ENV", "test"}, {"MIX_BUILD_PATH", nil}, {"MIX_DEPS_PATH", nil}]
      ]

      command!("mix", ["deps.get"], options)

      command!(
        "mix",
        [
          "run",
          Path.join(__DIR__, "check_compatibility_replay.exs"),
          "--installed",
          repository,
          kit
        ],
        options
      )
    after
      # Remove consumer priv links before their package target, including on Windows.
      File.rm_rf!(consumers)
    end
  end

  defp command!(program, args, options) do
    {_, status} =
      System.cmd(program, args, [into: IO.stream(), stderr_to_stdout: true] ++ options)

    if status != 0, do: raise("installed consumer command failed with exit #{status}")
  end

  # Only the pattern is glob syntax. The package root is the lookup's working
  # directory, never part of the pattern: a Windows temp path's backslashes,
  # like brackets and braces in any path, would be read as glob syntax.
  def documents!(package, pattern) do
    pattern
    |> String.to_charlist()
    |> :filelib.wildcard(String.to_charlist(package))
    |> Enum.map(&Path.join(package, List.to_string(&1)))
    |> Enum.sort()
    |> case do
      [] -> raise "package has no example documents"
      paths -> paths
    end
  end

  defp fetch_json!(url), do: url |> fetch!() |> :json.decode()

  defp fetch!("https://" <> _ = url) do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    ssl = :httpc.ssl_verify_host_options(true)
    # Hex's API rejects requests without a User-Agent header.
    headers = [{~c"user-agent", ~c"agent-blueprint-protocol/consumer-examples"}]

    case :httpc.request(:get, {String.to_charlist(url), headers}, [ssl: ssl, timeout: 60_000],
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _headers, bytes}} ->
        bytes

      {:ok, {{_, status, _}, _headers, _bytes}} ->
        raise "package registry returned HTTP #{status}"

      _ ->
        raise "package registry request failed"
    end
  end
end

if :code.is_loaded(Mix.Project) == false, do: ConsumerExamples.main(System.argv())
