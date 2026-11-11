defmodule AgentBlueprintProtocol.Evidence do
  @moduledoc """
    This struct records checks and facts produced by verification.

    Use it when inspecting results of compatibility or reconcile operations.

    This module does not authorize operations.

    ## Example

    ```elixir
    match?({:ok, %AgentBlueprintProtocol.Evidence{}}, AgentBlueprintProtocol.Evidence.build())
    ```
  """
  @moduledoc since: "1.0.0"

  alias AgentBlueprintProtocol.{BoundsAlgebra, Digest, Error}

  defmodule Signatures do
    @moduledoc """
      This struct lists key identities reported by signature verification.

      Use it when reading signature detail in an Evidence check.

      This module does not authorize operations.

      ## Example

      ```elixir
      %AgentBlueprintProtocol.Evidence.Signatures{key_ids: []}
      ```
    """
    @moduledoc since: "1.0.0"
    @enforce_keys [:key_ids]
    defstruct [:key_ids]

    @typedoc """
      The public data type for AgentBlueprintProtocol.Evidence.Signatures.
    """
    @type t :: %__MODULE__{key_ids: [binary()]}
  end

  defmodule Binding do
    @moduledoc """
      This struct records binding checks and surfaces left unverified.

      Use it when reading binding detail in an Evidence check.

      This module does not authorize operations.

      ## Example

      ```elixir
      %AgentBlueprintProtocol.Evidence.Binding{checked: [], not_verified: []}
      ```
    """
    @moduledoc since: "1.0.0"
    @enforce_keys [:checked, :not_verified]
    defstruct [:checked, :not_verified]

    @typedoc """
      The public data type for AgentBlueprintProtocol.Evidence.Binding.
    """
    @type t :: %__MODULE__{checked: [atom()], not_verified: [atom()]}
  end

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

  @typedoc """
    A check record. Detail variants may grow, so match known forms and keep a catch-all branch.
  """
  @type check :: %{
          surface: atom(),
          subject: [binary() | non_neg_integer()],
          verified: boolean(),
          detail: term()
        }

  @typedoc """
    The public data type for AgentBlueprintProtocol.Evidence.
  """
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

  @spec build(keyword() | map()) :: {:ok, t()} | {:error, Error.t()}
  @doc """
    Creates an Evidence value from validated check results and facts.

    ## Example

    ```elixir
    match?(
      {:ok, %AgentBlueprintProtocol.Evidence{}},
      AgentBlueprintProtocol.Evidence.build()
    )
    ```

    ```elixir
    match?(
      {:ok, %AgentBlueprintProtocol.Evidence{}},
      AgentBlueprintProtocol.Evidence.build(not_verified: [:tenancy])
    )
    ```
  """
  @doc since: "1.0.0"
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
         not_verified: Enum.uniq(@host_owned ++ extras ++ unchecked(Map.get(attrs, :checks, [])))
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

  defp unchecked(checks) do
    Enum.flat_map(checks, fn check ->
      surfaces = if check.verified, do: [], else: [check.surface]

      case check[:detail] do
        %Binding{not_verified: skipped} -> surfaces ++ skipped
        _ -> surfaces
      end
    end)
  end

  defp extras_of(extras) when is_list(extras) do
    case invalid_index(extras, &(not is_atom(&1))) do
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
    case invalid_index(checks, &(!check_ok?(&1))) do
      nil -> :ok
      index -> {:error, %Error{code: :invalid_type, subject: ["checks", index]}}
    end
  end

  defp checks_check(_), do: {:error, %Error{code: :invalid_type, subject: ["checks"]}}

  defp check_ok?(%{surface: surface, subject: subject, verified: verified} = check)
       when is_atom(surface) and is_boolean(verified) and is_list(subject),
       do:
         is_nil(invalid_index(subject, &(not (is_binary(&1) or (is_integer(&1) and &1 >= 0))))) and
           detail_ok?(Map.get(check, :detail)) and
           verified_detail?(verified, Map.get(check, :detail))

  defp check_ok?(_), do: false

  defp detail_ok?(detail) when detail in [nil, :no_signatures_present, :retained, :quarantined],
    do: true

  defp detail_ok?(%BoundsAlgebra.ClampEvidence{}), do: true
  defp detail_ok?(%Digest{}), do: true

  defp detail_ok?(%Signatures{key_ids: ids}) when is_list(ids),
    do: ids != [] and Enum.all?(ids, &is_binary/1) and length(ids) == length(Enum.uniq(ids))

  defp detail_ok?(%Binding{checked: checked, not_verified: skipped})
       when is_list(checked) and is_list(skipped),
       do: Enum.all?(checked ++ skipped, &is_atom/1)

  defp detail_ok?(_), do: false

  defp verified_detail?(false, _detail), do: true

  defp verified_detail?(true, detail)
       when detail in [:no_signatures_present, :retained, :quarantined], do: false

  defp verified_detail?(true, %Binding{checked: checked, not_verified: skipped}),
    do: checked != [] and skipped == []

  defp verified_detail?(true, _detail), do: true

  defp bounds_check(nil), do: :ok

  defp bounds_check(%BoundsAlgebra.BoundSet{}), do: :ok

  defp bounds_check(_), do: {:error, %Error{code: :invalid_type, subject: ["effective_bounds"]}}

  defp clamps_check(clamps) when is_list(clamps) do
    case invalid_index(clamps, &(not is_struct(&1, BoundsAlgebra.ClampEvidence))) do
      nil -> :ok
      index -> {:error, %Error{code: :invalid_type, subject: ["clamps", index]}}
    end
  end

  defp clamps_check(_), do: {:error, %Error{code: :invalid_type, subject: ["clamps"]}}

  defp retained_check(retained) when is_list(retained) do
    case invalid_index(retained, &(not is_binary(&1))) do
      nil ->
        :ok

      index ->
        {:error, %Error{code: :invalid_type, subject: ["optional_extensions_retained", index]}}
    end
  end

  defp retained_check(_),
    do: {:error, %Error{code: :invalid_type, subject: ["optional_extensions_retained"]}}

  defp invalid_index(list, predicate), do: invalid_index(list, predicate, 0)
  defp invalid_index([], _predicate, _index), do: nil

  defp invalid_index([value | rest], predicate, index) do
    if predicate.(value), do: index, else: invalid_index(rest, predicate, index + 1)
  end

  defp invalid_index(_, _predicate, index), do: index

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
