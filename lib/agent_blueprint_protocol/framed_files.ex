defmodule AgentBlueprintProtocol.FramedFiles do
  @moduledoc false

  @spec digest([binary()], (binary() -> binary()), iodata()) :: binary()
  def digest(paths, read, prefix) do
    hash = :crypto.hash_update(:crypto.hash_init(:sha256), prefix)

    digest =
      paths
      |> Enum.sort()
      |> Enum.reduce(hash, fn path, hash ->
        bytes = read.(path)

        :crypto.hash_update(hash, [<<byte_size(path)::64>>, path, <<byte_size(bytes)::64>>, bytes])
      end)
      |> :crypto.hash_final()

    "sha-256:" <> Base.url_encode64(digest, padding: false)
  end
end
