defmodule AgentBlueprintProtocol.Architecture.CiTriggerFilterTest do
  @moduledoc """
  CI trigger-filter gate for the docs-only split.

  The heavy CI workflow (`ci.yml`) skips a push that changes only its
  `paths-ignore` paths, to save CI minutes. The lean doc-gates workflow
  (`docs-gates.yml`) triggers on exactly those paths. A docs-only push is
  therefore safe only if every gate that reads, digests, or pins an
  ignored path is one the lean workflow runs.

  The model below classifies every `mix quality` step and every heavy CI
  job: `{:lean, command}` (the lean workflow runs `command`) or
  `{:reads, globs}` (heavy-only; it reads exactly these paths). The
  privacy scan and the secret scan read every tracked path, so both must
  be lean. Script-backed heavy-only steps are cross-checked against their
  source: a doc-path reference in such a script reds the model as stale.

  Goes RED on: an unclassified step or job; a lean step missing from the
  lean workflow; a heavy-only step reading an ignored path (for example
  `lib/**` added to `paths-ignore`, which compile reads); the two path
  lists drifting apart.
  """

  use ExUnit.Case, async: true

  @heavy ".github/workflows/ci.yml"
  @lean ".github/workflows/docs-gates.yml"

  # Builds the Hex archive, which packages the shipped documents, but its
  # verdict reads only the archive's corpus; that every declared package
  # file exists is the publish guard's check, in the lean suite.
  @archive_note :packages_docs_verdict_reads_corpus_only

  @gates %{
    "hex.audit" => {:reads, ["mix.exs", "mix.lock"]},
    "deps.unlock --check-unused" => {:reads, ["mix.exs", "mix.lock"]},
    "deps.audit" => {:reads, ["mix.lock"]},
    "deps.currency" => {:reads, ["mix.exs", "mix.lock", "scripts/check_deps_currency.exs"]},
    "format --check-formatted" =>
      {:reads, [".formatter.exs", "mix.exs", "config/**", "lib/**", "scripts/**", "test/**"]},
    "compile --warnings-as-errors" => {:reads, ["mix.exs", "mix.lock", "config/**", "lib/**"]},
    "credo --strict" => {:reads, ["mix.exs", "config/**", "lib/**", "scripts/**", "test/**"]},
    "test --cover --seed 42" => {:lean, "mix test"},
    "conformance.verify" => {:reads, ["mix.exs", "config/**", "lib/**", "priv/**"]},
    "conformance.mutations" =>
      {:reads, ["mix.exs", "mix.lock", "config/**", "lib/**", "priv/**", "scripts/**"]},
    "kit.build" =>
      {:reads,
       [
         "package.json",
         "package-lock.json",
         "tsconfig.json",
         "verifier/**",
         "priv/**",
         "scripts/build_kit.mjs"
       ]},
    "verifier.agreement" =>
      {:reads,
       ["mix.exs", "package.json", "config/**", "lib/**", "priv/**", "scripts/**", "verifier/**"],
       @archive_note},
    "compatibility.replay" => {:lean, "mix compatibility.replay"},
    "dialyzer" => {:reads, ["mix.exs", "mix.lock", "config/**", "lib/**"]},
    "docs --warnings-as-errors" => {:lean, "mix docs --warnings-as-errors"},
    "spec.extraction" => {:lean, "mix spec.extraction"},
    "grammar.derivation" => {:lean, "mix grammar.derivation"},
    "registry.equality" => {:lean, "mix registry.equality"},
    "release.asset" =>
      {:reads, ["mix.exs", "config/**", "lib/**", "priv/**", "scripts/**", "verifier/**"],
       @archive_note},
    "release.candidate" => {:lean, "mix release.candidate"},
    "ci:workflow-syntax" => {:reads, [".github/workflows/**"]},
    "ci:secret-scan" =>
      {:lean, "gitleaks/v8@83d9cd684c87d95d656c1458ef04895a7f1cbd8e git --config"},
    "ci:spec-extraction" => {:lean, "filter-repo --path spec/ --path priv/conformance"},
    # The same suite the lean workflow runs on the dev pin; the doc-reading
    # tests are toolchain-independent file reads.
    "ci:compatibility" => {:lean, "mix test"},
    # Its steps are the quality steps above plus the kit build.
    "ci:quality" => {:reads, []}
  }

  @doc_marker ~r/\.md\b|"docs\/|documentation\/|"spec\//

  test "the privacy scan and the secret scan read every tracked path" do
    privacy = File.read!("test/architecture/public_surface_privacy_test.exs")
    assert privacy =~ ~s(["ls-files", "-z"]), "the privacy scan no longer walks git ls-files"

    assert File.read!(@heavy) =~ ~r/gitleaks.*\sgit\s/,
           "the CI secret scan no longer runs gitleaks over the git history"

    # Both read everything, so both must run in the lean workflow.
    assert {:lean, "mix test"} = @gates["test --cover --seed 42"]
    assert {:lean, _} = @gates["ci:secret-scan"]
  end

  test "every quality step and heavy CI job is classified for the docs-only split" do
    steps = Enum.map(Mix.Project.config()[:aliases][:quality], &to_string/1)

    jobs =
      for [_, job] <- Regex.scan(~r/^  ([a-z][a-z0-9-]*):\n/m, jobs_block(@heavy)),
          do: "ci:" <> job

    assert Enum.sort(steps ++ jobs) == Enum.sort(Map.keys(@gates)),
           "unclassified or stale entries: " <>
             inspect({(steps ++ jobs) -- Map.keys(@gates), Map.keys(@gates) -- (steps ++ jobs)})
  end

  test "the lean workflow runs every lean gate" do
    lean = File.read!(@lean)

    missing =
      for {gate, {:lean, command}} <- @gates, not String.contains?(lean, command), do: gate

    assert missing == [], "lean gates the doc-gates workflow does not run: #{inspect(missing)}"
  end

  test "no heavy-only gate reads a path the heavy workflow ignores" do
    globs = paths(File.read!(@heavy), "paths-ignore")
    {tracked, 0} = System.cmd("git", ["ls-files", "-z"])

    ignored =
      for path <- String.split(tracked, <<0>>, trim: true), matches_any?(path, globs), do: path

    offenders =
      for {gate, {:reads, reads}} <- normalized_gates(),
          path <- ignored,
          matches_any?(path, reads),
          uniq: true,
          do: {gate, path}

    assert offenders == [],
           "heavy-only gates read paths a docs-only push skips (#{length(offenders)}), " <>
             "e.g. #{inspect(Enum.take(offenders, 8))}"
  end

  test "heavy-only scripts reference no documentation path" do
    assert File.read!("scripts/check_release_candidate.exs") =~ @doc_marker,
           "the doc-path marker no longer matches a known doc-reading script"

    aliases = Mix.Project.config()[:aliases]

    offenders =
      for {gate, {:reads, _}} <- normalized_gates(),
          step <- List.wrap(aliases[String.to_atom(gate)]),
          [_, script] <- Regex.scan(~r/(scripts\/[\w.]+\.(?:exs|mjs))/, to_string(step)),
          File.read!(script) =~ @doc_marker,
          do: {gate, script}

    assert offenders == [], "heavy-only scripts read documentation paths: #{inspect(offenders)}"
  end

  test "the lean workflow triggers on exactly the paths the heavy workflow ignores" do
    heavy = paths(File.read!(@heavy), "paths-ignore")
    lean = paths(File.read!(@lean), "paths")

    assert heavy != [], "the heavy workflow has no docs-only paths-ignore"
    assert lean == heavy, "trigger lists differ: heavy #{inspect(heavy)}, lean #{inspect(lean)}"
    assert File.read!(@lean) =~ ~r/push:\n\s+branches:\n\s+- main\n\s+paths:/
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

  defp normalized_gates do
    Enum.map(@gates, fn
      {gate, {:reads, reads, _note}} -> {gate, {:reads, reads}}
      other -> other
    end)
  end

  defp jobs_block(path) do
    [_, jobs] = String.split(File.read!(path), "\njobs:\n", parts: 2)
    jobs
  end

  # The inline list after `key:` (the only form these workflows use).
  defp paths(workflow, key) do
    case Regex.run(~r/^\s+#{key}:\s*\[([^\]]*)\]/m, workflow) do
      [_, list] ->
        list
        |> String.split(",", trim: true)
        |> Enum.map(&(&1 |> String.trim() |> String.trim("'") |> String.trim("\"")))

      nil ->
        []
    end
  end

  defp matches_any?(path, globs), do: Enum.any?(globs, &Regex.match?(glob_regex(&1), path))

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
