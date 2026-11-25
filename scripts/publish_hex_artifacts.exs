# Upload only missing, verified archives with Hex 2.7.0's API, package before docs.
# From a directory without mix.exs (no project is loaded or compiled under the key):
#   mix run --no-mix-exs PATH/publish_hex_artifacts.exs [--organization ORG] NAME VERSION --checksum SHA256 [--package ARCHIVE] [--docs DOCS]
# Check the live release and, when held, its stage immediately before posting docs.
# HEX_API_KEY comes only from this step's env. No response body or key is printed.
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
    key = System.fetch_env!("HEX_API_KEY")
    if key == "", do: raise("HEX_API_KEY is empty; publication stopped")
    auth = [key: key]

    archive = if archive, do: File.read!(archive)
    docs = if docs, do: File.read!(docs)

    if archive && Base.encode16(:crypto.hash(:sha256, archive), case: :lower) != checksum do
      raise "package archive does not match --checksum; verify the archive and dispatch Publish again"
    end

    # Use the same repository configuration as Hex.API.Release.get/4, but
    # revalidate the API response instead of accepting its cached release state.
    config =
      Hex.API.Client.build_config(repo, auth)
      |> Map.update!(:http_headers, &Map.put(&1, "cache-control", "no-cache"))

    package_result =
      if archive do
        case served_release!(config, name, version, checksum) do
          :missing ->
            Hex.API.Release.publish(repo, archive, auth, fn _ -> :ok end, replace: false)
            |> upload_result!(name, version, "package")

          {:served, _} ->
            IO.puts("Hex package: already served; upload skipped")
        end
      end

    docs_result =
      if docs do
        publish_docs!(repo, name, version, docs, checksum, auth, config, package_result)
      end

    if match?({:staged, _}, package_result) or match?({:staged, _}, docs_result) do
      raise "Hex holds #{name} #{version} for approval; approve it on hex.pm, then dispatch Publish again on the same commit; the next run uploads only what is missing"
    end
  end

  defp served_release!(config, name, version, checksum) do
    case release_state(:mix_hex_api_release.get(config, name, version), version, checksum) do
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

  def release_stage?(body, checksum) do
    match?(%{"status" => "staged", "kind" => "release", "checksum" => ^checksum}, body)
  end

  defp publish_docs!(repo, name, version, docs, checksum, auth, config, {:staged, package}) do
    unless release_stage?(package, checksum) do
      raise "Hex did not confirm the staged package checksum; inspect the stage before dispatching Publish again"
    end

    unless served_release!(config, name, version, checksum) == :missing do
      raise "Hex already serves #{name} #{version}; dispatch Publish again to recheck its docs"
    end

    require_active_stage!(config, name, version, checksum)

    case upload_docs!(repo, name, version, docs, auth) do
      {:staged, receipt} ->
        unless release_stage?(receipt, checksum) do
          raise "Hex did not confirm docs joined the inspected release stage; check the stage before approving"
        end

        IO.puts("Hex package and docs: staged together for approval")
        {:staged, receipt}

      :ok ->
        raise "Hex did not confirm docs joined the inspected release stage; check the served release and stage before retrying"
    end
  end

  defp publish_docs!(repo, name, version, docs, checksum, auth, config, _package_result) do
    case served_release!(config, name, version, checksum) do
      {:served, false} ->
        upload_docs!(repo, name, version, docs, auth)

      {:served, true} ->
        IO.puts("Hex docs: already served; upload skipped")

      :missing ->
        raise "Hex does not serve #{name} #{version} yet; dispatch Publish again on the same commit once it is served"
    end
  end

  defp require_active_stage!(config, name, version, checksum) do
    path =
      :mix_hex_api.build_repository_path(config, ["packages", name, "releases", version, "staged"])

    confirmed =
      case :mix_hex_api.get(config, path) do
        {:ok, {200, _headers, %{"name" => ^name, "version" => ^version} = stage}} ->
          release_stage?(stage, checksum)

        _ ->
          false
      end

    unless confirmed do
      raise "Hex did not confirm an active stage for #{name} #{version}; inspect the stage before dispatching Publish again"
    end
  end

  defp upload_docs!(repo, name, version, docs, auth) do
    # The POST has no create-only precondition. State can change after the last read.
    Hex.API.ReleaseDocs.publish(repo, name, version, docs, auth)
    |> upload_result!(name, version, "docs")
  end

  defp upload_result!(
         {:ok, {code, _headers, %{"status" => "staged"} = body}},
         _name,
         _version,
         _label
       )
       when code in 200..299, do: {:staged, body}

  defp upload_result!({:ok, {code, _headers, _body}}, _name, _version, label)
       when code in 200..299 do
    IO.puts("Hex #{label}: archive accepted")
  end

  defp upload_result!(_result, name, version, label) do
    raise "#{name} #{version} #{label} upload failed; dispatch Publish again on the same commit once the cause is resolved; the next run uploads only what is missing"
  end
end

PublishHexArtifacts.main(System.argv())
