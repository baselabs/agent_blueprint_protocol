# The compatibility replay gate: certifies the manifest's compatibility
# claims (prior_census_verdicts, verification_semantics_version's
# equivalence span) and the release history from LIVE repository state.
#
#   mix compatibility.replay
#
# 1. Tag census map: every manifest-era release tag (one carrying
#    priv/release-metadata.json — any git failure or an empty tag set
#    REFUSES loudly), grouped by the census digest each tag's manifest
#    names. The group HEAD's census is loaded and its RECOMPUTED
#    identity asserted equal to that name (the compatibility matrix
#    keys on the recomputed digest); sibling tags of a group share the
#    census by that verified name, and each history row binds to its
#    own tag's tree through that tag's manifest.
# 2. Prior-census replay: each distinct census loads through
#    Corpus.load_prior_census (the census's OWN index integrity; the two
#    current-state couplings suspended) and runs under the current
#    Runner. Disagreements are classified: an extension-surface
#    disagreement is explained ONLY by a spec/registry/registry.json
#    diff between the census's release and HEAD naming a namespace the
#    case's input carries; every other disagreement is unexplained.
# 3. Claim-vs-evidence, both checkable directions: "equivalent" with any
#    disagreement reds; "diverged_by_registry_census" with zero
#    disagreements or any UNEXPLAINED one reds; "not_equivalent" is
#    authored intent — never inverse-checked, but a not_equivalent claim
#    whose census's history rows all carry the CURRENT semantics version
#    reds as a self-contradiction; an unclaimed census reds; a claim
#    naming no discoverable census reds; an unknown verdict word reds.
# 4. History verification: every PRIOR release's row is verified against
#    DERIVED state — corpus digest from the loaded census's recomputed
#    identity, registry digest from the census index bytes, specification
#    digest recomputed over the tag's framed spec/ walk — and every prior
#    manifest-era tag has a row, both directions. The CURRENT release's
#    row is verified against the live manifest by the release-candidate
#    check (its tag exists only after release; the row gains its tag
#    verification at the next release). The committed history must be a
#    PREFIX of the working-tree history (append-only).
# 5. Kit replay: the TS verifier replays each PRIOR census through
#    --prior-corpus; its report must byte-equal the Elixir side's and its
#    exit must equal the report's own exit_status. (The current census's
#    TS agreement is the verifier.agreement gate's own duty.)
# 6. The classifier self-check proves the divergence classifier's three
#    outcomes on synthetic inputs every run — the vacuity guard for the
#    arm no real registry divergence exercises yet.
#
# Seeded reds (self-proving, the agreement-gate pattern): claim flips
#    (including a self-contradictory not_equivalent claim), a tampered
#    census file, a tampered history row, and both tag-absent refusal
#    arms (git failure in a non-repository directory; an empty tag set
#    in a bare repository). The census-dependent claim seeds run whenever
#    a prior census exists (the real repository always carries one).
#    Each must raise; a seed that stays green raises.
#
# Tag-absent posture: this gate needs git release tags. Where they are
# absent (shallow clone, an unpacked archive, a tag-less scratch) it
# REFUSES with a named reason — never a silent skip.
# ABP_COMPATIBILITY_REPLAY=off is the named operator override for
# tag-less environments; it prints loudly and is NEVER a green claim
# (ABP_RC_REPROVE=off's rule).

Code.require_file("release_identity.exs", __DIR__)
Code.require_file("gate_node.exs", __DIR__)

