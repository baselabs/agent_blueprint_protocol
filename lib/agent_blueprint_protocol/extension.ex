defmodule AgentBlueprintProtocol.Extension do
  @moduledoc false

  alias AgentBlueprintProtocol.{Canonicalization, Json}

  @identifier_bytes 512
  @ceiling_extensions 32

  @namespace ~r/\A[a-z0-9][a-z0-9.-]*\/[a-z0-9][a-z0-9.-]*\z/

  @doc false
  @spec envelope_ok?(Json.value()) :: :ok | {:error, AgentBlueprintProtocol.Error.t()}
  def envelope_ok?({:object, members}) do
    with {:ok, _} <- Canonicalization.encode({:object, members}),
         :ok <- shape(members),
         {:ok, namespaces} <- namespaces(members),
         :ok <- cardinality(namespaces) do
      no_duplicates(namespaces)
    end
  end

  def envelope_ok?(_not_an_object),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  @doc false
  @spec bodies(list() | map()) ::
          [{binary(), Json.value()}] | {:error, AgentBlueprintProtocol.Error.t()}
  def bodies(members) when is_list(members) or is_map(members) do
    with {:ok, regions} <- regions_of(members) do
      for {_criticality, {:object, namespaces}} <- regions,
          {ns, body} <- namespaces,
          do: {ns, body}
    end
  end

  def bodies(_), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  @doc false
  @spec critical_namespaces(list() | map()) ::
          MapSet.t() | {:error, AgentBlueprintProtocol.Error.t()}
  def critical_namespaces(members) when is_list(members) or is_map(members) do
    with {:ok, regions} <- regions_of(members) do
      for {"critical", {:object, namespaces}} <- regions,
          {ns, _body} <- namespaces,
          do: ns,
          into: MapSet.new()
    end
  end

  def critical_namespaces(_), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  defp regions_of(members) do
    case member_value(members, "extensions") do
      nil ->
        {:ok, []}

      {:object, regions} = value ->
        with {:ok, _} <- Canonicalization.encode(value), do: {:ok, regions}

      _ ->
        {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}
    end
  end

  # ---- internals ------------------------------------------------------------------

  defp shape(members) do
    names = Enum.map(members, fn {name, _} -> name end)

    if Enum.sort(names) != ["critical", "optional"] do
      # A single missing half is a missing member; anything else unknown.
      if names == ["critical"] or names == ["optional"],
        do: {:error, %AgentBlueprintProtocol.Error{code: :missing_required_field}},
        else: {:error, %AgentBlueprintProtocol.Error{code: :unknown_member}}
    else
      :ok
    end
  end

  defp namespaces(members) do
    entries =
      Enum.flat_map(members, fn
        {_region, {:object, ns_members}} when is_list(ns_members) ->
          Enum.map(ns_members, fn {ns, body} -> namespace_entry(ns, body) end)

        {_region, _not_an_object} ->
          [{:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}]
      end)

    first_error = Enum.find(entries, &match?({:error, _}, &1))

    if first_error,
      do: first_error,
      else: {:ok, Enum.map(entries, fn {:ok, ns, _body} -> ns end)}
  end

  defp namespace_entry(ns, body) do
    if namespace_form?(ns),
      do: {:ok, ns, body},
      else: {:error, %AgentBlueprintProtocol.Error{code: :extension_namespace_invalid}}
  end

  defp namespace_form?(ns) do
    byte_size(ns) <= @identifier_bytes and Regex.match?(@namespace, ns)
  end

  defp cardinality(namespaces) do
    if length(namespaces) <= @ceiling_extensions,
      do: :ok,
      else: {:error, %AgentBlueprintProtocol.Error{code: :invalid_cardinality}}
  end

  defp no_duplicates(namespaces) do
    if length(namespaces) == length(Enum.uniq(namespaces)),
      do: :ok,
      else: {:error, %AgentBlueprintProtocol.Error{code: :extension_duplicate}}
  end

  # Root member lists only: both artifact call sites run against the ordered
  # member list (the scan walk and the authored-channel tie), never the
  # engine's hook-shaped map.
  defp member_value(members, name) when is_map(members), do: Map.get(members, name)

  defp member_value([], _name), do: nil
  defp member_value([{name, value} | _], name), do: value
  defp member_value([_ | rest], name), do: member_value(rest, name)
  defp member_value(_, _), do: :invalid
end
