# Upload only missing, verified archives with Hex 2.7.0's API, package before docs.
# From a directory without mix.exs (no project is loaded or compiled under the key):
#   mix run --no-mix-exs PATH/publish_hex_artifacts.exs [--organization ORG] NAME VERSION [--package ARCHIVE] [--docs DOCS]
# The read-only plan already compared served bytes. Never replace a version. A held
# upload stops here; approve it, then dispatch Publish again on the same commit.
# HEX_API_KEY comes only from this step's env. No response body or key is printed.
defmodule PublishHexArtifacts do
  @moduledoc false

  def main(argv) do
    case OptionParser.parse(argv,
           strict: [organization: :string, package: :string, docs: :string]
         ) do
      {opts, [name, version], []} ->
        if is_nil(opts[:package]) and is_nil(opts[:docs]),
          do: raise("at least one archive is required")

        publish(opts[:organization], name, version, opts[:package], opts[:docs])

      _ ->
        raise "usage: publish_hex_artifacts.exs [--organization ORG] NAME VERSION [--package ARCHIVE] [--docs DOCS]"
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

    if archive do
      require_unheld!(Hex.API.Release.get(repo, name, version, auth), name, version)

      accepted!(
        Hex.API.Release.publish(repo, File.read!(archive), auth),
        name,
        version,
        "package"
      )
    end

    if docs do
      accepted!(
        Hex.API.ReleaseDocs.publish(repo, name, version, File.read!(docs), auth),
        name,
        version,
        "docs"
      )
    end
  end

  defp require_unheld!({:ok, {404, _headers, _body}}, _name, _version), do: :ok

  defp require_unheld!({:ok, {200, _headers, _body}}, name, version) do
    raise "Hex already holds #{name} #{version} (awaiting approval or not yet propagated); approve it on hex.pm, then dispatch Publish again on the same commit"
  end

  defp require_unheld!(_result, name, version) do
    raise "could not confirm whether Hex holds #{name} #{version}; publication refused"
  end

  defp accepted!({:ok, {code, _headers, body}}, name, version, label) when code in 200..299 do
    if is_map(body) and body["status"] == "staged" do
      raise "Hex holds #{name} #{version}'s #{label} for approval; approve it on hex.pm, then dispatch Publish again on the same commit; the next run uploads only what is missing."
    end

    IO.puts("Hex #{label}: archive accepted")
  end

  defp accepted!(_result, name, version, label) do
    raise "#{name} #{version} #{label} upload failed; nothing was replaced. Dispatch Publish again on the same commit once the cause is resolved; the next run uploads only what is missing."
  end
end

PublishHexArtifacts.main(System.argv())
