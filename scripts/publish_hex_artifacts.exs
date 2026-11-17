# Hex 2.7.0's archive API submits these exact bytes to the public hexpm repository.
# Do not rebuild here, persist authentication, or print response bodies/credentials.
defmodule PublishHexArtifacts do
  @moduledoc false

  def main([version, archive, docs]) do
    key = System.fetch_env!("HEX_API_KEY")
    if key == "", do: raise("HEX_API_KEY absent; publication stopped")
    Hex.start()

    package = Hex.API.Release.publish("hexpm", File.read!(archive), key: key)
    package_state = accepted!(package, "Hex package")

    documentation =
      Hex.API.ReleaseDocs.publish(
        "hexpm",
        "agent_blueprint_protocol",
        version,
        File.read!(docs),
        key: key
      )

    docs_state = accepted!(documentation, "Hex docs")

    if :staged in [package_state, docs_state] do
      raise "Hex approval pending; approve on hex.pm and recover by hand with verified artifacts"
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
