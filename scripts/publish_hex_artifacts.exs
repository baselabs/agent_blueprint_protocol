# Upload only missing, verified archives with Hex 2.7.0's API, package before docs.
# From a directory without mix.exs (no project is loaded or compiled under the key):
#   mix run --no-mix-exs PATH/publish_hex_artifacts.exs [--organization ORG] NAME VERSION --counterpart-repository REPO --counterpart-package NAME [--counterpart-package NAME ...] --checksum SHA256 [--package ARCHIVE] [--docs DOCS]
# Check the live release and, when held, its stage immediately before posting docs.
# Public release reads are anonymous. Organization release reads use a separate API-read key.
# Credentials come only from this step's env. No response body or key is printed.
# Exit status: 0 when every requested archive is served, 75 (EX_TEMPFAIL) when Hex
# holds the release or docs for approval, 1 on any other failure.
defmodule PublishHexArtifacts do
  @moduledoc false

  @held 75
  @usage "usage: publish_hex_artifacts.exs [--organization ORG] NAME VERSION " <>
           "--counterpart-repository REPO --counterpart-package NAME [--counterpart-package NAME ...] " <>
           "--checksum SHA256 [--package ARCHIVE] [--docs DOCS]"

  def main(argv) do
    case OptionParser.parse(argv,
           strict: [
             organization: :string,
             counterpart_repository: :string,
             counterpart_package: :keep,
             checksum: :string,
             package: :string,
             docs: :string
           ]
         ) do
      {opts, [name, version], []} ->
        if is_nil(opts[:package]) and is_nil(opts[:docs]),
          do: raise("at least one archive is required")

        checksum = opts[:checksum] || ""

        unless Regex.match?(~r/\A[0-9a-f]{64}\z/, checksum) do
          raise "--checksum must be a full lowercase SHA-256 of the verified package archive"
        end

        repo = if repo = opts[:organization], do: String.trim(repo)
        counterpart_option = String.trim(opts[:counterpart_repository] || "")
        counterpart_repo = counterpart_repository!(repo, counterpart_option)
        counterpart_packages = Keyword.get_values(opts, :counterpart_package)

        if counterpart_packages == [] or Enum.any?(counterpart_packages, &(String.trim(&1) == "")) do
          Mix.raise("at least one non-empty --counterpart-package is required")
        end

        publish(
          {repo, counterpart_repo, counterpart_packages},
          name,
          version,
          opts[:package],
          opts[:docs],
          checksum
        )

      _ ->
        Mix.raise(@usage)
    end
  end

  defp counterpart_repository!(nil, repo) when repo not in ["", "hexpm"], do: repo

  defp counterpart_repository!(repo, "hexpm") when is_binary(repo) and repo not in ["", "hexpm"],
    do: nil

  defp counterpart_repository!(_repo, _counterpart) do
    Mix.raise(
      "--counterpart-repository must name an organization for a public upload or hexpm for an organization upload"
    )
  end

  defp publish(
         {repo, counterpart_repo, counterpart_packages},
         name,
         version,
         archive,
         docs,
         checksum
       ) do
    if Mix.Project.get() do
      raise "a Mix project is loaded; run from a directory without mix.exs"
    end

    Hex.start()
    Enum.each([Hex.API.Client, Hex.API.Release, Hex.API.ReleaseDocs], &Code.ensure_loaded!/1)
    release_config = uncached_config(repo, release_read_auth!(repo))
    upload_key = System.fetch_env!("HEX_API_KEY")
    if upload_key == "", do: raise("HEX_API_KEY is empty; publication stopped")
    upload_auth = [key: upload_key]

    archive = if archive, do: File.read!(archive)
    docs = if docs, do: File.read!(docs)

    if archive && digest(archive) != checksum do
      raise "package archive does not match --checksum. Verify the archive and dispatch Publish again."
    end

    target = %{
      repo: repo,
      name: name,
      version: version,
      checksum: checksum,
      release_config: release_config,
      upload_config: uncached_config(repo, upload_auth),
      upload_auth: upload_auth
    }

    check_counterpart!(counterpart_repo, counterpart_packages, version)

    package_result = if archive, do: publish_package!(target, archive), else: :skipped
    docs_result = if docs, do: publish_docs!(target, docs, package_result)

    case exit_status(package_result, docs_result) do
      @held ->
        IO.puts(
          :stderr,
          "Hex holds #{name} #{version} for approval. Approve it on hex.pm, then dispatch Publish again on the same commit."
        )

        @held

      status ->
        status
    end
  end

  def exit_status(package_result, docs_result) do
    if package_result == :held or match?({:staged, _}, package_result) or docs_result == :held,
      do: @held,
      else: 0
  end

  defp release_read_auth!(nil), do: []

  defp release_read_auth!(_repo) do
    key = System.fetch_env!("HEX_ORG_KEY_PUBLISH_API_READ")

    if String.trim(key) == "" do
      raise "HEX_ORG_KEY_PUBLISH_API_READ is empty. Configure the organization API-read key before dispatching Publish again."
    end

    [key: key]
  end

  # Use Hex's repository routing and ask the API to revalidate cached responses.
  defp uncached_config(repo, auth) do
    Hex.API.Client.build_config(repo, auth)
    |> no_cache()
  end

  defp no_cache(config) do
    config
    |> Map.update!(:http_headers, &Map.put(&1, "cache-control", "no-cache"))
  end

  def check_counterpart!(repo, packages, version) do
    auth = release_read_auth!(repo)

    # Hex.HTTP follows redirects and can read netrc. Use hex_core's bundled adapter
    # directly for this check, with the default HTTPS API and only explicit auth.
    config =
      %{
        :mix_hex_core.default_config()
        | api_repository: repo || :undefined,
          api_key: auth[:key] || :undefined,
          http_adapter:
            {:mix_hex_http_httpc, %{http_options: [autoredirect: false, timeout: 15_000]}}
      }
      |> no_cache()

    # hexpm answers 404 for a missing release and also for a key without access to
    # the organization, so an organization 404 proves absence only after the same
    # key reads the organization itself (hexpm repository_controller.ex:4-37).
    if repo, do: counterpart_access!(:mix_hex_api.get(config, ["repos", repo]), repo, version)

    packages
    |> Stream.map(&:mix_hex_api_release.get(config, &1, version))
    |> check_counterpart_responses!(version)
  end

  def counterpart_access!({:ok, {200, _headers, %{"name" => repo}}}, repo, _version), do: :ok

  def counterpart_access!(_response, _repo, version),
    do: Mix.raise("Hex counterpart check refused version #{version}: registry result unknown")

  def check_counterpart_responses!(responses, version) do
    Enum.each(responses, fn
      {:ok, {404, _headers, _body}} ->
        :ok

      {:ok, {200, _headers, %{"version" => ^version}}} ->
        Mix.raise("Hex counterpart check refused version #{version}: already listed")

      _response ->
        Mix.raise("Hex counterpart check refused version #{version}: registry result unknown")
    end)

    IO.puts("Hex counterpart check passed")
  end

  defp require_org_package!(%{repo: repo, name: name, release_config: release_config}) do
    case :mix_hex_api_package.get(release_config, name) do
      {:ok, {200, _headers, %{"name" => ^name, "repository" => ^repo}}} ->
        :ok

      _ ->
        raise "could not confirm access to Hex package #{repo}/#{name}. Check the organization API-read key and package name."
    end
  end

  defp served_release!(%{
         release_config: release_config,
         name: name,
         version: version,
         checksum: checksum
       }) do
    case release_state(:mix_hex_api_release.get(release_config, name, version), version, checksum) do
      :retired ->
        raise "#{name} #{version} is retired; publication refused"

      :different_package ->
        raise "#{name} #{version}: served package bytes differ; verify the release commit"

      :unknown ->
        raise "could not confirm the Hex release or docs state for #{name} #{version}; dispatch Publish again on the same commit"

      state ->
        state
    end
  end

  def release_state({:ok, {404, _headers, _body}}, _version, _checksum), do: :missing

  def release_state(
        {:ok,
         {200, _headers,
          %{
            "version" => version,
            "retirement" => retirement,
            "checksum" => served_checksum,
            "has_docs" => has_docs
          }}},
        version,
        checksum
      ) do
    cond do
      retirement != nil -> :retired
      served_checksum != checksum -> :different_package
      is_boolean(has_docs) -> {:served, has_docs}
      true -> :unknown
    end
  end

  def release_state(_response, _version, _checksum), do: :unknown

  defp publish_package!(target, archive) do
    if target.repo, do: require_org_package!(target)
    {release_stage, docs_stage} = pending_stages!(target)

    case package_action(served_release!(target), release_stage, docs_stage) do
      :skip ->
        IO.puts("Hex package: already served; upload skipped")
        :live

      :keep ->
        IO.puts("Hex package: matching stage kept")
        :held

      :wait ->
        raise "Hex still holds docs for this version. Check the release and docs stage before retrying."

      :upload ->
        body =
          Hex.API.Release.publish(target.repo, archive, target.upload_auth, fn _ -> :ok end,
            replace: false
          )
          |> upload_body!(target, "package")

        case package_receipt(
               body,
               target.name,
               target.version,
               target.checksum,
               package_url(target)
             ) do
          :invalid ->
            raise "Hex did not confirm the inspected package in its upload receipt. Check the version on Hex before retrying."

          result ->
            result
        end
    end
  end

  def package_action({:served, _}, _, _), do: :skip
  def package_action(:missing, {:pending_release, _}, _), do: :keep
  def package_action(:missing, :absent, :absent), do: :upload
  def package_action(_, _, _), do: :wait

  def package_receipt(body, name, version, checksum, package_url) do
    case body do
      %{
        "name" => ^name,
        "version" => ^version,
        "checksum" => ^checksum,
        "status" => "staged",
        "kind" => "release",
        "approval_checksum" => approval
      } ->
        if sha256?(approval), do: {:staged, approval}, else: :invalid

      %{"package_url" => ^package_url, "version" => ^version, "checksum" => ^checksum}
      when not is_map_key(body, "status") and not is_map_key(body, "kind") ->
        :live

      _ ->
        :invalid
    end
  end

  defp package_url(%{release_config: config, name: name}) do
    path =
      config
      |> :mix_hex_api.build_repository_path(["packages", name])
      |> :mix_hex_api.join_path_segments()

    config.api_url <> "/" <> path
  end

  defp publish_docs!(target, docs, package_result) do
    if target.repo, do: require_org_package!(target)
    {release_stage, docs_stage} = pending_stages!(target)

    # Approval can serve the release while its stage still exists.
    case docs_action(release_stage, docs_stage, served_release!(target), package_result) do
      :attach ->
        case upload_docs!(target, docs) |> docs_receipt(target, "release", target.checksum) do
          :staged ->
            IO.puts("Hex package and docs: staged together for approval")
            :held

          _ ->
            raise "Hex did not confirm docs joined the inspected release stage. Check the served release and stage before retrying."
        end

      :upload ->
        case upload_docs!(target, docs) |> docs_receipt(target, "docs", digest(docs)) do
          :live ->
            IO.puts("Hex docs: archive accepted")

          :staged ->
            IO.puts("Hex docs: staged for approval")
            :held

          :invalid ->
            raise "Hex did not confirm the docs upload for the inspected release. Check the served release and docs stage before retrying."
        end

      :keep ->
        IO.puts(
          "Hex stage kept. Approve the stage, then dispatch Publish again with the same release_commit so missing docs upload live."
        )

        :held

      :skip ->
        IO.puts("Hex docs: already served; upload skipped")

      :wait ->
        raise "Hex release or stage changed before the docs upload. Dispatch Publish again on the same commit."
    end
  end

  # A package POST creates a stage without docs. Hex folds the docs checksum
  # into its approval checksum, so only this run's unchanged receipt proves
  # that the active stage is still empty.
  def docs_action({:pending_release, approval}, :absent, :missing, {:staged, approval}),
    do: :attach

  def docs_action({:pending_release, _}, _, _, _), do: :keep
  def docs_action(_, :pending_docs, {:served, _}, _), do: :keep
  def docs_action(:absent, :absent, {:served, true}, _), do: :skip

  def docs_action(:absent, :absent, {:served, false}, result) when result in [:live, :skipped],
    do: :upload

  def docs_action(_, _, _, _), do: :wait

  defp pending_stages!(target) do
    docs_stage = pending_stage!(target, "docs", ["docs", "staged"])
    release_stage = pending_stage!(target, "release", ["staged"])
    {release_stage, docs_stage}
  end

  defp pending_stage!(target, kind, suffix) do
    path =
      :mix_hex_api.build_repository_path(
        target.upload_config,
        ["packages", target.name, "releases", target.version] ++ suffix
      )

    response = :mix_hex_api.get(target.upload_config, path)

    case stage_state(response, kind, target.name, target.version, target.checksum) do
      :invalid ->
        raise "could not confirm a matching Hex #{kind} stage for #{target.name} #{target.version}. Inspect the pending stage before retrying."

      state ->
        state
    end
  end

  def stage_state({:ok, {404, _headers, _body}}, _kind, _name, _version, _checksum), do: :absent

  def stage_state({:ok, {200, _headers, body}}, kind, name, version, checksum) do
    case body do
      %{"name" => ^name, "version" => ^version, "kind" => ^kind, "status" => status}
      when status in ["approved", "rejected", "expired"] ->
        :absent

      %{
        "name" => ^name,
        "version" => ^version,
        "kind" => "release",
        "status" => "staged",
        "checksum" => ^checksum,
        "approval_checksum" => approval
      }
      when kind == "release" ->
        if sha256?(approval), do: {:pending_release, approval}, else: :invalid

      %{
        "name" => ^name,
        "version" => ^version,
        "kind" => "docs",
        "status" => "staged",
        "checksum" => docs_checksum
      }
      when kind == "docs" ->
        if sha256?(docs_checksum), do: :pending_docs, else: :invalid

      _ ->
        :invalid
    end
  end

  def stage_state(_, _, _, _, _), do: :invalid

  defp upload_docs!(target, docs) do
    # The POST has no create-only precondition. State can change after the last read.
    Hex.API.ReleaseDocs.publish(
      target.repo,
      target.name,
      target.version,
      docs,
      target.upload_auth
    )
    |> upload_response!(target, "docs")
  end

  # A live docs write answers 201 with an empty body (hexpm docs_controller.ex:79-119).
  # A held write answers with the stage it joined. Anything else is refused.
  # A release stage reports the package checksum; a docs-only stage reports the
  # docs archive checksum (hexpm staged_release_view.ex:12), so the caller names it.
  def docs_receipt({201, body}, _target, _kind, _checksum) when body in [nil, ""], do: :live

  def docs_receipt(
        {code,
         %{
           "name" => name,
           "version" => version,
           "status" => "staged",
           "kind" => kind,
           "checksum" => checksum
         }},
        %{name: name, version: version},
        kind,
        checksum
      )
      when code in 200..299,
      do: :staged

  def docs_receipt(_response, _target, _kind, _checksum), do: :invalid

  defp upload_response!({:ok, {code, _headers, body}}, _target, _kind) when code in 200..299,
    do: {code, body}

  defp upload_response!(_result, target, kind) do
    raise "#{target.name} #{target.version} #{kind} upload failed. Resolve the cause and dispatch Publish again on the same commit."
  end

  defp upload_body!({:ok, {code, _headers, body}}, _target, _kind) when code in 200..299, do: body

  defp upload_body!(_result, target, kind) do
    raise "#{target.name} #{target.version} #{kind} upload failed. Resolve the cause and dispatch Publish again on the same commit."
  end

  defp sha256?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp digest(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end

System.halt(PublishHexArtifacts.main(System.argv()))
