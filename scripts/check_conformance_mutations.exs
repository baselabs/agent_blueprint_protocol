# The conformance mutation gate.
#
#   MIX_ENV=test mix run --no-start scripts/check_conformance_mutations.exs
#
# For each entry: isolate a scratch copy of the repo, apply exactly ONE
# source mutation at a one-match anchor, run `mix conformance.verify`, and
# raise `mutation survived` when the corpus STAYS GREEN — a vacuous case set
# is precisely the quiet failure this gate exists to kill. Baseline-green
# runs first per unique command (a deleted/drifted target scoring a red as
# "caught" is the false-green BAP recorded). The calibration entry proves
# the raise path live.
#
# Calibration self-proof (2026-08-23, this session): with the
# `duplicate-member-check-removal` entry's command inverted in a throwaway
# scratch (expecting exit 0), the mutated corpus verified GREEN and the
# battery raised `mutation survived: duplicate-member-check-removal` — the
# raise path is not decorative. Restored; the shipped entry is caught.

defmodule AgentBlueprintProtocol.ConformanceMutationGate do
  @root Path.expand("..", __DIR__)

  @mutations [
    %{
      # The strict Ed25519 signature rule removed (R canonical and not
      # small-order, S < L, checked before :crypto.verify): the key-holder
      # R = identity, S = k*a case verifies on the backend's cofactorless
      # equation and disagrees with its expected denial.
      name: "strict-signature-rule-removed",
      path: "lib/agent_blueprint_protocol/signature.ex",
      from:
        "      not strict_signature?(parts.signature) ->\n        {:error, :signature_not_verified}\n\n",
      to: "",
      command: ["mix", "conformance.verify"]
    },
    %{
      # Every matched key counts as usable Ed25519: the small-order, y = p, and
      # off-curve key cases stop denying signature_algorithm_unsupported, and the
      # identity-key forgery (R = [r]B, S = r) verifies on the backend's equation.
      name: "strict-key-usable-check-removed",
      path: "lib/agent_blueprint_protocol/signature.ex",
      from: "          strict_point?(encoding)\n",
      to: "          _ = encoding\n          true\n",
      command: ["mix", "conformance.verify"]
    },
    %{
      # S < L dropped: the S = L and S + L cases' pinned strict predicate
      # (false) disagrees, whatever the backend concludes.
      name: "strict-scalar-bound-removed",
      path: "lib/agent_blueprint_protocol/signature.ex",
      from: "    s < @ed_l and strict_point?(r)",
      to: "    _ = s\n    strict_point?(r)",
      command: ["mix", "conformance.verify"]
    },
    %{
      # y >= p accepted: the y = p key and the non-canonical R cases flip.
      name: "strict-canonical-y-removed",
      path: "lib/agent_blueprint_protocol/signature.ex",
      from: "    if y >= @ed_p do",
      to: "    if false do",
      command: ["mix", "conformance.verify"]
    },
    %{
      # The y = 0 (order-4) test dropped: the order-4 key and R cases flip.
      name: "strict-small-order-y-zero-removed",
      path: "lib/agent_blueprint_protocol/signature.ex",
      from: "    y == 0 or y_sqrt_m1 == x or y_sqrt_m1 == @ed_p - x",
      to: "    y_sqrt_m1 == x or y_sqrt_m1 == @ed_p - x",
      command: ["mix", "conformance.verify"]
    },
    %{
      # The y*sqrt(-1) = x order-8 test dropped: two order-8 cases flip.
      name: "strict-small-order-plus-x-removed",
      path: "lib/agent_blueprint_protocol/signature.ex",
      from: "    y == 0 or y_sqrt_m1 == x or y_sqrt_m1 == @ed_p - x",
      to: "    y == 0 or y_sqrt_m1 == @ed_p - x",
      command: ["mix", "conformance.verify"]
    },
    %{
      # The y*sqrt(-1) = -x order-8 test dropped: the other two order-8 cases flip.
      name: "strict-small-order-minus-x-removed",
      path: "lib/agent_blueprint_protocol/signature.ex",
      from: "    y == 0 or y_sqrt_m1 == x or y_sqrt_m1 == @ed_p - x",
      to: "    y == 0 or y_sqrt_m1 == x",
      command: ["mix", "conformance.verify"]
    },
    %{
      # The root == 0 branch never matches: the sign-set identity and order-2
      # encodings (non-canonical R) decode as usable points and flip.
      name: "strict-root-zero-branch-removed",
      path: "lib/agent_blueprint_protocol/signature.ex",
      from: "        0 ->\n          # root == 0 happens",
      to: "        -1 ->\n          # root == 0 happens",
      command: ["mix", "conformance.verify"]
    },
    %{
      # One digit of sqrt(-1) changed: square roots and the order-8 tests go
      # wrong, so honest keys or the order-8 cases flip.
      name: "strict-sqrt-m1-digit",
      path: "lib/agent_blueprint_protocol/signature.ex",
      from: "  @ed_sqrt_m1 19_681_161_376",
      to: "  @ed_sqrt_m1 19_681_161_377",
      command: ["mix", "conformance.verify"]
    },
    %{
      # One digit of L changed (L - 1): the S = L - 1 case's pinned strict
      # predicate (true) disagrees.
      name: "strict-group-order-digit",
      path: "lib/agent_blueprint_protocol/signature.ex",
      from: "_285_454_250_989\n  @ed_p",
      to: "_285_454_250_988\n  @ed_p",
      command: ["mix", "conformance.verify"]
    },
    %{
      # The intersection's meet flips narrowest→widest: the operational
      # widening case's effective (pinned to the narrow 3s) disagrees.
      name: "intersect-min-to-max",
      path: "lib/agent_blueprint_protocol/bounds_algebra.ex",
      from: "      :pos_integer ->\n        Enum.min(values)",
      to: "      :pos_integer ->\n        Enum.max(values)",
      command: ["mix", "conformance.verify"]
    },
    %{
      # Duplicate members load as-last-wins instead of denying: the
      # invalid_duplicate case agrees as valid -> disagreement. Also the
      # CALIBRATION entry (see the module doc's self-proof).
      name: "duplicate-member-check-removal",
      path: "lib/agent_blueprint_protocol/json.ex",
      from: "    if keys != Enum.uniq(keys), do: throw({:abp_error, :duplicate_member})",
      to: "    if false, do: throw({:abp_error, :duplicate_member})",
      command: ["mix", "conformance.verify"]
    },
    %{
      # Byte-order member sort instead of UTF-16 code units: the BMP/SFP
      # boundary-near and sort-order tamper cases disagree on encoded bytes.
      name: "utf16-sort-key-drop",
      path: "lib/agent_blueprint_protocol/canonicalization.ex",
      from: "{:ok, Enum.sort_by(members, fn {name, _} -> sort_key(name) end)}",
      to: "{:ok, Enum.sort_by(members, fn {name, _} -> name end)}",
      command: ["mix", "conformance.verify"]
    },
    %{
      # Padded base64url accepted: the padded case's expected
      # :base64url_padded never fires (it denies :base64url_invalid or
      # decodes) -> disagreement either way.
      name: "padded-base64url-accept",
      path: "lib/agent_blueprint_protocol/base64url.ex",
      from: "      String.contains?(input, \"=\") -> {:error, :base64url_padded}",
      to: "      false -> {:error, :base64url_padded}",
      command: ["mix", "conformance.verify"]
    },
    %{
      # Revision outside the supported set passes negotiation: the
      # above-max case (revision 2 vs support {1}) verifies green instead
      # of denying -> disagreement.
      name: "revision-max-plus-one",
      path: "lib/agent_blueprint_protocol/negotiation.ex",
      from:
        "      not MapSet.member?(support.revisions, revision) -> {:error, :protocol_revision_unsupported}",
      to: "      false -> {:error, :protocol_revision_unsupported}",
      command: ["mix", "conformance.verify"]
    },
    %{
      # The obligation meet flips strictest→loosest: the obligation-varying corpus
      # cases (obligation varies across sources) disagree — the strict-
      # blueprint valid case clamps to a denial, and the authority-widening
      # case verifies green under-narrowed (the privilege-escalation
      # direction). Invisible before those cases existed (all-equal
      # obligations made min==max).
      name: "obligation-meet-min",
      path: "lib/agent_blueprint_protocol/bounds_algebra.ex",
      from:
        "      {:obligation, family} ->\n        Enum.max_by(values, &index_of(@lattices[family], &1))",
      to:
        "      {:obligation, family} ->\n        Enum.min_by(values, &index_of(@lattices[family], &1))",
      command: ["mix", "conformance.verify"]
    },
    %{
      # CALIBRATION-class sibling: mutating the CORPUS's own expectation
      # (not the implementation) must also go red — the gate observes
      # corpus drift, not just implementation drift.
      name: "calibration-corpus-expectation-flip",
      path: "priv/conformance/cases/json-decode.json",
      from: "\"code\":\"duplicate_member\"",
      to: "\"code\":\"trailing_bytes\"",
      command: ["mix", "conformance.verify"]
    }
  ]

  @copy_paths [
    ".formatter.exs",
    "lib",
    "mix.exs",
    "mix.lock",
    "priv",
    "scripts"
  ]

  def run do
    Enum.each(@mutations, &run_mutation/1)
    IO.puts("conformance mutation gate: ok mutations=#{length(@mutations)}")
  end

  defp run_mutation(mutation) do
    baseline_green!(mutation.command)

    scratch =
      Path.join(
        System.tmp_dir!(),
        "abp-conformance-mutation-#{mutation.name}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(scratch)

    try do
      Enum.each(@copy_paths, &copy_path(&1, scratch))
      File.ln_s!(Path.join(@root, "deps"), Path.join(scratch, "deps"))
      copy_build(scratch)
      mutate_once!(Path.join(scratch, mutation.path), mutation.from, mutation.to)

      {output, status} =
        System.cmd(hd(mutation.command), tl(mutation.command),
          cd: scratch,
          stderr_to_stdout: true,
          env: [{"MIX_ENV", "dev"}]
        )

      if status == 0 do
        raise "mutation survived: #{mutation.name}\n#{output}"
      end

      IO.puts("mutation caught: #{mutation.name}")
    after
      File.rm_rf!(scratch)
    end
  end

  # Baseline non-vacuity: the UNMUTATED command must run green in a clean
  # scratch, or a red cannot be attributed to the mutation (the deleted-test
  # false-green). Cached per unique command per battery run.
  defp baseline_green!(command) do
    key = {:baseline_green, command}

    if Process.get(key) != :ok do
      scratch =
        Path.join(
          System.tmp_dir!(),
          "abp-conformance-baseline-#{System.unique_integer([:positive, :monotonic])}"
        )

      File.mkdir_p!(scratch)

      try do
        Enum.each(@copy_paths, &copy_path(&1, scratch))
        File.ln_s!(Path.join(@root, "deps"), Path.join(scratch, "deps"))
        copy_build(scratch)

        {output, status} =
          System.cmd(hd(command), tl(command),
            cd: scratch,
            stderr_to_stdout: true,
            env: [{"MIX_ENV", "dev"}]
          )

        if status != 0 do
          raise "baseline not green: the unmutated command exited #{status}\n#{output}"
        end

        Process.put(key, :ok)
      after
        File.rm_rf!(scratch)
      end
    end

    :ok
  end

  defp copy_path(relative, scratch) do
    source = Path.join(@root, relative)
    target = Path.join(scratch, relative)
    File.mkdir_p!(Path.dirname(target))
    {:ok, _copied} = File.cp_r(source, target)
  end

  defp copy_build(scratch) do
    for env <- ~w(dev test) do
      source = Path.join(@root, "_build/#{env}")

      if File.dir?(source) do
        target = Path.join(scratch, "_build/#{env}")
        File.mkdir_p!(Path.dirname(target))
        {:ok, _} = File.cp_r(source, target)
      end
    end
  end

  defp mutate_once!(path, source, replacement) do
    contents = File.read!(path)

    if count(contents, source) != 1 do
      raise "mutation anchor is not exact: #{path}"
    end

    File.write!(path, String.replace(contents, source, replacement))
  end

  defp count(contents, source) do
    length(:binary.matches(contents, source))
  end
end

AgentBlueprintProtocol.ConformanceMutationGate.run()
