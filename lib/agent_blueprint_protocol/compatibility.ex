defmodule AgentBlueprintProtocol.Compatibility do
  @moduledoc """
  The compatibility surface : identity-exact or
  error. A manifest identity — one `build_identities` member entry — is
  matched only by an observed identity carrying the EXACT
  `(kind, name, version, digest)` tuple. Version ranges deny
  `:compatibility_identity_inexact` on BOTH sides (a range is malformed,
  never silently unmatchable — the manifest side is decode-checked through
  the registry table; `verify/2` re-asserts it for struct-bypassed inputs,
  the structural-bypass rim lesson, and checks the host-built observed side, which
  never passes a decoder).

  A manifest identity with no exact observed counterpart denies
  `:compatibility_entry_missing`. Two observed candidates for one
  manifest identity — including byte-identical duplicates, a repeated
  observation is the defect, not a dedup case — deny
  `:compatibility_duplicate_entry`; so does a duplicated name in a
  struct-bypassed manifest (decode denies it through `unique_by`).
  Observed identities the manifest does not name are evidence-neutral:
  the host's wider surface is not this manifest's concern, and no check
  entry or denial exists for them.

  Subjects are schema-derived paths (`["build_identities", i]` for
  manifest entries, `["identities", i]` for observed ones) — never input
  values.
  Compatibility verification reports identity facts; it never authorizes execution.
  """

  alias AgentBlueprintProtocol.{Deployment, Digest, Error, Evidence}

  defmodule Observed do
    @moduledoc """
    The host's observed build identities: what the environment actually
    resolved. Host-built (never decoded), so `verify/2` type-checks the
    list itself.
    Observed identities are host-supplied facts that carry no authority.
    """

    defstruct [:identities]

    @type identity :: %{
            kind: binary(),
            name: binary(),
            version: binary(),
            digest: binary()
          }

    @type t :: %__MODULE__{identities: [identity()]}
  end

  @identity_keys [:kind, :name, :version, :digest]

  @exact_charset ~r/\A[A-Za-z0-9.+-]+\z/

  # ---- the exactness predicate ------------------------------------------------------

  @doc """
  `true` when the identity's `version` is an exact spelling — `false` for
  any range expression (`*`, `latest`, `x`/`X` segments, comparator or
  tilde vocabulary, charset violations). Total over junk input: any
  non-conforming shape answers `false`, never raises. This is the public
  binary-level predicate; the decode-side registry check applies the same
  rule to manifest entries (their agreement is pinned by test).
  """
  @spec exact?(term()) :: boolean()
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

  @doc """
  Verify every manifest identity against the observed identities:
  identity-exact matching, one `%{surface: :compatibility}` check per
  manifest identity (`detail` = the matched observed `Digest`), the seven
  host-owned atoms in `not_verified`. Denies per the moduledoc; every
  malformed input shape denies typed.
  """
  @spec verify(Deployment.t(), Observed.t()) :: {:ok, Evidence.t()} | {:error, Error.t()}
  def verify(%Deployment{} = deployment, %Observed{identities: identities})
      when is_list(identities) do
    with {:ok, manifest} <- manifest_identities(deployment),
         {:ok, observed} <- validated_observed(identities) do
      match_manifest(manifest, observed, deployment)
    end
  end

  def verify(%Deployment{}, %Observed{}),
    do: {:error, %Error{code: :invalid_type, subject: ["identities"]}}

  def verify(%Deployment{}, _), do: {:error, %Error{code: :invalid_type, subject: ["observed"]}}

  def verify(_, _), do: {:error, %Error{code: :invalid_type, subject: ["deployment"]}}

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
  defp validated_observed(identities) do
    identities
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {identity, index}, {:ok, acc} ->
      cond do
        not well_formed?(identity) ->
          {:halt, {:error, %Error{code: :invalid_type, subject: ["identities", index]}}}

        not exact?(identity) ->
          {:halt,
           {:error, %Error{code: :compatibility_identity_inexact, subject: ["identities", index]}}}

        true ->
          {:cont, {:ok, [identity | acc]}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

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
        {:halt, {{:error, %Error{code: reason, subject: ["build_identities", index]}}, seen}}
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
