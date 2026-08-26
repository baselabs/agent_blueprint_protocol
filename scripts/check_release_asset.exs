# The release-asset gate: the standalone verifier tarball (the per-release
# kit: verifier/ + the conformance corpus) runs against the SHIPPED hex
# archive's corpus — exit 0 with a byte-identical report — and the asset's
# construction is deterministic (the archive corpus, byte-exact).
#
#   mix release.asset          # build scratch asset → run over the archive corpus
#   mix release.asset --write  # regenerate verifier-<version>.tar.gz at repo root
#
# The CI job runs this gate on every push; a broken or drifted asset reds
# BEFORE a release tag carries it.

defmodule AgentBlueprintProtocol.ReleaseAssetGate do
  @escript "agent_blueprint_protocol_conformance"

  def run(write?) do
    version = Mix.Project.config()[:version]
    tar = "verifier-#{version}.tar.gz"

    build_asset(tar)
    findings = smoke_findings(tar)

    if findings != [] do
      File.rm(tar)
      raise "release asset: FAILED\n\n#{Enum.join(findings, "\n")}"
    end

    if write? do
      IO.puts(
        "release asset: ok (#{tar} built; standalone run over the archive corpus byte-identical)"
      )
    else
      File.rm(tar)
      IO.puts("release asset: ok (standalone run over the archive corpus byte-identical)")
    end
  end

  defp build_asset(tar) do
    files =
      Path.wildcard("verifier/**/*", match_dot: true)
      |> Enum.reject(&File.dir?/1)
      |> Enum.map(&{String.replace_prefix(&1, "verifier/", ""), File.read!(&1)})

    corpus =
      Path.wildcard("priv/conformance/**/*", match_dot: true)
      |> Enum.reject(&File.dir?/1)
      |> Enum.map(
        &{String.replace_prefix(&1, "priv/conformance/", "conformance/"), File.read!(&1)}
      )

    # erl_tar.add wants binaries, not charlists, for name/value pairs
    entries = Enum.map(files ++ corpus, fn {name, bytes} -> {String.to_charlist(name), bytes} end)
    :ok = :erl_tar.create(String.to_charlist(tar), entries, [:compressed])
  end

  # The standalone smoke: unpack the asset in a scratch, run its CLI over
  # its own corpus AND over the SHIPPED hex archive's corpus, and require
  # exit 0 with a report byte-identical to the escript's over the same
  # archive bytes.
  defp smoke_findings(tar) do
    scratch = Path.join(System.tmp_dir!(), "abp-release-asset-#{asset_rand()}")
    File.mkdir_p!(scratch)

    try do
      :ok =
        :erl_tar.extract(String.to_charlist(tar), [
          {:cwd, String.to_charlist(scratch)},
          :compressed
        ])

      {_unpack, archive} = build_hex_archive()
      corpus_dir = Path.join(archive, "priv/conformance")
      escript_report = escript_report(archive, corpus_dir)

      findings =
        case run_cli(scratch, Path.join(scratch, "conformance")) do
          {report, 0} ->
            if report == escript_report,
              do: [],
              else: ["the asset's report over its own corpus diverges from the escript's"]

          {_out, code} ->
            ["the asset's standalone run over its own corpus exited #{code} (0 required)"]
        end

      findings =
        case run_cli(scratch, corpus_dir) do
          {report, 0} ->
            if report == escript_report,
              do: findings,
              else:
                findings ++
                  [
                    "the asset's report over the SHIPPED archive corpus is not byte-identical to the escript's"
                  ]

          {_out, code} ->
            findings ++
              ["the asset's run over the SHIPPED archive corpus exited #{code} (0 required)"]
        end

      findings
    after
      File.rm_rf!(scratch)
    end
  end

  defp asset_rand do
    :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)
  end

  defp run_cli(scratch, corpus_dir) do
    System.cmd("node", [Path.join(scratch, "cli.ts"), "--corpus", corpus_dir],
      stderr_to_stdout: false,
      env: [{"NODE_NO_WARNINGS", "1"}]
    )
  end

  defp build_hex_archive do
    dir =
      Path.join(
        System.tmp_dir!(),
        "abp-release-asset-hex-#{:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)}"
      )

    File.mkdir_p!(dir)

    # Both builds run with cwd = the ORIGINAL tree (this gate's own mix
    # project): hex.build unpacks INTO the dir, and the escript is built
    # at the repo root and copied BESIDE the archive — inside a
    # release-candidate scratch the reference must come from the same
    # tree under test.
    {_out, 0} =
      System.cmd("mix", ["hex.build", "--unpack", "--output", dir],
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}, {"MIX_QUIET", "1"}]
      )

    {_out, 0} =
      System.cmd("mix", ["escript.build"],
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}, {"MIX_QUIET", "1"}]
      )

    File.cp!(@escript, Path.join(dir, @escript))
    {dir, dir}
  end

  defp escript_report(dir, corpus_dir) do
    escript = Path.join(dir, @escript)
    {out, 0} = System.cmd(escript, ["--corpus", corpus_dir], stderr_to_stdout: true)
    String.trim_trailing(out)
  end
end

write? = System.argv() == ["--write"] or System.get_env("ABP_ASSET_WRITE") == "1"
AgentBlueprintProtocol.ReleaseAssetGate.run(write?)
