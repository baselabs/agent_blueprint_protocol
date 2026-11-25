# Derive the contents manifest from both archives, verify the packages in
# consumer projects, and run the packaged examples. Compatibility replay
# needs this checkout's release tags and scripts. The examples run from the
# extracted packages.
Code.require_file("consumer_examples.exs", __DIR__)

unless Code.ensure_loaded?(AgentBlueprintProtocol.PackageContents) do
  Code.require_file("../lib/agent_blueprint_protocol/error.ex", __DIR__)
  Code.require_file("../lib/agent_blueprint_protocol/framed_files.ex", __DIR__)
  Code.require_file("../lib/agent_blueprint_protocol/package_contents.ex", __DIR__)
end

defmodule VerifyReleasePackages do
  @moduledoc false

  alias AgentBlueprintProtocol.PackageContents

  def main(["--local", hex, npm, "--write-manifest", output]),
    do: verify(["--local", hex, npm], output)

  def main(args), do: verify(args, nil)

  defp verify(args, output) do
    ConsumerExamples.with_packages("verify_release_packages.exs", args, fn packages ->
      manifest = contents_manifest!(packages)
      manifest_path = Path.join(packages.scratch, "release-manifest.json")
      bytes = IO.iodata_to_binary(:json.encode(manifest)) <> "\n"
      File.write!(manifest_path, bytes)

      verify_installed!(packages, manifest_path)
      ConsumerExamples.run_gates!(packages)
      if output, do: File.write!(output, bytes)

      IO.puts(
        "release packages: installed contents, compatibility replay and package gates passed"
      )
    end)
  end

  defp contents_manifest!(%{package: hex, installed: installed}) do
    npm = Path.join(installed, "package")
    metadata = File.read!(Path.join(hex, "priv/release-metadata.json"))
    ^metadata = File.read!(Path.join(npm, "dist/release-metadata.json"))
    manifest = :json.decode(metadata)

    %{"version" => version} = :json.decode(File.read!(Path.join(npm, "package.json")))
    ^version = Map.fetch!(manifest, "package_version")
    ^version = get_in(manifest, ["verifier_kit", "version"])

    Map.put(manifest, "package_checksums", %{
      "hex" => PackageContents.checksum!(hex, :hex),
      "npm" => PackageContents.checksum!(npm, :npm)
    })
  end

  # Consumers live inside the driver's scratch directory and are removed before
  # it: a consumer's build links its priv directory into the unpacked package,
  # and Windows cannot remove that link once the package is gone.
  defp verify_installed!(
         %{package: package, tarball: tarball, installed: installed, scratch: scratch},
         manifest_path
       ) do
    repository = File.cwd!()

    ConsumerExamples.command!(
      ConsumerExamples.node_executable(),
      [Path.join(__DIR__, "postpublish_smoke.mjs"), "--local", tarball, installed],
      []
    )

    npm = Path.join(installed, "node_modules/@agent-blueprint-protocol/verifier")

    ConsumerExamples.command!(
      ConsumerExamples.node_executable(),
      [Path.join(__DIR__, "check_installed_package_contents.mjs"), manifest_path, package, npm],
      []
    )

    consumers = Path.join(scratch, "consumers")
    File.mkdir!(consumers)
    consumer = Path.join(consumers, "replay")
    File.mkdir!(consumer)

    if File.regular?(".tool-versions"),
      do: File.cp!(".tool-versions", Path.join(consumer, ".tool-versions"))

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

      ConsumerExamples.command!("mix", ["deps.get"], options)

      # A second Mix run would try to recreate the dependency's priv link on Windows.
      ConsumerExamples.command!(
        "mix",
        [
          "run",
          Path.join(__DIR__, "check_compatibility_replay.exs"),
          "--installed",
          repository,
          manifest_path,
          npm
        ],
        options
      )
    after
      File.rm_rf!(consumers)
    end
  end
end

case :init.get_plain_arguments() do
  [script | _args] ->
    if Path.expand(List.to_string(script)) == __ENV__.file,
      do: VerifyReleasePackages.main(System.argv())

  [] ->
    :ok
end
