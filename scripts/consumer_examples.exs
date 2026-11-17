# Load the extracted package's Elixir gates in-process: Node cannot spawn Windows
# .bat files, and program source must never cross a shell argument boundary.
defmodule ConsumerExamples do
  @moduledoc false

  def main(["--registry", version]) do
    version = version!(version)

    with_scratch(fn scratch ->
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
    with_scratch(&run!(archive, tarball, &1))
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
    IO.puts("consumer examples: all four package gates passed")
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

  defp with_scratch(run) do
    scratch =
      Path.join(
        System.tmp_dir!(),
        "consumer-examples-#{Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)}"
      )

    File.mkdir!(scratch)

    try do
      run.(scratch)
    after
      File.rm_rf!(scratch)
    end
  end
end

if :code.is_loaded(Mix.Project) == false, do: ConsumerExamples.main(System.argv())
