defmodule AgentBlueprintProtocol.Architecture.CiTriggerFilterTest do
  @moduledoc """
  CI trigger-filter gate: a push that the CI workflow's `paths-ignore`
  skips runs no gate at all, so an ignored path must be one no gate reads.

  The gate-read set is derived, not listed: the public-surface privacy
  scan reads every tracked file (`git ls-files`) and the CI secret scan
  runs gitleaks over the full history, so every tracked path is read by a
  gate. Both facts are asserted from the sources below; if either scan
  ever narrows, this gate must be revisited rather than silently widened.

  Goes RED on: a `paths-ignore` glob that matches any tracked path (for
  example `**/*.md`, which skipped CI for the specification, the
  CHANGELOG, the guides, and the verifier's runner contract).
  """

  use ExUnit.Case, async: true

  @workflow ".github/workflows/ci.yml"

  test "the privacy scan and the secret scan read every tracked path" do
    privacy = File.read!("test/architecture/public_surface_privacy_test.exs")
    assert privacy =~ ~s(["ls-files", "-z"]), "the privacy scan no longer walks git ls-files"

    workflow = File.read!(@workflow)

    assert workflow =~ ~r/gitleaks.*\sgit\s/,
           "the CI secret scan no longer runs gitleaks over the git history"
  end

  test "no CI paths-ignore glob skips a path a gate reads" do
    globs = paths_ignore(File.read!(@workflow))
    {tracked, 0} = System.cmd("git", ["ls-files", "-z"])
    gate_read = String.split(tracked, <<0>>, trim: true)

    skipped =
      for path <- gate_read, glob <- globs, Regex.match?(glob_regex(glob), path), uniq: true do
        {glob, path}
      end

    assert skipped == [],
           "CI paths-ignore skips pushes that change gate-read paths (" <>
             "#{length(skipped)} matches), e.g. #{inspect(Enum.take(skipped, 8))}"
  end

  test "the landing page deploys only from a release tag or a manual dispatch" do
    # The site names the package version; a deploy from a main-branch push
    # would publish a version Hex does not have yet.
    pages = File.read!(".github/workflows/pages.yml")
    [_, on_block] = Regex.run(~r/\non:\n((?:  [^\n]*\n|\s*\n)+)/, pages)

    refute on_block =~ ~r/branches:/,
           "pages.yml deploys on a branch push; it must deploy only on a release tag"

    assert on_block =~ ~r/tags:\s*\[\s*"v\*"\s*\]/,
           "pages.yml must deploy on release tags (v*)"

    assert on_block =~ ~r/workflow_dispatch:/, "pages.yml must keep a manual dispatch"
  end

  # The `paths-ignore` entries of every trigger, inline (`[a, b]`) or block
  # (`- a`) form.
  defp paths_ignore(workflow) do
    inline =
      ~r/paths-ignore:\s*\[([^\]]*)\]/
      |> Regex.scan(workflow)
      |> Enum.flat_map(fn [_, list] -> String.split(list, ",", trim: true) end)

    block =
      ~r/paths-ignore:\s*\n((?:\s+-\s*[^\n]+\n)+)/
      |> Regex.scan(workflow)
      |> Enum.flat_map(fn [_, lines] ->
        for line <- String.split(lines, "\n", trim: true),
            do: String.replace(line, ~r/^\s+-\s*/, "")
      end)

    (inline ++ block)
    |> Enum.map(&(&1 |> String.trim() |> String.trim("'") |> String.trim("\"")))
    |> Enum.reject(&(&1 == ""))
  end

  # GitHub filter-pattern subset: `**` crosses directories, `*` does not.
  defp glob_regex(glob) do
    body =
      glob
      |> Regex.escape()
      |> String.replace("\\*\\*/", "(?:.*/)?")
      |> String.replace("\\*\\*", ".*")
      |> String.replace("\\*", "[^/]*")

    Regex.compile!("\\A" <> body <> "\\z")
  end
end
