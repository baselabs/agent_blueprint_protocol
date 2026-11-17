Code.require_file("gate_node.exs", __DIR__)
node = AgentBlueprintProtocol.GateNode.find_node!()

codes =
  Enum.map(AgentBlueprintProtocol.Error.codes(), &Atom.to_string/1) ++
    Enum.map(AgentBlueprintProtocol.Error.ceiling_keys(), &("ceiling:" <> Atom.to_string(&1)))

mapping = Enum.map(AgentBlueprintProtocol.federation_mapping(), &Map.from_struct/1)

{_, status} =
  System.cmd(
    node,
    [
      "scripts/check_typescript_consumer.mjs",
      "--error-codes",
      IO.iodata_to_binary(:json.encode(codes)),
      "--mapping",
      IO.iodata_to_binary(:json.encode(mapping))
    ],
    into: IO.stream(),
    stderr_to_stdout: true
  )

if status != 0, do: raise("TypeScript packed consumer or guide failed")
