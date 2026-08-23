defmodule AgentBlueprintProtocol.Extension do
  @moduledoc """
  The positional extension envelope shared by BOTH artifact tables:
  `{"critical": {namespace → payload}, "optional": {namespace → payload}}`,
  digest-covered, with namespace form and total cardinality. Extracted from
  Blueprint so the Deployment table carries the same judgment as
  DATA instead of a copy of it — one envelope, one definition, two tables.

  Negotiation keeps its own region walk (its judgments — lifecycle states,
  schema pins — are different from the table's shape checks); this module is
  the TABLE-check and scan-walk surface only.
  Extension envelopes are inert data — an extension never authorizes an operation.
  Extension envelopes are inert data — an extension never authorizes an operation.
  """

  alias AgentBlueprintProtocol.Json

  @identifier_bytes 512
  @ceiling_extensions 32

  @namespace ~r/\A[a-z0-9][a-z0-9.-]*\/[a-z0-9][a-z0-9.-]*\z/

  @doc """
  The envelope shape check a table carries: exactly critical + optional
  regions, namespace form, total cardinality, no namespace in both.
  """
  @spec envelope_ok?(Json.value()) :: :ok | {:error, term()}
  def envelope_ok?({:object, members}) do
    with :ok <- shape(members),
         {:ok, namespaces} <- namespaces(members),
         :ok <- cardinality(namespaces) do
      no_duplicates(namespaces)
    end
  end

  def envelope_ok?(_not_an_object), do: {:error, :invalid_type}

  @doc """
  Every `{namespace, body}` pair in the envelope, both regions, in document
  order — the scan's walk over the open region.
  """
  @spec bodies(list() | map()) :: [{binary(), Json.value()}]
  def bodies(members) do
    for {:object, regions} <- List.wrap(member_value(members, "extensions")),
        {_criticality, {:object, namespaces}} <- regions,
        {ns, body} <- namespaces,
        do: {ns, body}
  end

  @doc """
  The critical region's namespace set for THIS value — the authored-channel
  tie (a validated-critical list must sit inside this set).
  """
  @spec critical_namespaces(list() | map()) :: MapSet.t()
  def critical_namespaces(members) do
    for {:object, regions} <- List.wrap(member_value(members, "extensions")),
        {"critical", {:object, namespaces}} <- regions,
        {ns, _body} <- namespaces,
        do: ns,
        into: MapSet.new()
  end

  # ---- internals ------------------------------------------------------------------

  defp shape(members) do
    names = Enum.map(members, fn {name, _} -> name end)

    if Enum.sort(names) != ["critical", "optional"] do
      # A single missing half is a missing member; anything else unknown.
      if names == ["critical"] or names == ["optional"],
        do: {:error, :missing_required_field},
        else: {:error, :unknown_member}
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
          [{:error, :invalid_type}]
      end)

    first_error = Enum.find(entries, &match?({:error, _}, &1))

    if first_error,
      do: first_error,
      else: {:ok, Enum.map(entries, fn {:ok, ns, _body} -> ns end)}
  end

  defp namespace_entry(ns, body) do
    if namespace_form?(ns), do: {:ok, ns, body}, else: {:error, :extension_namespace_invalid}
  end

  defp namespace_form?(ns) do
    byte_size(ns) <= @identifier_bytes and Regex.match?(@namespace, ns)
  end

  defp cardinality(namespaces) do
    if length(namespaces) <= @ceiling_extensions,
      do: :ok,
      else: {:error, :invalid_cardinality}
  end

  defp no_duplicates(namespaces) do
    if length(namespaces) == length(Enum.uniq(namespaces)),
      do: :ok,
      else: {:error, :extension_duplicate}
  end

  # Root member lists only: both artifact call sites run against the ordered
  # member list (the scan walk and the authored-channel tie), never the
  # engine's hook-shaped map.
  defp member_value(members, name) when is_list(members) do
    case List.keyfind(members, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end
end
