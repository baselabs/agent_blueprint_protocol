# Check package identity, docs presence, and served docs provenance without a Mix project.
#   mix run --no-mix-exs PATH/hex_release_state.exs [--organization ORG] plan NAME VERSION PACKAGE_TAR
#   mix run --no-mix-exs PATH/hex_release_state.exs [--organization ORG] read-back NAME VERSION PACKAGE_TAR DOCS_OUTPUT DISPATCHED_SHA REPO_DIR
#   mix run --no-mix-exs PATH/hex_release_state.exs docs-provenance NAME VERSION DOCS_ARCHIVE DISPATCHED_SHA REPO_DIR
# Hex 2.7.0 vendors hex_core v0.21.1: Release has atom keys :version,
# :outer_checksum (raw bytes), and an optional :retired map, omitted when active.
# Docs HTTP 200 means served, 404 means absent; planning never inspects docs bytes.
Code.require_file("gate_command.exs", __DIR__)

defmodule HexReleaseState do
  @moduledoc false
  @attempts 6
  @delay 10_000

  def main(argv) do
    if Mix.Project.get() do
      raise "a Mix project is loaded; run from a directory without mix.exs"
    end

    case OptionParser.parse(argv, strict: [organization: :string]) do
      {opts, ["plan", name, version, package], []} ->
        run(opts[:organization], name, version, package, :plan)

      {opts, ["read-back", name, version, package, output, dispatched, repository], []} ->
        run(
          opts[:organization],
          name,
          version,
          package,
          {:read_back, output, dispatched, repository}
        )

      {[], ["docs-provenance", name, version, archive, dispatched, repository], []} ->
        inspect_docs!(archive, name, version, dispatched, repository)

      _ ->
        raise "usage: hex_release_state.exs [--organization ORG] plan NAME VERSION PACKAGE_TAR | " <>
                "[--organization ORG] read-back NAME VERSION PACKAGE_TAR DOCS_OUTPUT DISPATCHED_SHA REPO_DIR | " <>
                "docs-provenance NAME VERSION DOCS_ARCHIVE DISPATCHED_SHA REPO_DIR"
    end
  end

  defp run(organization, name, version, package, action) do
    output = if action == :plan, do: System.fetch_env!("GITHUB_OUTPUT")
    if output == "", do: raise("GITHUB_OUTPUT is empty")
    checksum = :crypto.hash(:sha256, File.read!(package))
    Hex.start()
    Code.ensure_loaded!(Hex.Repo)
    repo = if organization, do: "hexpm:" <> organization, else: "hexpm"

    case action do
      :plan ->
        {package_state, docs_state, _response} = state(repo, name, version, checksum)
        package_sha256 = Base.encode16(checksum, case: :lower)

        File.write!(
          output,
          "package=#{package_state}\ndocs=#{docs_state}\nchecksum=#{package_sha256}\n",
          [:append]
        )

        IO.puts("Package checksum: #{package_sha256}")

        if {package_state, docs_state} == {:served, :served} do
          IO.puts(
            "#{name} #{version}: package is already served with these bytes and its docs are served; nothing will be uploaded"
          )
        else
          IO.puts("#{name} #{version}: package=#{package_state}, docs=#{docs_state}")
        end

      {:read_back, output, dispatched, repository} ->
        read_back(repo, name, version, checksum, output, dispatched, repository, @attempts)
    end
  end

  defp state(repo, name, version, checksum) do
    package = package_state(Hex.Repo.get_package(repo, name, nil), name, version, checksum)
    response = Hex.Repo.get_docs(repo, name, version)
    docs = docs_state(response, name, version)

    if package == :upload and docs == :served do
      raise "#{name} #{version}: docs are served without the package; inconsistent registry state"
    end

    {package, docs, response}
  end

  defp package_state({:ok, {200, _headers, %{releases: releases}}}, name, version, checksum)
       when is_list(releases) do
    case Enum.filter(releases, &(Map.fetch!(&1, :version) == version)) do
      [] -> :upload
      [release] -> served_package!(release, name, version, checksum)
      _ -> raise "#{name} #{version}: ambiguous registry release; publication refused"
    end
  end

  defp package_state({:ok, {404, _headers, _body}}, name, _version, _checksum) do
    raise "Hex has no package #{name}; a first publication is the owner's; this workflow never creates a package"
  end

  defp package_state(_result, name, _version, _checksum) do
    raise "could not confirm Hex package #{name}; publication refused"
  end

  defp served_package!(release, name, version, checksum) do
    cond do
      Map.has_key?(release, :retired) ->
        raise "#{name} #{version} is retired; publication refused"

      Map.get(release, :outer_checksum) != checksum ->
        raise "#{name} #{version}: served package bytes differ; nothing was replaced"

      true ->
        :served
    end
  end

  defp docs_state({:ok, {200, _headers, _body}}, _name, _version), do: :served
  defp docs_state({:ok, {404, _headers, _body}}, _name, _version), do: :upload

  defp docs_state(_result, name, version) do
    raise "could not confirm Hex docs for #{name} #{version}; publication refused"
  end

  defp read_back(repo, name, version, checksum, output, dispatched, repository, attempts) do
    case state(repo, name, version, checksum) do
      {:served, :served, {:ok, {200, _headers, bytes}}} ->
        File.write!(output, bytes)
        inspect_docs!(output, name, version, dispatched, repository)
        IO.puts("#{name} #{version}: package is served with the built bytes and docs are served")

      _absent when attempts > 1 ->
        Process.sleep(@delay)
        read_back(repo, name, version, checksum, output, dispatched, repository, attempts - 1)

      _absent ->
        raise "#{name} #{version} is not served yet: Hex holds it for approval or has not propagated it. Approve it on hex.pm, then dispatch Publish again on the same commit; the next run uploads only what is missing."
    end
  end

  defp inspect_docs!(archive, name, version, dispatched, repository) do
    entries = docs_entries!(archive)
    archive_file!(entries, "index.html")
    release = entries |> archive_file!("release.json") |> decode_release!()

    if release["package"] != name do
      raise "docs release.json package does not match #{name}; publication refused"
    end

    if release["version"] != version do
      raise "docs release.json version does not match #{version}; publication refused"
    end

    commit = Map.get(release, "commit")

    unless is_binary(commit) and Regex.match?(~r/\A[0-9a-f]{40}\z/, commit) do
      raise "docs release.json commit is not a full Git SHA; publication refused"
    end

    unless Regex.match?(~r/\A[0-9a-f]{40}\z/, dispatched) do
      raise "dispatched commit is not a full Git SHA; publication refused"
    end

    ancestry = ["-C", repository, "merge-base", "--is-ancestor", commit, dispatched]

    case AgentBlueprintProtocol.GateCommand.capture("git", ancestry, stderr_to_stdout: true) do
      {_output, 0} ->
        IO.puts("published commit: #{commit}")

      {_output, 1} ->
        raise "docs release.json commit is not the dispatched commit or its ancestor; publication refused"

      _ ->
        raise "could not confirm docs release.json commit ancestry; publication refused"
    end
  end

  defp docs_entries!(archive) do
    bytes = archive |> File.read!() |> :zlib.gunzip()

    case :erl_tar.extract({:binary, bytes}, [:memory]) do
      {:ok, entries} -> entries
      _ -> raise "invalid tar"
    end
  rescue
    _ -> raise "docs archive is not a readable gzip tar; publication refused"
  end

  defp archive_file!(entries, name) do
    case Enum.filter(entries, fn {path, _bytes} -> to_string(path) in [name, "./" <> name] end) do
      [{_path, bytes}] -> bytes
      [] -> raise "docs archive is missing #{name}; publication refused"
      _ -> raise "docs archive contains multiple #{name} entries; publication refused"
    end
  end

  defp decode_release!(bytes) do
    case :json.decode(bytes) do
      release when is_map(release) -> release
      _ -> raise "not an object"
    end
  rescue
    _ -> raise "docs release.json is not a valid JSON object; publication refused"
  end
end

HexReleaseState.main(System.argv())