defmodule AgentBlueprintProtocol.CompatibilityReplayGate do
  alias AgentBlueprintProtocol.Conformance.{Corpus, Report, Runner}

  @history_path "priv/release-history.json"
  @history_format "agent-blueprint-protocol-release-history"
  @verdicts ~w(equivalent diverged_by_registry_census not_equivalent)
  @registry_surfaces ~w(extension.resolve negotiation.negotiate)
  @registry_path "spec/registry/registry.json"

  def run do
    if System.get_env("ABP_COMPATIBILITY_REPLAY") == "off" do
      IO.puts(
        "compatibility replay: SKIPPED — ABP_COMPATIBILITY_REPLAY=off names an " <>
          "operator override, never a green claim"
      )
    else
      expected = AgentBlueprintProtocol.ReleaseIdentity.expected_metadata()
      tags = manifest_tags!(nil)
      claims = expected["prior_census_verdicts"]
      current_digest = expected["corpus_digest"]

      censuses =
        tags
        |> census_groups()
        |> Enum.map(&replay_census(&1, current_digest))

      rows = read_history_rows!()

      findings =
        claim_findings(censuses, claims, rows, expected["verification_semantics_version"]) ++
          history_findings(tags, censuses, rows)

      if findings != [],
        do: raise("compatibility replay: FAILED\n\n" <> Enum.join(findings, "\n"))

      replay_kit!(censuses)
      classifier_self_check!()
      seeded_reds!(censuses, tags, claims)

      prior = Enum.count(censuses, &(!&1.current))
      prior_word = if(prior == 1, do: "census", else: "censuses")

      IO.puts(
        "compatibility replay: ok (#{length(tags)} manifest-era tags, #{prior} prior #{prior_word})"
      )
    end
  end

  # ---- tag census map -----------------------------------------------------------

  # Every release tag that carries a manifest (the manifest era). Any git
  # failure — or an empty result — refuses loudly: a tag-less checkout
  # cannot support this gate.
  def manifest_tags!(cwd) do
    cd = if(cwd, do: [cd: cwd], else: [])

    # The listing merges stderr (its failure detail belongs in the
    # refusal); the per-tag CONTENT read does not (a stray stderr byte
    # on a successful read would splice into Jason.decode!).
    tags =
      case System.cmd("git", ["tag", "-l", "v*"], [stderr_to_stdout: true] ++ cd) do
        {listing, 0} ->
          listing
          |> String.split("\n", trim: true)
          |> Enum.sort()
          |> Enum.flat_map(fn tag ->
            case System.cmd("git", ["show", "#{tag}:priv/release-metadata.json"], cd) do
              {out, 0} -> [{tag, Jason.decode!(out)}]
              _other -> []
            end
          end)

        {out, status} ->
          raise refusal("git tag listing exited #{status}", out)
      end

    if tags == [], do: raise(refusal("no manifest-era release tags found", ""))

    tags
  end

  defp refusal(reason, detail) do
    """
    compatibility replay: refused — #{reason}.
    The gate certifies claims against released censuses; a tag-less or
    non-repository checkout cannot support it (fetch tags, or name the
    override ABP_COMPATIBILITY_REPLAY=off, which is never a green claim).
    #{detail}
    """
  end

  # One entry per DISTINCT census digest, carrying every release tag that
  # shipped it, newest-first ("newest" compares version TUPLES —
  # lexicographic tag order lies from 0.10.0 on). The digest key is the
  # tag manifest's CLAIM; replay_census replaces it with the recomputed
  # census identity after asserting the two agree.
  defp census_groups(tags) do
    tags
    |> Enum.reduce(%{}, fn {tag, manifest}, groups ->
      Map.update(
        groups,
        manifest["corpus_digest"],
        %{digest: manifest["corpus_digest"], tags: [tag]},
        fn group ->
          %{group | tags: [tag | group.tags]}
        end
      )
    end)
    |> Enum.map(fn {_digest, group} ->
      %{group | tags: Enum.sort_by(group.tags, &version_tuple/1, :desc)}
    end)
    |> Enum.sort_by(&(&1.tags |> hd() |> version_tuple()), :desc)
  end

  defp version_tuple(tag) do
    tag
    |> String.trim_leading("v")
    |> String.split(".")
    |> Enum.map(fn part ->
      case Integer.parse(part) do
        {n, _rest} -> n
        :error -> 0
      end
    end)
    |> List.to_tuple()
  end

  # ---- census replay --------------------------------------------------------------

  defp replay_census(group, current_digest) do
    tag = hd(group.tags)
    map = census_map_at(tag)

    case Corpus.load_prior_census(map) do
      {:ok, corpus} ->
        unless corpus.identity == group.digest do
          raise """
          compatibility replay: census at #{tag} recomputes to #{corpus.identity},
          but the tag's manifest claims #{group.digest} — the manifest's census
          claim is not the census (the compatibility matrix keys on the
          RECOMPUTED digest).
          """
        end

        results = Runner.run(corpus)

        disagreements =
          corpus.cases
          |> Enum.zip(results)
          |> Enum.flat_map(fn {{_path, case_objs}, {_result_path, file_results}} ->
            Enum.zip(case_objs, file_results)
          end)
          |> Enum.reject(fn {_case_obj, result} -> result.agree end)
          |> Enum.map(fn {case_obj, _result} -> case_obj end)

        changed = changed_namespaces(tag)
        {explained, unexplained} = classify(disagreements, changed)

        Map.merge(group, %{
          digest: corpus.identity,
          current: corpus.identity == current_digest,
          map: map,
          corpus: corpus,
          results: results,
          changed_namespaces: changed,
          explained: explained,
          unexplained: unexplained
        })

      {:error, error} ->
        raise """
        compatibility replay: census claimed #{group.digest} at #{tag} failed its OWN
        integrity chain under load_prior_census: #{inspect(error.code)} #{inspect(error.subject)}
        """
    end
  end

  defp census_map_at(tag) do
    index = git!(["show", "#{tag}:priv/conformance/index.json"])

    index
    |> Jason.decode!()
    |> Map.get("files")
    |> Enum.map(& &1["path"])
    |> Enum.reduce(%{"index.json" => index}, fn path, acc ->
      Map.put(acc, path, git!(["show", "#{tag}:priv/conformance/#{path}"]))
    end)
  end

  # A namespace is CHANGED when its registry entry differs between the
  # census's release and HEAD — added, removed, or edited.
  defp changed_namespaces(tag) do
    at_tag = registry_at(tag)
    at_head = registry_at_head()

    (Map.keys(at_tag) ++ Map.keys(at_head))
    |> Enum.uniq()
    |> Enum.filter(fn ns -> Map.get(at_tag, ns) != Map.get(at_head, ns) end)
    |> MapSet.new()
  end

  defp registry_at(tag), do: git!(["show", "#{tag}:#{@registry_path}"]) |> read_registry()

  defp registry_at_head, do: File.read!(@registry_path) |> read_registry()

  defp read_registry(bytes) do
    bytes
    |> Jason.decode!()
    |> Map.get("entries", [])
    |> Enum.into(%{}, fn entry -> {entry["namespace"], entry} end)
  end

  # The divergence classifier: an extension-surface disagreement whose
  # input carries a CHANGED namespace is registry-explained; everything
  # else is unexplained. Pure — proven by the self-check every run.
  def classify(disagreements, changed) do
    changed_list = MapSet.to_list(changed)

    Enum.split_with(disagreements, fn case_obj ->
      case_obj["surface"] in @registry_surfaces and
        Enum.any?(changed_list, &String.contains?(Jason.encode!(case_obj["input"]), &1))
    end)
  end

  # ---- claim-vs-evidence -----------------------------------------------------------

  def claim_findings(censuses, claims, rows, current_semantics) do
    priors = censuses |> Enum.reject(& &1.current) |> Map.new(&{&1.digest, &1})

    semantics_by_version =
      Map.new(rows, &{&1["package_version"], &1["verification_semantics_version"]})

    Enum.flat_map(priors, fn {_digest, census} ->
      case Map.get(claims, census.digest) do
        nil ->
          ["claim: prior census #{census.digest} (at #{hd(census.tags)}) carries no verdict"]

        "not_equivalent" ->
          not_equivalent_findings(census, semantics_by_version, current_semantics)

        "equivalent" ->
          for case_obj <- census.explained ++ census.unexplained do
            "claim: #{census.digest} is claimed equivalent but case " <>
              inspect(case_obj["id"]) <> " disagrees at #{hd(census.tags)}"
          end

        "diverged_by_registry_census" ->
          divergence_findings(census)

        _other ->
          ["claim: unknown verdict word for #{census.digest}"]
      end
    end) ++
      for(
        digest <- Map.keys(claims) -- Map.keys(priors),
        do: "claim: #{digest} names no discoverable prior census (stale claim?)"
      ) ++
      for(
        {digest, verdict} <- claims,
        verdict not in @verdicts,
        do: "claim: unknown verdict word #{inspect(verdict)} for #{digest}"
      )
  end

  # not_equivalent is authored intent — never inverse-checked against the
  # replay — but a self-contradiction IS mechanically detectable: if every
  # release of that census records the CURRENT semantics version, no bump
  # separates this release from that census and the break claim is stale.
  defp not_equivalent_findings(census, semantics_by_version, current_semantics) do
    recorded =
      census.tags
      |> Enum.map(&Map.get(semantics_by_version, version_of(&1)))
      |> Enum.uniq()

    if recorded == [current_semantics] do
      [
        "claim: #{census.digest} is claimed not_equivalent but every one of its " <>
          "history rows records the current semantics version #{current_semantics} — " <>
          "bump the release's semantics version or fix the claim"
      ]
    else
      []
    end
  end

  defp version_of("v" <> rest), do: rest

  defp divergence_findings(%{explained: [], unexplained: []}),
    do: ["claim: census is claimed diverged_by_registry_census but replays clean"]

  defp divergence_findings(census) do
    for case_obj <- census.unexplained do
      "claim: divergence on " <>
        inspect(case_obj["id"]) <> " is not explained by any changed namespace"
    end
  end

  # ---- history verification ----------------------------------------------------------

  # Every PRIOR release's row is verified against DERIVED state: the
  # loaded census's recomputed corpus digest, the census index's own
  # registry digest, and the spec digest recomputed from the tag's tree.
  # The current release's row is the release-candidate check's static
  # arm (the tag exists only after release). The committed history must
  # be a PREFIX of the working-tree history — append-only.
  def history_findings(tags, censuses, rows) do
    current = Mix.Project.config()[:version] |> to_string()
    census_by_tag = census_by_tag(tags, censuses)
    row_versions = Enum.map(rows, & &1["package_version"])

    duplicates =
      if length(Enum.uniq(row_versions)) != length(row_versions),
        do: ["history: duplicate package_version rows"],
        else: []

    format =
      if format_ok?(),
        do: [],
        else: ["history: #{@history_path} carries a wrong format member"]

    ordering =
      if row_versions == Enum.sort_by(row_versions, &version_tuple(&1)),
        do: [],
        else: ["history: rows are not in ascending release order"]

    row_findings =
      Enum.flat_map(rows, fn row ->
        version = row["package_version"]

        if version == current do
          []
        else
          case tag_for_version(tags, version) do
            nil ->
              ["history: row #{version} names no release tag"]

            tag ->
              census = Map.fetch!(census_by_tag, tag)
              index_registry = census.corpus.index["registry_digest"]

              []
              |> mismatch(
                "history: #{version} corpus_digest",
                row["corpus_digest"],
                census.digest
              )
              |> mismatch(
                "history: #{version} registry_digest",
                row["registry_digest"],
                index_registry
              )
              |> mismatch(
                "history: #{version} spec_digest",
                row["spec_digest"],
                spec_digest_at(tag)
              )
          end
        end
      end)

    missing_rows =
      for {tag, manifest} <- tags,
          manifest["package_version"] != current,
          manifest["package_version"] not in row_versions do
        "history: release #{manifest["package_version"]} (tag #{tag}) has no row (append-only: add the row)"
      end

    # The append-only invariant covers RELEASED rows: the current
    # release's row is the live manifest's working claim, re-synced until
    # its tag exists (and frozen by this same check once a later release
    # makes it historical).
    prefix =
      case committed_rows() do
        {:ok, committed} ->
          committed_prior = Enum.reject(committed, &(&1["package_version"] == current))
          working_prior = Enum.reject(rows, &(&1["package_version"] == current))

          if Enum.take(working_prior, length(committed_prior)) == committed_prior,
            do: [],
            else: [
              "history: the committed history is not a prefix of the working tree (append-only violated)"
            ]

        :absent ->
          []
      end

    duplicates ++ format ++ ordering ++ row_findings ++ missing_rows ++ prefix
  end

  defp census_by_tag(tags, censuses) do
    tags
    |> Enum.flat_map(fn {tag, _manifest} ->
      case Enum.find(censuses, fn census -> tag in census.tags end) do
        nil -> []
        census -> [{tag, census}]
      end
    end)
    |> Map.new()
  end

  defp tag_for_version(tags, version) do
    case Enum.find(tags, fn {_tag, manifest} -> manifest["package_version"] == version end) do
      {tag, _manifest} -> tag
      nil -> nil
    end
  end

  # The one legitimate absence (the history file's first release: the
  # path unknown to HEAD) is decided by an empty ls-tree listing — an
  # exit-code-stable probe; every other failure raises via git!/decode,
  # so the append-only guard never fails open.
  defp committed_rows do
    listing = git!(["ls-tree", "HEAD", "--", @history_path]) |> String.trim()

    if listing == "" do
      :absent
    else
      case Jason.decode(git!(["show", "HEAD:#{@history_path}"])) do
        {:ok, %{"rows" => rows}} when is_list(rows) -> {:ok, rows}
        _other -> raise "compatibility replay: HEAD's committed history is undecodable"
      end
    end
  end

  defp mismatch(findings, _label, same, same), do: findings

  defp mismatch(findings, label, recorded, actual),
    do:
      findings ++
        ["#{label} records #{inspect(recorded)}, derived state carries #{inspect(actual)}"]

  defp read_history_rows! do
    case Jason.decode(File.read!(@history_path)) do
      {:ok, %{"rows" => rows}} when is_list(rows) -> rows
      _other -> raise "compatibility replay: #{@history_path} is unreadable"
    end
  end

  defp format_ok? do
    case Jason.decode(File.read!(@history_path)) do
      {:ok, %{"format" => @history_format}} -> true
      _other -> false
    end
  end

  # The framed spec digest over a TAG's spec/ tree — the same derivation as
  # ReleaseIdentity.spec_digest (u64 len path, path, u64 len bytes, bytes;
  # path-sorted; tagged sha-256), read from git instead of the working tree.
  def spec_digest_at(tag) do
    framed =
      git!(["ls-tree", "-r", "--name-only", tag, "--", "spec/"])
      |> String.split("\n", trim: true)
      |> Enum.sort()
      |> Enum.map_join(fn path ->
        bytes = git!(["show", "#{tag}:#{path}"])
        <<byte_size(path)::unsigned-64>> <> path <> <<byte_size(bytes)::unsigned-64>> <> bytes
      end)

    "sha-256:" <> Base.url_encode64(:crypto.hash(:sha256, framed), padding: false)
  end

  # ---- kit replay ---------------------------------------------------------------------

  defp replay_kit!(censuses) do
    node = AgentBlueprintProtocol.GateNode.find_node!()

    Enum.each(censuses, fn census ->
      unless census.current do
        dir = write_census_dir!(census.map)

        try do
          {out, status} =
            System.cmd(node, [Path.expand("../verifier/cli.ts", __DIR__), "--prior-corpus", dir],
              stderr_to_stdout: true
            )

          {:ok, bytes} = Report.to_bytes(census.corpus, census.results)

          if out != bytes do
            raise """
            kit/escript drift over prior census #{census.digest}:
              escript: #{bytes}
              kit:     #{out}
            """
          end

          case Jason.decode(out) do
            {:ok, %{"exit_status" => reported}} when reported == status ->
              :ok

            _other ->
              raise("kit exit #{status} disagrees with its own report over #{census.digest}")
          end
        after
          File.rm_rf!(dir)
        end
      end
    end)
  end

  defp write_census_dir!(map) do
    dir =
      Path.join(System.tmp_dir!(), "abp-compat-#{System.unique_integer([:positive, :monotonic])}")

    File.mkdir_p!(dir)

    Enum.each(map, fn {path, bytes} ->
      # The index's path allowlist is prefix+suffix only; a hostile tree
      # could still name `cases/../../outside.json` — refuse traversal
      # rather than write outside the scratch dir.
      if Path.type(path) != :relative or ".." in Path.split(path) do
        raise "compatibility replay: census file path escapes the corpus directory: #{path}"
      end

      target = Path.join(dir, path)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, bytes)
    end)

    dir
  end

  # ---- the classifier self-check --------------------------------------------------------

  defp classifier_self_check! do
    extension_case = %{
      "surface" => "extension.resolve",
      "input" => %{"artifact" => %{"extensions" => %{"com.example/changed" => %{}}}}
    }

    plain_case = %{"surface" => "blueprint.decode", "input" => %{"text" => "{}"}}
    changed = MapSet.new(["com.example/changed"])

    {explained, unexplained} = classify([extension_case, plain_case], changed)

    unless explained == [extension_case],
      do: raise("classifier self-check: extension case not explained")

    unless unexplained == [plain_case],
      do: raise("classifier self-check: plain case wrongly explained")

    {[], []} = classify([], changed)
    {[], [^extension_case]} = classify([extension_case], MapSet.new())
    :ok
  end

  # ---- seeded reds ------------------------------------------------------------------------

  defp seeded_reds!(censuses, tags, claims) do
    prior = Enum.find(censuses, &(!&1.current))
    rows = read_history_rows!()

    if prior do
      assert_findings!(
        fn -> claim_findings([prior], Map.delete(claims, prior.digest), rows, 1) end,
        "unclaimed census"
      )

      clean = %{prior | explained: [], unexplained: []}

      assert_findings!(
        fn ->
          claim_findings(
            [clean],
            Map.put(claims, prior.digest, "diverged_by_registry_census"),
            rows,
            1
          )
        end,
        "diverged claim on a clean census"
      )

      disagreeing = %{
        prior
        | explained: [],
          unexplained: [%{"id" => "seed", "surface" => "json.decode", "input" => %{}}]
      }

      assert_findings!(
        fn -> claim_findings([disagreeing], claims, rows, 1) end,
        "equivalent claim with a disagreement"
      )

      assert_findings!(
        fn ->
          claim_findings([clean], Map.put(claims, prior.digest, "not_equivalent"), rows, 1)
        end,
        "not_equivalent claim with no recorded semantics break"
      )

      Enum.each(
        [
          "unclaimed census",
          "diverged claim on a clean census",
          "equivalent claim with a disagreement",
          "not_equivalent claim with no recorded semantics break"
        ],
        &IO.puts("seeded red fired: #{&1}")
      )
    end

    sample = prior || hd(censuses)
    path = sample_map_path(sample)

    case Corpus.load_prior_census(Map.put(sample.map, path, String.duplicate("x", 32))) do
      {:error, _} -> :ok
      {:ok, _corpus} -> raise("seeded red did not diverge: tampered census loaded clean")
    end

    IO.puts("seeded red fired: tampered census file")

    tampered_rows =
      Enum.map(rows, fn row ->
        if row["package_version"] == "0.4.1",
          do: Map.put(row, "spec_digest", "sha-256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"),
          else: row
      end)

    if history_findings(tags, censuses, tampered_rows) == [],
      do: raise("seeded red did not diverge: tampered history row passed")

    IO.puts("seeded red fired: tampered history row")

    # Both refusal arms: a non-repository directory (git failure) and a
    # fresh empty repository (the empty-tag-set refusal). The sentinel
    # pattern keeps every failure raise OUTSIDE the rescue that proves
    # the refusal fired.
    refused? = fn dir ->
      try do
        manifest_tags!(dir)
        false
      rescue
        RuntimeError -> true
      after
        File.rm_rf!(dir)
      end
    end

    empty = Path.join(System.tmp_dir!(), "abp-compat-empty-#{System.unique_integer([:positive])}")
    File.mkdir_p!(empty)
    unless refused?.(empty), do: raise("tag-absent seed: the git-failure refusal did not fire")

    bare = Path.join(System.tmp_dir!(), "abp-compat-bare-#{System.unique_integer([:positive])}")
    File.mkdir_p!(bare)
    _ = System.cmd("git", ["init", "--quiet"], cd: bare, stderr_to_stdout: true)

    unless refused?.(bare),
      do: raise("tag-absent seed: the empty-tag-set refusal did not fire")

    IO.puts("seeded red fired: tag-absent refusal (git failure + empty tag set)")
  end

  defp sample_map_path(census) do
    census.map
    |> Map.keys()
    |> Enum.sort()
    |> Enum.find(&String.starts_with?(&1, "cases/"))
    |> then(&(&1 || "index.json"))
  end

  defp assert_findings!(fun, name) do
    if fun.() == [],
      do: raise("seeded red did not diverge: #{name}"),
      else: :ok
  end

  # ---- environment --------------------------------------------------------------------------

  # Content reads never merge stderr into the bytes (a stray warning byte
  # would splice into census/spec content and false-red confusingly);
  # failures raise with the exit status.
  defp git!(args) do
    case System.cmd("git", args, stderr_to_stdout: false) do
      {out, 0} ->
        out

      {_out, status} ->
        raise "git #{inspect(args)} exited #{status} (content read — stderr left to the console)"
    end
  end
end

AgentBlueprintProtocol.CompatibilityReplayGate.run()
