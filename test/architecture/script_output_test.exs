defmodule AgentBlueprintProtocol.Architecture.ScriptOutputTest do
  use ExUnit.Case, async: true

  # Capture is confined to these exact helpers. Every other native launch must
  # stream. Diagnostics contain locations only, never source or child output.
  @capture_elixir ~S'''
  def capture(program, args, options \\ []) do
    announce(program, args, options)
    System.cmd(program, args, options)
  end
  '''
  @port_elixir ~S'''
  def open(program, args, options) do
    announce(program, args, [])
    Port.open({:spawn_executable, program}, [args: args] ++ options)
  end
  '''
  @capture_node """
  export function capture(program,args,options={}) {
    announce(program,args,options);
    return spawnSync(program,args,options);
  }
  """
  @stream_node """
  export function stream(program,args,options={}) {
    announce(program,args,options);
    return spawnSync(program,args,{...options,stdio:'inherit'});
  }
  """
  @standalone_node """
  const result=spawnSync(program,args,{cwd:scratch,stdio:'inherit'});
  """
  @kit_node ~s|const result = spawnSync(process.execPath, [cli, ...args], { stdio: "inherit" });|
  @node_call ~r/\b(?:spawnSync|spawn|execFileSync|execFile|execSync|exec)\s*\(/

  test "every script child streams or announces before capture" do
    offenders =
      for path <- Path.wildcard("scripts/**/*.{ex,exs,js,mjs,cjs,ts}"),
          line <- violations(File.read!(path), Path.extname(path), path),
          do: "#{path}:#{line}"

    assert offenders == [], "silent child process at " <> Enum.join(offenders, ", ")
  end

  test "capture helpers announce program, arguments, and cwd without environment values" do
    elixir = File.read!("scripts/gate_command.exs")
    node = File.read!("scripts/gate_command.mjs")

    elixir_valid =
      blank(elixir, @capture_elixir) != elixir and blank(elixir, @port_elixir) != elixir and
        elixir =~ ~S'IO.puts(:stderr, "command: #{inspect([program | args])} (cwd: #{cwd})")' and
        not (elixir =~ "get_env")

    node_valid =
      node =~ @capture_node and node =~ @stream_node and
        node =~
          "process.stderr.write('command: '+JSON.stringify([program,...args])+' (cwd: '+cwd+')\\n');" and
        not (node =~ "process.env")

    assert elixir_valid, "scripts/gate_command.exs:1"
    assert node_valid, "scripts/gate_command.mjs:1"
  end

  test "literal samples reject silent, indirect, and overridden launches" do
    for source <- [
          ~s|System.cmd("mix", ["deps.get"])|,
          ~s|System.cmd(program, args, options)|,
          ~s|System.cmd(program, args, into: buffer)|,
          ~s|System.cmd(program, args, [into: IO.stream()] ++ options)|,
          ~s|Port.open({:spawn_executable, git}, options)|,
          ~s|System.shell("git status")|,
          ~s|:os.cmd(~c"git status")|,
          ~s|:erlang.open_port({:spawn, ~c"git status"}, [])|,
          ~s|alias System, as: Child; Child.cmd(program, args)|,
          ~s|apply(System, :cmd, [program, args])|
        ] do
      assert violations(source, ".exs", "sample") != []
    end

    for source <- [
          ~s|System.cmd("mix", ["deps.get"], into: IO.stream(), stderr_to_stdout: true)|,
          ~s|AgentBlueprintProtocol.GateCommand.capture(program, args, options)|
        ] do
      assert violations(source, ".exs", "sample") == []
    end

    for source <- [
          "spawnSync(program,args,{encoding:'utf8'});",
          "spawnSync(program,args,{stdio:'inherit',...options});",
          "execFileSync(program,args);",
          "child.spawn(program,args);",
          "import {spawnSync as hidden} from 'node:child_process'; hidden(program,args);"
        ] do
      assert violations(source, ".mjs", "sample") != []
    end

    assert violations(@standalone_node, ".mjs", "scripts/run_package_typescript_examples.mjs") ==
             []

    assert violations(@capture_node, ".mjs", "scripts/gate_command.mjs") == []

    assert violations(@capture_elixir, ".exs", "scripts/gate_command.exs") == []

    assert violations(
             String.replace(@capture_elixir, "announce(program, args, options)", ""),
             ".exs",
             "scripts/gate_command.exs"
           ) != []

    assert violations(
             String.replace(@capture_node, "announce(program,args,options);", ""),
             ".mjs",
             "scripts/gate_command.mjs"
           ) != []
  end

  defp violations(source, extension, path) when extension in [".ex", ".exs"] do
    source =
      if path == "scripts/gate_command.exs" do
        source |> blank(@capture_elixir) |> blank(@port_elixir)
      else
        source
      end

    {_ast, lines} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {{:., _, [{:__aliases__, _, [:System]}, :cmd]}, meta, [_, _, options]} = ast, lines ->
          {ast, if(streaming?(options), do: lines, else: [meta[:line] | lines])}

        {{:., _, [{:__aliases__, _, [module]}, function]}, meta, _} = ast, lines
        when {module, function} in [{:System, :cmd}, {:System, :shell}, {:Port, :open}] ->
          {ast, [meta[:line] | lines]}

        {{:., _, [:os, function]}, meta, _} = ast, lines when function in [:cmd, :spawn] ->
          {ast, [meta[:line] | lines]}

        {{:., _, [:erlang, :open_port]}, meta, _} = ast, lines ->
          {ast, [meta[:line] | lines]}

        {:alias, meta, [{:__aliases__, _, [module]} | _]} = ast, lines
        when module in [:System, :Port] ->
          {ast, [meta[:line] | lines]}

        {:apply, meta, [{:__aliases__, _, [module]} | _]} = ast, lines
        when module in [:System, :Port] ->
          {ast, [meta[:line] | lines]}

        ast, lines ->
          {ast, lines}
      end)

    Enum.reverse(lines)
  end

  defp violations(source, _extension, path) do
    source =
      case path do
        "scripts/gate_command.mjs" -> source |> blank(@capture_node) |> blank(@stream_node)
        "scripts/run_package_typescript_examples.mjs" -> blank(source, @standalone_node)
        "scripts/build_kit.mjs" -> blank(source, @kit_node)
        _ -> source
      end

    calls = for [{offset, _}] <- Regex.scan(@node_call, source, return: :index), do: offset

    # No alternate child-process import or lookup can hide an aliased call.
    imports = node_imports(source, path)

    aliases =
      for [{offset, _}] <- Regex.scan(~r/child_process/, imports, return: :index), do: offset

    for offset <- calls ++ aliases do
      source |> binary_part(0, offset) |> String.split("\n") |> length()
    end
  end

  defp node_imports(source, owner)
       when owner in ["scripts/gate_command.mjs", "scripts/run_package_typescript_examples.mjs"],
       do: blank(source, "import {spawnSync} from 'node:child_process';")

  defp node_imports(source, "scripts/build_kit.mjs"),
    do: blank(source, ~s|import { spawnSync } from "node:child_process";|)

  defp node_imports(source, _path), do: source

  defp streaming?(options) when is_list(options) do
    case Keyword.get(options, :into) do
      {{:., _, [{:__aliases__, _, [:IO]}, :stream]}, _, []} -> true
      _ -> false
    end
  end

  defp streaming?(_options), do: false

  defp blank(source, allowed) do
    pattern =
      allowed |> String.split() |> Enum.map_join("\\s+", &Regex.escape/1) |> Regex.compile!()

    Regex.replace(
      pattern,
      source,
      fn match ->
        String.replace(match, ~r/[^\n]/, " ")
      end,
      global: false
    )
  end
end
