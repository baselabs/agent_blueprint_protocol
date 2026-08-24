defmodule AgentBlueprintProtocol.ArchitectureScan do
  @moduledoc false
  # Test-only static-analysis helpers backing the architecture gates
  # (package boundary, identifier naming, non-authorizing vocabulary, purity).
  #
  # This module lives under test/support and is loaded by test_helper.exs rather
  # than through elixirc_paths, so it is never shipped in the package and never
  # counts toward coverage. All logic is pure over source text and AST.

  @shipped_roots ["lib", "priv"]

  @doc "Source files (*.ex/*.exs) under the shipped-surface roots that exist."
  def source_files(roots \\ @shipped_roots) do
    roots
    |> Enum.flat_map(fn root -> Path.wildcard(Path.join(root, "**/*.{ex,exs}")) end)
    |> Enum.sort()
  end

  @doc """
  Every extension-stripped path segment (directories and basenames) beneath the
  shipped-surface roots. Used by the identifier gate to reject version tokens in
  paths (e.g. a `v1/` directory or a `blueprint_v2.ex` file).
  """
  def path_segments(roots \\ @shipped_roots) do
    roots
    |> Enum.flat_map(fn root -> Path.wildcard(Path.join(root, "**/*")) end)
    |> Enum.flat_map(&Path.split/1)
    |> Enum.map(&Path.rootname/1)
    |> Enum.uniq()
  end

  @doc """
  Executable identifiers in a source file: module-alias segments, def/defp
  /defmacro(p) names, and atom literals. `@moduledoc`/`@doc`/`@typedoc`
  /`@shortdoc` bodies are stripped first so documentation prose (which may
  legitimately describe the non-authorizing stance) is never scanned as an
  identifier. Returns `[{kind, string}]` where kind is :module | :function | :atom.
  """
  def identifiers(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path)

    {_ast, acc} =
      ast
      |> strip_docs()
      |> Macro.prewalk([], &collect/2)

    Enum.reverse(acc)
  end

  @non_version_hump_stems ["Base", "Ed", "IPV", "IPv", "Ipv"]

  @contract_identities MapSet.new([
                         {"mix.exs", :package_source_ref, ~S(source_ref: "v#{@version}")}
                       ])

  @doc false
  def package_source_ref_observations do
    "mix.exs"
    |> File.read!()
    |> then(&Regex.scan(~r/source_ref:\s*"v(?:#\{@version\}|\d+)"/, &1))
    |> Enum.map(fn [name] -> %{path: "mix.exs", kind: :package_source_ref, name: name} end)
  end

  @doc "True when a string carries a conventional implementation-version token."
  def version_token?(string) do
    Regex.match?(~r/(^|_)v\d/i, string) or
      Regex.match?(~r/[a-z0-9]V\d/, string) or
      version_hump_digit?(string)
  end

  @doc """
  Applies this repository's durable-identifier decision to one observed name.

  Implementation genealogy is rejected. The sole version-bearing durable
  identity is the exact package tag source reference emitted from `mix.exs`;
  path, kind, and spelling are all part of the allowlist key.
  """
  def check_durable_identifier(%{path: path, kind: kind, name: name}) do
    identity = {path, kind, name}

    cond do
      MapSet.member?(@contract_identities, identity) ->
        :ok

      version_token?(name) or package_source_ref?(name) ->
        {:error, :implementation_version_identifier}

      true ->
        :ok
    end
  end

  defp package_source_ref?(name),
    do: Regex.match?(~r/\bsource_ref\b.*\bv(?:#\{@version\}|\d)/i, name)

  defp version_hump_digit?(string) do
    ~r/[A-Z]+[a-z]*\d+/
    |> Regex.scan(string)
    |> Enum.map(fn [word] -> hump_stem(word) end)
    |> Enum.any?(&(&1 not in @non_version_hump_stems))
  end

  defp hump_stem(word), do: Regex.replace(~r/\d+\z/, word, "")

  @doc "True when a string carries authorization-decision vocabulary."
  def authorization_token?(string) do
    Regex.match?(~r/authoris|authoriz/i, string)
  end

  defp strip_docs(ast) do
    Macro.prewalk(ast, fn
      {:@, _, [{doc, _, [_body]}]} when doc in [:moduledoc, :doc, :typedoc, :shortdoc] ->
        {:@, [], [{doc, [], [true]}]}

      other ->
        other
    end)
  end

  defp collect({:defmodule, _, [{:__aliases__, _, segs} | _]} = node, acc)
       when is_list(segs) do
    {node, Enum.reduce(segs, acc, fn seg, a -> [{:module, Atom.to_string(seg)} | a] end)}
  end

  defp collect({kind, _, [{name, _, _} | _]} = node, acc)
       when kind in [:def, :defp, :defmacro, :defmacrop] and is_atom(name) do
    {node, [{:function, Atom.to_string(name)} | acc]}
  end

  defp collect(atom, acc) when is_atom(atom) and not is_boolean(atom) and not is_nil(atom) do
    {atom, [{:atom, Atom.to_string(atom)} | acc]}
  end

  defp collect(node, acc), do: {node, acc}

  @doc """
  Every remote {module, function} the compiled beam at `beam_path` can
  call, alias-expanded at compile time (a renamed alias cannot hide) and
  including compiler BIF rewrites (`Map.has_key?` arrives as `:maps.find`).
  Dynamic dispatch (`apply/3`) surfaces as `{:erlang, :apply}` — the gates
  ban it, which makes the census total over shipped code: a module not in
  the census cannot be reached without either a listed call site or apply.
  """
  @spec beam_remote_calls(Path.t()) :: [{module(), atom()}]
  def beam_remote_calls(beam_path) do
    disasm = :beam_disasm.file(:erlang.binary_to_list(to_string(beam_path)))
    self_mod = :erlang.element(2, disasm)
    disasm |> then(&:erlang.element(6, &1)) |> collect_remote(self_mod, []) |> Enum.uniq()
  end

  defp collect_remote({:extfunc, mod, fun, _arity}, _self, acc)
       when is_atom(mod) and is_atom(fun),
       do: [{mod, fun} | acc]

  # dynamic dispatch compiles to the dedicated apply opcodes, not extfuncs
  defp collect_remote({:apply, _arity}, _self, acc), do: [{:erlang, :apply} | acc]
  defp collect_remote({:apply_last, _arity, _dealloc}, _self, acc), do: [{:erlang, :apply} | acc]

  # direct cross-module calls (same-release beams) carry the target inline
  defp collect_remote({:call, _arity, {mod, fun, _a}} = instr, self, acc)
       when is_atom(mod) and is_atom(fun),
       do: if(mod == self, do: acc, else: collect_remote_tuple(instr, self, [{mod, fun} | acc]))

  defp collect_remote(tuple, self, acc) when is_tuple(tuple),
    do: collect_remote_tuple(tuple, self, acc)

  defp collect_remote([head | tail], self, acc),
    do: collect_remote(tail, self, collect_remote(head, self, acc))

  defp collect_remote(_other, _self, acc), do: acc

  defp collect_remote_tuple(tuple, self, acc),
    do:
      tuple
      |> :erlang.tuple_to_list()
      |> Enum.reverse()
      |> Enum.reduce(acc, &collect_remote(&1, self, &2))
end
