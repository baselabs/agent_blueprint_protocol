defmodule AgentBlueprintProtocol.ExtensionRegistry do
  @moduledoc """
    This module exposes registered extension namespaces and their lifecycle data.

    Use it when inspecting the registry or its federation schema.

    This module does not authorize operations.

    ## Example

    ```elixir
    is_list(AgentBlueprintProtocol.ExtensionRegistry.registered_extensions())
    ```
  """
  @moduledoc since: "1.0.0"

  alias AgentBlueprintProtocol.{Canonicalization, Digest, Json}

  defstruct [
    :namespace,
    :owner,
    :criticality,
    :state,
    :schema_digest,
    :a2a_uri,
    :promoted_at_revision
  ]

  @typedoc """
    A registered extension criticality value.
  """
  @type criticality :: :critical | :optional
  @typedoc """
    A registered extension lifecycle value.
  """
  @type state :: :reserved | :active | :deprecated | :retired

  @typedoc """
    A registry lifecycle value. Match known values and keep a catch-all branch.
  """
  @type output_state :: atom()

  @typedoc """
    The public data type for AgentBlueprintProtocol.ExtensionRegistry.
  """
  @type t :: %__MODULE__{
          namespace: binary(),
          owner: binary(),
          criticality: criticality(),
          state: state(),
          schema_digest: binary() | nil,
          a2a_uri: binary(),
          promoted_at_revision: pos_integer() | nil
        }

  @typedoc """
    A registry entry returned by lookup.
  """
  @type output :: %__MODULE__{
          namespace: binary(),
          owner: binary(),
          criticality: criticality(),
          state: output_state(),
          schema_digest: binary() | nil,
          a2a_uri: binary(),
          promoted_at_revision: pos_integer() | nil
        }

  # The federation envelope's minimal schema, authored here because this
  # package owns the namespace. Inside the bounded dialect: closed object,
  # no reserved-semantics names (the denylist applies to critical bodies
  # too — a legitimate owner schema does not shadow core bound names).
  @spec federation_schema() :: Json.value()
  @doc """
    Returns the schema used for Federation extension content.

    ## Example

        iex> match?({:object, _}, AgentBlueprintProtocol.ExtensionRegistry.federation_schema())
        true
  """
  @doc since: "1.0.0"
  def federation_schema do
    {:object,
     [
       {"additionalProperties", {:boolean, false}},
       {"properties",
        {:object,
         [
           {"issuer", {:object, [{"type", {:string, "string"}}]}},
           {"subject", {:object, [{"type", {:string, "string"}}]}},
           {"audience", {:object, [{"type", {:string, "string"}}]}}
         ]}},
       {"type", {:string, "object"}}
     ]}
  end

  defp tagged_federation_digest do
    {:ok, jcs} = Canonicalization.encode(federation_schema())
    Digest.to_tagged(Digest.hash(:extension_schema, jcs))
  end

  # Compile-time content as a literal-returning function (module attributes
  # cannot hold the defining module's own structs); a change here is a code
  # release either way — the drift-unrepresentable acceptance holds.
  defp entries do
    [
      %__MODULE__{
        namespace: "com.example/federation",
        owner: "Agent Blueprint Protocol",
        criticality: :critical,
        state: :deprecated,
        schema_digest: tagged_federation_digest(),
        a2a_uri: "https://example.com/extensions/federation",
        promoted_at_revision: nil
      },
      %__MODULE__{
        namespace: "io.github.baselabs/federation",
        owner: "Agent Blueprint Protocol",
        criticality: :critical,
        state: :active,
        schema_digest: tagged_federation_digest(),
        a2a_uri: "https://baselabs.github.io/agent_blueprint_protocol/extensions/federation",
        promoted_at_revision: nil
      }
    ]
  end

  defp by_namespace do
    Map.new(entries(), fn entry -> {entry.namespace, entry} end)
  end

  @spec registered_extensions() :: [output()]
  @doc """
    Returns the registered extension entries.

    ## Example

        iex> Enum.all?(AgentBlueprintProtocol.ExtensionRegistry.registered_extensions(), &is_struct(&1, AgentBlueprintProtocol.ExtensionRegistry))
        true
  """
  @doc since: "1.0.0"
  def registered_extensions, do: entries()

  @doc false
  @spec entry(binary()) :: {:ok, output()} | :error | {:error, AgentBlueprintProtocol.Error.t()}
  def entry(namespace) when is_binary(namespace),
    do: Map.fetch(by_namespace(), namespace)

  def entry(_), do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}

  @spec digest() :: Digest.t()
  @doc """
    Returns the digest of the compiled extension registry.

    ## Example

        iex> match?(%AgentBlueprintProtocol.Digest{algorithm: :sha256, bytes: <<_::256>>}, AgentBlueprintProtocol.ExtensionRegistry.digest())
        true
  """
  @doc since: "1.0.0"
  def digest do
    projected =
      {:object,
       Enum.map(entries(), fn entry ->
         {entry.namespace,
          {:object,
           [
             {"a2a_uri", {:string, entry.a2a_uri}},
             {"criticality", {:string, Atom.to_string(entry.criticality)}},
             {"owner", {:string, entry.owner}},
             {"promoted_at_revision",
              if(prom = entry.promoted_at_revision, do: {:integer, prom}, else: :null)},
             {"schema_digest", if(sd = entry.schema_digest, do: {:string, sd}, else: :null)},
             {"state", {:string, Atom.to_string(entry.state)}}
           ]}}
       end)}

    {:ok, jcs} = Canonicalization.encode(projected)
    Digest.hash(:extension_registry, jcs)
  end
end
