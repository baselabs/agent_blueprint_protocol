defmodule AgentBlueprintProtocol.Architecture.ScratchAllocationTest do
  @moduledoc """
  One rule for every scratch directory, in each runtime that makes one:
  the runtime's exclusive, unique-name primitive creates it, and the
  scope that created it removes it, also on failure. Nothing uses a fixed
  name under the shared temp directory.

  - Elixir: `AgentBlueprintProtocol.Scratch` (test/support/scratch.exs) is
    the only reader of `System.tmp_dir`. It creates with an exclusive mkdir
    under a random name and removes in `after`. ExUnit's `:tmp_dir` tag is
    not used: it leaves its directory behind after the test.
  - Node and TypeScript: `const dir = mkdtempSync(join(tmpdir(), "abp-..."))`,
    removed by `rmSync(dir, ...)` in a `finally`. Every `tmpdir()` call is
    that argument, and every `mkdtempSync` result is bound and removed.

  Goes RED on: any other reader of the temp directory, a `:tmp_dir` tag,
  a `tmpdir()` outside `mkdtempSync`, an unbound or unremoved
  `mkdtempSync`, and a scan that no longer sees the known allocators,
  which would make the gate vacuous.
  """

  use ExUnit.Case, async: true

  @self "test/architecture/scratch_allocation_test.exs"
  @scratch "test/support/scratch.exs"
  @elixir_roots ["lib", "scripts", "test"]
  @node_roots ["scripts", "verifier", "lib"]
  @known_node_allocators [
    "scripts/check_conformance_product.mjs",
    "scripts/check_release_promotion.mjs",
    "verifier/self_checks.ts"
  ]

  test "every Elixir scratch directory comes from Scratch" do
    offenders =
      for path <- files(@elixir_roots, "**/*.{ex,exs}"),
          path != @self,
          reason <- elixir_offences(path, File.read!(path)),
          do: {path, reason}

    assert offenders == [], "scratch directories outside Scratch: #{inspect(offenders)}"
    assert File.read!(@scratch) =~ "System.tmp_dir!()"

    assert elixir_offences("x.exs", ~s|Path.join(System.tmp_dir!(), "abp-x")|) != []
    assert elixir_offences("x.exs", "@moduletag :tmp_dir") != []
    assert elixir_offences("x.exs", "@tag tmp_dir: true") != []
    assert elixir_offences(@scratch, "System.tmp_dir!()") == []
  end

  test "every Node and TypeScript scratch directory is mkdtemp, bound and removed in finally" do
    sources =
      for path <- files(@node_roots, "**/*.{mjs,cjs,js,ts}"),
          not String.contains?(path, "node_modules/"),
          do: {path, File.read!(path)}

    offenders = for {path, source} <- sources, reason <- node_offences(source), do: {path, reason}
    assert offenders == [], "scratch directories outside the rule: #{inspect(offenders)}"

    allocators = for {path, source} <- sources, source =~ "mkdtempSync(", do: path

    assert @known_node_allocators -- allocators == [],
           "the scan no longer sees #{inspect(@known_node_allocators -- allocators)}"

    good =
      ~s|const d=mkdtempSync(join(tmpdir(),'abp-x-'));try{}finally{rmSync(d,{recursive:true})}|

    assert node_offences(good) == []

    multiline = """
    const directory = mkdtempSync(join(tmpdir(), "abp-x-"));
    try {
    } finally {
      rmSync(directory, {recursive: true, force: true});
    }
    """

    assert node_offences(multiline) == []

    list =
      ~s|const root=resolve('.'),d=mkdtempSync(join(tmpdir(),'abp-x-'));try{}finally{rmSync(d,{recursive:true})}|

    assert node_offences(list) == []
    assert node_offences(~s|o.d=mkdtempSync(join(tmpdir(),'abp-x-'));|) != []
    assert node_offences(~s|writeFileSync(join(tmpdir(),'fixed.log'),'')|) != []
    assert node_offences(~s|const d=mkdtempSync(join(tmpdir(),'abp-x-'));|) != []
    assert node_offences(~s|cpSync(a, mkdtempSync(join(tmpdir(),'abp-x-')))|) != []
  end

  defp files(roots, glob) do
    roots
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, glob)))
    |> Enum.sort()
  end

  defp elixir_offences(path, source) do
    [
      (path != @scratch and source =~ "System.tmp_dir") && "reads System.tmp_dir outside Scratch",
      source =~ ~r/@(?:module|describe)?tag\s+(?::tmp_dir\b|tmp_dir:)/ && "uses ExUnit's :tmp_dir"
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp node_offences(source) do
    tmpdirs = count(source, ~r/\btmpdir\(\)/)
    allocations = count(source, ~r/\bmkdtempSync\(join\(tmpdir\(\)\s*,/)
    calls = count(source, ~r/\bmkdtempSync\(/)
    # A declarator binds the result, alone (`const d = mkdtempSync(...)`) or
    # inside a declaration list (`const root = ..., d = mkdtempSync(...)`).
    bound = Regex.scan(~r/(?<![.\w])(\w+)\s*=\s*mkdtempSync\(/, source, capture: :all_but_first)

    unremoved =
      for [name] <- bound,
          not Regex.match?(~r/finally\s*\{\s*rmSync\(#{name}\b/, source),
          do: "#{name} is not removed by rmSync in a finally"

    [
      tmpdirs != allocations && "tmpdir() outside mkdtempSync(join(tmpdir(), ...))",
      calls != length(bound) && "mkdtempSync result not bound to a const"
    ]
    |> Enum.filter(&is_binary/1)
    |> Kernel.++(unremoved)
  end

  defp count(source, regex), do: regex |> Regex.scan(source) |> length()
end
