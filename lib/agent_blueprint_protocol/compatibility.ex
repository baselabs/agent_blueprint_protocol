defmodule AgentBlueprintProtocol.Compatibility do
  @moduledoc """
    This module compares manifest build identities with identities observed by a host.

    Use it when checking whether a Deployment matches an environment report.

    This module does not authorize operations.

    ## Example

    ```elixir
    dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
    {:ok, deployment} =
      AgentBlueprintProtocol.Deployment.decode(
        File.read!(Path.join(dependency_root, "examples/echo-deployment.json"))
      )
    observed = %AgentBlueprintProtocol.Compatibility.Observed{identities: []}
    match?({:error, %AgentBlueprintProtocol.Error{}}, AgentBlueprintProtocol.Compatibility.verify(deployment, observed))
    ```
  """
  @moduledoc since: "1.0.0"

  alias AgentBlueprintProtocol.{Deployment, Digest, Error, Evidence}

  defmodule Observed do
    @moduledoc """
      This struct contains build identities observed by a host.

      Use it when supplying environment identity data to compatibility verification.

      This module does not authorize operations.

      ## Example

      ```elixir
      %AgentBlueprintProtocol.Compatibility.Observed{identities: []}
      ```
    """
    @moduledoc since: "1.0.0"

    defstruct [:identities]

    @typedoc """
      One observed build identity.
    """
    @type identity :: %{
            kind: binary(),
            name: binary(),
            version: binary(),
            digest: binary()
          }

    @typedoc """
      The public data type for AgentBlueprintProtocol.Compatibility.Observed.
    """
    @type t :: %__MODULE__{identities: [identity()]}
  end

  @identity_keys [:kind, :name, :version, :digest]

  @exact_charset ~r/\A[A-Za-z0-9.+-]+\z/

  # ---- the exactness predicate ------------------------------------------------------

  @spec exact?(term()) :: boolean()
  @doc """
    Reports whether a version spelling identifies one exact version.

    ## Example

    ```elixir
    AgentBlueprintProtocol.Compatibility.exact?(%{
      kind: "package",
      name: "example.package",
      version: "1.2.3",
      digest: "sha-256:example"
    })
    ```
  """
  @doc since: "1.0.0"
  def exact?(%{version: version} = identity)
      when is_binary(version) and map_size(identity) == 4 do
    release =
      version |> String.split("-", parts: 2) |> hd() |> String.split("+", parts: 2) |> hd()

    segments = String.split(release, ".")

    lowered = String.downcase(version)

    version != "" and Regex.match?(@exact_charset, version) and
      lowered not in ["*", "latest"] and
      not Enum.any?(segments, &(&1 in ["x", "X", "*"]))
  end

  def exact?(_), do: false

  # ---- the verification -------------------------------------------------------------

  @spec verify(Deployment.t(), Observed.t()) :: {:ok, Evidence.t()} | {:error, Error.t()}
  @doc """
    Compares a Deployment’s build identities with those reported by a host.

    ## Example

    ```elixir
    dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
    {:ok, deployment} =
      AgentBlueprintProtocol.Deployment.decode(
        File.read!(Path.join(dependency_root, "examples/echo-deployment.json"))
      )

    observed = %AgentBlueprintProtocol.Compatibility.Observed{identities: []}
    match?({:error, %AgentBlueprintProtocol.Error{}}, AgentBlueprintProtocol.Compatibility.verify(deployment, observed))
    ```
  """
  @doc since: "1.0.0"
  def verify(%Deployment{} = deployment, %Observed{identities: identities})
      when is_list(identities) do
    with {:ok, _} <- deployment_shape(deployment),
         {:ok, manifest} <- manifest_identities(deployment),
         {:ok, observed} <- validated_observed(identities) do
      match_manifest(manifest, observed, deployment)
    end
  end

  def verify(%Deployment{}, %Observed{}),
    do: {:error, %Error{code: :invalid_type, subject: ["identities"]}}

  def verify(%Deployment{}, _), do: {:error, %Error{code: :invalid_type, subject: ["observed"]}}

  def verify(_, _), do: {:error, %Error{code: :invalid_type, subject: ["deployment"]}}

  defp deployment_shape(deployment) do
    case Deployment.canonical_bytes(deployment) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, %{reason | subject: ["deployment"] ++ reason.subject}}
    end
  end

  # The manifest side: read build_identities as identity maps with their
  # member indices. Absent member, non-array member, or a malformed entry
  # denies typed (struct-bypassed inputs never reach Registry.validate).
  defp manifest_identities(%Deployment{} = deployment) do
    case Deployment.to_value(deployment) do
      {:object, members} ->
        read_manifest_member(List.keyfind(members, "build_identities", 0))

      _not_an_object ->
        {:error, %Error{code: :invalid_type, subject: ["build_identities"]}}
    end
  end

  defp read_manifest_member({"build_identities", {:array, []}}),
    do: {:error, %Error{code: :invalid_cardinality, subject: ["build_identities"]}}

  defp read_manifest_member({"build_identities", {:array, entries}}) when is_list(entries) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, acc} ->
      case identity_of(entry) do
        {:ok, identity} ->
          {:cont, {:ok, [{identity, index} | acc]}}

        :error ->
          {:halt, {:error, %Error{code: :invalid_type, subject: ["build_identities", index]}}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp read_manifest_member({"build_identities", _malformed}),
    do: {:error, %Error{code: :invalid_type, subject: ["build_identities"]}}

  defp read_manifest_member(_absent),
    do: {:error, %Error{code: :missing_required_field, subject: ["build_identities"]}}

  # Exactly the four members — an extra or duplicated key (first-wins in
  # keyfind, so counted) is a struct-bypass defect decode denies
  # (unknown_member/duplicate_member); verify re-asserts it.
  defp identity_of({:object, entry_members})
       when is_list(entry_members) and length(entry_members) == 4 do
    read =
      Enum.reduce_while(@identity_keys, {%{}, []}, fn key, {acc, missing} ->
        case List.keyfind(entry_members, Atom.to_string(key), 0) do
          {_, {:string, value}} -> {:cont, {Map.put(acc, key, value), missing}}
          {_, _wrong_tag} -> {:halt, {acc, :wrong_tag}}
          nil -> {:cont, {acc, [key | missing]}}
        end
      end)

    case read do
      {identity, []} -> {:ok, identity}
      _malformed -> :error
    end
  end

  defp identity_of(_), do: :error

  # The observed side: host-built, so every shape is checked here — exactly
  # the four keys, every value a binary, every version an exact spelling.
  defp validated_observed(identities), do: validated_observed(identities, 0, [])
  defp validated_observed([], _index, acc), do: {:ok, Enum.reverse(acc)}

  defp validated_observed([identity | rest], index, acc) do
    cond do
      not well_formed?(identity) ->
        {:error, %Error{code: :invalid_type, subject: ["identities", index]}}

      not exact?(identity) ->
        {:error, %Error{code: :compatibility_identity_inexact, subject: ["identities", index]}}

      true ->
        validated_observed(rest, index + 1, [identity | acc])
    end
  end

  defp validated_observed(_, index, _),
    do: {:error, %Error{code: :invalid_type, subject: ["identities", index]}}

  defp well_formed?(identity) do
    is_map(identity) and map_size(identity) == 4 and
      Enum.all?(@identity_keys, &is_map_key(identity, &1)) and
      Enum.all?(@identity_keys, &is_binary(Map.get(identity, &1)))
  end

  # Match, manifest member order: per identity — its own exactness, the
  # unique-by name re-assertion, then the observed candidates with the
  # exact tuple. None denies missing; many deny duplicate; one emits the
  # check with the parsed observed digest.
  defp match_manifest(manifest, observed, deployment) do
    {result, _seen} =
      Enum.reduce_while(manifest, {{:ok, []}, MapSet.new()}, fn {identity, index}, acc ->
        identity_step(identity, index, observed, acc)
      end)

    case result do
      {:ok, reversed} ->
        Evidence.build(protocol_revision: revision_of(deployment), checks: Enum.reverse(reversed))

      error ->
        error
    end
  end

  defp identity_step(identity, index, observed, {{:ok, checks}, seen}) do
    cond do
      not exact?(identity) ->
        {:halt, {{:error, error(:compatibility_identity_inexact, index)}, seen}}

      MapSet.member?(seen, identity.name) ->
        {:halt, {{:error, error(:compatibility_duplicate_entry, index)}, seen}}

      true ->
        candidate_step(
          Enum.filter(observed, &matches?(identity, &1)),
          identity,
          index,
          checks,
          seen
        )
    end
  end

  defp candidate_step([], _identity, index, _checks, seen),
    do: {:halt, {{:error, error(:compatibility_entry_missing, index)}, seen}}

  defp candidate_step(candidates, _identity, index, _checks, seen) when length(candidates) > 1,
    do: {:halt, {{:error, error(:compatibility_duplicate_entry, index)}, seen}}

  defp candidate_step([match], identity, index, checks, seen),
    do: emit_check(match, index, checks, seen, identity.name)

  defp emit_check(match, index, checks, seen, name) do
    case Digest.from_tagged(match.digest) do
      {:ok, digest} ->
        {:cont,
         {{:ok,
           [
             %{
               surface: :compatibility,
               subject: ["build_identities", index],
               verified: true,
               detail: digest
             }
             | checks
           ]}, MapSet.put(seen, name)}}

      {:error, reason} ->
        {:halt,
         {{:error, %{reason | subject: ["build_identities", index] ++ reason.subject}}, seen}}
    end
  end

  defp error(code, index), do: %Error{code: code, subject: ["build_identities", index]}

  defp matches?(identity, observed),
    do: Enum.all?(@identity_keys, &(Map.get(identity, &1) == Map.get(observed, &1)))

  # Non-object roots already denied above (manifest_identities gates the
  # same read); this private helper fails loud on the impossible shape.
  defp revision_of(%Deployment{} = deployment) do
    {:object, members} = Deployment.to_value(deployment)

    case List.keyfind(members, "protocol_revision", 0) do
      {"protocol_revision", {:integer, n}} when is_integer(n) -> n
      _ -> nil
    end
  end
end
