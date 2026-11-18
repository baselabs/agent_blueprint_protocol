# Compare rebuilt archives with Hex's signed registry and stored docs, without a project or key.
#   mix run --no-mix-exs PATH/hex_release_state.exs [--organization ORG] plan|read-back NAME VERSION PACKAGE_TAR DOCS_TAR
# Hex 2.7.0 vendors hex_core v0.21.1: Release has atom keys :version,
# :outer_checksum (raw bytes), and an optional :retired map, omitted when active.
# get_docs passes HTTP responses through unchanged; only HTTP 404 means absent.
defmodule HexReleaseState do
  @moduledoc false
  @attempts 6
  @delay 10_000

  def main(argv) do
    case OptionParser.parse(argv, strict: [organization: :string]) do
      {opts, [mode, name, version, package, docs], []} when mode in ["plan", "read-back"] ->
        run(opts[:organization], mode, name, version, package, docs)

      _ ->
        raise "usage: hex_release_state.exs [--organization ORG] plan|read-back NAME VERSION PACKAGE_TAR DOCS_TAR"
    end
  end

  defp run(organization, mode, name, version, package, docs) do
    if Mix.Project.get() do
      raise "a Mix project is loaded; run from a directory without mix.exs"
    end

    output = if mode == "plan", do: System.fetch_env!("GITHUB_OUTPUT")
    if output == "", do: raise("GITHUB_OUTPUT is empty")
    checksum = :crypto.hash(:sha256, File.read!(package))
    docs_bytes = File.read!(docs)
    Hex.start()
    Code.ensure_loaded!(Hex.Repo)
    repo = if organization, do: "hexpm:" <> organization, else: "hexpm"

    if mode == "plan" do
      {package_state, docs_state} = state(repo, name, version, checksum, docs_bytes)
      File.write!(output, "package=#{package_state}\ndocs=#{docs_state}\n", [:append])

      if {package_state, docs_state} == {:served, :served} do
        IO.puts("#{name} #{version} is already served with these bytes; nothing will be uploaded")
      else
        IO.puts("#{name} #{version}: package=#{package_state}, docs=#{docs_state}")
      end
    else
      read_back(repo, name, version, checksum, docs_bytes, @attempts)
    end
  end

  defp state(repo, name, version, checksum, docs_bytes) do
    package = package_state(Hex.Repo.get_package(repo, name, nil), name, version, checksum)
    docs = docs_state(Hex.Repo.get_docs(repo, name, version), name, version, docs_bytes)

    if package == :upload and docs == :served do
      raise "#{name} #{version}: docs are served without the package; inconsistent registry state"
    end

    {package, docs}
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

  defp docs_state({:ok, {200, _headers, bytes}}, _name, _version, bytes), do: :served
  defp docs_state({:ok, {404, _headers, _body}}, _name, _version, _bytes), do: :upload

  defp docs_state({:ok, {200, _headers, _body}}, name, version, _bytes) do
    raise "#{name} #{version}: served docs bytes differ; nothing was replaced"
  end

  defp docs_state(_result, name, version, _bytes) do
    raise "could not confirm Hex docs for #{name} #{version}; publication refused"
  end

  defp read_back(repo, name, version, checksum, docs, attempts) do
    case state(repo, name, version, checksum, docs) do
      {:served, :served} ->
        IO.puts("#{name} #{version}: package and docs are served with the built bytes")

      _absent when attempts > 1 ->
        Process.sleep(@delay)
        read_back(repo, name, version, checksum, docs, attempts - 1)

      _absent ->
        raise "#{name} #{version} is not served yet: Hex holds it for approval or has not propagated it. Approve it on hex.pm, then dispatch Publish again on the same commit; the next run uploads only what is missing."
    end
  end
end

HexReleaseState.main(System.argv())
