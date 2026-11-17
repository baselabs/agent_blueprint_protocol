# Publish verified bytes with Hex 2.7.0's own API: the package archive, then its docs.
# Usage: mix run --no-mix-exs scripts/publish_hex_artifacts.exs [--organization ORG] NAME VERSION ARCHIVE DOCS
# Without --organization the package goes to the public repository; with it, to that
# organization's repository. Hex's API calls take the organization exactly as
# `mix hex.publish --organization ORG` passes it (nil for public).
# The key comes only from HEX_API_KEY in the step's env. Nothing is rebuilt here, no
# authentication is persisted, and no response body or credential is printed.
defmodule PublishHexArtifacts do
  @moduledoc false

  def main(argv) do
    case OptionParser.parse(argv, strict: [organization: :string]) do
      {opts, [name, version, archive, docs], []} ->
        publish(opts[:organization], name, version, archive, docs)

      _ ->
        raise "usage: publish_hex_artifacts.exs [--organization ORG] NAME VERSION ARCHIVE DOCS"
    end
  end

  defp publish(repo, name, version, archive, docs) do
    key = System.fetch_env!("HEX_API_KEY")
    if key == "", do: raise("HEX_API_KEY is empty; publication stopped")
    Hex.start()
    auth = [key: key]

    absent!(Hex.API.Release.get(repo, name, version, auth), repo, name, version)

    package_state =
      accepted!(Hex.API.Release.publish(repo, File.read!(archive), auth), "Hex package")

    docs_state =
      accepted!(
        Hex.API.ReleaseDocs.publish(repo, name, version, File.read!(docs), auth),
        "Hex docs"
      )

    if :staged in [package_state, docs_state] do
      raise "Hex approval pending; approve on hex.pm and recover by hand with the verified artifacts"
    end
  end

  defp absent!({:ok, {404, _headers, _body}}, _repo, _name, _version), do: :ok

  defp absent!({:ok, {code, _headers, _body}}, repo, name, version) when code in 200..299 do
    raise "#{where(repo)} already has #{name} #{version}; publication refused"
  end

  defp absent!(_result, repo, name, version) do
    raise "could not confirm #{name} #{version} is absent from #{where(repo)}; publication refused"
  end

  defp where(nil), do: "the public Hex repository"
  defp where(organization), do: "Hex organization #{organization}"

  defp accepted!({:ok, {code, _headers, body}}, label) when code in 200..299 do
    IO.puts("#{label}: archive accepted")
    if is_map(body) and body["status"] == "staged", do: :staged, else: :published
  end

  defp accepted!(_result, label) do
    raise "#{label} upload failed or occupied; manual recovery required, do not redispatch"
  end
end

PublishHexArtifacts.main(System.argv())
