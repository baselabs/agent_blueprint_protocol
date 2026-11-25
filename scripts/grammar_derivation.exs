# The grammar derivation: parses the disciplined CDDL subset under
# spec/grammar/ and renders the derived JSON Schema files. The gate entry
# is scripts/check_grammar_derivation.exs; tests require this file to
# exercise the derivation without running the gate on load.

defmodule AgentBlueprintProtocol.GrammarDerivation do
  @name_re ~r/^[a-z0-9][a-z0-9-]*$/

  @grammar_dir "spec/grammar"
  @derived_dir "spec/grammar/derived"

  @artifacts [
    {"blueprint.cddl", "blueprint", "blueprint-decode"},
    {"deployment.cddl", "deployment", "deployment-decode"},
    {"taskenvelope.cddl", "taskenvelope", "federation-decode"},
    {"procedure.cddl", "procedure", "procedure-verify"}
  ]

  def run(write?) do
    findings =
      Enum.flat_map(@artifacts, fn {cddl, root, decode_case} ->
        derive_findings(cddl, root, decode_case, write?)
      end)

    findings = findings ++ procedure_twin_findings(write?)

    if findings != [] do
      raise """
      grammar derivation: FAILED

      #{Enum.join(findings, "\n")}
      """
    end

    goldens =
      @artifacts
      |> Enum.map(fn {_, root, decode} ->
        count = golden_count(root, decode)
        "#{root}: #{count} goldens"
      end)
      |> Enum.join(", ")

    IO.puts(
      "grammar derivation: ok (#{length(@artifacts)} grammars derived byte-exact; #{goldens})"
    )
  end

  defp procedure_twin_findings(write?) do
    {:ok, schema} = derive(File.read!(Path.join(@grammar_dir, "procedure.cddl")), "procedure")

    bytes =
      "// Derived from spec/grammar/procedure.cddl by grammar.derivation.\nexport const PROCEDURE_SCHEMA = " <>
        Jason.encode!(schema) <> ";\n"

    path = "verifier/procedure_schema.ts"

    if write? do
      File.write!(path, bytes)
      []
    else
      if File.read!(path) == bytes, do: [], else: ["#{path} differs from the derived schema"]
    end
  end

  defp derive_findings(cddl, root, decode_case, write?) do
    source = File.read!(Path.join(@grammar_dir, cddl))

    case derive(source, root) do
      {:ok, schema} ->
        json = render(schema)
        path = Path.join(@derived_dir, "#{root}.schema.json")

        cond do
          write? ->
            File.write!(path, json)
            corpus_findings(root, decode_case, schema) ++ table_coupling_findings(root, schema)

          not File.exists?(path) ->
            ["#{path} is missing — run `mix grammar.derivation --write`"]

          File.read!(path) != json ->
            [
              "#{path} does not match a fresh derivation of #{cddl} — " <>
                "the derived files are never hand-edited (regenerate, or fix the CDDL)"
            ]

          true ->
            corpus_findings(root, decode_case, schema) ++ table_coupling_findings(root, schema)
        end

      {:error, reason} ->
        ["#{cddl}: #{reason}"]
    end
  end

  # Root cross-read: the derived root schema carries EXACTLY the
  # compiled registry's member names and required flags — a loosened
  # grammar (member dropped from required, member invented) reds even
  # when every corpus golden still carries the member.
  defp table_coupling_findings(root, schema) do
    {compiled_names, compiled_required} =
      case root do
        "blueprint" ->
          table = AgentBlueprintProtocol.Blueprint.table()
          {Enum.map(table, & &1.name), table |> Enum.filter(& &1.required) |> Enum.map(& &1.name)}

        "deployment" ->
          table = AgentBlueprintProtocol.Deployment.table()
          {Enum.map(table, & &1.name), table |> Enum.filter(& &1.required) |> Enum.map(& &1.name)}

        "procedure" ->
          table = AgentBlueprintProtocol.Procedure.table()
          {Enum.map(table, & &1.name), table |> Enum.filter(& &1.required) |> Enum.map(& &1.name)}

        "taskenvelope" ->
          names = AgentBlueprintProtocol.Federation.envelope_members()
          {names, nil}
      end

    root_def = schema["$defs"][root]
    derived_names = Map.keys(root_def["properties"] || %{})
    derived_required = root_def["required"] || []

    name_drift =
      List.wrap(
        if compiled_names -- derived_names != [],
          do: "grammar is missing members: #{inspect(compiled_names -- derived_names)}"
      ) ++
        List.wrap(
          if derived_names -- compiled_names != [],
            do: "grammar invents members: #{inspect(derived_names -- compiled_names)}"
        )

    required_drift =
      if compiled_required == nil do
        []
      else
        List.wrap(
          if compiled_required -- derived_required != [],
            do:
              "grammar loosened required members: #{inspect(compiled_required -- derived_required)}"
        ) ++
          List.wrap(
            if derived_required -- compiled_required != [],
              do:
                "grammar tightened members into required: #{inspect(derived_required -- compiled_required)}"
          )
      end

    name_drift ++ required_drift
  end

  # Corpus goldens: every VALID case of the artifact's decode surface
  # plus the golden vectors must validate under the derived schema.
  defp corpus_findings("procedure", _decode_case, schema) do
    cases = Jason.decode!(File.read!(case_file("procedure-verify")))["cases"]
    {:ok, tagged_schema} = schema |> Jason.encode!() |> AgentBlueprintProtocol.Json.decode()

    Enum.flat_map(Enum.filter(cases, &(&1["expected"]["verdict"] == "valid")), fn c ->
      deployment = Jason.decode!(c["input"]["text"])

      {:ok, body} =
        deployment["extensions"]["critical"]["io.github.baselabs/procedure"]
        |> Jason.encode!()
        |> AgentBlueprintProtocol.Json.decode()

      case AgentBlueprintProtocol.Schema.validate_instance(
             tagged_schema,
             body,
             AgentBlueprintProtocol.Schema.dialect()
           ) do
        :ok -> []
        {:error, error} -> ["procedure golden #{c["id"]} fails its schema: #{inspect(error)}"]
      end
    end)
  end

  defp corpus_findings(root, decode_case, schema) do
    cases =
      decode_case
      |> case_file()
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("cases")
      |> Enum.filter(&(&1["expected"]["verdict"] == "valid" and is_binary(&1["input"]["text"])))
      |> Enum.map(&{&1["id"], &1["input"]["text"]})

    vectors =
      case Path.wildcard("priv/conformance/vectors/#{root}*golden.json") do
        [] ->
          []

        files ->
          files |> Enum.map(&File.read!/1) |> Enum.map(&Jason.decode!/1)
      end

    # The validator speaks the tagged Json representation: case inputs
    # arrive as JSON text (decode directly); vectors and the derived
    # schema arrive as decoded maps (encode→decode to tag them).
    tag = fn value ->
      {:ok, tagged} = value |> Jason.encode!() |> AgentBlueprintProtocol.Json.decode()
      tagged
    end

    instances =
      Enum.map(cases, fn {id, text} ->
        {:ok, instance} = AgentBlueprintProtocol.Json.decode(text)
        {id, instance}
      end) ++
        Enum.with_index(vectors, fn v, i -> {"golden-vector-#{i}", tag.(v)} end)

    tagged_schema = tag.(schema)

    Enum.flat_map(instances, fn {id, instance} ->
      case AgentBlueprintProtocol.Schema.validate_instance(
             tagged_schema,
             instance,
             "https://json-schema.org/draft/2020-12/schema"
           ) do
        :ok ->
          []

        {:error, reason} ->
          ["#{root} golden #{inspect(id)} fails its derived schema: #{inspect(reason)}"]
      end
    end)
  end

  defp golden_count(root, decode_case) do
    valid_cases =
      decode_case
      |> case_file()
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("cases")
      |> Enum.count(&(&1["expected"]["verdict"] == "valid"))

    valid_cases + length(Path.wildcard("priv/conformance/vectors/#{root}*golden.json"))
  end

  defp case_file(decode_case), do: "priv/conformance/cases/#{decode_case}.json"

  # ---- the CDDL subset parser -------------------------------------------
  #
  # Total and fail-closed: every construct outside the disciplined
  # subset is an {:error, reason}, never a guess.

  def derive(source, root_rule) do
    with {:ok, rules} <- parse_rules(strip_comments(source), %{}, "") do
      if Map.has_key?(rules, root_rule) do
        {:ok,
         %{
           "$defs" =>
             Map.new(rules, fn {name, expr} ->
               {name, render_type(Map.put(expr, :root?, name == root_rule), rules)}
             end),
           "$ref" => "#/$defs/#{root_rule}"
         }}
      else
        {:error, "root rule #{inspect(root_rule)} is not defined"}
      end
    end
  end

  defp strip_comments(source) do
    source
    |> String.split("\n")
    |> Enum.map(fn line -> line |> String.split(";") |> hd() |> String.trim() end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  # Rules are line-oriented: a rule starts at `name =` and its body is
  # the remaining text on that line plus subsequent continuation lines
  # up to the next rule, including map-choice arms.
  defp parse_rules("", rules, _partial), do: {:ok, rules}

  defp parse_rules(source, rules, _partial) do
    lines = String.split(source, "\n")

    case take_rule(lines) do
      {name, body, []} ->
        finalize_rule(name, body, rules)

      {name, body, rest} ->
        with {:ok, parsed} <- parse_type(String.trim(body), rules, name) do
          parse_rules(Enum.join(rest, "\n"), Map.put(rules, name, parsed), "")
        else
          {:error, reason} -> {:error, "#{name}: #{reason}"}
        end

      {:error, _reason} = error ->
        error

      nil ->
        {:ok, rules}
    end
  end

  defp finalize_rule(name, body, rules) do
    with {:ok, parsed} <- parse_type(String.trim(body), rules, name) do
      {:ok, Map.put(rules, name, parsed)}
    else
      {:error, reason} -> {:error, "#{name}: #{reason}"}
    end
  end

  @rule_start_re ~r/^([a-z0-9][a-z0-9-]*)\s*=\s*(.*)$/

  defp take_rule([]), do: nil

  defp take_rule([line | rest]) do
    case Regex.run(@rule_start_re, line) do
      [_, name, first] ->
        {continuation, remainder} =
          Enum.split_while(rest, &(not Regex.match?(@rule_start_re, &1)))

        body = Enum.join([first | continuation], "\n")
        {name, body, remainder}

      nil ->
        # Fail-closed: a top-level line that is not a rule start is
        # unsupported syntax (continuation lines were consumed with
        # their rule body) — skipping it would let the normative
        # grammar text diverge from the derived schema silently.
        {:error, "unsupported top-level syntax: #{inspect(line)}"}
    end
  end

  # Split only outside maps, arrays and quoted strings. Unbalanced delimiters
  # fail before rendering, including choices with an empty or unsupported arm.
  defp parse_type(expr, rules, ctx) do
    with {:ok, arms} <- split_top_level(expr, ["/"]) do
      cond do
        length(arms) == 1 ->
          parse_term(hd(arms), rules, ctx)

        Enum.all?(arms, &String.starts_with?(&1, "\"")) ->
          parse_enum(arms)

        Enum.all?(arms, &String.starts_with?(&1, "{")) ->
          arms
          |> Enum.reduce_while({:ok, []}, fn arm, {:ok, parsed} ->
            case parse_term(arm, rules, ctx) do
              {:ok, %{kind: :object} = object} -> {:cont, {:ok, parsed ++ [object]}}
              {:error, _} = error -> {:halt, error}
            end
          end)
          |> case do
            {:ok, choices} -> {:ok, %{kind: :choice, choices: choices}}
            error -> error
          end

        true ->
          {:error, "unsupported type choice"}
      end
    end
  end

  defp parse_term("{" <> body, rules, _ctx) do
    body = body |> String.replace_suffix("}", "") |> String.trim()

    with {:ok, members} <- split_members(body) do
      members
      |> Enum.reduce_while({:ok, {[], []}}, fn raw, {:ok, {props, req}} ->
        case parse_member(raw, rules) do
          {:ok, {name, optional?, type}} ->
            req = if optional?, do: req, else: [name | req]
            {:cont, {:ok, {[{name, type} | props], req}}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, {props, req}} ->
          {:ok,
           %{
             kind: :object,
             properties: Map.new(props),
             required: Enum.reverse(req)
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp parse_term("[" <> body, rules, _ctx) do
    body = body |> String.replace_suffix("]", "") |> String.trim()

    with {:ok, min, max, item_expr} <- parse_occurrence(body),
         {:ok, item} <- parse_type(item_expr, rules, "array item") do
      {:ok, %{kind: :array, min: min, max: max, item: item}}
    end
  end

  defp parse_term(expr, _rules, _ctx) do
    cond do
      expr in ["tstr", "text"] -> {:ok, %{kind: :string}}
      expr in ["integer", "int", "uint"] -> {:ok, %{kind: :integer}}
      expr == "null" -> {:ok, %{kind: :null}}
      expr == "bool" -> {:ok, %{kind: :boolean}}
      expr == "any" -> {:ok, %{kind: :any}}
      expr == "integer .gt 0" -> {:ok, %{kind: :integer, minimum: 1}}
      String.starts_with?(expr, "\"") -> parse_enum([expr])
      Regex.match?(@name_re, expr) -> {:ok, %{kind: :ref, target: expr}}
      true -> {:error, "unsupported type expression: #{inspect(expr)}"}
    end
  end

  defp parse_enum(arms) do
    arms
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case Jason.decode(part) do
        {:ok, value} when is_binary(value) -> {:cont, {:ok, acc ++ [value]}}
        _ -> {:halt, {:error, "unsupported string literal: #{inspect(part)}"}}
      end
    end)
    |> case do
      {:ok, [value]} -> {:ok, %{kind: :literal, value: value}}
      {:ok, values} -> {:ok, %{kind: :enum, values: values}}
      error -> error
    end
  end

  defp parse_member(raw, rules) do
    trimmed = String.trim(raw)

    with {:ok, optional?, rest} <- take_optional(trimmed) do
      case Regex.run(~r/^([a-z0-9_][a-z0-9_-]*)\s*:\s*(.+)$/s, String.trim(rest)) do
        [_, key, type_expr] ->
          case parse_type(String.trim(type_expr), rules, key) do
            {:ok, type} -> {:ok, {key, optional?, type}}
            {:error, reason} -> {:error, "member #{inspect(key)}: #{reason}"}
          end

        nil ->
          {:error, "unsupported member syntax: #{inspect(trimmed)}"}
      end
    end
  end

  defp take_optional("? " <> rest), do: {:ok, true, rest}
  defp take_optional("?" <> rest), do: {:ok, true, rest}
  defp take_optional(rest), do: {:ok, false, rest}

  # CDDL group entries separate by commas OR newlines (RFC 8610 §3.5),
  # but only at group depth zero — a nested inline map's own commas and
  # newlines do not separate the outer group's entries.
  defp split_members(body), do: split_top_level(body, [",", "\n"])

  defp split_top_level(source, separators),
    do: split_tokens(String.graphemes(source), separators, [], false, false, "", [])

  defp split_tokens([], _separators, [], false, false, current, parts) do
    if String.trim(current) == "",
      do: {:error, "empty type or member"},
      else: {:ok, parts ++ [String.trim(current)]}
  end

  defp split_tokens([], _separators, _stack, _quoted, _escaped, _current, _parts),
    do: {:error, "unbalanced type expression"}

  defp split_tokens([ch | rest], separators, stack, true, escaped, current, parts) do
    cond do
      escaped -> split_tokens(rest, separators, stack, true, false, current <> ch, parts)
      ch == "\\" -> split_tokens(rest, separators, stack, true, true, current <> ch, parts)
      ch == "\"" -> split_tokens(rest, separators, stack, false, false, current <> ch, parts)
      true -> split_tokens(rest, separators, stack, true, false, current <> ch, parts)
    end
  end

  defp split_tokens([ch | rest], separators, stack, false, false, current, parts) do
    cond do
      ch == "\"" ->
        split_tokens(rest, separators, stack, true, false, current <> ch, parts)

      ch in ["{", "["] ->
        split_tokens(rest, separators, [ch | stack], false, false, current <> ch, parts)

      ch in ["}", "]"] ->
        case {ch, stack} do
          {"}", ["{" | tail]} ->
            split_tokens(rest, separators, tail, false, false, current <> ch, parts)

          {"]", ["[" | tail]} ->
            split_tokens(rest, separators, tail, false, false, current <> ch, parts)

          _ ->
            {:error, "unbalanced type expression"}
        end

      stack == [] and ch in separators ->
        if String.trim(current) == "" do
          if ch == "\n",
            do: split_tokens(rest, separators, stack, false, false, "", parts),
            else: {:error, "empty type or member"}
        else
          split_tokens(rest, separators, stack, false, false, "", parts ++ [String.trim(current)])
        end

      true ->
        split_tokens(rest, separators, stack, false, false, current <> ch, parts)
    end
  end

  @occurrence_re ~r/^(\d*)\*(\d*)\s+(.+)$/s

  defp parse_occurrence(body) do
    case Regex.run(@occurrence_re, body) do
      [_, min, max, item] ->
        {:ok, parse_bound(min, 0), parse_bound(max, nil), String.trim(item)}

      nil ->
        {:ok, nil, nil, body}
    end
  end

  defp parse_bound("", default), do: default
  defp parse_bound(digits, _default), do: String.to_integer(digits)

  # ---- rendering ---------------------------------------------------------

  # Only the ROOT artifact def closes the object: the bounded dialect's
  # complexity ceiling budgets keywords, and sub-object closure is
  # enforced by the compiled registry tables (the grammar tables in the
  # specification document them); the derived schema pins shape, type,
  # and cardinality and closes the artifact root.
  defp render_type(%{kind: :object, properties: props, required: req, root?: true}, rules) do
    rendered =
      Map.new(props, fn {name, type} ->
        {name, render_type(type, rules)}
      end)

    %{
      "type" => "object",
      "properties" => rendered,
      "required" => Enum.sort(req),
      "additionalProperties" => false
    }
  end

  defp render_type(%{kind: :object, properties: props, required: req}, rules) do
    rendered =
      Map.new(props, fn {name, type} ->
        {name, render_type(type, rules)}
      end)

    %{"type" => "object", "properties" => rendered}
    |> maybe_put("required", Enum.sort(req), req != [])
  end

  defp render_type(%{kind: :choice, choices: choices} = type, rules) do
    %{
      "oneOf" =>
        Enum.map(choices, &render_type(Map.put(&1, :root?, Map.get(type, :root?, false)), rules))
    }
  end

  defp render_type(%{kind: :null}, _rules), do: %{"type" => "null"}
  defp render_type(%{kind: :literal, value: value}, _rules), do: %{"const" => value}

  defp render_type(%{kind: :array, min: min, max: max, item: item}, rules) do
    schema = %{"type" => "array", "items" => render_type(item, rules)}

    schema
    |> maybe_put("minItems", min, min != nil)
    |> maybe_put("maxItems", max, max != nil)
  end

  defp render_type(%{kind: :string}, _rules), do: %{"type" => "string"}

  defp render_type(%{kind: :integer, minimum: n}, _rules),
    do: %{"type" => "integer", "minimum" => n}

  defp render_type(%{kind: :integer}, _rules), do: %{"type" => "integer"}

  defp render_type(%{kind: :boolean}, _rules), do: %{"type" => "boolean"}
  defp render_type(%{kind: :any}, _rules), do: %{}
  defp render_type(%{kind: :enum, values: values}, _rules), do: %{"enum" => Enum.sort(values)}
  defp render_type(%{kind: :ref, target: target}, rules), do: check_ref(target, rules)

  defp check_ref(target, rules) do
    if Map.has_key?(rules, target) do
      %{"$ref" => "#/$defs/#{target}"}
    else
      raise "grammar derivation: dangling rule reference #{inspect(target)}"
    end
  end

  defp maybe_put(map, _key, _value, false), do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)

  # Deterministic rendering: keys sorted, two-space indent.
  defp render(schema) do
    json = render_value(schema, 0)
    json <> "\n"
  end

  defp render_value(map, depth) when is_map(map) do
    if map_size(map) == 0 do
      "{}"
    else
      inner =
        map
        |> Enum.sort()
        |> Enum.map_join(",\n", fn {k, v} ->
          pad(depth + 1) <> Jason.encode!(k) <> ": " <> render_value(v, depth + 1)
        end)

      "{\n" <> inner <> "\n" <> pad(depth) <> "}"
    end
  end

  defp render_value(list, depth) when is_list(list) do
    if list == [] do
      "[]"
    else
      inner =
        Enum.map_join(list, ",\n", fn v -> pad(depth + 1) <> render_value(v, depth + 1) end)

      "[\n" <> inner <> "\n" <> pad(depth) <> "]"
    end
  end

  defp render_value(scalar, _depth), do: Jason.encode!(scalar)

  defp pad(depth), do: String.duplicate("  ", depth)
end
