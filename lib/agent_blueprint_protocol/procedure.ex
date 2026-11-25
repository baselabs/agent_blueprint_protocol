defmodule AgentBlueprintProtocol.Procedure do
  @moduledoc """
  The procedure binding stage for per-attempt deployment and returned-run imports.
  A denial halts the import. Equality is conditional on host observations; it is
  not execution authority or proof of the observer, service or evidence source.
  This module does not authorize operations.
  Roles and profiles are host data. Validity is digest-covered and host-owned.
  """
  @moduledoc since: "1.2.0"
  alias AgentBlueprintProtocol.{
    Base64Url,
    Bounds,
    Canonicalization,
    Compatibility,
    Deployment,
    Digest,
    Error,
    Evidence,
    Json,
    Portability,
    Registry,
    Schema
  }

  @namespace "io.github.baselabs/procedure"
  @forms ~w(artifact build configuration service environment)
  @bases ~w(host_computed operator_attested host_configured host_observed holder_asserted)
  @assurance %{
    "host_computed" => :measured,
    "operator_attested" => :attested,
    "host_configured" => :configured,
    "host_observed" => :observed,
    "holder_asserted" => :asserted
  }
  @not_verified ~w(identity_validity observer_trust measurement_freshness evidence_authenticity holder_assertion_truth configuration_execution service_implementation)a
  @schema_path Path.expand("../../spec/grammar/derived/procedure.schema.json", __DIR__)
  @external_resource @schema_path
  @schema_bytes File.read!(@schema_path)

  defstruct [:value]
  @type t :: %__MODULE__{value: Json.value()}

  defmodule Inputs do
    @moduledoc "Host observations for a single procedure import. This struct does not authorize operations. Documents are tagged JSON keyed by their recomputed commitment."
    defstruct [
      :inventory,
      :accepted_profiles,
      :attempt,
      :execution_boundary,
      :phase,
      children: [],
      documents: %{}
    ]

    @type t :: %__MODULE__{
            inventory: map(),
            accepted_profiles: [binary()],
            attempt: binary(),
            execution_boundary: binary(),
            phase: :before_send | :returned,
            children: [Deployment.t() | binary()],
            documents: %{binary() => Json.value()}
          }
  end

  @doc "The shipped procedure schema. Hosts supply it through negotiation support."
  @doc since: "1.2.0"
  @spec schema() :: Json.value()
  def schema do
    {:ok, value} = Json.decode(@schema_bytes)
    value
  end

  @doc "Decode a closed procedure body, with the registry's pinned failure precedence."
  @doc since: "1.2.0"
  @spec decode(Json.value() | binary(), Bounds.t() | map()) :: {:ok, t()} | {:error, Error.t()}
  def decode(input, bounds \\ Bounds.maximum())

  def decode(input, bounds) when is_binary(input) do
    with {:ok, value} <- Canonicalization.verify(input, bounds), do: decode(value, bounds)
  end

  def decode(value, bounds) do
    with {:ok, _} <- Canonicalization.encode(value, bounds),
         :ok <- Registry.validate(table(), value),
         :ok <- Portability.scan(value) do
      {:ok, %__MODULE__{value: value}}
    end
  end

  @doc "Compute SHA-256 over JCS of a typed document with a 256-bit nonce."
  @doc since: "1.2.0"
  @spec document_commitment(Json.value()) :: {:ok, binary()} | {:error, Error.t()}
  def document_commitment({:object, _} = document) do
    with {:ok, bytes} <- Canonicalization.encode(document),
         doc = plain(document),
         :ok <-
           ensure(is_binary(doc["type"]) and doc["type"] != "", :invalid_constraint, ["type"]),
         :ok <- ensure(nonce?(doc["nonce"]), :invalid_constraint, ["nonce"]) do
      {:ok, Digest.to_tagged(Digest.of(bytes))}
    end
  end

  def document_commitment(_), do: error(:invalid_type, ["document"])

  @doc "Verify procedure bindings as part of an import; a denial halts that import."
  @doc since: "1.2.0"
  @spec verify(Deployment.t(), Inputs.t()) :: {:ok, Evidence.t()} | {:error, Error.t()}
  def verify(%Deployment{} = deployment, %Inputs{} = inputs) do
    with :ok <- input_shape(inputs),
         :ok <- Deployment.verify_content_digest(deployment),
         {:ok, body} <- body_of(deployment),
         {:ok, decoded} <- decode(body),
         body = plain(decoded.value),
         :ok <- profile_check(body["profile"], inputs.accepted_profiles),
         :ok <- declaration_check(body, deployment),
         :ok <- documents_check(body, inputs.documents),
         {:ok, compatibility} <-
           Compatibility.verify(deployment, %Compatibility.Observed{
             identities: inputs.inventory["builds"]
           }),
         {:ok, members} <- children_check(deployment, body, inputs),
         digest = Deployment.content_digest(deployment),
         :ok <-
           ensure(
             inputs.inventory["manifest_digest"] == Digest.to_tagged(digest) and
               inputs.inventory["attempt"] == inputs.attempt,
             :binding_incomplete,
             ["inventory"]
           ),
         :ok <- pairing(body, inputs.inventory["instances"]) do
      Evidence.build(
        protocol_revision: 1,
        deployment_digest: digest,
        checks:
          [
            check([], %{
              profile_digest: commitment(body["profile"]),
              attempt: inputs.attempt,
              execution_boundary: inputs.execution_boundary,
              phase: inputs.phase
            })
          ] ++
            instance_checks(body) ++ members ++ compatibility.checks,
        not_verified: @not_verified
      )
    end
  end

  def verify(_, _), do: error(:invalid_type)

  defp input_shape(i) do
    valid =
      inventory_shape?(i.inventory) and input_collections?(i) and
        digest?(i.attempt) and digest?(i.execution_boundary) and
        i.phase in [:before_send, :returned]

    ensure(valid, :invalid_type, ["inputs"])
  end

  defp input_collections?(i) do
    proper_list?(i.children) and length(i.children) <= 255 and is_map(i.documents) and
      not is_struct(i.documents) and map_size(i.documents) <= 1024 and
      proper_list?(i.accepted_profiles) and length(i.accepted_profiles) <= 256 and
      Enum.all?(i.accepted_profiles, &digest?/1)
  end

  defp inventory_shape?(inventory) when is_map(inventory) and not is_struct(inventory) do
    proper_list?(inventory["builds"]) and proper_list?(inventory["instances"]) and
      length(inventory["instances"]) <= 1024 and
      Enum.all?(inventory["instances"], &(is_map(&1) and not is_struct(&1))) and
      digest?(inventory["manifest_digest"]) and digest?(inventory["attempt"])
  end

  defp inventory_shape?(_), do: false
  defp proper_list?([]), do: true
  defp proper_list?([_ | rest]), do: proper_list?(rest)
  defp proper_list?(_), do: false

  defp body_of(%Deployment{value: {:object, _} = value}) do
    with {:object, _} = extensions <- member(value, "extensions"),
         {:object, _} = critical <- member(extensions, "critical"),
         body when body != nil <- member(critical, @namespace) do
      {:ok, body}
    else
      _ -> error(:missing_required_field, ["extensions", "critical", @namespace])
    end
  end

  defp member({:object, pairs}, name) do
    case List.keyfind(pairs, name, 0) do
      {_, value} -> value
      _ -> nil
    end
  end

  @doc false
  @spec table() :: [Registry.spec()]
  def table do
    [
      object("profile", profile_table()),
      array("instances", object_kind(instance_table()), 1, 256),
      object(
        "composition",
        [array("members", object_kind([id("id"), digest("deployment_digest")]), 1, 64)],
        false
      )
    ]
  end

  defp profile_table do
    [
      id("profile_id"),
      array("roles", object_kind(role_table()), 1, 128),
      object(
        "composition",
        [
          number("min"),
          number("max"),
          array("member_profiles", %{kind: :string, check: &tagged_digest/1}, 1, 128)
        ],
        false
      )
    ]
  end

  defp role_table do
    [
      id("role"),
      array("forms", %{kind: enum(@forms)}, 1, 5),
      array("bases", %{kind: enum(@bases)}, 1, 5),
      number("min"),
      number("max"),
      %{name: "schema", required: false, kind: :any},
      array("exact", %{kind: :string, check: &identifier/1}, 0, 128, false),
      array("covers", %{kind: :string, check: &identifier/1}, 0, 16, false),
      array(
        "relations",
        object_kind([id("relation"), id("target_role"), number("min"), number("max")]),
        0,
        16,
        false
      ),
      field("evidence", enum(~w(required optional))),
      field("principal", enum(~w(required optional forbidden))),
      field("validity", enum(~w(required optional)))
    ]
  end

  defp instance_table do
    [
      id("id"),
      id("role"),
      %{name: "identity", required: true, kind: :custom, check: &identity/1},
      object("provenance", provenance_table()),
      array("binds", object_kind([id("relation"), id("target")]), 0, 16, false)
    ]
  end

  defp provenance_table do
    [
      field("basis", enum(@bases)),
      digest("evidence", false),
      %{name: "principal", required: false, kind: :custom, check: &principal/1},
      object("validity", [timestamp("not_before"), timestamp("not_after", false)], false)
    ]
  end

  defp identity({:object, members} = value) do
    case List.keyfind(members, "form", 0) do
      {_, {:string, form}} when form in @forms ->
        fields =
          case form do
            "build" -> [id("name")]
            "service" -> [digest("enrollment"), digest("contract"), digest("published", false)]
            _ -> [digest("digest")]
          end

        Registry.validate([field("form", enum(@forms)) | fields], value)

      _ ->
        Registry.validate(
          [
            field("form", enum(@forms)),
            digest("digest", false),
            id("name", false),
            digest("enrollment", false),
            digest("contract", false),
            digest("published", false)
          ],
          value
        )
    end
  end

  defp identity(_), do: error(:invalid_type)

  defp principal({:object, pairs} = value) do
    with :ok <- Registry.validate([digest("key", false), digest("enrollment", false)], value) do
      case length(pairs) do
        0 -> error(:missing_required_field, ["key"])
        1 -> :ok
        _ -> error(:invalid_constraint)
      end
    end
  end

  defp principal(_), do: error(:invalid_type)

  defp field(name, kind, required \\ true), do: %{name: name, kind: kind, required: required}

  defp id(name, required \\ true),
    do: Map.put(field(name, :string, required), :check, &identifier/1)

  defp digest(name, required \\ true),
    do: Map.put(field(name, :string, required), :check, &tagged_digest/1)

  defp timestamp(name, required \\ true),
    do: Map.put(field(name, :string, required), :check, &timestamp_check/1)

  defp number(name), do: field(name, :integer)

  defp object(name, members, required \\ true),
    do: field(name, {:object, %{members: members}}, required)

  defp object_kind(members), do: %{kind: {:object, %{members: members}}}

  defp array(name, element, min, max, required \\ true),
    do: Map.merge(field(name, {:array, element}, required), %{min_items: min, max_items: max})

  defp enum(values), do: {:enum, MapSet.new(values)}

  defp identifier({:string, s}),
    do:
      ensure(
        byte_size(s) in 1..512 and Regex.match?(~r/\A[a-z0-9][a-z0-9._\/-]*\z/, s),
        :invalid_constraint
      )

  defp tagged_digest({:string, s}) do
    case Digest.from_tagged(s) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp timestamp_check({:string, s}),
    do:
      ensure(
        Regex.match?(~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/, s) and
          match?({:ok, _, _}, DateTime.from_iso8601(s)),
        :invalid_constraint
      )

  defp profile_check(profile, accepted) do
    roles = profile["roles"]
    names = Enum.map(roles, & &1["role"])

    with :ok <-
           ensure(unique?(names) and commitment(profile) in accepted, :invalid_constraint, [
             "profile"
           ]),
         :ok <- each(roles, &role_check(&1, names)),
         :ok <-
           ensure(
             acyclic?(Map.new(roles, &{&1["role"], &1["covers"] || []})),
             :invalid_constraint,
             ["profile", "covers"]
           ) do
      composition_profile_check(profile["composition"])
    end
  end

  defp role_check(role, names) do
    path = ["profile", role["role"]]

    with :ok <-
           ensure(
             bounds?(role, 256) and unique?(role["forms"]) and unique?(role["bases"]),
             :invalid_constraint,
             path
           ),
         :ok <- ensure(role_references?(role, names), :invalid_constraint, path),
         :ok <-
           each(
             role["relations"] || [],
             &ensure(
               bounds?(&1, 16) and &1["target_role"] in names,
               :invalid_constraint,
               path ++ ["relations"]
             )
           ) do
      role_schema_check(role, path)
    end
  end

  defp role_references?(role, names) do
    unique?(Enum.map(role["relations"] || [], & &1["relation"])) and
      Enum.all?(role["covers"] || [], &(&1 in names and &1 != role["role"])) and
      unique?(role["covers"] || []) and unique?(role["exact"] || [])
  end

  defp role_schema_check(%{"schema" => schema} = role, path) do
    with {:ok, _} <- Schema.parse(tag(schema), Schema.dialect()),
         do:
           ensure(
             total_schema?(schema) and
               ("configuration" not in role["forms"] or configuration_schema?(schema, schema)),
             :invalid_constraint,
             path ++ ["schema"]
           )
  end

  defp role_schema_check(role, path),
    do:
      ensure(
        (role["exact"] || []) == [] and "configuration" not in role["forms"],
        :invalid_constraint,
        path ++ ["schema"]
      )

  defp configuration_schema?(%{"$ref" => ref}, root) do
    tokens =
      ref
      |> String.trim_leading("#/")
      |> String.split("/")
      |> Enum.map(&(&1 |> String.replace("~1", "/") |> String.replace("~0", "~")))

    target =
      Enum.reduce(tokens, root, fn key, value ->
        if is_list(value),
          do: Enum.at(value, String.to_integer(key)),
          else: Map.fetch!(value, key)
      end)

    configuration_schema?(target, root)
  end

  defp configuration_schema?(
         %{"type" => "object", "additionalProperties" => false} = schema,
         _root
       ),
       do: Enum.sort(Map.keys(schema["properties"] || %{})) == Enum.sort(schema["required"] || [])

  defp configuration_schema?(_, _), do: false

  defp composition_profile_check(nil), do: :ok

  defp composition_profile_check(rule),
    do:
      ensure(bounds?(rule, 64) and unique?(rule["member_profiles"]), :invalid_constraint, [
        "profile",
        "composition"
      ])

  defp total_schema?(schema) when is_map(schema) do
    children =
      Map.values(schema["properties"] || %{}) ++
        (schema["oneOf"] || []) ++
        Map.values(schema["$defs"] || %{}) ++ List.wrap(schema["items"])

    closed_object?(schema) and Enum.all?(children, &total_schema?/1)
  end

  defp total_schema?(_), do: true

  defp closed_object?(schema) do
    object? =
      "object" in List.wrap(schema["type"]) or
        Enum.any?(~w(properties required additionalProperties), &Map.has_key?(schema, &1))

    if object? do
      schema["additionalProperties"] == false and
        Enum.sort(Map.keys(schema["properties"] || %{})) == Enum.sort(schema["required"] || [])
    else
      true
    end
  end

  defp declaration_check(body, deployment) do
    instances = body["instances"]
    roles = Map.new(body["profile"]["roles"], &{&1["role"], &1})
    ids = Map.new(instances, &{&1["id"], &1})
    builds = plain(Deployment.to_value(deployment))["build_identities"]

    with :ok <-
           ensure(proper_list?(builds) and Enum.all?(builds, &is_map/1), :invalid_type, [
             "build_identities"
           ]),
         :ok <-
           ensure(
             map_size(ids) == length(instances) and
               unique?(Enum.map(instances, &{&1["role"], &1["identity"]})),
             :invalid_constraint,
             ["instances"]
           ),
         :ok <- each(instances, fn i -> instance_declaration(i, roles, ids, builds) end),
         :ok <-
           each(body["profile"]["roles"], fn r ->
             n = Enum.count(instances, &(&1["role"] == r["role"]))

             ensure(n >= r["min"] and n <= r["max"], :invalid_cardinality, [
               "instances",
               r["role"]
             ])
           end),
         :ok <-
           ensure(
             acyclic?(
               Map.new(instances, fn i ->
                 {i["id"], Enum.map(i["binds"] || [], & &1["target"])}
               end)
             ),
             :invalid_constraint,
             ["instances", "binds"]
           ) do
      composition_declaration(body)
    end
  end

  defp composition_declaration(body) do
    members = get_in(body, ["composition", "members"]) || []

    ensure(
      unique?(Enum.map(members, & &1["id"])) and
        member_count?(body["profile"]["composition"], length(members)),
      :invalid_constraint,
      ["composition"]
    )
  end

  defp member_count?(nil, count), do: count == 0
  defp member_count?(rule, count), do: count >= rule["min"] and count <= rule["max"]

  defp instance_declaration(instance, roles, ids, builds) do
    role = roles[instance["role"]]
    binds = instance["binds"] || []
    path = ["instances", instance["id"]]

    with :ok <- ensure(role != nil, :invalid_constraint, path ++ ["role"]),
         :ok <-
           ensure(
             instance["identity"]["form"] in role["forms"] and
               instance["provenance"]["basis"] in role["bases"],
             :invalid_constraint,
             path
           ),
         :ok <-
           ensure(
             provenance_conforms?(instance["provenance"], role),
             :invalid_constraint,
             path ++ ["provenance"]
           ),
         :ok <-
           ensure(
             build_resolves?(instance["identity"], builds),
             :invalid_constraint,
             path ++ ["identity"]
           ),
         :ok <- ensure(unique?(binds), :invalid_constraint, path ++ ["binds"]),
         :ok <-
           ensure(
             covered_attributed?(instance, roles, ids),
             :invalid_constraint,
             path ++ ["binds"]
           ),
         :ok <-
           each(
             binds,
             &ensure(
               binding_target?(&1, instance, role, roles, ids),
               :invalid_constraint,
               path ++ ["binds"]
             )
           ) do
      each(role["relations"] || [], fn relation ->
        count = Enum.count(binds, &(&1["relation"] == relation["relation"]))
        ensure(member_count?(relation, count), :invalid_constraint, path ++ ["binds"])
      end)
    end
  end

  defp covered_attributed?(instance, roles, ids) do
    not Enum.any?(roles, fn {_, role} -> instance["role"] in (role["covers"] || []) end) or
      Enum.any?(instance["binds"] || [], fn bind ->
        target = ids[bind["target"]]

        bind["relation"] == "part_of" and target != nil and
          instance["role"] in (roles[target["role"]]["covers"] || [])
      end)
  end

  defp provenance_conforms?(provenance, role) do
    Enum.all?(
      ~w(evidence principal validity),
      &(role[&1] != "required" or Map.has_key?(provenance, &1))
    ) and
      (role["principal"] != "forbidden" or not Map.has_key?(provenance, "principal"))
  end

  defp build_resolves?(%{"form" => "build", "name" => name}, builds),
    do: Enum.count(builds, &(&1["name"] == name)) == 1

  defp build_resolves?(_, _), do: true

  defp binding_target?(binding, instance, role, roles, ids) do
    target = ids[binding["target"]]
    relation = Enum.find(role["relations"] || [], &(&1["relation"] == binding["relation"]))

    covered =
      binding["relation"] == "part_of" and target != nil and
        instance["role"] in (roles[target["role"]]["covers"] || [])

    target != nil and (covered or (relation != nil and relation["target_role"] == target["role"]))
  end

  defp documents_check(body, documents) do
    roles = Map.new(body["profile"]["roles"], &{&1["role"], &1})

    each(body["instances"], fn instance ->
      each(committed_refs(instance), &document_check(&1, roles[instance["role"]], documents))
    end)
  end

  defp committed_refs(instance) do
    refs = identity_refs(instance["identity"])

    case get_in(instance, ["provenance", "principal", "enrollment"]) do
      nil -> refs
      digest -> refs ++ [{digest, "principal-enrollment"}]
    end
  end

  defp identity_refs(%{"form" => "configuration", "digest" => digest}),
    do: [{digest, "configuration"}]

  defp identity_refs(%{"form" => "environment", "digest" => digest}),
    do: [{digest, "environment"}]

  defp identity_refs(%{"form" => "service", "enrollment" => enrollment, "contract" => contract}),
    do: [{enrollment, "enrollment"}, {contract, "contract"}]

  defp identity_refs(_), do: []

  defp document_check({digest, type}, role, documents) do
    path = ["documents", digest]

    with :ok <- ensure(Map.has_key?(documents, digest), :binding_incomplete, path),
         {:ok, actual} <- document_commitment(documents[digest]) |> document_result(path),
         :ok <- ensure(actual == digest, :binding_incomplete, path),
         doc = plain(documents[digest]),
         :ok <-
           ensure(
             doc["type"] == "agent-blueprint-protocol/procedure-" <> type,
             :invalid_constraint,
             path ++ ["type"]
           ) do
      if type == "principal-enrollment",
        do: :ok,
        else: document_schema(documents[digest], role, path)
    end
  end

  defp document_result({:error, reason}, path),
    do: {:error, %{reason | subject: path ++ reason.subject}}

  defp document_result(result, _path), do: result

  defp document_schema(document, role, path) do
    validation =
      if Map.has_key?(role, "schema"),
        do: Schema.validate_instance(tag(role["schema"]), document, Schema.dialect()),
        else: :ok

    case validation do
      {:error, reason} ->
        error(:invalid_constraint, path ++ reason.subject)

      :ok ->
        doc = plain(document)

        each(role["exact"] || [], fn name ->
          ensure(
            Compatibility.exact?(%{kind: "build", name: name, version: doc[name], digest: ""}),
            :invalid_constraint,
            path ++ [name]
          )
        end)
    end
  end

  defp children_check(deployment, body, inputs) do
    root = Digest.to_tagged(Deployment.content_digest(deployment))
    children = child_index(inputs.children)

    walk_children(
      body,
      inputs,
      children,
      [root],
      %{root => %{profile_digest: commitment(body["profile"]), height: 0}},
      1
    )
    |> case do
      {:ok, checks, _} -> {:ok, checks}
      error -> error
    end
  end

  # Index covered content only. Decode and validate Deployments only when referenced.
  defp child_index(children) do
    Enum.reduce(children, %{}, fn child, acc ->
      with {:ok, value} <- child_value(child),
           %Digest{} = digest <- Deployment.content_digest(%Deployment{value: value}) do
        Map.update(acc, Digest.to_tagged(digest), [child], &(&1 ++ [child]))
      else
        _ -> acc
      end
    end)
  end

  defp child_value(%Deployment{value: value}), do: {:ok, value}
  defp child_value(bytes) when is_binary(bytes), do: Json.decode(bytes)
  defp child_value(_), do: :ignore
  defp child_bytes(%Deployment{} = child), do: Deployment.canonical_bytes(child)
  defp child_bytes(value) when is_binary(value), do: {:ok, value}

  defp walk_children(body, inputs, children, path, seen, depth) do
    Enum.reduce_while(get_in(body, ["composition", "members"]) || [], {:ok, [], seen}, fn member,
                                                                                          {:ok,
                                                                                           checks,
                                                                                           seen} ->
      digest = member["deployment_digest"]

      with :ok <- ensure(depth < 8 and digest not in path, :invalid_constraint, ["composition"]),
           {:ok, nested, seen} <-
             visit_child(
               digest,
               member["id"],
               body["profile"]["composition"]["member_profiles"],
               inputs,
               children,
               path,
               seen,
               depth
             ) do
        detail = check(["composition", hd(path), member["id"]], %{deployment_digest: digest})
        {:cont, {:ok, checks ++ [detail] ++ nested, seen}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp visit_child(digest, id, profiles, inputs, children, path, seen, depth) do
    case Map.get(seen, digest) do
      %{height: height, profile_digest: profile_digest} ->
        with :ok <- ensure(profile_digest in profiles, :invalid_constraint, ["profile"]),
             :ok <- ensure(depth + height <= 8, :invalid_constraint, ["composition"]),
             do: {:ok, [], seen}

      nil ->
        verify_child(digest, id, profiles, inputs, children, path, seen, depth)
    end
  end

  defp verify_child(digest, id, profiles, inputs, children, path, seen, depth) do
    candidates = Map.get(children, digest, [])

    with :ok <- ensure(candidates != [], :binding_incomplete, ["composition", id]),
         :ok <- ensure(length(candidates) == 1, :invalid_constraint, ["children"]),
         {:ok, bytes} <- child_bytes(hd(candidates)),
         {:ok, child} <- Deployment.decode(bytes),
         {:ok, value} <- body_of(child),
         {:ok, decoded} <- decode(value),
         body = plain(decoded.value),
         :ok <- profile_check(body["profile"], profiles),
         :ok <- declaration_check(body, child),
         :ok <- documents_check(body, inputs.documents),
         entry = %{profile_digest: commitment(body["profile"]), height: 0},
         seen = Map.put(seen, digest, entry),
         {:ok, checks, seen} <-
           walk_children(body, inputs, children, [digest | path], seen, depth + 1) do
      heights =
        Enum.map(
          get_in(body, ["composition", "members"]) || [],
          &Map.fetch!(seen, &1["deployment_digest"]).height
        )

      {:ok, checks, Map.put(seen, digest, %{entry | height: 1 + Enum.max(heights, fn -> 0 end)})}
    end
  end

  defp pairing(body, observed) do
    declared = body["instances"]
    # Covers never exempts an observation: a part_of observation still needs
    # its own declaration and exact value and relation comparison.
    with :ok <-
           ensure(length(observed) == length(declared), :binding_incomplete, [
             "inventory",
             "instances"
           ]) do
      each(declared, &pair_observation(&1, observed))
    end
  end

  defp pair_observation(instance, observed) do
    matches = Enum.filter(observed, &(&1["id"] == instance["id"]))
    path = ["inventory", "instances", instance["id"]]

    with :ok <- ensure(length(matches) == 1, :binding_incomplete, path),
         do:
           ensure(
             hd(matches) == instance,
             :binding_incomplete,
             path ++ first_difference(instance, hd(matches))
           )
  end

  defp first_difference(a, b) when is_map(a) and is_map(b) do
    (Map.keys(a) ++ Map.keys(b))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.find_value([], fn name ->
      cond do
        not Map.has_key?(a, name) or not Map.has_key?(b, name) -> [name]
        a[name] != b[name] -> [name | first_difference(a[name], b[name])]
        true -> nil
      end
    end)
  end

  defp first_difference(_, _), do: []

  defp instance_checked(instance, body) do
    role = Enum.find(body["profile"]["roles"], &(&1["role"] == instance["role"]))
    documents = committed_refs(instance) != []

    relations =
      (role["relations"] || []) != [] or (instance["binds"] || []) != [] or
        Enum.any?(body["profile"]["roles"], &(instance["role"] in (&1["covers"] || [])))

    [:declaration] ++
      if(documents, do: [:documents], else: []) ++
      [:pairing] ++ if relations, do: [:relations], else: []
  end

  defp instance_checks(body) do
    Enum.map(body["instances"], fn i ->
      check(["instances", i["id"]], %{
        basis: i["provenance"]["basis"],
        assurance: @assurance[i["provenance"]["basis"]],
        validity: i["provenance"]["validity"],
        checked: instance_checked(i, body)
      })
    end)
  end

  defp check(subject, detail),
    do: %{
      surface: :procedure,
      subject: subject,
      verified: true,
      detail: struct(Evidence.Procedure, detail)
    }

  defp bounds?(r, max),
    do:
      is_integer(r["min"]) and is_integer(r["max"]) and r["min"] >= 0 and r["max"] >= r["min"] and
        r["max"] <= max

  defp unique?(xs), do: length(xs) == length(Enum.uniq(xs))

  defp acyclic?(graph) do
    Enum.reduce_while(Map.keys(graph), {:ok, %{}}, fn node, {:ok, done} ->
      case path_clear?(node, graph, %{}, done) do
        {:ok, done} -> {:cont, {:ok, done}}
        :cycle -> {:halt, :cycle}
      end
    end) != :cycle
  end

  defp path_clear?(node, graph, path, done) do
    cond do
      Map.has_key?(path, node) ->
        :cycle

      Map.has_key?(done, node) ->
        {:ok, done}

      true ->
        descend(node, graph, path, done)
    end
  end

  defp descend(node, graph, path, done) do
    result =
      Enum.reduce_while(Map.get(graph, node, []), {:ok, done}, fn next, {:ok, done} ->
        case path_clear?(next, graph, Map.put(path, node, true), done) do
          {:ok, done} -> {:cont, {:ok, done}}
          :cycle -> {:halt, :cycle}
        end
      end)

    case result do
      {:ok, done} -> {:ok, Map.put(done, node, true)}
      :cycle -> :cycle
    end
  end

  defp digest?(s), do: match?({:ok, _}, Digest.from_tagged(s))

  defp nonce?(s) when is_binary(s) do
    Regex.match?(~r/\A[0-9a-f]{64}\z/, s) or match?({:ok, <<_::256>>}, Base64Url.decode(s))
  end

  defp nonce?(_), do: false

  defp commitment(value) do
    {:ok, bytes} = Canonicalization.encode(tag(value))
    Digest.to_tagged(Digest.of(bytes))
  end

  defp plain({:object, pairs}), do: Map.new(pairs, fn {k, v} -> {k, plain(v)} end)
  defp plain({:array, values}), do: Enum.map(values, &plain/1)
  defp plain(:null), do: nil
  defp plain({_, value}), do: value
  defp tag(v) when is_map(v), do: {:object, Enum.map(Enum.sort(v), fn {k, v} -> {k, tag(v)} end)}
  defp tag(v) when is_list(v), do: {:array, Enum.map(v, &tag/1)}
  defp tag(v) when is_binary(v), do: {:string, v}
  defp tag(v) when is_boolean(v), do: {:boolean, v}
  defp tag(v) when is_integer(v), do: {:integer, v}
  defp tag(v) when is_float(v), do: {:float, v}
  defp tag(nil), do: :null

  defp each(list, fun),
    do:
      Enum.reduce_while(list, :ok, fn v, :ok ->
        case fun.(v) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)

  defp ensure(true, _, _), do: :ok
  defp ensure(_, code, path), do: error(code, path)
  defp ensure(value, code), do: ensure(value, code, [])
  defp error(code, subject \\ []), do: {:error, %Error{code: code, subject: subject}}
end
