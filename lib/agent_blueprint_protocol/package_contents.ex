defmodule AgentBlueprintProtocol.PackageContents do
  @moduledoc """
  Verifies installed release files against a checksum from the published release manifest.

  Pass the installation root and the matching entry in `package_checksums`
  from a trusted copy of the release's `release-manifest.json`. Verification
  reads the specified installation on demand.
  """

  alias AgentBlueprintProtocol.{Error, FramedFiles}

  @domain "agent-blueprint-protocol/package-contents"
  @exclusions %{
    hex: ~w(priv/release-metadata.json priv/release-history.json .hex hex_metadata.config),
    npm: ~w(dist/release-metadata.json dist/release-history.json)
  }

  @typedoc "Registry distribution named by the published manifest."
  @type distribution :: :hex | :npm

  @doc """
  Checks the package files at `root` against the published `expected` checksum.

  An unsuccessful result identifies the checksum field and distribution.
  A malformed checksum returns `:digest_encoding_invalid`, an unreadable or
  unsupported tree returns `:invalid_constraint`, and a different digest
  returns `:digest_mismatch`.
  """
  @doc since: "1.2.0"
  @spec verify(Path.t(), distribution(), term()) :: :ok | {:error, Error.t()}
  def verify(root, distribution, expected) when is_map_key(@exclusions, distribution) do
    cond do
      not is_binary(expected) or
          not Regex.match?(~r/\Asha-256:[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]\z/, expected) ->
        denial(:digest_encoding_invalid, distribution)

      checksum!(root, distribution) == expected ->
        :ok

      true ->
        denial(:digest_mismatch, distribution)
    end
  rescue
    File.Error -> denial(:invalid_constraint, distribution)
  end

  @doc false
  @spec checksum!(Path.t(), distribution()) :: binary()
  def checksum!(root, distribution) do
    exclusions = Map.fetch!(@exclusions, distribution)
    prefix = [@domain, 0, Atom.to_string(distribution), 0]
    FramedFiles.digest(paths!(root, "", exclusions), &File.read!(Path.join(root, &1)), prefix)
  end

  defp paths!(root, relative, exclusions) do
    directory = Path.join(root, relative)

    # Raw names must reach the path check so they cannot disappear from the digest.
    names =
      case :file.list_dir_all(directory) do
        {:ok, names} ->
          names

        {:error, reason} ->
          raise File.Error, reason: reason, action: "list directory", path: directory
      end

    Enum.flat_map(names, fn entry ->
      name = IO.chardata_to_string(entry)

      unless String.valid?(name) and not String.contains?(name, "\\"),
        do: raise(File.Error, reason: :einval, action: "read package entry", path: root)

      path = relative <> name
      absolute = Path.join(root, path)

      case File.lstat!(absolute).type do
        :directory ->
          paths!(root, path <> "/", exclusions)

        :regular ->
          if path in exclusions, do: [], else: [path]

        _ ->
          raise File.Error, reason: :einval, action: "read package entry", path: absolute
      end
    end)
  end

  defp denial(code, distribution) do
    {:error, %Error{code: code, subject: ["package_checksums", Atom.to_string(distribution)]}}
  end
end
