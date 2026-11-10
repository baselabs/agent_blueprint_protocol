alias AgentBlueprintProtocol.{Json, Schema}
alias AgentBlueprintProtocol.Conformance.Corpus

validate = fn schema_path, value_path ->
  {:ok, schema} = Json.decode(File.read!(schema_path))
  {:ok, value} = Json.decode(File.read!(value_path))

  case Schema.validate_instance(schema, value, Schema.dialect()) do
    :ok -> :ok
    {:error, error} -> raise "conformance schema: #{value_path}: #{inspect(error.code)}"
  end
end

validate.("spec/conformance/index.schema.json", "priv/conformance/index.json")

for path <- Path.wildcard("priv/conformance/cases/*.json") do
  validate.("spec/conformance/case-file.schema.json", path)
  %{"cases" => cases} = :json.decode(File.read!(path))

  for row <- cases do
    name = String.replace(row["surface"], ".", "-")
    {:ok, schema} = Json.decode(File.read!("spec/conformance/#{name}.schema.json"))

    %{"properties" => %{"class" => %{"enum" => classes}}} =
      :json.decode(File.read!("spec/conformance/#{name}.schema.json"))

    true = classes == Corpus.classes()
    # The original row is parsed by the library scanner, preserving numeric tags.
    {:ok, {:object, members}} = Json.decode(File.read!(path))
    {"cases", {:array, values}} = List.keyfind(members, "cases", 0)
    value = Enum.find(values, fn {:object, pairs} -> {"id", {:string, row["id"]}} in pairs end)

    if row["surface"] == "reconcile" and is_map(row["input"]["inputs"]) and
         Map.has_key?(row["input"]["inputs"], "support") do
      {:ok, support_schema} = Json.decode(File.read!("spec/conformance/support.schema.json"))
      {:object, row_members} = value
      {"input", {:object, input_members}} = List.keyfind(row_members, "input", 0)
      {"inputs", {:object, host_members}} = List.keyfind(input_members, "inputs", 0)
      {"support", support} = List.keyfind(host_members, "support", 0)
      :ok = Schema.validate_instance(support_schema, support, Schema.dialect())
    end

    if row["surface"] == "reconcile" and row["expected"]["verdict"] == "valid" do
      {:ok, evidence_schema} = Json.decode(File.read!("spec/conformance/evidence.schema.json"))
      {:object, row_members} = value
      {"expected", {:object, expected_members}} = List.keyfind(row_members, "expected", 0)
      {"evidence", evidence} = List.keyfind(expected_members, "evidence", 0)
      :ok = Schema.validate_instance(evidence_schema, evidence, Schema.dialect())
    end

    case Schema.validate_instance(schema, value, Schema.dialect()) do
      :ok -> :ok
      {:error, error} -> raise "conformance schema: #{row["id"]}: #{inspect(error.code)}"
    end
  end
end

node = System.find_executable("node") || raise "node missing"

{output, status} =
  System.cmd(node, ["scripts/check_conformance_product.mjs"], stderr_to_stdout: true)

IO.write(output)
if status != 0, do: raise("conformance product failed")
