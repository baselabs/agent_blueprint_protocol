defmodule AgentBlueprintProtocol.Evidence do
  @moduledoc """
  The evidence record : the non-authorizing result of
  a verification pass — per-surface checks, effective bounds, clamp
  evidence, and extension facts.

  Evidence is not a decision. `not_verified` is mandatory and always
  non-empty: `build/1` unions in the seven host-owned surfaces this
  protocol structurally cannot establish — tenancy, live policy,
  authority, effect ownership, execution, billing, evaluation truth — so a
  caller cannot read an `%Evidence{}` and conclude "everything is fine".
  The seven are a module constant computed in at construction, never
  passed; callers may only add surfaces they also did not establish.

  The `defstruct` stays public-shaped (a struct is forgeable like any
  struct — the same ruling as the struct-bypass rim): the constructor's
  typed denials cover every malformed input shape, and the property lane
  pins the seven-atom law over every path the package produces.
  """

  alias AgentBlueprintProtocol.{BoundsAlgebra, Digest, Error}

  @host_owned ~w(tenancy live_policy authority effect_ownership execution billing evaluation_truth)a

  defstruct [
    :protocol_revision,
    :blueprint_digest,
    :deployment_digest,
    checks: [],
    effective_bounds: nil,
    clamps: [],
    optional_extensions_retained: [],
    not_verified: []
  ]

  @type check :: %{
          surface: atom(),
          subject: [binary() | non_neg_integer()],
          verified: boolean(),
          detail: nil | BoundsAlgebra.ClampEvidence.t() | Digest.t() | binary()
        }

  @type t :: %__MODULE__{
          protocol_revision: pos_integer() | nil,
          blueprint_digest: Digest.t() | nil,
          deployment_digest: Digest.t() | nil,
          checks: [check()],
          effective_bounds: BoundsAlgebra.BoundSet.t() | nil,
          clamps: [BoundsAlgebra.ClampEvidence.t()],
          optional_extensions_retained: [binary()],
          not_verified: [atom()]
        }

  @doc """
  The only constructor the package uses. Accepts a keyword list or map of
  the struct's own field names; `:not_verified` extras are UNIONED after
  the seven host-owned atoms (duplicates collapse), never replacing them.
  Unknown keys deny `:unknown_member` (subject is the containing surface,
  never the forged key — an error is not an echo channel); malformed
  `:not_verified` shapes deny `:invalid_type` with the member path.
  """
  @spec build(keyword() | map()) :: {:ok, t()} | {:error, Error.t()}
  def build(attrs \\ [])

  def build([]), do: {:ok, %__MODULE__{not_verified: @host_owned}}

  def build(attrs) when is_map(attrs) and not is_struct(attrs) do
    with :ok <- known_keys(attrs),
         {:ok, extras} <- extras_of(Map.get(attrs, :not_verified, [])),
         :ok <- revision_check(Map.get(attrs, :protocol_revision)),
         :ok <- digest_check(Map.get(attrs, :blueprint_digest), "blueprint_digest"),
         :ok <- digest_check(Map.get(attrs, :deployment_digest), "deployment_digest"),
         :ok <- checks_check(Map.get(attrs, :checks, [])),
         :ok <- bounds_check(Map.get(attrs, :effective_bounds)),
         :ok <- clamps_check(Map.get(attrs, :clamps, [])),
         :ok <- retained_check(Map.get(attrs, :optional_extensions_retained, [])) do
      {:ok,
       %__MODULE__{
         protocol_revision: Map.get(attrs, :protocol_revision),
         blueprint_digest: Map.get(attrs, :blueprint_digest),
         deployment_digest: Map.get(attrs, :deployment_digest),
         checks: Map.get(attrs, :checks, []),
         effective_bounds: Map.get(attrs, :effective_bounds),
         clamps: Map.get(attrs, :clamps, []),
         optional_extensions_retained: Map.get(attrs, :optional_extensions_retained, []),
         not_verified: Enum.uniq(@host_owned ++ extras)
       }}
    end
  end

  def build(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      build(Map.new(attrs))
    else
      {:error, %Error{code: :invalid_type, subject: ["evidence"]}}
    end
  end

  def build(_not_map_or_keyword),
    do: {:error, %Error{code: :invalid_type, subject: ["evidence"]}}

  defp extras_of(extras) when is_list(extras) do
    case Enum.find_index(extras, &(not is_atom(&1))) do
      nil -> {:ok, extras}
      index -> {:error, %Error{code: :invalid_type, subject: ["not_verified", index]}}
    end
  end

  defp extras_of(_), do: {:error, %Error{code: :invalid_type, subject: ["not_verified"]}}

  defp revision_check(nil), do: :ok

  defp revision_check(n) when is_integer(n) and n >= 1, do: :ok

  defp revision_check(_),
    do: {:error, %Error{code: :invalid_type, subject: ["protocol_revision"]}}

  defp digest_check(nil, _name), do: :ok

  defp digest_check(%Digest{}, _name), do: :ok

  defp digest_check(_, name),
    do: {:error, %Error{code: :invalid_type, subject: [name]}}

  defp checks_check(checks) when is_list(checks) do
    case Enum.find_index(checks, &(!check_ok?(&1))) do
      nil -> :ok
      index -> {:error, %Error{code: :invalid_type, subject: ["checks", index]}}
    end
  end

  defp checks_check(_), do: {:error, %Error{code: :invalid_type, subject: ["checks"]}}

  defp check_ok?(%{surface: surface, subject: subject, verified: verified})
       when is_atom(surface) and is_boolean(verified) and is_list(subject),
       do: Enum.all?(subject, &(is_binary(&1) or (is_integer(&1) and &1 >= 0)))

  defp check_ok?(_), do: false

  defp bounds_check(nil), do: :ok

  defp bounds_check(%BoundsAlgebra.BoundSet{}), do: :ok

  defp bounds_check(_), do: {:error, %Error{code: :invalid_type, subject: ["effective_bounds"]}}

  defp clamps_check(clamps) when is_list(clamps) do
    case Enum.find_index(clamps, &(not is_struct(&1, BoundsAlgebra.ClampEvidence))) do
      nil -> :ok
      index -> {:error, %Error{code: :invalid_type, subject: ["clamps", index]}}
    end
  end

  defp clamps_check(_), do: {:error, %Error{code: :invalid_type, subject: ["clamps"]}}

  defp retained_check(retained) when is_list(retained) do
    case Enum.find_index(retained, &(not is_binary(&1))) do
      nil ->
        :ok

      index ->
        {:error, %Error{code: :invalid_type, subject: ["optional_extensions_retained", index]}}
    end
  end

  defp retained_check(_),
    do: {:error, %Error{code: :invalid_type, subject: ["optional_extensions_retained"]}}

  defp known_keys(attrs) do
    allowed = MapSet.new(map_fields())

    if Enum.all?(attrs, fn {key, _} -> MapSet.member?(allowed, key) end),
      do: :ok,
      else: {:error, %Error{code: :unknown_member, subject: ["evidence"]}}
  end

  defp map_fields do
    __MODULE__.__struct__()
    |> Map.from_struct()
    |> Map.keys()
  end
end
