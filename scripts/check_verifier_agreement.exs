# The verifier agreement gate: the Elixir escript
# and the TypeScript verifier must produce BYTE-IDENTICAL JCS reports over
# the same corpus — repo-side AND from the built Hex archive — and the TS
# self-check battery (RFC 8785 Appendix B, the integer-window matrix, the
# Ed25519 key acceptance list, the stored JOSE vectors) must pass.
#
#   mix verifier.agreement
#
# Any divergence, non-zero exit, or missing node is a hard failure. Seeded
# reds run after the agreement checks: scratch-copy mutations of the
# verifier, each DIRECTIONAL and asserted to have caused the expected
# divergence — a seed that fails to diverge raises (the vacuous-seed guard;
# member-ORDER mutations are byte-inert under JCS and are banned as seeds
# by design). The calibration entry proves the divergence detector fires.
#
# Calibration self-proof (2026-08-23, this session): with the report-format
# mutation's expected divergence INVERTED in a throwaway edit (expecting
# byte equality), the harness raised `seeded red did not diverge` — the
# raise path is live. Restored; the shipped entry fires.

Code.require_file("release_identity.exs", __DIR__)

defmodule AgentBlueprintProtocol.VerifierAgreementGate do
  # The single-source runtime floor (shared with the release identity
  # chain via release_identity.exs).
  @node_floor AgentBlueprintProtocol.ReleaseIdentity.verifier_major_floor()

  @root Path.expand("..", __DIR__)
  @corpus "priv/conformance"
  @verifier "verifier"

  def run do
    node = find_node!()

    escript_bytes = run_escript!()
    ts_bytes = run_ts!(node, Path.join(@root, @corpus))

    if escript_bytes != ts_bytes do
      raise """
      report byte drift (repo corpus):
        escript: #{escript_bytes}
        node:    #{ts_bytes}
      """
    end

    IO.puts("agreement: repo corpus byte-identical")

    archive_corpus = build_and_unpack_archive!()
    archive_bytes = run_ts!(node, archive_corpus)

    if escript_bytes != archive_bytes do
      raise """
      report byte drift (archive corpus):
        escript: #{escript_bytes}
        node:    #{archive_bytes}
      """
    end

    IO.puts("agreement: archive corpus byte-identical")

    {self_out, self_status} =
      System.cmd(node, [Path.join([@root, @verifier, "self_checks.ts"])],
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "dev"}]
      )

    unless self_status == 0, do: raise("self-checks failed:\n#{self_out}")
    IO.puts(String.trim_trailing(self_out))

    seeded_reds(node, escript_bytes)
    IO.puts("verifier agreement gate: ok")
  end

  # ---- the agreement runs ---------------------------------------------------------

  defp run_escript! do
    {build_out, build_status} =
      System.cmd("mix", ["escript.build"],
        cd: @root,
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}]
      )

    unless build_status == 0, do: raise("escript build failed:\n#{build_out}")

    {out, status} =
      System.cmd(Path.join(@root, "agent_blueprint_protocol_conformance"), ["--corpus", @corpus],
        cd: @root,
        stderr_to_stdout: true
      )

    unless status == 0, do: raise("escript disagreement over the shipped corpus:\n#{out}")
    out
  end

  defp run_ts!(node, corpus_dir) do
    # The verifier is REPO-side (never shipped in the archive): the script
    # always runs from @root; only the corpus directory moves.
    {out, status} =
      System.cmd(node, [Path.join(@root, "verifier/cli.ts"), "--corpus", corpus_dir],
        cd: @root,
        stderr_to_stdout: true
      )

    unless status == 0, do: raise("TS verifier disagreement:\n#{out}")
    out
  end

  defp build_and_unpack_archive! do
    build_dir =
      Path.join(
        System.tmp_dir!(),
        "abp-verifier-agreement-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(build_dir)
    unpack_dir = Path.join(build_dir, "pkg")

    {out, status} =
      System.cmd("mix", ["hex.build", "--unpack", "--output", unpack_dir],
        cd: @root,
        stderr_to_stdout: true,
        env: [{"MIX_QUIET", "1"}, {"MIX_ENV", "test"}]
      )

    unless status == 0, do: raise("hex archive build failed:\n#{out}")
    Path.join(unpack_dir, "priv/conformance")
  end

  # ---- seeded reds ------------------------------------------------------------------

  @seeded_reds [
    %{
      # DIRECTIONAL disagreement-forcing: every invalid-case code comparison
      # inverts, so the TS side disagrees where the escript agrees — report
      # bytes differ (agreed 86 vs fewer) and the exit flips to 1.
      name: "verdict-comparison-inverted",
      path: "runner.ts",
      from: "    if (!actual.ok) return actual.e === memberString(expected, \"code\");",
      to: "    if (!actual.ok) return actual.e !== memberString(expected, \"code\");",
      expect: :byte_drift
    },
    %{
      # CALIBRATION: a report MEMBER VALUE change must byte-drift (JCS sorts
      # members, so ORDER mutations are inert and banned; the format member
      # is load-bearing content). Proves the divergence detector fires.
      name: "calibration-report-format-drift",
      path: "report.ts",
      from: "const FORMAT = \"agent-blueprint-protocol-conformance-report\";",
      to: "const FORMAT = \"agent-blueprint-protocol-conformance-report-x\";",
      expect: :byte_drift
    },
    %{
      # Window-check deletion must fail the SELF-CHECK battery (the
      # inherited MUST is falsifiable only through the vectors — the
      # corpus ships zero window-deny cases).
      name: "window-check-deleted",
      path: "decode.ts",
      from: "      if (beyondIjsonMax(lexeme)) {",
      to: "      if (false) {",
      expect: :self_check_failure
    }
  ]

  defp seeded_reds(node, baseline_bytes) do
    Enum.each(@seeded_reds, &run_seeded_red(&1, node, baseline_bytes))
  end

  defp run_seeded_red(seed, node, baseline_bytes) do
    scratch =
      Path.join(
        System.tmp_dir!(),
        "abp-verifier-seed-#{seed.name}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(scratch)

    try do
      File.cp_r!(Path.join(@root, @verifier), Path.join(scratch, "verifier"))
      File.cp_r!(Path.join(@root, @corpus), Path.join(scratch, "corpus"))

      mutate_once!(
        Path.join(Path.join(scratch, "verifier"), seed.path),
        seed.from,
        seed.to
      )

      case seed.expect do
        :byte_drift ->
          {out, status} =
            System.cmd(
              node,
              [Path.join(scratch, "verifier/cli.ts"), "--corpus", Path.join(scratch, "corpus")],
              stderr_to_stdout: true
            )

          if out == baseline_bytes do
            raise "seeded red did not diverge: #{seed.name} (vacuous seed or broken detector)"
          end

          # The verdict seed must also flip the exit contract; the format
          # seed may legitimately exit 0 with drifted bytes.
          if seed.name == "verdict-comparison-inverted" and status == 0 do
            raise "seeded red exited 0 despite forced disagreement: #{seed.name}"
          end

        :self_check_failure ->
          {out, status} =
            System.cmd(node, [Path.join(scratch, "verifier/self_checks.ts")],
              stderr_to_stdout: true
            )

          if status == 0 do
            raise "seeded red did not fail self-checks: #{seed.name}\n#{out}"
          end
      end

      IO.puts("seeded red fired: #{seed.name}")
    after
      File.rm_rf!(scratch)
    end
  end

  defp mutate_once!(path, from, to) do
    content = File.read!(path)

    case :binary.match(content, from) do
      {at, _len} ->
        case :binary.match(content, from, [{:scope, {at + 1, byte_size(content) - at - 1}}]) do
          :nomatch ->
            File.write!(path, :binary.replace(content, from, to, [:global]))
            :ok

          _second_match ->
            raise "mutation anchor not unique: #{path}: #{inspect(from)}"
        end

      :nomatch ->
        raise "mutation anchor not found: #{path}: #{inspect(from)}"
    end
  end

  # ---- environment --------------------------------------------------------------------

  defp find_node! do
    executable = if(match?({:win32, _}, :os.type()), do: "node.exe", else: "node")

    case System.find_executable(executable) do
      nil ->
        raise """
        node not found: the verifier agreement gate requires Node >= 24.
        The TS verifier is a hard prerequisite of `mix quality` (recorded,
        user-visible — install node or remove verifier.agreement from quality
        deliberately).
        """

      path ->
        {version_out, 0} = System.cmd(path, ["--version"], stderr_to_stdout: true)
        version_out |> String.trim() |> major!() |> assert_node_version!(path)
        path
    end
  end

  defp major!("v" <> rest), do: rest |> String.split(".") |> hd() |> String.to_integer()
  defp major!(other), do: other |> String.split(".") |> hd() |> String.to_integer()

  defp assert_node_version!(major, _path) when major >= @node_floor, do: :ok

  defp assert_node_version!(major, path),
    do:
      raise("node #{major} at #{path} is below the >= #{@node_floor} requirement (got v#{major})")
end

AgentBlueprintProtocol.VerifierAgreementGate.run()
