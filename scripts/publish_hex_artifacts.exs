# Publish verified bytes with Hex 2.7.0's own API: the package archive, then its docs.
# Usage, from a directory without mix.exs, such as the verified archives' own:
#   mix run --no-mix-exs PATH/publish_hex_artifacts.exs [--organization ORG] NAME VERSION ARCHIVE DOCS
# Without mix.exs no project is loaded or compiled while the key is in the environment, and
# the Hex archive stays on the code path; with one, Mix narrows the path to the project's
# dependencies and Hex's modules become unloadable. A loaded project refuses before the key
# is read. The workflow refuses an existing version or a missing package before this step;
# Hex itself refuses a second upload of a version, because no replace is requested.
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
    if Mix.Project.get() do
      raise "a Mix project is loaded; run from a directory without mix.exs"
    end

    Hex.start()
    Enum.each([Hex.API.Release, Hex.API.ReleaseDocs], &Code.ensure_loaded!/1)

    key = System.fetch_env!("HEX_API_KEY")
    if key == "", do: raise("HEX_API_KEY is empty; publication stopped")
    auth = [key: key]

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

  defp accepted!({:ok, {code, _headers, body}}, label) when code in 200..299 do
    IO.puts("#{label}: archive accepted")
    if is_map(body) and body["status"] == "staged", do: :staged, else: :published
  end

  defp accepted!(_result, label) do
    raise "#{label} upload failed or occupied; manual recovery required, do not redispatch"
  end
end

PublishHexArtifacts.main(System.argv())
