Code.require_file("../scripts/package_examples.exs", __DIR__)

defmodule AgentBlueprintProtocol.PackageExamplesTest do
  use ExUnit.Case, async: true, group: :project_build

  @moduletag timeout: :infinity

  import ExUnit.CaptureIO
  alias AgentBlueprintProtocol.Scratch

  test "producer and glossary JSON excerpts execute in their packaged snippets" do
    documents = ["documentation/producer.md", "documentation/glossary.md"]

    for file <- documents do
      source = File.read!(file)
      snippets = PackageExamples.cells(source, file)
      json = Regex.scan(~r/^```json\r?\n(.*?)^```/ms, source, capture: :all_but_first)

      assert json != [], "#{file} must show JSON"
      assert snippets != [], "#{file} must check its JSON with runnable package snippets"

      for [example] <- json do
        assert Enum.any?(snippets, &String.contains?(&1.code, String.trim(example))),
               "#{file} has JSON that its package snippets do not exercise"
      end
    end

    Scratch.with_dir("guide-json", fn root ->
      archive = Path.join(root, "package.tar")

      {output, status} =
        System.cmd("mix", ["hex.build", "--output", archive], stderr_to_stdout: true)

      assert status == 0, output
      PackageExamples.run(archive, :snippets, documents)
    end)
  end

  test "each snippet document runs in its own consumer project" do
    Scratch.with_dir("snippet-isolation", fn root ->
      archive = Path.join(root, "package.tar")

      {build, status} =
        System.cmd("mix", ["hex.build", "--output", archive], stderr_to_stdout: true)

      assert status == 0, build

      probe = """
      ```elixir
      if File.exists?(".consumer-probe"), do: raise("document reused another consumer project")
      File.write!(".consumer-probe", "executed")
      ```
      """

      documents =
        for index <- 1..2 do
          path = Path.join(root, "guide-#{index}.md")
          File.write!(path, probe)
          path
        end

      output =
        capture_io(fn ->
          result =
            try do
              PackageExamples.run(archive, :snippets, documents)
            rescue
              error -> {:failed, Exception.message(error)}
            end

          send(self(), {:snippet_run, result})
        end)

      assert_received {:snippet_run, result}
      refute output =~ "document reused another consumer project", output
      assert result == :ok, "#{inspect(result)}\n" <> output
      assert output =~ "package snippets: 2 blocks in 2 documents passed outside the checkout"
    end)
  end

  # Every packaged document whose runnable Elixir cells generate a key runs in
  # real IEx, cell by cell with its prior bindings, against the local build.
  # After each cell the session records every 32-byte binary in its bindings
  # to a private scratch file; a generated Ed25519 pair is a recorded private
  # key whose derived public key is also recorded. The whole session output
  # must disclose neither key of any pair, alone or together, in any
  # rendering the detector knows. Key bytes and session output never enter a
  # failure message.
  @key_window 16
  @key_capture """
  Application.ensure_all_started(:crypto)

  defmodule KeyExampleCapture do
    def record(binding, path) do
      File.write!(path, binding |> Keyword.values() |> binaries([]) |> Enum.join(), [:append])
    end

    defp binaries(<<_::binary-size(32)>> = value, acc), do: [value | acc]
    defp binaries(value, acc) when is_tuple(value), do: binaries(Tuple.to_list(value), acc)
    defp binaries(%_{} = value, acc), do: binaries(Map.from_struct(value), acc)

    defp binaries(value, acc) when is_map(value),
      do: Enum.reduce(value, acc, fn {key, item}, acc -> binaries(item, binaries(key, acc)) end)

    defp binaries([head | tail], acc), do: binaries(tail, binaries(head, acc))
    defp binaries(_value, acc), do: acc
  end
  """

  test "interactive key examples disclose neither generated key and retain later block bindings" do
    documents = key_documents()
    assert "documentation/compose-and-sign.md" in documents
    assert Enum.any?(documents, &String.ends_with?(&1, ".livemd"))

    for file <- documents,
        cell <- interactive_cells(file),
        file == "documentation/compose-and-sign.md" or String.contains?(cell.code, "private_key") do
      code = String.trim(cell.code)

      assert String.starts_with?(code, "(\n") and String.ends_with?(code, "\n)"),
             "#{file} block #{cell.index}: interactive key examples must be one parenthesized expression"
    end

    Scratch.with_dir("interactive-signing", fn root ->
      for file <- documents do
        session =
          interactive_session(Path.join(root, Path.basename(file)), file, interactive_cells(file))

        assert session.status == 0, "#{file}: interactive session failed (exit #{session.status})"
        assert session.raised == false, "#{file}: interactive session raised an exception"
        assert session.pairs != [], "#{file}: no generated key pair reached a session binding"

        assert session.disclosures == [],
               "#{file}: interactive session disclosed generated key material"

        if file == "documentation/compose-and-sign.md" do
          assert session.summary, "#{file}: interactive blocks lost their bindings"
        end
      end
    end)
  end

  test "the interactive key gate rejects a printed private key and a printed key tuple" do
    file = "documentation/compose-and-sign.md"
    generation = "  {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)\n"

    controls = [
      {"printed-private-key", "  IO.inspect(private_key, limit: :infinity)\n", [:private]},
      {"printed-key-tuple",
       "  IO.inspect({public_key, private_key}, limit: :infinity, width: 24)\n",
       [:private, :public]}
    ]

    Scratch.with_dir("interactive-signing-controls", fn root ->
      for {name, plant, disclosed} <- controls do
        cells =
          for cell <- interactive_cells(file) do
            if String.contains?(cell.code, generation),
              do: %{cell | code: String.replace(cell.code, generation, generation <> plant)},
              else: cell
          end

        planted = Enum.filter(cells, &String.contains?(&1.code, plant))
        assert length(planted) == 1, "#{name}: the plant must land in exactly one key block"

        for cell <- planted do
          code = String.trim(cell.code)

          assert String.starts_with?(code, "(\n") and String.ends_with?(code, "\n)"),
                 "#{name}: the planted key block must stay one parenthesized expression"
        end

        session = interactive_session(Path.join(root, name), file, cells)
        assert session.status == 0, "#{name}: planted session failed (exit #{session.status})"
        assert session.raised == false, "#{name}: planted session raised an exception"
        assert session.summary, "#{name}: planted session lost its bindings"

        labels = session.disclosures |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()

        assert labels == disclosed,
               "#{name}: the gate must report exactly #{inspect(disclosed)} as disclosed, got #{inspect(labels)}"
      end
    end)
  end

  test "the key disclosure detector finds each key in every known rendering" do
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    {other_public, other_private} = :crypto.generate_key(:eddsa, :ed25519)
    pairs = [{public, private}]

    renderings = [
      integer_bytes: inspect(private, limit: :infinity),
      integer_bytes: inspect({public, private}, limit: :infinity, width: 24),
      integer_bytes: inspect(:binary.bin_to_list(private), limit: :infinity, width: 12),
      integer_bytes: inspect(private, base: :hex, limit: :infinity),
      integer_bytes: inspect(private, base: :binary, limit: :infinity),
      integer_bytes: inspect(private, base: :octal, limit: :infinity),
      hex: Base.encode16(private),
      hex: Base.encode16(private, case: :lower),
      hex:
        private |> Base.encode16() |> String.graphemes() |> Enum.chunk_every(2) |> Enum.join(":"),
      base64: Base.encode64(private),
      base64: Base.url_encode64(private, padding: false),
      base64: Base.encode64(<<48, 46, 2, 1, 0>> <> private),
      base64: Base.url_encode64(<<1, 2>> <> private <> <<3>>),
      raw_bytes: "prefix " <> private <> " suffix"
    ]

    for {rendering, text} <- renderings do
      found = disclosures(text, pairs)
      assert {:private, rendering} in found, "the detector missed a #{rendering} rendering"
    end

    assert {:public, :integer_bytes} in disclosures(inspect(public), pairs)

    clean =
      Enum.join(
        [
          inspect({other_public, other_private}, limit: :infinity),
          Base.encode16(other_private),
          Base.url_encode64(other_private),
          other_private,
          inspect(Enum.to_list(1..64))
        ],
        "\n"
      )

    assert disclosures(clean, pairs) == [], "the detector reported a key that was not printed"
  end

  defp key_documents do
    Mix.Project.config()[:package][:files]
    |> Enum.flat_map(&markdown_entry/1)
    |> Enum.filter(fn file ->
      file
      |> File.read!()
      |> PackageExamples.cells(file)
      |> Enum.any?(&(&1.code =~ "generate_key("))
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp markdown_entry(entry) do
    cond do
      String.ends_with?(entry, [".md", ".livemd", ".cheatmd"]) ->
        [entry]

      File.dir?(entry) ->
        for relative <-
              :filelib.wildcard(~c"**/*.{md,livemd,cheatmd}", String.to_charlist(entry)),
            not Enum.any?(Path.split(List.to_string(relative)), &String.starts_with?(&1, ".")),
            do: Path.join(entry, List.to_string(relative))

      true ->
        []
    end
  end

  # A notebook's install cell is the published-package step; the session uses
  # the local build on ERL_LIBS in its place. Every other cell runs as written.
  defp interactive_cells(file) do
    file
    |> File.read!()
    |> PackageExamples.cells(file)
    |> Enum.reject(&String.starts_with?(String.trim(&1.code), "Mix.install("))
  end

  # A guide block is pasted into IEx as written. A Livebook cell is evaluated
  # whole, with its final value shown, so the session feeds each notebook cell
  # to IEx as one parenthesized evaluation.
  defp interactive_session(root, file, cells) do
    File.mkdir_p!(root)
    capture = Path.join(root, "key-capture.bin")
    File.write!(capture, "")
    File.chmod!(capture, 0o600)
    prelude = Path.join(root, "prelude.exs")
    File.write!(prelude, @key_capture)
    input = Path.join(root, "input.exs")

    code =
      Enum.map_join(cells, "\n", fn cell ->
        evaluation =
          if Path.extname(file) == ".livemd", do: "(\n" <> cell.code <> "\n)", else: cell.code

        evaluation <> "\nKeyExampleCapture.record(binding(), #{inspect(capture)})\n"
      end)

    File.write!(input, code <> "\nSystem.halt(0)\n")

    {output, status} =
      System.cmd("sh", ["-c", ~s(iex --dot-iex "$1" < "$2"), "iex", prelude, input],
        cd: root,
        env: [{"ERL_LIBS", Path.join(Mix.Project.build_path(), "lib")}],
        stderr_to_stdout: true
      )

    recorded = for <<value::binary-size(32) <- File.read!(capture)>>, uniq: true, do: value
    File.rm!(capture)
    pairs = key_pairs(recorded)

    %{
      status: status,
      raised: String.contains?(output, "** ("),
      summary: String.contains?(output, "reloaded_pair: true"),
      pairs: pairs,
      disclosures: disclosures(output, pairs)
    }
  end

  defp key_pairs(recorded) do
    known = MapSet.new(recorded)

    for private <- recorded,
        {public, ^private} <- [:crypto.generate_key(:eddsa, :ed25519, private)],
        MapSet.member?(known, public),
        do: {public, private}
  end

  # Disclosure is any 16-byte (@key_window) run of a key: as raw bytes; as
  # integers in decimal, hex, octal or binary notation, in one line or wrapped
  # (binary and list inspection); as hex text in either case with or without
  # separators; or inside base64 or base64url text at any byte alignment,
  # padded or not, across line breaks.
  defp disclosures(output, pairs) do
    integers = integer_stream(output)
    compact = String.replace(output, ~r/\s+/, "")
    hex_text = output |> String.downcase() |> String.replace(~r/[\s:,"'_-]+/, "")

    for {public, private} <- pairs,
        {label, key} <- [private: private, public: public],
        rendering <- renderings(key, output, integers, compact, hex_text),
        uniq: true,
        do: {label, rendering}
  end

  defp renderings(key, output, integers, compact, hex_text) do
    windows =
      for offset <- 0..(byte_size(key) - @key_window), do: binary_part(key, offset, @key_window)

    checks = [
      raw_bytes: Enum.any?(windows, &(:binary.match(output, &1) != :nomatch)),
      integer_bytes: Enum.any?(windows, &integer_run?(integers, &1)),
      hex: Enum.any?(windows, &String.contains?(hex_text, Base.encode16(&1, case: :lower))),
      base64: Enum.any?(base64_windows(key), &String.contains?(compact, &1))
    ]

    for {rendering, true} <- checks, do: rendering
  end

  # Each integer in the output becomes two bytes: a byte value as <<0, value>>,
  # anything else as a separator <<1, 0>>. A key run then matches only at an
  # even offset.
  defp integer_stream(output) do
    ~r/0x[0-9A-Fa-f]+|0b[01]+|0o[0-7]+|\d+/
    |> Regex.scan(output)
    |> Enum.map(fn [token] ->
      case token do
        "0x" <> digits -> String.to_integer(digits, 16)
        "0b" <> digits -> String.to_integer(digits, 2)
        "0o" <> digits -> String.to_integer(digits, 8)
        digits -> String.to_integer(digits)
      end
    end)
    |> Enum.map_join(fn
      value when value in 0..255 -> <<0, value>>
      _value -> <<1, 0>>
    end)
  end

  defp integer_run?(stream, window) do
    pattern = for <<byte <- window>>, into: <<>>, do: <<0, byte>>
    stream |> :binary.matches(pattern) |> Enum.any?(fn {at, _} -> rem(at, 2) == 0 end)
  end

  # A base64 character depends on the key alone when all six of its bits fall
  # inside the key. For each of the three byte alignments, the run of such
  # characters is cut into windows that each encode at least 15 key bytes.
  defp base64_windows(key) do
    size = div((@key_window - 1) * 8 + 5, 6)

    for shift <- 0..2,
        encode <- [&Base.encode64(&1, padding: false), &Base.url_encode64(&1, padding: false)],
        text = encode.(<<0::size(shift * 8)>> <> key <> <<0, 0>>),
        first = div(shift * 8 + 5, 6),
        last = div((shift + byte_size(key)) * 8, 6) - 1,
        interior = binary_part(text, first, last - first + 1),
        offset <- 0..(byte_size(interior) - size),
        uniq: true,
        do: binary_part(interior, offset, size)
  end

  test "snippet extraction preserves order and source lines and skips only marked fragments" do
    source =
      "```elixir\nx = 1\n```\n<!-- fragment -->\n```elixir\nmissing()\n```\n```sh\nfalse\n```\n```elixir\nx + 1\n```\n"

    assert [%{code: "x = 1\n", index: 1, line: 2}, %{code: "x + 1\n", index: 3, line: 12}] =
             PackageExamples.cells(source, "guide.md")
  end

  test "fragment marking is adjacent, supports CRLF, and never hides an unknown info string" do
    for newline <- ["\n", "\r\n"] do
      marked = Enum.join(["<!-- fragment -->", "```elixir", "missing()", "```", ""], newline)
      assert PackageExamples.cells(marked, "guide.md") == []
      separated = String.replace(marked, "-->" <> newline, "-->" <> newline <> newline)
      assert length(PackageExamples.cells(separated, "guide.md")) == 1
    end

    for marking <- ["fragment", "ignored"] do
      assert_raise RuntimeError, ~r/unknown Elixir fence marking/, fn ->
        PackageExamples.cells(
          "<!-- fragment -->\n```elixir #{marking}\nmissing()\n```\n",
          "guide.md"
        )
      end
    end
  end

  test "the TypeScript package gate skips comment fragments and rejects all info suffixes" do
    Scratch.with_dir("typescript-fragments", fn root ->
      {packed, 0} =
        System.cmd("node", [
          "scripts/npm.mjs",
          "pack",
          "./dist/package",
          "--ignore-scripts",
          "--json",
          "--pack-destination",
          root
        ])

      [%{"filename" => filename}] = Jason.decode!(packed)
      archive = Path.join(root, filename)
      file = Path.join(root, "guide.md")

      for newline <- ["\n", "\r\n"] do
        source =
          for language <- ~w(js javascript ts typescript), into: "" do
            Enum.join(
              [
                "<!-- fragment -->",
                "```#{language}",
                "throw new Error('fragment was executed')",
                "```",
                "```#{language}",
                "console.log('runnable block')",
                "```",
                ""
              ],
              newline
            )
          end

        File.write!(file, source)

        {output, status} =
          System.cmd("node", ["scripts/run_package_typescript_examples.mjs", archive, file],
            stderr_to_stdout: true
          )

        assert status == 0, "TypeScript comment fragments must be skipped: " <> output
        assert output =~ "package TypeScript: 4 examples passed"
      end

      for marking <- ["fragment", "ignored"] do
        File.write!(
          file,
          "<!-- fragment -->\n```ts #{marking}\nthrow new Error('must not run')\n```\n"
        )

        {output, status} =
          System.cmd("node", ["scripts/run_package_typescript_examples.mjs", archive, file],
            stderr_to_stdout: true
          )

        assert status != 0
        assert output =~ "unknown fence marking"
      end
    end)
  end

  test "an unknown snippet marking fails instead of hiding unrunnable code" do
    assert_raise RuntimeError, ~r/guide.md block 1: unknown Elixir fence marking/, fn ->
      PackageExamples.cells("```elixir ignored\nmissing()\n```\n", "guide.md")
    end
  end
end
