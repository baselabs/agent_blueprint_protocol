defmodule AgentBlueprintProtocol.PackageContentsTest do
  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{Error, PackageContents, Scratch}

  @hex "sha-256:-N1GvPYuKnv6Br--iACuSSCvmVojkp5MQGObQb0b41w"
  @npm "sha-256:4M6Z06tLFrxM9rwwrYtoAhLPVXNtiSP3dKOmebaG0yY"

  setup do
    root = Scratch.dir!("package-contents")
    on_exit(fn -> File.rm_rf!(root) end)

    File.mkdir!(Path.join(root, "nested"))

    for {path, bytes} <- [
          {".sample", <<0, 255>>},
          {"nested/z", "abc"},
          {"nested/中", ""},
          {"nested/𐀀", "d"},
          {"nested/\uE000", "e"}
        ],
        do: File.write!(Path.join(root, path), bytes)

    %{root: root}
  end

  test "both distributions match independent framed vectors", %{root: root} do
    assert PackageContents.verify(root, :hex, @hex) == :ok
    assert PackageContents.verify(root, :npm, @npm) == :ok
    assert PackageContents.verify(root, :npm, @hex) == mismatch("npm")
  end

  test "only the named release records and Hex installation metadata are excluded", %{root: root} do
    File.mkdir!(Path.join(root, "priv"))

    for path <- ~w(priv/release-metadata.json priv/release-history.json .hex hex_metadata.config),
        do: File.write!(Path.join(root, path), "record")

    assert PackageContents.verify(root, :hex, @hex) == :ok
    assert PackageContents.verify(root, :npm, @npm) == mismatch("npm")

    File.mkdir!(Path.join(root, "dist"))

    for path <- ~w(dist/release-metadata.json dist/release-history.json),
        do: File.write!(Path.join(root, path), "record")

    File.rm_rf!(Path.join(root, "priv"))
    File.rm!(Path.join(root, ".hex"))
    File.rm!(Path.join(root, "hex_metadata.config"))

    assert PackageContents.verify(root, :npm, @npm) == :ok
    assert PackageContents.verify(root, :hex, @hex) == mismatch("hex")
  end

  test "changed, added, and removed files fail verification", %{root: root} do
    file = Path.join(root, "nested/z")
    File.write!(file, "abd")
    assert PackageContents.verify(root, :hex, @hex) == mismatch("hex")
    File.write!(file, "abc")

    extra = Path.join(root, ".extra")
    File.write!(extra, "")
    assert PackageContents.verify(root, :hex, @hex) == mismatch("hex")
    File.rm!(extra)

    File.rm!(file)
    assert PackageContents.verify(root, :hex, @hex) == mismatch("hex")
  end

  test "invalid checksums and unreadable roots return typed denials", %{root: root} do
    assert {:error, %Error{code: :digest_encoding_invalid, subject: ["package_checksums", "hex"]}} =
             PackageContents.verify(root, :hex, nil)

    assert PackageContents.verify(root, :hex, @hex <> "\n") ==
             {:error,
              %Error{code: :digest_encoding_invalid, subject: ["package_checksums", "hex"]}}

    assert PackageContents.verify(Path.join(root, "missing"), :hex, @hex) ==
             {:error, %Error{code: :invalid_constraint, subject: ["package_checksums", "hex"]}}
  end

  if not match?({:win32, _}, :os.type()) do
    test "links cannot stand in for packaged files", %{root: root} do
      File.ln_s!(Path.join(root, ".sample"), Path.join(root, "linked"))

      assert PackageContents.verify(root, :hex, @hex) ==
               {:error, %Error{code: :invalid_constraint, subject: ["package_checksums", "hex"]}}
    end

    test "path separators in entry names cannot alter framing", %{root: root} do
      File.write!(Path.join(root, "x\\y"), "")

      assert PackageContents.verify(root, :hex, @hex) ==
               {:error, %Error{code: :invalid_constraint, subject: ["package_checksums", "hex"]}}
    end
  end

  if :os.type() == {:unix, :linux} do
    test "a raw filename makes the package tree unverifiable", %{root: root} do
      path = root <> "/" <> <<255>>
      :ok = :file.write_file(path, "")
      on_exit(fn -> :file.delete(path) end)

      assert PackageContents.verify(root, :hex, @hex) ==
               {:error, %Error{code: :invalid_constraint, subject: ["package_checksums", "hex"]}}
    end
  end

  defp mismatch(distribution),
    do: {:error, %Error{code: :digest_mismatch, subject: ["package_checksums", distribution]}}
end
