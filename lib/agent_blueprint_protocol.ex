defmodule AgentBlueprintProtocol do
  @moduledoc """
    The facade decodes and verifies protocol artifacts through the Elixir reference implementation.

    Use it when an application needs artifact codecs and combined verification calls.

    This module does not authorize operations.

    ## Example

    ```elixir
    dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!()
    bytes = File.read!(Path.join(dependency_root, "examples/echo-blueprint.json"))
    match?({:ok, %AgentBlueprintProtocol.Blueprint{}}, AgentBlueprintProtocol.decode_blueprint(bytes))
    ```
  """
  @moduledoc since: "1.0.0"

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

  @typedoc """
    A typed error result returned by a fallible facade operation.
  """
  @type failure :: {:error, AgentBlueprintProtocol.Error.t()}

  @spec decode_blueprint(binary(), Bounds.t() | map()) ::
          {:ok, Blueprint.t()} | failure()
  @doc """
    Decodes and validates Blueprint bytes under the supplied parse limits.

    ## Example

        iex> dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!(); :ok
        :ok
        iex> bytes = File.read!(Path.join(dependency_root, "examples/echo-blueprint.json"))
        iex> match?({:ok, %AgentBlueprintProtocol.Blueprint{}}, AgentBlueprintProtocol.decode_blueprint(bytes))
        true
        iex> match?({:ok, %AgentBlueprintProtocol.Blueprint{}}, AgentBlueprintProtocol.decode_blueprint(bytes, %{bytes: 5000}))
        true
  """
  @doc since: "1.0.0"
  def decode_blueprint(bytes, bounds \\ Bounds.maximum()),
    do: Blueprint.decode(bytes, bounds)

  @spec decode_deployment(binary(), Bounds.t() | map()) ::
          {:ok, Deployment.t()} | failure()
  @doc """
    Decodes and validates Deployment bytes under the supplied parse limits.

    ## Example

        iex> dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!(); :ok
        :ok
        iex> bytes = File.read!(Path.join(dependency_root, "examples/echo-deployment.json"))
        iex> match?({:ok, %AgentBlueprintProtocol.Deployment{}}, AgentBlueprintProtocol.decode_deployment(bytes))
        true
        iex> match?({:ok, %AgentBlueprintProtocol.Deployment{}}, AgentBlueprintProtocol.decode_deployment(bytes, %{bytes: 5000}))
        true
  """
  @doc since: "1.0.0"
  def decode_deployment(bytes, bounds \\ Bounds.maximum()),
    do: Deployment.decode(bytes, bounds)

  @spec negotiate(
          Blueprint.t() | Deployment.t() | AgentBlueprintProtocol.Json.value(),
          Negotiation.Support.t()
        ) ::
          {:ok, Negotiation.Outcome.t()} | failure()
  @doc """
    Checks an artifact against a consumer support posture.

    ## Example

        iex> dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!(); :ok
        :ok
        iex> with {:ok, blueprint} <- AgentBlueprintProtocol.Blueprint.decode(File.read!(Path.join(dependency_root, "examples/echo-blueprint.json"))), support = %AgentBlueprintProtocol.Negotiation.Support{revisions: MapSet.new([1]), core_fields: MapSet.new([])}, do: match?({:ok, %AgentBlueprintProtocol.Negotiation.Outcome{}}, AgentBlueprintProtocol.negotiate(blueprint, support))
        true
  """
  @doc since: "1.0.0"
  def negotiate(artifact, %Negotiation.Support{} = support),
    do: Negotiation.negotiate(artifact, support)

  def negotiate(artifact, _)
      when is_struct(artifact, Blueprint) or is_struct(artifact, Deployment),
      do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["support"]}}

  def negotiate({:object, _}, _),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["support"]}}

  def negotiate(_, _),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["artifact"]}}

  @spec intersect(BoundsAlgebra.Sources.t()) ::
          {:ok, BoundsAlgebra.Result.t()} | failure()
  @doc """
    Intersects the Blueprint, Deployment, and host bound sources.

    ## Example

        iex> dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!(); :ok
        :ok
        iex> with {:ok, blueprint} <- AgentBlueprintProtocol.Blueprint.decode(File.read!(Path.join(dependency_root, "examples/echo-blueprint.json"))), {:ok, deployment} <- AgentBlueprintProtocol.Deployment.decode(File.read!(Path.join(dependency_root, "examples/echo-deployment.json"))), {:ok, blueprint_bounds} <- AgentBlueprintProtocol.BoundsAlgebra.from_blueprint(blueprint), {:ok, deployment_bounds} <- AgentBlueprintProtocol.BoundsAlgebra.from_deployment(deployment), sources = %AgentBlueprintProtocol.BoundsAlgebra.Sources{blueprint: blueprint_bounds, deployment: deployment_bounds, host: deployment_bounds, protected_clamp: :acknowledge}, do: match?({:ok, %AgentBlueprintProtocol.BoundsAlgebra.Result{}}, AgentBlueprintProtocol.intersect(sources))
        true
  """
  @doc since: "1.0.0"
  def intersect(%BoundsAlgebra.Sources{} = sources),
    do: BoundsAlgebra.intersect(sources)

  def intersect(_),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["sources"]}}

  @spec verify_compatibility(Deployment.t(), Compatibility.Observed.t()) ::
          {:ok, AgentBlueprintProtocol.Evidence.t()} | failure()
  @doc """
    Compares manifest identities with identities reported by a host.

    ## Example

        iex> match?({:error, %AgentBlueprintProtocol.Error{code: :invalid_type}}, AgentBlueprintProtocol.verify_compatibility(:invalid, :invalid))
        true
  """
  @doc since: "1.0.0"
  def verify_compatibility(%Deployment{} = deployment, %Compatibility.Observed{} = observed),
    do: Compatibility.verify(deployment, observed)

  def verify_compatibility(%Deployment{}, _),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["observed"]}}

  def verify_compatibility(_, _),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["deployment"]}}

  @spec reconcile(Blueprint.t(), Deployment.t(), Reconcile.Inputs.t()) ::
          {:ok, AgentBlueprintProtocol.Evidence.t()} | failure()
  @doc """
    Runs the composed verification pass for a Blueprint and Deployment pair.

    ## Example

        iex> dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!(); :ok
        :ok
        iex> with {:ok, blueprint} <- AgentBlueprintProtocol.Blueprint.decode(File.read!(Path.join(dependency_root, "examples/echo-blueprint.json"))), {:ok, deployment} <- AgentBlueprintProtocol.Deployment.decode(File.read!(Path.join(dependency_root, "examples/echo-deployment.json"))), {:ok, host_bounds} <- AgentBlueprintProtocol.BoundsAlgebra.from_deployment(deployment), inputs = %AgentBlueprintProtocol.Reconcile.Inputs{host_bounds: host_bounds, support: %AgentBlueprintProtocol.Negotiation.Support{revisions: MapSet.new([1]), core_fields: MapSet.new([])}, keys: [], protected_clamp: :acknowledge, observations: %AgentBlueprintProtocol.Deployment.Observations{}}, do: match?({:ok, %AgentBlueprintProtocol.Evidence{}}, AgentBlueprintProtocol.reconcile(blueprint, deployment, inputs))
        true
  """
  @doc since: "1.0.0"
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

  @spec decode_federation_envelope(binary(), Bounds.t() | map()) ::
          {:ok, Federation.t()} | failure()
  @doc """
    Decodes and validates Federation envelope bytes under the supplied parse limits.

    ## Example

        iex> dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!(); :ok
        :ok
        iex> bytes = File.read!(Path.join(dependency_root, "examples/federation-envelope.json"))
        iex> match?({:ok, %AgentBlueprintProtocol.Federation{}}, AgentBlueprintProtocol.decode_federation_envelope(bytes))
        true
        iex> match?({:ok, %AgentBlueprintProtocol.Federation{}}, AgentBlueprintProtocol.decode_federation_envelope(bytes, %{bytes: 5000}))
        true
  """
  @doc since: "1.0.0"
  def decode_federation_envelope(bytes, bounds \\ Bounds.maximum()),
    do: Federation.decode(bytes, bounds)

  @spec federation_mapping() :: [Federation.Mapping.Row.t()]
  @doc """
    Returns the field mapping data for the supported federation carriers.

    ## Example

        iex> is_list(AgentBlueprintProtocol.federation_mapping())
        true
  """
  @doc since: "1.0.0"
  def federation_mapping, do: Federation.mapping()

  @spec canonical_bytes(Blueprint.t() | Deployment.t() | Federation.t()) ::
          {:ok, binary()} | failure()
  @doc """
    Returns canonical JSON bytes for the supplied artifact.

    ## Example

        iex> dependency_root = Mix.Project.deps_paths()[:agent_blueprint_protocol] || File.cwd!(); :ok
        :ok
        iex> with {:ok, blueprint} <- AgentBlueprintProtocol.Blueprint.decode(File.read!(Path.join(dependency_root, "examples/echo-blueprint.json"))), do: match?({:ok, bytes} when is_binary(bytes), AgentBlueprintProtocol.canonical_bytes(blueprint))
        true
  """
  @doc since: "1.0.0"
  def canonical_bytes(%Blueprint{} = blueprint), do: Blueprint.canonical_bytes(blueprint)
  def canonical_bytes(%Deployment{} = deployment), do: Deployment.canonical_bytes(deployment)
  def canonical_bytes(%Federation{} = envelope), do: Federation.canonical_bytes(envelope)

  def canonical_bytes(_),
    do: {:error, %AgentBlueprintProtocol.Error{code: :invalid_type, subject: ["artifact"]}}
end
