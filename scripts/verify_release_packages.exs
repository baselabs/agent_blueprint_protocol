# Release verification for a tagged checkout: the shipped consumer driver's
# package gates, then the installed compatibility replay. The replay runs every
# earlier release census and the signed 0.8.x goldens through the installed
# Hex and npm verifiers, so it needs this checkout's release tags and scripts;
# the shipped driver never loads a checkout file.
Code.require_file("consumer_examples.exs", __DIR__)

defmodule VerifyReleasePackages do
  @moduledoc false

  def main(args) do
    ConsumerExamples.with_packages("verify_release_packages.exs", args, fn packages ->
      replay!(packages)
      ConsumerExamples.run_gates!(packages)
      IO.puts("release packages: installed compatibility replay and package gates passed")
    end)
  end

  # Consumers live inside the driver's scratch directory and are removed before
  # it: a consumer's build links its priv directory into the unpacked package,
  # and Windows cannot remove that link once the package is gone.
  def replay!(%{package: package, tarball: tarball, installed: installed, scratch: scratch}) do
    repository = File.cwd!()

    ConsumerExamples.command!(
      ConsumerExamples.node_executable(),
      [Path.join(__DIR__, "postpublish_smoke.mjs"), "--local", tarball, installed],
      []
    )

    kit = Path.join(installed, "node_modules/@agent-blueprint-protocol/verifier/dist/kit/cli.mjs")
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

      ConsumerExamples.command!(
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
