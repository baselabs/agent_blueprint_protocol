defmodule AgentBlueprintProtocol do
  @moduledoc """
  Portable, non-authorizing contracts for agent blueprints and their
  environment-local deployment manifests.

  The package is intentionally inert. Successful parsing, validation,
  canonicalization, digest verification, or signature verification will mean
  only that supplied bytes satisfy the supplied protocol inputs. Authorization,
  tenancy, live policy, effect ownership, and execution remain the consuming
  host's responsibility.

  The facade delegates and never implements.
  """

  alias AgentBlueprintProtocol.{
    Blueprint,
    Bounds,
    BoundsAlgebra,
    Compatibility,
    Deployment,
    Federation,
    Negotiation,
    Reconcile
  }

  @type failure :: {:error, term()}

  @doc """
  Decode and fully verify a Blueprint artifact: canonical verify → registry
  validation → portability scan → content-digest comparison. See
  `AgentBlueprintProtocol.Blueprint` for the pipeline contract.
  """
  @spec decode_blueprint(binary(), Bounds.t() | map()) ::
          {:ok, Blueprint.t()} | failure()
  def decode_blueprint(bytes, bounds \\ Bounds.maximum()),
    do: Blueprint.decode(bytes, bounds)

  @doc """
  Decode and fully verify a Deployment Manifest: the same four-stage
  pipeline under the 19-member table and the `:deployment_content` digest
  domain. See `AgentBlueprintProtocol.Deployment` for the pipeline and
  binding-surface contracts.
  """
  @spec decode_deployment(binary(), Bounds.t() | map()) ::
          {:ok, Deployment.t()} | failure()
  def decode_deployment(bytes, bounds \\ Bounds.maximum()),
    do: Deployment.decode(bytes, bounds)

  @doc """
  Negotiate an artifact against a consumer's support posture (the evolution gate):
  the revision SET, the required-core-field checks, and the extension state
  machine. In a STANDALONE pass this runs immediately after canonical
  verification, before any semantic read; in the composed import
  (`reconcile/3`) the digest stage runs between canonical and negotiation
  — see `AgentBlueprintProtocol.Reconcile` for the pinned stage order.
  """
  @spec negotiate(Blueprint.t() | term(), Negotiation.Support.t()) ::
          {:ok, Negotiation.Outcome.t()} | failure()
  def negotiate(artifact, %Negotiation.Support{} = support),
    do: Negotiation.negotiate(artifact, support)

  def negotiate(%Blueprint{}, _),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["support"]}}

  def negotiate(_, _),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["artifact"]}}

  @doc """
  Intersect the three bound sources (Blueprint, Deployment `host_bounds`,
  host policy) under the protected-clamp posture — the narrowest
  intersection with deny-by-default protected clamps. See
  `AgentBlueprintProtocol.BoundsAlgebra` for the direction law, the
  marker-union rule, and the clamp evidence contract.
  """
  @spec intersect(BoundsAlgebra.Sources.t()) ::
          {:ok, BoundsAlgebra.Result.t()} | failure()
  def intersect(%BoundsAlgebra.Sources{} = sources),
    do: BoundsAlgebra.intersect(sources)

  def intersect(_),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["sources"]}}

  @doc """
  Verify the Deployment's manifest identities against the host's observed
  build identities: identity-exact or error — ranges deny on both sides,
  duplicates deny, unmatched manifest entries deny, extra observed
  identities are evidence-neutral. The result is an `%Evidence{}` naming
  the seven host-owned surfaces in `not_verified`. See
  `AgentBlueprintProtocol.Compatibility`.
  """
  @spec verify_compatibility(Deployment.t(), Compatibility.Observed.t()) ::
          {:ok, AgentBlueprintProtocol.Evidence.t()} | failure()
  def verify_compatibility(%Deployment{} = deployment, %Compatibility.Observed{} = observed),
    do: Compatibility.verify(deployment, observed)

  def verify_compatibility(%Deployment{}, _),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["observed"]}}

  def verify_compatibility(_, _),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["deployment"]}}

  @doc """
  The one call per import: the composed non-authorizing
  pass — canonical → digest → negotiation → structure → portability →
  signatures → bind → bounds, each stage reject-or-annotate, never
  repair. The result is an `%Evidence{}` — never a decision. See
  `AgentBlueprintProtocol.Reconcile` for the stage machinery and the
  `Reconcile.Inputs` contract.
  """
  @spec reconcile(Blueprint.t(), Deployment.t(), Reconcile.Inputs.t()) ::
          {:ok, AgentBlueprintProtocol.Evidence.t()} | failure()
  def reconcile(
        %Blueprint{} = blueprint,
        %Deployment{} = deployment,
        %Reconcile.Inputs{} = inputs
      ),
      do: Reconcile.reconcile(blueprint, deployment, inputs)

  def reconcile(%Blueprint{}, %Deployment{}, _),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["inputs"]}}

  def reconcile(%Blueprint{}, _, _),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["deployment"]}}

  def reconcile(_, _, _),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["blueprint"]}}

  @doc """
  Decode and fully verify a Federation TaskEnvelope: canonical verify →
  the 23-member registry walk → the federation portability pass. See
  `AgentBlueprintProtocol.Federation` for the envelope contract, the
  lossy-aware state codecs, and the carrier placement laws.
  """
  @spec decode_federation_envelope(binary(), Bounds.t() | map()) ::
          {:ok, Federation.t()} | failure()
  def decode_federation_envelope(bytes, bounds \\ Bounds.maximum()),
    do: Federation.decode(bytes, bounds)

  @doc """
  The 23-row field-by-field A2A/MCP Tasks mapping as data (the
  published table with the transport flags lives at
  `docs/federation-mapping.md`).
  """
  @spec federation_mapping() :: [Federation.Mapping.Row.t()]
  def federation_mapping, do: Federation.mapping()

  @doc """
  The artifact's canonical JCS bytes (the public
  contract's canonicalize row). Delegates to each
  artifact's own encoder; never re-canonicalizes non-canonical input
  (decode is the byte-verification surface).
  """
  @spec canonical_bytes(Blueprint.t() | Deployment.t() | Federation.t()) ::
          {:ok, binary()} | failure()
  def canonical_bytes(%Blueprint{} = blueprint), do: Blueprint.canonical_bytes(blueprint)
  def canonical_bytes(%Deployment{} = deployment), do: Deployment.canonical_bytes(deployment)
  def canonical_bytes(%Federation{} = envelope), do: Federation.canonical_bytes(envelope)

  def canonical_bytes(_),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["artifact"]}}
end
