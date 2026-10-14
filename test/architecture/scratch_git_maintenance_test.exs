defmodule AgentBlueprintProtocol.Architecture.ScratchGitMaintenanceTest do
  @moduledoc """
  Scratch-repository maintenance gate: every script or test that runs a git
  command which starts git's automatic maintenance (`commit`, `merge`,
  `fetch`, `pull`, `am`, `rebase`, `clone`) also turns that maintenance off
  (`maintenance.auto` false) for the repository it drives.

  From git 2.54 the default maintenance strategy is "geometric", and those
  commands start `git maintenance run --auto --detach`: a repack that keeps
  writing into `.git` after the command returns. A throwaway repository
  removed with `File.rm_rf!/1` then races that process; the release-candidate
  reprove failed on hosted CI that way (`could not remove files and
  directories recursively ... file already exists`).

  Goes RED on: a file that drives such a git command without disabling
  automatic maintenance; a scan that no longer sees the two known drivers
  (the release-candidate reprove and the privacy-gate test), which would
  make the gate vacuous.
  """

  use ExUnit.Case, async: true

  @roots ["scripts", "test"]
  @self "test/architecture/scratch_git_maintenance_test.exs"
  @known_drivers [
    "scripts/check_release_candidate.exs",
    "test/architecture/public_surface_privacy_test.exs"
  ]

  # A git argument list whose first element is a subcommand that runs
  # automatic maintenance when it finishes.
  @maintenance_subcommand ~r/\[\s*"(commit|merge|fetch|pull|am|rebase|clone)"/

  test "every scratch git repository that commits disables automatic maintenance" do
    drivers =
      for root <- @roots,
          path <- Path.wildcard(Path.join(root, "**/*.{ex,exs}")),
          path != @self,
          File.read!(path) =~ @maintenance_subcommand,
          do: path

    assert Enum.sort(@known_drivers -- drivers) == [],
           "the scan no longer sees the known git drivers #{inspect(@known_drivers -- drivers)}"

    # The setting itself, as a quoted git config key (a comment naming it
    # does not count).
    offenders = Enum.reject(drivers, &(File.read!(&1) =~ ~s("maintenance.auto")))

    assert offenders == [],
           "these files run git commands that start detached background maintenance " <>
             "without setting maintenance.auto false: #{inspect(offenders)}"
  end
end
