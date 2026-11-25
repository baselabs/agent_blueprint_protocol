# Upload only missing, verified archives with Hex 2.7.0's API, package before docs.
# From a directory without mix.exs (no project is loaded or compiled under the key):
#   mix run --no-mix-exs PATH/publish_hex_artifacts.exs [--organization ORG] NAME VERSION --checksum SHA256 [--package ARCHIVE] [--docs DOCS]
# Check the live release and, when held, its stage immediately before posting docs.
# Public release reads are anonymous. Organization release reads use a separate API-read key.
# Credentials come only from this step's env. No response body or key is printed.
defmodule PublishHexArtifacts do
  @moduledoc false

  def main(argv) do
    case OptionParser.parse(argv,
           strict: [organization: :string, checksum: :string, package: :string, docs: :string]
         ) do
      {opts, [name, version], []} ->
        if is_nil(opts[:package]) and is_nil(opts[:docs]),
          do: raise("at least one archive is required")

        checksum = opts[:checksum] || ""

        unless Regex.match?(~r/\A[0-9a-f]{64}\z/, checksum) do
          raise "--checksum must be a full lowercase SHA-256 of the verified package archive"
        end

        publish(opts[:organization], name, version, opts[:package], opts[:docs], checksum)

      _ ->
        raise "usage: publish_hex_artifacts.exs [--organization ORG] NAME VERSION --checksum SHA256 [--package ARCHIVE] [--docs DOCS]"
    end
  end

  defp publish(repo, name, version, archive, docs, checksum) do
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

    package_result = if archive, do: publish_package!(target, archive), else: :skipped
    docs_result = if docs, do: publish_docs!(target, docs, package_result)

    if package_result == :held or match?({:staged, _}, package_result) or docs_result == :held do
      raise "Hex holds #{name} #{version} for approval. Approve it on hex.pm, then dispatch Publish again on the same commit."
    end
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
    |> Map.update!(:http_headers, &Map.put(&1, "cache-control", "no-cache"))
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
        case upload_docs!(target, docs) do
          %{
            "name" => name,
            "version" => version,
            "status" => "staged",
            "kind" => "release",
            "checksum" => checksum
          }
          when name == target.name and version == target.version and checksum == target.checksum ->
            IO.puts("Hex package and docs: staged together for approval")
            :held

          _ ->
            raise "Hex did not confirm docs joined the inspected release stage. Check the served release and stage before retrying."
        end

      :upload ->
        case upload_docs!(target, docs) do
          %{"status" => "staged"} ->
            IO.puts("Hex docs: staged for approval")
            :held

          _ ->
            IO.puts("Hex docs: archive accepted")
        end

      :keep ->
        IO.puts("Hex stage kept. Approve it, then dispatch again to fill any missing docs.")
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
    |> upload_body!(target, "docs")
  end

  defp upload_body!({:ok, {code, _headers, body}}, _target, _kind) when code in 200..299, do: body

  defp upload_body!(_result, target, kind) do
    raise "#{target.name} #{target.version} #{kind} upload failed. Resolve the cause and dispatch Publish again on the same commit."
  end

  defp sha256?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp digest(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end

PublishHexArtifacts.main(System.argv())
