defmodule AgentBlueprintProtocol.ExtensionRegistry do
  @moduledoc """
  The COMPILED-IN extension registry: entries are module-attribute
  data, so registry content is a code release — drift is unrepresentable and
  a beam-census architecture gate asserts nothing reads a registry file at
  runtime.

  Entry fields: `namespace`, `owner`, `criticality` (`:critical` |
  `:optional`), `state` (`:reserved` | `:active` | `:deprecated` |
  `:retired`, advancing monotonically), `schema_digest` (`Digest.to_tagged`
  string or `nil` when the owner has not authored a schema — nil denies
  critical bodies at negotiation with `:extension_schema_unavailable`),
  `a2a_uri` (an externally versioned declaration URI, never dereferenced by
  this package), and `promoted_at_revision` (the promotion-governance field:
  optional → critical moves only with a protocol revision increment, which
  the registry author records here; demotion needs no bump).

  **Schema authoring contract:** an owner digests
  `Digest.hash(:extension_schema, JCS(parsed_document))` — JCS of the
  PARSED document, never raw file bytes — and the schema must lie inside
  `Schema`'s bounded 2020-12 dialect (the digest pins that too). This
  package owns `com.example/federation`'s schema and ships it authored
  (`federation_schema/0`); the estate-contract product registration carries
  the FIRST product-owned pin, bound to its corpus-resident document
  (`priv/conformance/schemas/estate-contract.schema.json`); the remaining
  product-owned entries carry `nil` until their owners author one.
  Registry entries are published facts about namespaces; the registry carries no authority.
  Registry entries are published facts about namespaces; the registry carries no authority.
  """

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

  @type criticality :: :critical | :optional
  @type state :: :reserved | :active | :deprecated | :retired

  @type t :: %__MODULE__{
          namespace: binary(),
          owner: binary(),
          criticality: criticality(),
          state: state(),
          schema_digest: binary() | nil,
          a2a_uri: binary(),
          promoted_at_revision: pos_integer() | nil
        }

  # The federation envelope's minimal schema, authored here because this
  # package owns the namespace. Inside the bounded dialect: closed object,
  # no reserved-semantics names (the denylist applies to critical bodies
  # too — a legitimate owner schema does not shadow core bound names).
  @spec federation_schema() :: Json.value()
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
  #
  # The estate-contract product registration: the FIRST product-owned critical
  # namespace with an authored schema pin. The document itself is corpus data
  # (priv/conformance/schemas/estate-contract.schema.json — hash-bound in the
  # corpus index, shipped in the archive); the pin below is
  # Digest.hash(:extension_schema, JCS(parsed document)), and the binding test
  # in ExtensionRegistryTest proves pin and shipped document agree. The
  # placeholder estate namespace deprecates in the same release: its payload
  # role (a free-object condition body) is superseded by the validated channel.
  defp entries do
    [
      %__MODULE__{
        namespace: "com.example.commerce/graph",
        owner: "ExampleCommerce",
        criticality: :critical,
        state: :active,
        schema_digest: nil,
        a2a_uri: "https://example.com/extensions/commerce-graph",
        promoted_at_revision: nil
      },
      %__MODULE__{
        namespace: "com.example.commerce/classification-labels",
        owner: "ExampleCommerce",
        criticality: :optional,
        state: :active,
        schema_digest: nil,
        a2a_uri: "https://example.com/extensions/commerce-classification-labels",
        promoted_at_revision: nil
      },
      %__MODULE__{
        namespace: "com.example.commerce/rubric-assertion",
        owner: "ExampleCommerce",
        criticality: :optional,
        state: :active,
        schema_digest: nil,
        a2a_uri: "https://example.com/extensions/commerce-rubric-assertion",
        promoted_at_revision: nil
      },
      %__MODULE__{
        namespace: "com.example.platform/estate",
        owner: "ExamplePlatform",
        criticality: :optional,
        state: :deprecated,
        schema_digest: nil,
        a2a_uri: "https://example.com/extensions/platform-estate",
        promoted_at_revision: nil
      },
      %__MODULE__{
        namespace: "com.example.platform/estate-contract",
        owner: "ExamplePlatform",
        criticality: :critical,
        state: :active,
        schema_digest: "sha-256:s_ToZWwxrhhd4vVxAyUh2Q6Gddston4tBSLHTLvCQAw",
        a2a_uri: "https://example.com/extensions/platform-estate-contract",
        promoted_at_revision: nil
      },
      %__MODULE__{
        namespace: "com.example/federation",
        owner: "Agent Blueprint Protocol",
        criticality: :critical,
        state: :active,
        schema_digest: tagged_federation_digest(),
        a2a_uri: "https://example.com/extensions/federation",
        promoted_at_revision: nil
      }
    ]
  end

  defp by_namespace do
    Map.new(entries(), fn entry -> {entry.namespace, entry} end)
  end

  @doc "The compiled registry entries (the six registered rows; one deprecated)."
  @spec registered_extensions() :: [t()]
  def registered_extensions, do: entries()

  @doc "Resolve a namespace; `:error` for the unregistered."
  @spec entry(binary()) :: {:ok, t()} | :error
  def entry(namespace) when is_binary(namespace),
    do: Map.fetch(by_namespace(), namespace)

  @doc """
  The registry's content digest (the corpus-registry binding):
  `Digest.hash(:extension_registry, JCS(entries projected to their declared
  field set, keyed by namespace))`. Object member order is JCS-canonical, so
  the entry list's order cannot leak. The conformance corpus index carries
  this value; a corpus built for one registry state must not silently verify
  against another — extension verdicts (unknown-critical, criticality
  conflicts, schema digests) depend on WHAT is registered.
  """
  @spec digest() :: Digest.t()
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
