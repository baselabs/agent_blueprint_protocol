defmodule AgentBlueprintProtocol.ProcedureCases do
  @moduledoc false
  alias AgentBlueprintProtocol.{Canonicalization, DeploymentFixture, Digest, Json}
  @namespace "io.github.baselabs/procedure"

  def tag(value) do
    {:ok, tagged} = value |> Jason.encode!() |> Json.decode()
    tagged
  end

  def plain({:object, pairs}), do: Map.new(pairs, fn {k, v} -> {k, plain(v)} end)
  def plain({:array, values}), do: Enum.map(values, &plain/1)
  def plain(:null), do: nil
  def plain({_, value}), do: value

  def hash(value) do
    {:ok, bytes} = Canonicalization.encode(tag(value))
    Digest.to_tagged(Digest.of(bytes))
  end

  def body do
    %{
      "profile" => %{
        "profile_id" => "example.profiles/one",
        "roles" => [
          %{
            "role" => "example.roles/one",
            "forms" => ["artifact"],
            "bases" => ["host_computed", "holder_asserted"],
            "min" => 1,
            "max" => 256,
            "evidence" => "optional",
            "principal" => "optional",
            "validity" => "optional"
          }
        ]
      },
      "instances" => [
        %{
          "id" => "example.instances/one",
          "role" => "example.roles/one",
          "identity" => %{"form" => "artifact", "digest" => hash("one")},
          "provenance" => %{"basis" => "host_computed"}
        }
      ]
    }
  end

  def manifest(body, opts \\ []) do
    extensions = DeploymentFixture.extensions(critical: %{@namespace => tag(body)})
    value = DeploymentFixture.fixture_value(Keyword.put(opts, :extensions, extensions))

    {:ok, bytes} = Canonicalization.encode(value)
    {bytes, plain(value)["deployment_digest"]}
  end

  def input(body, opts \\ []) do
    {text, digest} = manifest(body, opts)
    builds = plain(DeploymentFixture.fixture_value())["build_identities"]

    %{
      "text" => text,
      "inputs" => %{
        "inventory" => %{
          "builds" => builds,
          "instances" => body["instances"],
          "manifest_digest" => digest,
          "attempt" => hash("attempt")
        },
        "documents" => %{},
        "children" => [],
        "accepted_profiles" => [hash(body["profile"])],
        "attempt" => hash("attempt"),
        "execution_boundary" => hash("boundary"),
        "import_point" => "before_send"
      }
    }
  end

  def row(name, input, class, code \\ nil) do
    %{
      "id" => "procedure-" <> name,
      "surface" => "procedure.verify",
      "class" => class,
      "input" => input,
      "expected" =>
        if(code,
          do: %{
            "verdict" => "invalid",
            "code" => code,
            "subject" => expected_subject(name, input)
          },
          else: %{
            "verdict" => "valid",
            "verified" => true,
            "evidence" => expected_evidence(input)
          }
        )
    }
  end

  # Subjects are authored from the stage contract, never from verifier output.
  defp expected_subject(name, input) do
    groups = [
      {~w(copied-inventory wrong-manifest), ["inventory"]},
      {~w(extra-instance ambiguous missing-observation covered-extra-instance observation-shape-exact),
       ["inventory", "instances"]},
      {~w(profile-mutated same-id-profile-mutated missing), ["profile"]},
      {~w(input-shape type closure observations-over children-over documents-over accepted-profiles-over),
       ["inputs"]},
      {~w(build-compatibility), ["build_identities", 0]},
      {~w(portable-uri portable-denied-name unknown child-digest schema-unknown schema-type schema-shape schema-null schema-reference schema-cycle),
       []},
      {~w(empty too-many duplicate-declaration duplicate-role-identity duplicate-id),
       ["instances"]},
      {~w(bad-digest algorithm), ["instances", 0, "identity", "digest"]},
      {~w(relation-cycle), ["instances", "binds"]},
      {~w(depth depth-shared), ["composition"]},
      {~w(child-missing), ["composition", "example.members/m-0"]},
      {~w(object-union-open object-open-additional object-required-only configuration-schema-empty configuration-schema-true configuration-schema-one-of configuration-schema-ref-open),
       ["profile", "example.roles/one", "schema"]},
      {~w(required-evidence required-principal required-validity principal-forbidden),
       ["instances", "example.instances/one", "provenance"]},
      {~w(unknown-role), ["instances", "example.instances/one", "role"]},
      {~w(build-unresolved), ["instances", "example.instances/one", "identity"]},
      {~w(part-of-not-permitted covered-attribution-missing),
       ["instances", "example.instances/one", "binds"]},
      {~w(role-cardinality), ["instances", "example.roles/one"]},
      {~w(role-count-order), ["instances", "example.roles/z"]},
      {~w(covers-cycle), ["profile", "covers"]},
      {~w(covers-undeclared-role), ["profile", "example.roles/whole"]},
      {~w(roles-over), ["profile", "roles"]},
      {~w(relations-over), ["instances", 0, "binds"]},
      {~w(covers-over), ["profile", "roles", 0, "covers"]},
      {~w(members-over), ["composition", "members"]},
      {~w(evidence-mutated),
       ["inventory", "instances", "example.instances/one", "provenance", "evidence"]},
      {~w(form-mutated),
       ["inventory", "instances", "example.instances/one", "identity", "digest"]},
      {~w(observation-member-order),
       ["inventory", "instances", "example.instances/one", "\uE000"]},
      {~w(service-release-drift),
       ["inventory", "instances", "example.instances/one", "identity", "enrollment"]},
      {~w(relation-drift covered-instance-drift),
       ["inventory", "instances", "example.instances/one", "binds"]}
    ]

    case Enum.find(groups, fn {names, _} -> name in names end) do
      {_, subject} ->
        subject

      nil ->
        body = get_in(Jason.decode!(input["text"]), ["extensions", "critical", @namespace])
        instance = hd(body["instances"])

        digest =
          if String.starts_with?(name, "principal-"),
            do: get_in(instance, ["provenance", "principal", "enrollment"]),
            else: instance["identity"]["digest"]

        suffix =
          cond do
            name in ~w(principal-enrollment-nonce configuration-document-nonce) ->
              ["nonce"]

            name in ~w(principal-enrollment-type configuration-document-type) ->
              ["type"]

            name == "document-inexact" ->
              ["version"]

            name in ~w(document-missing document-mismatch principal-enrollment-missing configuration-document-schema false-document-schema) ->
              []

            true ->
              raise "missing authored subject for #{name}"
          end

        ["documents", digest] ++ suffix
    end
  end

  defp expected_evidence(input) do
    deployment = Jason.decode!(input["text"])
    body = get_in(deployment, ["extensions", "critical", @namespace])
    opts = input["inputs"]

    detail =
      Map.new(
        ~w(profile_digest attempt execution_boundary import_point basis assurance validity deployment_digest),
        &{&1, nil}
      )
      |> Map.put("checked", [])

    check = fn subject, values ->
      %{
        "surface" => "procedure",
        "subject" => subject,
        "verified" => true,
        "detail" => Map.merge(detail, values)
      }
    end

    header =
      check.([], %{
        "profile_digest" => hash(body["profile"]),
        "attempt" => opts["attempt"],
        "execution_boundary" => opts["execution_boundary"],
        "import_point" => opts["import_point"]
      })

    assurances = %{
      "host_computed" => "measured",
      "operator_attested" => "attested",
      "host_configured" => "configured",
      "host_observed" => "observed",
      "holder_asserted" => "asserted"
    }

    instances =
      Enum.map(body["instances"], fn i ->
        role = Enum.find(body["profile"]["roles"], &(&1["role"] == i["role"]))

        document? =
          i["identity"]["form"] in ~w(configuration service environment) or
            get_in(i, ["provenance", "principal", "enrollment"]) != nil

        relation? =
          (role["relations"] || []) != [] or (i["binds"] || []) != [] or
            Enum.any?(body["profile"]["roles"], &(i["role"] in (&1["covers"] || [])))

        checked =
          ["declaration"] ++
            if(document?, do: ["documents"], else: []) ++
            ["pairing"] ++ if relation?, do: ["relations"], else: []

        check.(["instances", i["id"]], %{
          "basis" => i["provenance"]["basis"],
          "assurance" => assurances[i["provenance"]["basis"]],
          "validity" => i["provenance"]["validity"],
          "checked" => checked
        })
      end)

    # Literal child declarations determine edge projections, with each subgraph expanded once.
    children =
      Enum.filter(opts["children"], &is_binary/1)
      |> Enum.flat_map(fn bytes ->
        case Jason.decode(bytes) do
          {:ok, %{"deployment_digest" => digest} = child} -> [{digest, child}]
          _ -> []
        end
      end)
      |> Map.new()

    {members, _} =
      expected_members(body, deployment["deployment_digest"], children, MapSet.new(), check)

    builds =
      Enum.with_index(deployment["build_identities"], fn entry, n ->
        %{
          "surface" => "compatibility",
          "subject" => ["build_identities", n],
          "verified" => true,
          "detail" => entry["digest"]
        }
      end)

    %{
      "protocol_revision" => 1,
      "blueprint_digest" => nil,
      "deployment_digest" => deployment["deployment_digest"],
      "checks" => [header] ++ instances ++ members ++ builds,
      "effective_bounds" => nil,
      "clamps" => [],
      "optional_extensions_retained" => [],
      "not_verified" =>
        ~w(tenancy live_policy authority effect_ownership execution billing evaluation_truth signature_created_at lifecycle_state signature_time_validity identity_validity observer_trust measurement_freshness evidence_authenticity holder_assertion_truth configuration_execution service_implementation)
    }
  end

  defp expected_members(body, parent, children, seen, check) do
    Enum.reduce(get_in(body, ["composition", "members"]) || [], {[], seen}, fn member,
                                                                               {checks, seen} ->
      digest = member["deployment_digest"]
      edge = check.(["composition", parent, member["id"]], %{"deployment_digest" => digest})

      if MapSet.member?(seen, digest) do
        {checks ++ [edge], seen}
      else
        child = Map.fetch!(children, digest)

        {nested, seen} =
          expected_members(
            get_in(child, ["extensions", "critical", @namespace]),
            digest,
            children,
            MapSet.put(seen, digest),
            check
          )

        {checks ++ [edge] ++ nested, seen}
      end
    end)
  end

  def cases do
    b = body()
    base = input(b)
    instance = hd(b["instances"])

    changes = [
      {"copied-inventory", put_in(base, ["inputs", "inventory", "attempt"], hash("other")),
       "invalid_constraint", "binding_incomplete"},
      {"wrong-manifest", put_in(base, ["inputs", "inventory", "manifest_digest"], hash("other")),
       "invalid_constraint", "binding_incomplete"},
      {"extra-instance",
       update_in(
         base,
         ["inputs", "inventory", "instances"],
         &(&1 ++ [Map.put(instance, "id", "example.instances/extra")])
       ), "invalid_constraint", "binding_incomplete"},
      {"ambiguous", update_in(base, ["inputs", "inventory", "instances"], &(&1 ++ &1)),
       "invalid_duplicate", "binding_incomplete"},
      {"missing-observation", put_in(base, ["inputs", "inventory", "instances"], []),
       "invalid_constraint", "binding_incomplete"},
      {"evidence-mutated",
       put_in(base, ["inputs", "inventory", "instances"], [
         put_in(instance, ["provenance", "evidence"], hash("evidence"))
       ]), "invalid_constraint", "binding_incomplete"},
      {"form-mutated",
       put_in(base, ["inputs", "inventory", "instances"], [
         put_in(instance, ["identity", "digest"], hash("other"))
       ]), "invalid_constraint", "binding_incomplete"},
      {"observation-member-order",
       put_in(base, ["inputs", "inventory", "instances"], [
         Map.merge(instance, %{"\uE000" => 0, "\u{10000}" => 0})
       ]), "invalid_constraint", "binding_incomplete"},
      {"profile-mutated", put_in(base, ["inputs", "accepted_profiles"], [hash("other")]),
       "invalid_constraint", "invalid_constraint"},
      {"input-shape", put_in(base, ["inputs", "import_point"], "unknown"), "invalid_type",
       "invalid_type"},
      {"build-compatibility", put_in(base, ["inputs", "inventory", "builds"], []),
       "invalid_constraint", "compatibility_entry_missing"}
    ]

    decode_changes = [
      {"portable-uri", put_in(b, ["profile", "profile_id"], "https://example.invalid/config"),
       "forbidden_portable_value", "forbidden_portable_value"},
      {"unknown", Map.put(b, "extra", true), "unknown_member", "unknown_member"},
      {"missing", Map.delete(b, "profile"), "invalid_constraint", "missing_required_field"},
      {"type", Map.put(b, "instances", false), "invalid_type", "invalid_type"},
      {"empty", Map.put(b, "instances", []), "invalid_cardinality", "invalid_cardinality"},
      {"too-many", Map.put(b, "instances", List.duplicate(instance, 257)), "maximum_plus_one",
       "invalid_cardinality"},
      {"unknown-role",
       put_in(b, ["instances"], [Map.put(instance, "role", "example.roles/unknown")]),
       "invalid_constraint", "invalid_constraint"},
      {"duplicate-declaration", Map.put(b, "instances", [instance, instance]),
       "invalid_duplicate", "invalid_constraint"},
      {"bad-digest",
       put_in(b, ["instances"], [put_in(instance, ["identity", "digest"], "sha-256:bad")]),
       "invalid_encoding", "digest_encoding_invalid"},
      {"algorithm",
       put_in(b, ["instances"], [put_in(instance, ["identity", "digest"], "other:bad")]),
       "invalid_encoding", "digest_algorithm_unsupported"},
      {"relation-cycle", cycle_body(b, instance), "invalid_constraint", "invalid_constraint"}
    ]

    asserted =
      put_in(b, ["instances"], [
        put_in(instance, ["provenance"], %{
          "basis" => "holder_asserted",
          "validity" => %{"not_before" => "2099-01-01T00:00:00Z"}
        })
      ])

    max_body =
      Map.put(
        b,
        "instances",
        Enum.map(1..256, fn n ->
          instance
          |> Map.put("id", "example.instances/i-#{n}")
          |> put_in(["identity", "digest"], hash(n))
        end)
      )

    docs = document_cases(b, instance)
    composition = composition_cases(b)
    other_forms = other_form_cases(b, instance)
    profiles = profile_cases(b, instance)
    declarations = declaration_cases(b, instance)

    [
      row("valid", base, "valid"),
      row("returned", put_in(base, ["inputs", "import_point"], "returned"), "valid"),
      row("holder-asserted", input(asserted), "valid"),
      row("max-instances", input(max_body), "exact_bound")
    ] ++
      Enum.map(changes, fn {name, i, class, code} -> row(name, i, class, code) end) ++
      Enum.map(decode_changes, fn {name, changed, class, code} ->
        row(name, input(changed), class, code)
      end) ++
      docs ++
      composition ++
      other_forms ++
      profiles ++
      declarations ++
      coverage_cases(b, instance) ++
      principal_cases(b, instance) ++
      limit_cases(b, instance) ++
      Enum.reject(
        constraint_cases(),
        &(&1["id"] in ~w(procedure-documents-exact procedure-documents-over))
      )
  end

  def carrier_cases(base) do
    support = %{
      "revisions" => [1],
      "schemas" => %{@namespace => plain(AgentBlueprintProtocol.Procedure.schema())}
    }

    for region <- ["critical", "optional"], surface <- ["negotiation.negotiate", "reconcile"] do
      blueprint =
        base["input"]["blueprint"]
        |> Jason.decode!()
        |> Map.put(
          "extensions",
          %{"critical" => %{}, "optional" => %{}} |> Map.put(region, %{@namespace => body()})
        )

      blueprint =
        Map.put(
          blueprint,
          "content_digest",
          Digest.hash(
            :blueprint_content,
            blueprint
            |> Map.drop(~w(content_digest signatures attestations))
            |> tag()
            |> Canonicalization.encode()
            |> elem(1)
          )
          |> Digest.to_tagged()
        )

      {input, subject} =
        if surface == "reconcile" do
          # Keep the old deployment binding: carrier denial must precede bind.
          {base["input"]
           |> Map.put("blueprint", blueprint |> tag() |> Canonicalization.encode() |> elem(1))
           |> put_in(["inputs", "support"], support), ["blueprint", "extensions"]}
        else
          {%{"artifact" => blueprint, "support" => support}, ["extensions"]}
        end

      %{
        "id" =>
          "procedure-blueprint-#{region}-#{if surface == "reconcile", do: "reconcile", else: "negotiate"}",
        "surface" => surface,
        "class" => "invalid_constraint",
        "input" => input,
        "expected" => %{
          "verdict" => "invalid",
          "code" => "extension_payload_forbidden",
          "subject" => subject
        }
      }
    end
  end

  def reconcile_cases(base, expectation, sign_deployment) do
    b = body()
    procedure = input(b)
    bp = Jason.decode!(base["input"]["blueprint"])
    deployment = Jason.decode!(procedure["text"])

    host =
      base["input"]["inputs"]
      |> Map.put("protected_clamp", "acknowledge")
      |> put_in(["support", "schemas"], %{
        @namespace => plain(AgentBlueprintProtocol.Procedure.schema())
      })
      |> Map.put("procedure", procedure["inputs"])

    expected = expectation.(bp, deployment, host)
    evidence = expected_evidence(procedure)

    expected =
      update_in(expected, ["evidence", "checks"], fn checks ->
        {before, after_checks} = Enum.split_while(checks, &(&1["surface"] != "bounds"))
        before ++ evidence["checks"] ++ after_checks
      end)

    expected =
      update_in(expected, ["evidence", "not_verified"], fn unchecked ->
        {owned, other} = Enum.split(unchecked, 10)
        Enum.uniq(owned ++ Enum.drop(evidence["not_verified"], 10) ++ other)
      end)

    row = fn name, dep, h, expected ->
      %{
        "id" => "reconcile-procedure-" <> name,
        "surface" => "reconcile",
        "class" => if(expected["verdict"] == "valid", do: "valid", else: "invalid_constraint"),
        "input" => %{
          "blueprint" => base["input"]["blueprint"],
          "deployment" => dep |> tag() |> Canonicalization.encode() |> elem(1),
          "inputs" => h
        },
        "expected" => expected
      }
    end

    optional =
      put_in(deployment, ["extensions"], %{"critical" => %{}, "optional" => %{@namespace => b}})

    optional =
      Map.put(
        optional,
        "deployment_digest",
        Digest.hash(
          :deployment_content,
          optional
          |> Map.drop(~w(deployment_digest signatures attestations))
          |> tag()
          |> Canonicalization.encode()
          |> elem(1)
        )
        |> Digest.to_tagged()
      )

    optional_host =
      host
      |> Map.delete("procedure")
      |> put_in(["support", "registry"], %{
        @namespace => %{"criticality" => "critical", "state" => "retired"}
      })

    {signature, public_key} =
      sign_deployment.(
        "procedure conformance signing seed",
        "example-procedure-key",
        deployment["deployment_digest"]
      )

    signed = Map.put(deployment, "signatures", [Jason.decode!(signature)])

    signed_host =
      Map.put(host, "keys", [
        %{
          "key_id" => "example-procedure-key",
          "key" => Base.url_encode64(public_key, padding: false)
        }
      ])

    signed_expected =
      update_in(expected, ["evidence", "checks"], fn checks ->
        Enum.map(checks, fn
          %{"surface" => "signatures", "subject" => ["deployment"]} = check ->
            %{check | "verified" => true, "detail" => %{"key_ids" => ["example-procedure-key"]}}

          check ->
            check
        end)
      end)

    [
      row.("valid", deployment, host, expected),
      row.("missing", deployment, Map.delete(host, "procedure"), %{
        "verdict" => "invalid",
        "code" => "binding_incomplete",
        "subject" => ["deployment", "procedure"]
      }),
      row.(
        "optional-retired",
        optional,
        optional_host,
        expectation.(bp, optional, optional_host)
      ),
      row.("signed", signed, signed_host, signed_expected),
      row.(
        "signed-wrong-attempt",
        signed,
        put_in(signed_host, ["procedure", "inventory", "attempt"], hash("other-attempt")),
        %{
          "verdict" => "invalid",
          "code" => "binding_incomplete",
          "subject" => ["deployment", "inventory"]
        }
      )
    ]
  end

  def constraint_cases do
    b = body()
    base = input(b)
    instance = hd(b["instances"])
    role = hd(b["profile"]["roles"])

    whole_role =
      role |> Map.put("role", "example.roles/whole") |> Map.put("covers", [role["role"]])

    whole =
      instance |> Map.put("id", "example.instances/whole") |> Map.put("role", whole_role["role"])

    covered =
      b
      |> put_in(["profile", "roles"], [role, whole_role])
      |> Map.put("instances", [whole, instance])

    document = %{
      "type" => "agent-blueprint-protocol/procedure-configuration",
      "nonce" => String.duplicate("0", 64),
      "revision" => 1
    }

    schema = %{
      "type" => "object",
      "properties" => %{
        "type" => %{"type" => "string"},
        "nonce" => %{"type" => "string"},
        "revision" => %{"type" => "integer"}
      },
      "required" => ~w(type nonce revision),
      "additionalProperties" => false
    }

    configuration = fn schema, doc ->
      cb =
        b
        |> put_in(["profile", "roles"], [
          role |> Map.put("forms", ["configuration"]) |> Map.put("schema", schema)
        ])
        |> Map.put("instances", [
          Map.put(instance, "identity", %{"form" => "configuration", "digest" => hash(doc)})
        ])

      put_in(input(cb), ["inputs", "documents"], %{hash(doc) => doc})
    end

    schema_rows =
      Enum.map(
        [
          {"empty", %{}},
          {"true", true},
          {"one-of", %{"oneOf" => [%{}]}},
          {"ref-open", %{"$ref" => "#/$defs/config", "$defs" => %{"config" => %{}}}}
        ],
        fn {name, schema} ->
          row(
            "configuration-schema-" <> name,
            configuration.(schema, document),
            "invalid_constraint",
            "invalid_constraint"
          )
        end
      )

    document_rows =
      Enum.map(
        [
          {"type", Map.put(document, "type", "example.other")},
          {"nonce", Map.put(document, "nonce", "short")},
          {"schema", Map.put(document, "revision", "wrong")}
        ],
        fn {name, doc} ->
          row(
            "configuration-document-" <> name,
            configuration.(schema, doc),
            "invalid_constraint",
            "invalid_constraint"
          )
        end
      )

    {bytes, digest} = manifest(b)
    leaf = {b, bytes, digest}
    shared = parent(b, [leaf])

    shared_depth = fn n ->
      {chain, descendants} =
        Enum.reduce(1..n, {shared, [bytes, elem(shared, 1)]}, fn _, {child, children} ->
          next = parent(b, [child])
          {next, [elem(next, 1) | children]}
        end)

      root = parent(b, [shared, chain])
      put_in(input(elem(root, 0)), ["inputs", "children"], descendants)
    end

    profile_order =
      b
      |> put_in(["profile", "roles"], [
        Map.put(role, "role", "example.roles/z"),
        Map.put(role, "role", "example.roles/a"),
        role
      ])

    schema_rows ++
      document_rows ++
      [
        row(
          "covered-attribution-missing",
          input(covered),
          "invalid_constraint",
          "invalid_constraint"
        ),
        row(
          "configuration-schema-ref",
          configuration.(
            %{"$ref" => "#/$defs/config", "$defs" => %{"config" => schema}},
            document
          ),
          "valid"
        ),
        row("depth-shared", shared_depth.(6), "maximum_plus_one", "invalid_constraint"),
        row("depth-shared-exact", shared_depth.(5), "exact_bound"),
        row(
          "role-count-order",
          input(profile_order),
          "invalid_cardinality",
          "invalid_cardinality"
        ),
        row(
          "children-exact",
          put_in(base, ["inputs", "children"], List.duplicate(false, 255)),
          "exact_bound"
        ),
        row(
          "documents-exact",
          put_in(base, ["inputs", "documents"], Map.new(1..1024, &{hash(&1), false})),
          "exact_bound"
        ),
        row(
          "accepted-profiles-exact",
          put_in(base, ["inputs", "accepted_profiles"], List.duplicate(hash(b["profile"]), 256)),
          "exact_bound"
        ),
        row(
          "children-over",
          put_in(base, ["inputs", "children"], List.duplicate(false, 256)),
          "maximum_plus_one",
          "invalid_type"
        ),
        row(
          "documents-over",
          put_in(base, ["inputs", "documents"], Map.new(1..1025, &{hash(&1), false})),
          "maximum_plus_one",
          "invalid_type"
        ),
        row(
          "accepted-profiles-over",
          put_in(base, ["inputs", "accepted_profiles"], List.duplicate(hash(b["profile"]), 257)),
          "maximum_plus_one",
          "invalid_type"
        ),
        row(
          "unused-children",
          put_in(base, ["inputs", "children"], [false, "not json", bytes]),
          "valid"
        )
      ]
  end

  defp coverage_cases(body, instance) do
    role = hd(body["profile"]["roles"])

    covering_role =
      role |> Map.put("role", "example.roles/whole") |> Map.put("covers", [role["role"]])

    whole =
      instance
      |> Map.put("id", "example.instances/whole")
      |> Map.put("role", covering_role["role"])

    covered = Map.put(instance, "binds", [%{"relation" => "part_of", "target" => whole["id"]}])

    b =
      body
      |> put_in(["profile", "roles"], [role, covering_role])
      |> Map.put("instances", [whole, covered])

    good = input(b)

    cyclic =
      put_in(b, ["profile", "roles"], [
        Map.put(role, "covers", [covering_role["role"]]),
        covering_role
      ])

    unauthorized = put_in(b, ["profile", "roles"], [role, Map.delete(covering_role, "covers")])

    [
      row("covered-instance", good, "valid"),
      row(
        "covered-instance-drift",
        put_in(good, ["inputs", "inventory", "instances"], [whole, Map.delete(covered, "binds")]),
        "invalid_constraint",
        "binding_incomplete"
      ),
      row(
        "covered-extra-instance",
        update_in(
          good,
          ["inputs", "inventory", "instances"],
          &(&1 ++ [Map.put(covered, "id", "example.instances/extra")])
        ),
        "invalid_constraint",
        "binding_incomplete"
      ),
      row("covers-cycle", input(cyclic), "invalid_constraint", "invalid_constraint"),
      row(
        "covers-undeclared-role",
        input(
          put_in(b, ["profile", "roles"], [
            role,
            Map.put(covering_role, "covers", ["example.roles/absent"])
          ])
        ),
        "invalid_constraint",
        "invalid_constraint"
      ),
      row(
        "part-of-not-permitted",
        input(unauthorized),
        "invalid_constraint",
        "invalid_constraint"
      )
    ]
  end

  defp principal_cases(body, instance) do
    doc = %{
      "type" => "agent-blueprint-protocol/procedure-principal-enrollment",
      "nonce" => Base.url_encode64(<<0::256>>, padding: false)
    }

    enrolled = put_in(instance, ["provenance", "principal"], %{"enrollment" => hash(doc)})
    b = Map.put(body, "instances", [enrolled])
    good = put_in(input(b), ["inputs", "documents"], %{hash(doc) => doc})
    malformed = Map.put(doc, "nonce", "short")
    bad_type = Map.put(doc, "type", "example.other-document")

    with_doc = fn document ->
      changed =
        put_in(b, ["instances"], [
          put_in(enrolled, ["provenance", "principal", "enrollment"], hash(document))
        ])

      put_in(input(changed), ["inputs", "documents"], %{hash(document) => document})
    end

    [
      row("principal-enrollment", good, "valid"),
      row("principal-enrollment-missing", input(b), "invalid_constraint", "binding_incomplete"),
      row(
        "principal-enrollment-nonce",
        with_doc.(malformed),
        "invalid_constraint",
        "invalid_constraint"
      ),
      row(
        "principal-enrollment-type",
        with_doc.(bad_type),
        "invalid_constraint",
        "invalid_constraint"
      )
    ]
  end

  defp limit_cases(body, instance) do
    role = hd(body["profile"]["roles"])

    roles = fn n ->
      Enum.map(1..n, fn i ->
        role |> Map.put("role", "example.roles/r-#{i}") |> Map.put("min", 0)
      end)
    end

    role_body = fn n -> put_in(body, ["profile", "roles"], [role | roles.(n)]) end

    targets =
      Enum.map(1..16, fn i ->
        instance
        |> Map.put("id", "example.instances/t-#{i}")
        |> put_in(["identity", "digest"], hash(i))
      end)

    relations =
      Enum.map(targets, &%{"relation" => "example.relations/next", "target" => &1["id"]})

    rule =
      Map.put(role, "relations", [
        %{
          "relation" => "example.relations/next",
          "target_role" => role["role"],
          "min" => 0,
          "max" => 16
        }
      ])

    related =
      body
      |> put_in(["profile", "roles"], [rule])
      |> Map.put("instances", [Map.put(instance, "binds", relations) | targets])

    covers_body = fn n ->
      names = Enum.map(roles.(n), & &1["role"])
      put_in(role_body.(n), ["profile", "roles"], [Map.put(role, "covers", names) | roles.(n)])
    end

    {bytes, digest} = manifest(body)
    leaf = {body, bytes, digest}
    members_body = fn n -> elem(parent(body, List.duplicate(leaf, n)), 0) end
    members = put_in(input(members_body.(64)), ["inputs", "children"], [bytes])
    observation_input = input(body)

    [
      row("roles-exact", input(role_body.(127)), "exact_bound"),
      row("roles-over", input(role_body.(128)), "maximum_plus_one", "invalid_cardinality"),
      row("relations-exact", input(related), "exact_bound"),
      row(
        "relations-over",
        input(
          put_in(related, ["instances"], [
            Map.put(instance, "binds", relations ++ [hd(relations)]) | targets
          ])
        ),
        "maximum_plus_one",
        "invalid_cardinality"
      ),
      row("covers-exact", input(covers_body.(16)), "exact_bound"),
      row("covers-over", input(covers_body.(17)), "maximum_plus_one", "invalid_cardinality"),
      row("members-exact", members, "exact_bound"),
      row("members-over", input(members_body.(65)), "maximum_plus_one", "invalid_cardinality"),
      row(
        "observation-shape-exact",
        put_in(
          observation_input,
          ["inputs", "inventory", "instances"],
          List.duplicate(instance, 1024)
        ),
        "exact_bound",
        "binding_incomplete"
      ),
      row(
        "observations-over",
        put_in(
          observation_input,
          ["inputs", "inventory", "instances"],
          List.duplicate(instance, 1025)
        ),
        "maximum_plus_one",
        "invalid_type"
      )
    ]
  end

  defp declaration_cases(body, instance) do
    duplicate_identity = Map.put(instance, "id", "example.instances/duplicate")
    duplicate_id = put_in(instance, ["identity", "digest"], hash("different"))

    profile =
      put_in(body, ["profile", "roles"], [Map.put(hd(body["profile"]["roles"]), "max", 255)])

    profile_input =
      put_in(input(profile), ["inputs", "accepted_profiles"], [hash(body["profile"])])

    schema = %{
      "type" => "object",
      "properties" => %{"tenant_id" => %{"type" => "string"}},
      "required" => ["tenant_id"],
      "additionalProperties" => false
    }

    portable =
      put_in(body, ["profile", "roles"], [Map.put(hd(body["profile"]["roles"]), "schema", schema)])

    cardinality =
      put_in(body, ["profile", "roles"], [
        Map.merge(hd(body["profile"]["roles"]), %{"min" => 2, "max" => 2})
      ])

    [
      row(
        "duplicate-role-identity",
        input(Map.put(body, "instances", [instance, duplicate_identity])),
        "invalid_duplicate",
        "invalid_constraint"
      ),
      row(
        "duplicate-id",
        input(Map.put(body, "instances", [instance, duplicate_id])),
        "invalid_duplicate",
        "invalid_constraint"
      ),
      row("same-id-profile-mutated", profile_input, "invalid_constraint", "invalid_constraint"),
      row("role-cardinality", input(cardinality), "invalid_cardinality", "invalid_cardinality"),
      row(
        "portable-denied-name",
        input(portable),
        "forbidden_portable_value",
        "forbidden_portable_value"
      )
    ]
  end

  defp profile_cases(body, instance) do
    rule = hd(body["profile"]["roles"])

    schema_cases = [
      {"schema-unknown", %{"pattern" => "fixed"}, "schema_keyword_not_allowed"},
      {"schema-type", %{"type" => false}, "schema_keyword_value_invalid"},
      {"schema-shape", [], "schema_invalid_shape"},
      {"schema-null", nil, "schema_invalid_shape"},
      {"schema-reference", %{"$ref" => "#/$defs/absent"}, "schema_ref_unresolvable"},
      {"schema-cycle", %{"$ref" => "#"}, "schema_ref_cycle"},
      {"object-union-open", %{"type" => ["object", "null"]}, "invalid_constraint"},
      {"object-open-additional", %{"additionalProperties" => true}, "invalid_constraint"},
      {"object-required-only", %{"required" => ["revision"]}, "invalid_constraint"}
    ]

    schema_cases =
      Enum.map(schema_cases, fn {name, schema, code} ->
        b = put_in(body, ["profile", "roles"], [Map.put(rule, "schema", schema)])
        row(name, input(b), "invalid_constraint", code)
      end)

    requirements =
      Enum.map(~w(evidence principal validity), fn member ->
        b = put_in(body, ["profile", "roles"], [Map.put(rule, member, "required")])
        row("required-" <> member, input(b), "invalid_constraint", "invalid_constraint")
      end)

    attested =
      instance
      |> put_in(["provenance"], %{
        "basis" => "operator_attested",
        "evidence" => hash("statement"),
        "principal" => %{"key" => hash("principal")},
        "validity" => %{
          "not_before" => "2099-01-01T00:00:00Z",
          "not_after" => "2100-01-01T00:00:00Z"
        }
      })

    attested_rule =
      rule
      |> Map.put("bases", ["operator_attested"])
      |> Map.put("evidence", "required")
      |> Map.put("principal", "required")
      |> Map.put("validity", "required")

    attested_body =
      body |> put_in(["profile", "roles"], [attested_rule]) |> put_in(["instances"], [attested])

    forbidden =
      put_in(attested_body, ["profile", "roles"], [
        Map.put(attested_rule, "principal", "forbidden")
      ])

    unknown_build =
      instance |> put_in(["identity"], %{"form" => "build", "name" => "example.builds/absent"})

    build_body =
      body
      |> put_in(["profile", "roles"], [Map.put(rule, "forms", ["build"])])
      |> put_in(["instances"], [unknown_build])

    relation = %{
      "relation" => "example.relations/next",
      "target_role" => instance["role"],
      "min" => 0,
      "max" => 16
    }

    target =
      instance
      |> Map.put("id", "example.instances/target")
      |> put_in(["identity", "digest"], hash("target"))

    related =
      Map.put(instance, "binds", [%{"relation" => relation["relation"], "target" => target["id"]}])

    related_body =
      body
      |> put_in(["profile", "roles"], [Map.put(rule, "relations", [relation])])
      |> put_in(["instances"], [related, target])

    related_input = input(related_body, activated_at: {:string, "2026-08-20T00:00:01Z"})

    relation_drift =
      put_in(related_input, ["inputs", "inventory", "instances"], [
        Map.put(related, "binds", []),
        target
      ])

    schema_cases ++
      requirements ++
      [
        row("attested", input(attested_body), "valid"),
        row("principal-forbidden", input(forbidden), "invalid_constraint", "invalid_constraint"),
        row("build-unresolved", input(build_body), "invalid_constraint", "invalid_constraint"),
        row("relations", related_input, "valid"),
        row("relation-drift", relation_drift, "invalid_constraint", "binding_incomplete")
      ]
  end

  defp cycle_body(body, instance) do
    relation = %{
      "relation" => "example.relations/next",
      "target_role" => instance["role"],
      "min" => 0,
      "max" => 16
    }

    role = hd(body["profile"]["roles"]) |> Map.put("relations", [relation])

    instance =
      Map.put(instance, "binds", [
        %{"relation" => relation["relation"], "target" => instance["id"]}
      ])

    body |> put_in(["profile", "roles"], [role]) |> put_in(["instances"], [instance])
  end

  defp other_form_cases(b, instance) do
    Enum.flat_map(~w(build environment service), fn form ->
      doc = fn type ->
        %{
          "type" => "agent-blueprint-protocol/procedure-" <> type,
          "nonce" => String.duplicate("1", 64),
          "revision" => 1
        }
      end

      documents =
        case form do
          "build" -> %{}
          "environment" -> Map.new([doc.("environment")], &{hash(&1), &1})
          "service" -> Map.new([doc.("enrollment"), doc.("contract")], &{hash(&1), &1})
        end

      identity =
        case form do
          "build" ->
            %{"form" => form, "name" => "agent_blueprint_protocol"}

          "environment" ->
            %{"form" => form, "digest" => hash(doc.(form))}

          "service" ->
            %{
              "form" => form,
              "enrollment" => hash(doc.("enrollment")),
              "contract" => hash(doc.("contract"))
            }
        end

      changed =
        b
        |> put_in(["profile", "roles"], [
          hd(b["profile"]["roles"])
          |> Map.put("forms", [form])
          |> Map.put("bases", [
            if(form == "environment", do: "host_observed", else: "host_computed")
          ])
        ])
        |> put_in(["instances"], [
          instance
          |> Map.put("identity", identity)
          |> put_in(
            ["provenance", "basis"],
            if(form == "environment", do: "host_observed", else: "host_computed")
          )
        ])

      good = put_in(input(changed), ["inputs", "documents"], documents)

      if form == "service" do
        published =
          put_in(changed, ["instances"], [
            put_in(hd(changed["instances"]), ["identity", "published"], hash("published"))
          ])

        drift =
          put_in(good, ["inputs", "inventory", "instances"], [
            put_in(hd(changed["instances"]), ["identity", "enrollment"], hash("another-release"))
          ])

        [
          row(form, good, "valid"),
          row(
            "service-published",
            put_in(input(published), ["inputs", "documents"], documents),
            "valid"
          ),
          row("service-release-drift", drift, "invalid_constraint", "binding_incomplete")
        ]
      else
        [row(form, good, "valid")]
      end
    end)
  end

  defp document_cases(b, instance) do
    doc = %{
      "type" => "agent-blueprint-protocol/procedure-configuration",
      "nonce" => String.duplicate("0", 64),
      "version" => "1.2.3"
    }

    schema = %{
      "type" => "object",
      "properties" => Map.new(~w(type nonce version), &{&1, %{"type" => "string"}}),
      "required" => ~w(type nonce version),
      "additionalProperties" => false
    }

    role =
      hd(b["profile"]["roles"])
      |> Map.put("forms", ["configuration"])
      |> Map.put("bases", ["host_configured"])
      |> Map.put("schema", schema)
      |> Map.put("exact", ["version"])

    b =
      b
      |> put_in(["profile", "roles"], [role])
      |> put_in(["instances"], [
        instance
        |> put_in(["identity"], %{"form" => "configuration", "digest" => hash(doc)})
        |> put_in(["provenance", "basis"], "host_configured")
      ])

    i = input(b)
    good = put_in(i, ["inputs", "documents"], %{hash(doc) => doc})
    false_doc = Map.put(doc, "type", "agent-blueprint-protocol/procedure-environment")

    false_body =
      b
      |> put_in(["profile", "roles"], [
        role |> Map.put("schema", false) |> Map.put("forms", ["environment"])
      ])
      |> put_in(["instances"], [
        hd(b["instances"])
        |> Map.put("identity", %{"form" => "environment", "digest" => hash(false_doc)})
      ])

    false_input =
      put_in(input(false_body), ["inputs", "documents"], %{hash(false_doc) => false_doc})

    bad = Map.put(doc, "version", "latest")

    bad_body =
      put_in(b, ["instances"], [put_in(hd(b["instances"]), ["identity", "digest"], hash(bad))])

    [
      row("configuration", good, "valid"),
      row("false-document-schema", false_input, "invalid_constraint", "invalid_constraint"),
      row("document-missing", i, "invalid_constraint", "binding_incomplete"),
      row(
        "document-mismatch",
        put_in(i, ["inputs", "documents"], %{hash(doc) => bad}),
        "invalid_constraint",
        "binding_incomplete"
      ),
      row(
        "document-inexact",
        put_in(input(bad_body), ["inputs", "documents"], %{hash(bad) => bad}),
        "invalid_constraint",
        "invalid_constraint"
      )
    ]
  end

  def parent(body, children) do
    profiles = Enum.map(children, fn {b, _, _} -> hash(b["profile"]) end) |> Enum.uniq()
    rule = %{"min" => 1, "max" => 64, "member_profiles" => profiles}

    members =
      Enum.with_index(children, fn {_, _, digest}, n ->
        %{"id" => "example.members/m-#{n}", "deployment_digest" => digest}
      end)

    b =
      body
      |> put_in(["profile", "composition"], rule)
      |> Map.put("composition", %{"members" => members})

    {text, digest} = manifest(b)
    {b, text, digest}
  end

  defp composition_cases(b) do
    {leaf_text, leaf_digest} = manifest(b)
    leaf = {b, leaf_text, leaf_digest}
    root = parent(b, [leaf, leaf])
    {rb, _, _} = root
    i = put_in(input(rb), ["inputs", "children"], [leaf_text])
    missing = row("child-missing", input(rb), "invalid_constraint", "binding_incomplete")

    tampered =
      Jason.decode!(leaf_text)
      |> Map.put("deployment_digest", hash("wrong"))
      |> tag()
      |> Canonicalization.encode()
      |> elem(1)

    {deep, descendants} =
      Enum.reduce(1..8, {leaf, []}, fn _, {child, descendants} ->
        {parent(b, [child]), [elem(child, 1) | descendants]}
      end)

    deep_input = put_in(input(elem(deep, 0)), ["inputs", "children"], descendants)

    leaves =
      Enum.map(1..256, fn n ->
        lb =
          put_in(b, ["instances"], [put_in(hd(b["instances"]), ["identity", "digest"], hash(n))])

        {text, digest} = manifest(lb)
        {lb, text, digest}
      end)

    branches = leaves |> Enum.chunk_every(64) |> Enum.map(&parent(b, &1))
    closure = parent(b, branches)

    closure_input =
      put_in(
        input(elem(closure, 0)),
        ["inputs", "children"],
        Enum.map(leaves ++ branches, &elem(&1, 1))
      )

    exact_branches = leaves |> Enum.take(251) |> Enum.chunk_every(64) |> Enum.map(&parent(b, &1))
    exact_root = parent(b, exact_branches)

    exact_closure =
      put_in(
        input(elem(exact_root, 0)),
        ["inputs", "children"],
        Enum.map(Enum.take(leaves, 251) ++ exact_branches, &elem(&1, 1))
      )

    {exact_depth, exact_descendants} =
      Enum.reduce(1..7, {leaf, []}, fn _, {child, descendants} ->
        {parent(b, [child]), [elem(child, 1) | descendants]}
      end)

    exact_depth_input =
      put_in(input(elem(exact_depth, 0)), ["inputs", "children"], exact_descendants)

    [
      row("dag-sharing", i, "valid"),
      row("closure-exact", exact_closure, "exact_bound"),
      row("depth-exact", exact_depth_input, "exact_bound"),
      missing,
      row(
        "child-digest",
        put_in(i, ["inputs", "children"], [tampered]),
        "digest_mismatch",
        "digest_mismatch"
      ),
      row("depth", deep_input, "maximum_plus_one", "invalid_constraint"),
      row("closure", closure_input, "maximum_plus_one", "invalid_type")
    ]
  end
end
