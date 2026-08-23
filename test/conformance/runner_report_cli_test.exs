defmodule AgentBlueprintProtocol.Conformance.RunnerReportCliTest do
  @moduledoc """
  The case executor, the report builder, and the CLI: dispatch over the
  live public surface, code-level shape-agnostic expectations, the
  vacuous-green refusal, and the exit-status contract.
  """

  use ExUnit.Case, async: false

  alias AgentBlueprintProtocol.{BlueprintFixture, DeploymentFixture}
  alias AgentBlueprintProtocol.Conformance.{Cli, Corpus, Report, Runner}
  alias AgentBlueprintProtocol.ConformanceTest.Builder

  defp corpus_with(cases) do
    %Corpus{
      index: %{},
      index_bytes: "index",
      cases: [{"cases/test.json", cases}],
      data: %{},
      raws: %{},
      case_ids: MapSet.new(Enum.map(cases, & &1["id"])),
      identity: "sha-256:test"
    }
  end

  # The loader fixtures' uniform expectation (invalid/invalid_type) agrees
  # for every surface EXCEPT bounds.new, whose empty input is a VALID
  # construction. For a run that must verify green, tighten that surface's
  # cells so they deny through the ceiling family.
  defp agreeable_minimal do
    Builder.minimal_cases()
    |> Enum.map(fn
      %{"surface" => "bounds.new"} = case_obj ->
        %{
          case_obj
          | "input" => %{"bounds" => %{"depth" => 65}},
            "expected" => %{"verdict" => "invalid", "code" => "ceiling:depth"}
        }

      case_obj ->
        case_obj
    end)
  end

  defp agree?(cases, case_id) do
    results = Runner.run(corpus_with(cases))
    all = Enum.flat_map(results, &elem(&1, 1))
    Enum.find(all, &(&1.case_id == case_id)).agree
  end

  describe "the runner: code-level, shape-agnostic expectations" do
    test "a bare-atom failure projects to its code string" do
      cases = [
        %{
          "id" => "json-duplicate",
          "surface" => "json.decode",
          "class" => "invalid_duplicate",
          "input" => %{"text" => "{\"a\":1,\"a\":2}"},
          "expected" => %{"verdict" => "invalid", "code" => "duplicate_member"}
        }
      ]

      assert agree?(cases, "json-duplicate")
    end

    test "an %Error{} failure projects to the same code string" do
      cases = [
        %{
          "id" => "fed-not-json",
          "surface" => "federation.decode",
          "class" => "invalid_type",
          "input" => %{"text" => "not json"},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_syntax"}
        }
      ]

      # Federation.decode returns %Error{} records; the projection lands on
      # the same code-level comparison as the bare-atom surfaces.
      assert agree?(cases, "fed-not-json")
    end

    test "the ceiling family renders as ceiling:<key>" do
      cases = [
        %{
          "id" => "json-ceiling",
          "surface" => "json.decode",
          "class" => "maximum_plus_one",
          "input" => %{"text" => "[[[[[1]]]]]", "bounds" => %{"depth" => 4}},
          "expected" => %{"verdict" => "invalid", "code" => "ceiling:depth"}
        }
      ]

      assert agree?(cases, "json-ceiling")
    end

    test "a valid case compares per-projection with base64url byte fallback" do
      cases = [
        %{
          "id" => "b64-valid",
          "surface" => "base64url.decode",
          "class" => "valid",
          "input" => %{"base64url" => "QQ"},
          "expected" => %{
            "verdict" => "valid",
            "decoded" => Base.url_encode64("A", padding: false)
          }
        }
      ]

      assert agree?(cases, "b64-valid")
    end

    test "a wrong expected code disagrees (expectations are load-bearing)" do
      cases = [
        %{
          "id" => "json-wrong-code",
          "surface" => "json.decode",
          "class" => "invalid_duplicate",
          "input" => %{"text" => "{\"a\":1,\"a\":2}"},
          "expected" => %{"verdict" => "invalid", "code" => "trailing_bytes"}
        }
      ]

      refute agree?(cases, "json-wrong-code")
    end

    test "the federation codec surface: A2A UNSPECIFIED denies unmappable" do
      cases = [
        %{
          "id" => "fed-a2a-unspecified",
          "surface" => "federation.decode",
          "class" => "federation_state_unmappable",
          "input" => %{"from_a2a_state" => "TASK_STATE_UNSPECIFIED"},
          "expected" => %{"verdict" => "invalid", "code" => "federation_state_unmappable"}
        }
      ]

      assert agree?(cases, "fed-a2a-unspecified")
    end

    test "bounds.new maximum_plus_one carries the ceiling family" do
      cases = [
        %{
          "id" => "bounds-mpo",
          "surface" => "bounds.new",
          "class" => "maximum_plus_one",
          "input" => %{"bounds" => %{"depth" => 65}},
          "expected" => %{"verdict" => "invalid", "code" => "ceiling:depth"}
        }
      ]

      assert agree?(cases, "bounds-mpo")
    end

    test "portability forbidden_portable_value over an artifact value" do
      cases = [
        %{
          "id" => "port-forbidden",
          "surface" => "portability.scan",
          "class" => "forbidden_portable_value",
          "input" => %{"text" => "{\"api_key\":\"" <> String.duplicate("A", 40) <> "\"}"},
          "expected" => %{"verdict" => "invalid", "code" => "forbidden_portable_value"}
        }
      ]

      assert agree?(cases, "port-forbidden")
    end

    test "deployment.decode with binding observations runs verify_binding (the binding classes' emitter)" do
      # The fixtures pair by default; diverged ceilings change the blueprint's
      # content digest, so the deployment's bound release no longer matches —
      # verify_binding's stage-1 denial.
      other_ceilings =
        {:object,
         [
           {"max_attempts", {:integer, 9}},
           {"max_concurrency", {:integer, 9}},
           {"max_cost", {:object, [{"amount", {:integer, 9}}, {"currency", {:string, "USD"}}]}},
           {"max_depth", {:integer, 9}},
           {"max_descendants", {:integer, 9}},
           {"max_elapsed_ms", {:integer, 9}},
           {"max_fan_out", {:integer, 9}},
           {"max_tokens", {:integer, 9}}
         ]}

      deployment_bytes = AgentBlueprintProtocol.DeploymentFixture.fixture_bytes([])

      diverged_blueprint =
        AgentBlueprintProtocol.BlueprintFixture.fixture_bytes(ceilings: other_ceilings)

      cases = [
        %{
          "id" => "deployment-binding-mismatch",
          "surface" => "deployment.decode",
          "class" => "digest_mismatch",
          "input" => %{
            "text" => deployment_bytes,
            "binding" => %{"blueprint" => diverged_blueprint}
          },
          "expected" => %{"verdict" => "invalid", "code" => "deployment_digest_mismatch"}
        }
      ]

      assert agree?(cases, "deployment-binding-mismatch")
    end
  end

  describe "the runner: dispatch coverage over every surface family" do
    test "canonicalization.encode valid + the bytes ceiling" do
      cases = [
        %{
          "id" => "canon-valid",
          "surface" => "canonicalization.encode",
          "class" => "valid",
          "input" => %{"text" => "{\"b\":2,\"a\":1}"},
          "expected" => %{"verdict" => "valid", "encoded" => "{\"a\":1,\"b\":2}"}
        },
        %{
          "id" => "canon-mpo",
          "surface" => "canonicalization.encode",
          "class" => "maximum_plus_one",
          "input" => %{"text" => "{\"b\":2,\"a\":1}", "bounds" => %{"bytes" => 1}},
          "expected" => %{"verdict" => "invalid", "code" => "ceiling:bytes"}
        }
      ]

      assert agree?(cases, "canon-valid")
      assert agree?(cases, "canon-mpo")
    end

    test "digest.tagged: roundtrip + verify both verdicts + a bad domain" do
      tagged =
        AgentBlueprintProtocol.Digest.to_tagged(
          AgentBlueprintProtocol.Digest.hash(:blueprint_content, "corpus")
        )

      cases = [
        %{
          "id" => "dt-valid",
          "surface" => "digest.tagged",
          "class" => "valid",
          "input" => %{"tagged" => tagged},
          "expected" => %{"verdict" => "valid", "tagged" => tagged}
        },
        %{
          "id" => "dt-bad",
          "surface" => "digest.tagged",
          "class" => "invalid_encoding",
          "input" => %{"tagged" => "junk"},
          "expected" => %{"verdict" => "invalid", "code" => "digest_encoding_invalid"}
        },
        %{
          "id" => "dt-verify-ok",
          "surface" => "digest.tagged",
          "class" => "valid",
          "input" => %{"text" => "corpus", "domain" => "blueprint_content", "declared" => tagged},
          "expected" => %{"verdict" => "valid", "verified" => true}
        },
        %{
          "id" => "dt-verify-bad",
          "surface" => "digest.tagged",
          "class" => "digest_mismatch",
          "input" => %{"text" => "other", "domain" => "blueprint_content", "declared" => tagged},
          "expected" => %{"verdict" => "invalid", "code" => "digest_mismatch"}
        },
        %{
          "id" => "dt-bad-domain",
          "surface" => "digest.tagged",
          "class" => "invalid_type",
          "input" => %{"text" => "corpus", "domain" => "nope", "declared" => tagged},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        }
      ]

      for id <- ~w(dt-valid dt-bad dt-verify-ok dt-verify-bad dt-bad-domain),
          do: assert(agree?(cases, id))
    end

    test "blueprint.decode + deployment.decode valid (the fixture goldens)" do
      cases = [
        %{
          "id" => "bp-valid",
          "surface" => "blueprint.decode",
          "class" => "valid",
          "input" => %{"text" => AgentBlueprintProtocol.BlueprintFixture.fixture_bytes([])},
          "expected" => %{"verdict" => "valid", "digest" => bp_digest_projection()}
        },
        %{
          "id" => "bp-missing",
          "surface" => "blueprint.decode",
          "class" => "invalid_constraint",
          "input" => %{"text" => "{}"},
          "expected" => %{"verdict" => "invalid", "code" => "missing_required_field"}
        },
        %{
          "id" => "dep-valid",
          "surface" => "deployment.decode",
          "class" => "valid",
          "input" => %{"text" => AgentBlueprintProtocol.DeploymentFixture.fixture_bytes([])},
          "expected" => %{"verdict" => "valid", "digest" => dep_digest_projection()}
        }
      ]

      for id <- ~w(bp-valid bp-missing dep-valid), do: assert(agree?(cases, id))
    end

    test "negotiation.negotiate + extension.resolve over a minimal artifact" do
      artifact = %{
        "protocol_revision" => 1,
        "content_digest" => "sha-256:corpus-vocabulary-selector",
        "required_core_fields" => [],
        "extensions" => %{
          "critical" => %{"com.example/federation" => %{"issuer" => "org-a"}},
          "optional" => %{}
        }
      }

      support = %{
        "revisions" => [1],
        "registry" => %{
          "com.example/federation" => %{
            "criticality" => "critical",
            "state" => "active",
            "promoted_at_revision" => 1.5,
            "extra_null" => nil
          }
        },
        "schemas" => %{
          "com.example/federation" =>
            AgentBlueprintProtocol.ExtensionRegistry.federation_schema() |> tagged_to_plain()
        }
      }

      cases = [
        %{
          "id" => "neg-valid",
          "surface" => "negotiation.negotiate",
          "class" => "valid",
          "input" => %{"artifact" => artifact, "support" => support},
          "expected" => %{"verdict" => "valid", "revision" => 1}
        },
        %{
          "id" => "neg-ext-valid",
          "surface" => "extension.resolve",
          "class" => "valid",
          "input" => %{"artifact" => artifact, "support" => support},
          "expected" => %{"verdict" => "valid", "critical" => ["com.example/federation"]}
        }
      ]

      assert agree?(cases, "neg-valid")
      assert agree?(cases, "neg-ext-valid")
    end

    test "bounds.new valid projection + unknown key passthrough" do
      cases = [
        %{
          "id" => "bn-valid",
          "surface" => "bounds.new",
          "class" => "valid",
          "input" => %{"bounds" => %{"depth" => 8}},
          "expected" => %{
            "verdict" => "valid",
            "bounds" => %{
              "bytes" => 5_000_000,
              "depth" => 8,
              "members" => 1_000,
              "items" => 10_000,
              "nodes" => 200_000,
              "string" => 100_000,
              "key" => 1_000,
              "number_lexeme" => 64
            }
          }
        },
        %{
          "id" => "bn-unknown",
          "surface" => "bounds.new",
          "class" => "invalid_constraint",
          "input" => %{"bounds" => %{"bogus" => 1}},
          "expected" => %{"verdict" => "invalid", "code" => "unknown_bound"}
        },
        %{
          "id" => "bn-bad-shape",
          "surface" => "bounds.new",
          "class" => "invalid_type",
          "input" => %{"bounds" => [1]},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        }
      ]

      for id <- ~w(bn-valid bn-unknown bn-bad-shape), do: assert(agree?(cases, id))
    end

    test "bounds_algebra.intersect: operational narrowing clamps + protected denial + unknown bound" do
      # All three sources share IDENTICAL protected bounds (no protected
      # narrowing); only the operational eight narrow toward the blueprint.
      narrow = %{
        "max_attempts" => 3,
        "max_concurrency" => 3,
        "max_cost" => %{"amount" => 3, "currency" => "USD"},
        "max_depth" => 3,
        "max_descendants" => 3,
        "max_elapsed_ms" => 3,
        "max_fan_out" => 3,
        "max_tokens" => 3,
        "classification_ceiling" => %{"ordinal" => "internal", "markers" => []},
        "authority_trait" => "local_policy",
        "approval_trait" => "none",
        "effect_impact_ceiling" => "ordinary",
        "disclosure_ceiling" => "none"
      }

      wide = %{
        "max_attempts" => 9,
        "max_concurrency" => 9,
        "max_cost" => %{"amount" => 9, "currency" => "USD"},
        "max_depth" => 9,
        "max_descendants" => 9,
        "max_elapsed_ms" => 9,
        "max_fan_out" => 9,
        "max_tokens" => 9,
        "classification_ceiling" => narrow["classification_ceiling"],
        "authority_trait" => narrow["authority_trait"],
        "approval_trait" => narrow["approval_trait"],
        "effect_impact_ceiling" => narrow["effect_impact_ceiling"],
        "disclosure_ceiling" => narrow["disclosure_ceiling"]
      }

      cases = [
        %{
          "id" => "ba-widen",
          "surface" => "bounds_algebra.intersect",
          "class" => "bound_widening_operational",
          "input" => %{"blueprint" => wide, "deployment" => narrow, "host" => narrow},
          "expected" => %{"verdict" => "valid", "clamp_count" => 8}
        },
        %{
          "id" => "ba-protected",
          "surface" => "bounds_algebra.intersect",
          "class" => "bound_widening_protected",
          "input" => %{
            "blueprint" => narrow,
            "deployment" => narrow,
            "host" =>
              Map.put(narrow, "classification_ceiling", %{"ordinal" => "public", "markers" => []})
          },
          "expected" => %{"verdict" => "invalid", "code" => "protected_bound_clamp_denied"}
        },
        %{
          "id" => "ba-unknown",
          "surface" => "bounds_algebra.intersect",
          "class" => "invalid_type",
          "input" => %{
            "blueprint" => %{"no_such_bound" => 1},
            "deployment" => wide,
            "host" => wide
          },
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        }
      ]

      for id <- ~w(ba-widen ba-protected ba-unknown), do: assert(agree?(cases, id))
    end

    test "portability.scan valid + compatibility.verify" do
      deployment = AgentBlueprintProtocol.DeploymentFixture.fixture_bytes([])

      cases = [
        %{
          "id" => "port-clean",
          "surface" => "portability.scan",
          "class" => "valid",
          "input" => %{"text" => "{\"kind\":\"ordinary\"}"},
          "expected" => %{"verdict" => "valid", "clean" => true}
        },
        %{
          "id" => "comp-valid",
          "surface" => "compatibility.verify",
          "class" => "compatibility_range_rejected",
          "input" => %{"text" => deployment, "observed" => %{"identities" => []}},
          "expected" => %{"verdict" => "invalid", "code" => "compatibility_entry_missing"}
        },
        %{
          "id" => "comp-bad-observed",
          "surface" => "compatibility.verify",
          "class" => "invalid_constraint",
          "input" => %{"text" => deployment, "observed" => %{}},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        },
        %{
          # the second-language mirror's parity finding: a malformed identity
          # ELEMENT (non-map, or missing keys) crashed build_observed with
          # FunctionClauseError (probed live 2026-08-23) instead of denying
          # typed. The map now falls to :invalid like prior_receipts.
          "id" => "comp-malformed-identity",
          "surface" => "compatibility.verify",
          "class" => "invalid_constraint",
          "input" => %{
            "text" => deployment,
            "observed" => %{"identities" => ["boom"]}
          },
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        }
      ]

      for id <- ~w(port-clean comp-valid comp-bad-observed comp-malformed-identity),
          do: assert(agree?(cases, id))

      # class labels are corpus taxonomy; the probe pinned the code
    end

    test "federation.decode: envelope valid + every codec arm" do
      alias AgentBlueprintProtocol.{Federation, FederationFixture}

      {:ok, env} = Federation.decode(FederationFixture.bytes(terminal: true))
      {:ok, carrier} = Federation.to_a2a_carrier(env)
      carrier_plain = tagged_to_plain(carrier)

      cases = [
        %{
          "id" => "fed-env-valid",
          "surface" => "federation.decode",
          "class" => "valid",
          "input" => %{"text" => FederationFixture.bytes(terminal: true)},
          "expected" => %{
            "verdict" => "valid",
            "canonical" => FederationFixture.bytes(terminal: true)
          }
        },
        %{
          "id" => "fed-a2a-to",
          "surface" => "federation.decode",
          "class" => "valid",
          "input" => %{"to_a2a_state" => "completed"},
          "expected" => %{"verdict" => "valid", "value" => "TASK_STATE_COMPLETED"}
        },
        %{
          "id" => "fed-mcp-from",
          "surface" => "federation.decode",
          "class" => "valid",
          "input" => %{"from_mcp_state" => "working"},
          "expected" => %{"verdict" => "valid", "value" => "working"}
        },
        %{
          "id" => "fed-mcp-to",
          "surface" => "federation.decode",
          "class" => "valid",
          "input" => %{"to_mcp_state" => "canceled"},
          "expected" => %{"verdict" => "valid", "value" => "cancelled"}
        },
        %{
          "id" => "fed-a2a-carrier",
          "surface" => "federation.decode",
          "class" => "valid",
          "input" => %{"from_a2a_carrier" => carrier_plain},
          "expected" => %{"verdict" => "valid", "decoded" => true}
        },
        %{
          "id" => "fed-mcp-carrier",
          "surface" => "federation.decode",
          "class" => "valid",
          "input" => %{"from_mcp_carrier" => %{}},
          "expected" => %{"verdict" => "invalid"}
        },
        %{
          "id" => "fed-bad-state",
          "surface" => "federation.decode",
          "class" => "invalid_type",
          "input" => %{"to_a2a_state" => "no-such-state"},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        },
        %{
          "id" => "fed-no-input",
          "surface" => "federation.decode",
          "class" => "invalid_type",
          "input" => %{},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        }
      ]

      for id <-
            ~w(fed-env-valid fed-a2a-to fed-mcp-from fed-mcp-to fed-a2a-carrier fed-bad-state fed-no-input),
          do: assert(agree?(cases, id))

      # The empty MCP carrier denies (no required members) — verdict only.
      refute agree?(cases, "fed-mcp-carrier")
    end

    test "federation.verify_commitment: denial paths through the context builder" do
      pub =
        :crypto.hash(:sha256, "fc-coverage-seed")
        |> then(&elem(:crypto.generate_key(:eddsa, :ed25519, &1), 0))

      commitment =
        AgentBlueprintProtocol.FederationFixture.tagged_digest(:federation_envelope, "r1")

      cases = [
        %{
          "id" => "fc-empty",
          "surface" => "federation.verify_commitment",
          "class" => "invalid_type",
          "input" => %{
            "envelope" => AgentBlueprintProtocol.FederationFixture.bytes(terminal: true),
            "context" => %{}
          },
          "expected" => %{"verdict" => "invalid", "code" => "signature_key_unsupported"}
        },
        %{
          "id" => "fc-priors",
          "surface" => "federation.verify_commitment",
          "class" => "signature_invalid",
          "input" => %{
            "envelope" => AgentBlueprintProtocol.FederationFixture.bytes(terminal: true),
            "context" => %{
              "keys" => [
                %{"key_id" => "remote-key", "key" => Base.url_encode64(pub, padding: false)}
              ],
              "prior_receipts" => [
                %{
                  "task_identity" => "task-7f3a2c",
                  "terminal_state" => "failed",
                  "commitment" => commitment
                }
              ]
            }
          },
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        },
        %{
          # A present-but-non-list prior_receipts
          # CRASHED build_context with Protocol.UndefinedError (Enum.map over
          # a string). Now denies typed like every other context rim.
          "id" => "fc-priors-not-a-list",
          "surface" => "federation.verify_commitment",
          "class" => "invalid_type",
          "input" => %{
            "envelope" => AgentBlueprintProtocol.FederationFixture.bytes(terminal: true),
            "context" => %{"prior_receipts" => "boom"}
          },
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        },
        %{
          "id" => "fc-bad-receipt",
          "surface" => "federation.verify_commitment",
          "class" => "invalid_type",
          "input" => %{
            "envelope" => AgentBlueprintProtocol.FederationFixture.bytes(terminal: true),
            "context" => %{"prior_receipts" => [%{"task_identity" => 1}]}
          },
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        },
        %{
          "id" => "fc-bad-sets",
          "surface" => "federation.verify_commitment",
          "class" => "invalid_type",
          "input" => %{
            "envelope" => AgentBlueprintProtocol.FederationFixture.bytes(terminal: true),
            "context" => %{"issuer_key_sets" => [1]}
          },
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        }
      ]

      for id <- ~w(fc-empty fc-priors fc-priors-not-a-list fc-bad-receipt fc-bad-sets),
          do: assert(agree?(cases, id))
    end

    test "signature.verify + schema.validate_instance dispatch" do
      cases = [
        %{
          "id" => "sig-bad-entry",
          "surface" => "signature.verify",
          "class" => "invalid_encoding",
          "input" => %{"entry" => "not-json", "keys" => []},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_syntax"}
        },
        %{
          "id" => "schema-ok",
          "surface" => "schema.validate_instance",
          "class" => "valid",
          "input" => %{
            "schema" => %{
              "type" => "object",
              "additionalProperties" => false,
              "properties" => %{}
            },
            "instance" => %{}
          },
          "expected" => %{"verdict" => "valid", "valid" => true}
        },
        %{
          "id" => "schema-bad-type",
          "surface" => "schema.validate_instance",
          "class" => "invalid_type",
          "input" => %{
            "schema" => %{"type" => "object"},
            "instance" => 5
          },
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        },
        %{
          "id" => "schema-no-schema",
          "surface" => "schema.validate_instance",
          "class" => "invalid_type",
          "input" => %{"instance" => %{}},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        }
      ]

      for id <- ~w(sig-bad-entry schema-ok schema-bad-type schema-no-schema),
          do: assert(agree?(cases, id))
    end
  end

  describe "the runner: edge and error branches" do
    test "json decode with scalar variety covers the plain projection" do
      cases = [
        %{
          "id" => "json-scalars",
          "surface" => "json.decode",
          "class" => "valid",
          "input" => %{
            "text" => ~s({"n":1.5,"b":true,"x":null,"s":"t","i":3,"a":[1,"u",false,null]})
          },
          "expected" => %{
            "verdict" => "valid",
            "value" => %{
              "n" => 1.5,
              "b" => true,
              "x" => nil,
              "s" => "t",
              "i" => 3,
              "a" => [1, "u", false, nil]
            }
          }
        }
      ]

      assert agree?(cases, "json-scalars")
    end

    test "the non-binary marker and base64url input paths" do
      cases = [
        %{
          "id" => "nb-marker",
          "surface" => "json.decode",
          "class" => "invalid_type",
          "input" => %{"non_binary" => true},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        },
        %{
          "id" => "b64-input",
          "surface" => "json.decode",
          "class" => "valid",
          "input" => %{"base64url" => Base.url_encode64("123", padding: false)},
          "expected" => %{"verdict" => "valid", "value" => 123}
        },
        %{
          "id" => "b64-bad-input",
          "surface" => "json.decode",
          "class" => "invalid_type",
          "input" => %{"base64url" => "!!"},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        },
        %{
          "id" => "no-bytes",
          "surface" => "json.decode",
          "class" => "invalid_type",
          "input" => %{},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        }
      ]

      for id <- ~w(nb-marker b64-input b64-bad-input no-bytes), do: assert(agree?(cases, id))
    end

    test "malformed expectations disagree without crashing (agreement guards)" do
      cases = [
        %{
          "id" => "guard-1",
          "surface" => "json.decode",
          "class" => "valid",
          "input" => %{"text" => "1"},
          "expected" => %{"verdict" => "invalid", "code" => "x"}
        },
        %{
          "id" => "guard-2",
          "surface" => "json.decode",
          "class" => "invalid",
          "input" => %{"text" => "{"},
          "expected" => %{"verdict" => "valid", "value" => 1}
        },
        %{
          "id" => "guard-3",
          "surface" => "json.decode",
          "class" => "valid",
          "input" => %{"text" => "1"},
          "expected" => %{"verdict" => "valid", "missing_projection" => 1}
        },
        %{
          "id" => "guard-4",
          "surface" => "json.decode",
          "class" => "valid",
          "input" => %{"text" => "1"},
          "expected" => %{"verdict" => "wat"}
        },
        %{
          "id" => "guard-5",
          "surface" => "no.such.surface",
          "class" => "valid",
          "input" => %{},
          "expected" => %{"verdict" => "valid", "value" => 1}
        }
      ]

      for id <- ~w(guard-1 guard-2 guard-3 guard-4 guard-5), do: refute(agree?(cases, id))
    end

    test "schema dialect paths + signature key paths" do
      schema = %{"type" => "object", "additionalProperties" => false, "properties" => %{}}

      cases = [
        %{
          "id" => "sc-dialect",
          "surface" => "schema.validate_instance",
          "class" => "invalid_type",
          "input" => %{"schema" => schema, "instance" => %{}, "dialect" => 5},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        },
        %{
          "id" => "sc-miss",
          "surface" => "schema.validate_instance",
          "class" => "invalid_type",
          "input" => %{"schema_file" => "schemas/absent.json", "instance" => %{}},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        },
        %{
          "id" => "sig-no-keys",
          "surface" => "signature.verify",
          "class" => "invalid_type",
          "input" => %{"entry" => "{}"},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        },
        %{
          "id" => "sig-bad-key",
          "surface" => "signature.verify",
          "class" => "invalid_type",
          "input" => %{"entry" => "{}", "keys" => [%{"key_id" => "k", "key" => "short"}]},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        },
        %{
          "id" => "sig-bad-entry-shape",
          "surface" => "signature.verify",
          "class" => "invalid_type",
          "input" => %{"entry" => "{}", "keys" => [5]},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        }
      ]

      for id <- ~w(sc-dialect sc-miss sig-no-keys sig-bad-key sig-bad-entry-shape),
          do: assert(agree?(cases, id))
    end

    test "support builder fallbacks: criticality/state/registry shapes" do
      artifact = %{
        "protocol_revision" => 1,
        "content_digest" => "sha-256:x",
        "required_core_fields" => [],
        "extensions" => %{"critical" => %{}, "optional" => %{}}
      }

      support = %{
        "revisions" => [1],
        "registry" => %{
          "com.example/x" => %{
            "criticality" => "optional",
            "state" => "reserved",
            "a2a_uri" => "https://x/y"
          },
          "com.example/y" => %{"criticality" => "critical", "state" => "deprecated"},
          "com.example/z" => %{"criticality" => "critical", "state" => "retired"}
        }
      }

      cases = [
        %{
          "id" => "neg-fallbacks",
          "surface" => "negotiation.negotiate",
          "class" => "valid",
          "input" => %{"artifact" => artifact, "support" => support},
          "expected" => %{"verdict" => "valid", "revision" => 1}
        }
      ]

      assert agree?(cases, "neg-fallbacks")

      unknown_critical = %{
        "protocol_revision" => 1,
        "content_digest" => "sha-256:x",
        "required_core_fields" => [],
        "extensions" => %{"critical" => %{"com.example/absent" => %{}}, "optional" => %{}}
      }

      denied = [
        %{
          "id" => "neg-unknown-critical",
          "surface" => "negotiation.negotiate",
          "class" => "extension_unknown_critical",
          "input" => %{"artifact" => unknown_critical, "support" => support},
          "expected" => %{"verdict" => "invalid", "code" => "extension_unknown_critical"}
        },
        %{
          "id" => "ext-unknown-critical",
          "surface" => "extension.resolve",
          "class" => "extension_unknown_critical",
          "input" => %{"artifact" => unknown_critical, "support" => support},
          "expected" => %{"verdict" => "invalid", "code" => "extension_unknown_critical"}
        }
      ]

      assert agree?(denied, "neg-unknown-critical")
      assert agree?(denied, "ext-unknown-critical")
    end

    test "deployment binding: unparseable observation time falls back nil" do
      other_ceilings =
        {:object,
         [
           {"max_attempts", {:integer, 9}},
           {"max_concurrency", {:integer, 9}},
           {"max_cost", {:object, [{"amount", {:integer, 9}}, {"currency", {:string, "USD"}}]}},
           {"max_depth", {:integer, 9}},
           {"max_descendants", {:integer, 9}},
           {"max_elapsed_ms", {:integer, 9}},
           {"max_fan_out", {:integer, 9}},
           {"max_tokens", {:integer, 9}}
         ]}

      cases = [
        %{
          "id" => "dep-bind-time",
          "surface" => "deployment.decode",
          "class" => "digest_mismatch",
          "input" => %{
            "text" => AgentBlueprintProtocol.DeploymentFixture.fixture_bytes([]),
            "binding" => %{
              "blueprint" =>
                AgentBlueprintProtocol.BlueprintFixture.fixture_bytes(ceilings: other_ceilings),
              "now" => "not-a-time"
            }
          },
          "expected" => %{"verdict" => "invalid", "code" => "deployment_digest_mismatch"}
        }
      ]

      assert agree?(cases, "dep-bind-time")
    end

    test "verify_commitment: issuer_key_sets parsing paths" do
      pub =
        :crypto.hash(:sha256, "fc-coverage-seed")
        |> then(&elem(:crypto.generate_key(:eddsa, :ed25519, &1), 0))

      cases = [
        %{
          "id" => "fc-sets-ok",
          "surface" => "federation.verify_commitment",
          "class" => "invalid_type",
          "input" => %{
            "envelope" => AgentBlueprintProtocol.FederationFixture.bytes(terminal: true),
            "context" => %{
              "issuer_key_sets" => %{
                "org-a" => [
                  %{"key_id" => "remote-key", "key" => Base.url_encode64(pub, padding: false)}
                ]
              }
            }
          },
          "expected" => %{"verdict" => "invalid", "code" => "signature_key_unsupported"}
        },
        %{
          "id" => "fc-sets-bad-keys",
          "surface" => "federation.verify_commitment",
          "class" => "invalid_type",
          "input" => %{
            "envelope" => AgentBlueprintProtocol.FederationFixture.bytes(terminal: true),
            "context" => %{"issuer_key_sets" => %{"org-a" => [%{"key_id" => 1}]}}
          },
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        }
      ]

      assert agree?(cases, "fc-sets-ok")
      assert agree?(cases, "fc-sets-bad-keys")
    end

    test "federation codec unmappable + bad logical spelling paths" do
      cases = [
        %{
          "id" => "fed-bad-from-mcp",
          "surface" => "federation.decode",
          "class" => "invalid_constraint",
          "input" => %{"from_mcp_state" => "pending"},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_constraint"}
        },
        %{
          "id" => "fed-bad-to-atom",
          "surface" => "federation.decode",
          "class" => "invalid_type",
          "input" => %{"to_mcp_state" => "no-such"},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        }
      ]

      for id <- ~w(fed-bad-from-mcp fed-bad-to-atom), do: assert(agree?(cases, id))
    end
  end

  describe "the runner: success paths over real fixtures" do
    test "signature.verify: a correctly signed entry verifies (RFC 7797 b64=false)" do
      alias AgentBlueprintProtocol.{Base64Url, Canonicalization, Digest, Signature}

      seed = :crypto.hash(:sha256, "corpus-signature-coverage")
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519, seed)

      header =
        {:object,
         [
           {"alg", {:string, "EdDSA"}},
           {"b64", {:boolean, false}},
           {"crit", {:array, [{:string, "b64"}]}},
           {"kid", {:string, "corpus-key"}}
         ]}

      attrs =
        {:object,
         [
           {"algorithm", {:string, "Ed25519"}},
           {"content_digest",
            {:string, Digest.to_tagged(Digest.hash(:deployment_content, "corpus"))}},
           {"created_at", {:string, "2026-08-23T00:00:00Z"}},
           {"key_id", {:string, "corpus-key"}},
           {"purpose", {:string, "deployment"}}
         ]}

      {:ok, h} = Canonicalization.encode(header)
      {:ok, a} = Canonicalization.encode(attrs)
      signing_input = Base64Url.encode(h) <> "." <> a
      sig = :crypto.sign(:eddsa, :none, signing_input, [priv, :ed25519])

      {:ok, entry_text} =
        Canonicalization.encode(
          {:object,
           [
             {"protected", header},
             {"signed_attributes", attrs},
             {"signature", {:string, Base64Url.encode(sig)}}
           ]}
        )

      keys = [%{"key_id" => "corpus-key", "key" => Base.url_encode64(pub, padding: false)}]

      cases = [
        %{
          "id" => "sig-valid",
          "surface" => "signature.verify",
          "class" => "valid",
          "input" => %{"entry" => entry_text, "keys" => keys},
          "expected" => %{"verdict" => "valid", "verified" => true}
        },
        %{
          "id" => "sig-rotten",
          "surface" => "signature.verify",
          "class" => "signature_invalid",
          "input" => %{
            "entry" => String.replace(entry_text, "Ed25519", "Ed25518"),
            "keys" => keys
          },
          "expected" => %{"verdict" => "invalid", "code" => "signature_not_verified"}
        }
      ]

      assert agree?(cases, "sig-valid")
      # The tampered attribute byte breaks the signature math.
      refute agree?(cases, "sig-rotten")
    end

    test "deployment binding: the paired fixtures bind OK and parse a valid clock" do
      cases = [
        %{
          "id" => "dep-bind-ok",
          "surface" => "deployment.decode",
          "class" => "valid",
          "input" => %{
            "text" => AgentBlueprintProtocol.DeploymentFixture.fixture_bytes([]),
            "binding" => %{
              "blueprint" => AgentBlueprintProtocol.BlueprintFixture.fixture_bytes([]),
              "now" => "2026-08-23T00:00:00Z"
            }
          },
          "expected" => %{"verdict" => "valid", "digest" => dep_digest_projection()}
        }
      ]

      assert agree?(cases, "dep-bind-ok")
    end

    test "compatibility.verify: exact observed identities verify" do
      identity = AgentBlueprintProtocol.DeploymentFixture.build_identity()
      {:object, members} = identity

      observed_identity =
        Map.new(members, fn
          {"digest", {:string, v}} -> {"digest", v}
          {k, {:string, v}} -> {k, v}
        end)

      cases = [
        %{
          "id" => "comp-exact",
          "surface" => "compatibility.verify",
          "class" => "valid",
          "input" => %{
            "text" => AgentBlueprintProtocol.DeploymentFixture.fixture_bytes([]),
            "observed" => %{"identities" => [observed_identity]}
          },
          "expected" => %{"verdict" => "valid", "verified" => true}
        }
      ]

      assert agree?(cases, "comp-exact")
    end

    test "verify_commitment: an honestly signed receipt verifies green" do
      alias AgentBlueprintProtocol.{
        Base64Url,
        Canonicalization,
        Digest,
        Federation,
        FederationFixture,
        Signature
      }

      seed = :crypto.hash(:sha256, "federation-receipt-coverage")
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519, seed)

      shell = FederationFixture.value(terminal: true)

      with_commitment =
        put_in_receipt(shell, "terminal_commitment", commitment_of(shell))

      covered = drop_receipt_signature(with_commitment)
      {:ok, cj} = Canonicalization.encode(covered)
      digest = Digest.hash(:federation_envelope, cj)

      attrs =
        {:object,
         [
           {"algorithm", {:string, "Ed25519"}},
           {"content_digest", {:string, Digest.to_tagged(digest)}},
           {"created_at", {:string, "2026-08-23T00:00:00Z"}},
           {"key_id", {:string, "remote-key"}},
           {"purpose", {:string, "federation-envelope"}}
         ]}

      header =
        {:object,
         [
           {"alg", {:string, "EdDSA"}},
           {"b64", {:boolean, false}},
           {"crit", {:array, [{:string, "b64"}]}},
           {"kid", {:string, "remote-key"}}
         ]}

      {:ok, h} = Canonicalization.encode(header)
      {:ok, a} = Canonicalization.encode(attrs)
      signing_input = Base64Url.encode(h) <> "." <> a
      sig = :crypto.sign(:eddsa, :none, signing_input, [priv, :ed25519])

      entry =
        {:object,
         [
           {"protected", header},
           {"signed_attributes", attrs},
           {"signature", {:string, Base64Url.encode(sig)}}
         ]}

      signed = put_in_receipt(with_commitment, "signature", entry)

      {:ok, envelope_text} = Canonicalization.encode(signed)

      cases = [
        %{
          "id" => "fc-valid",
          "surface" => "federation.verify_commitment",
          "class" => "valid",
          "input" => %{
            "envelope" => envelope_text,
            "context" => %{
              "keys" => [
                %{"key_id" => "remote-key", "key" => Base.url_encode64(pub, padding: false)}
              ],
              "prior_receipts" => [
                %{
                  "task_identity" => "task-7f3a2c",
                  "terminal_state" => "completed",
                  "commitment" =>
                    AgentBlueprintProtocol.Digest.to_tagged(
                      AgentBlueprintProtocol.Digest.hash(:federation_envelope, "divergent")
                    )
                }
              ]
            }
          },
          "expected" => %{"verdict" => "invalid", "code" => "federation_terminal_conflict"}
        },
        %{
          "id" => "fc-green",
          "surface" => "federation.verify_commitment",
          "class" => "valid",
          "input" => %{
            "envelope" => envelope_text,
            "context" => %{
              "keys" => [
                %{"key_id" => "remote-key", "key" => Base.url_encode64(pub, padding: false)}
              ]
            }
          },
          "expected" => %{"verdict" => "valid", "task_identity" => "task-7f3a2c"}
        }
      ]

      assert {:ok, %Federation{}} = Federation.decode(envelope_text)
      assert agree?(cases, "fc-valid")
      assert agree?(cases, "fc-green")
      _ = Signature
    end

    test "raw_file inputs resolve against sidecars; misses deny" do
      raws = %{"raw/x.raw" => "123"}

      corpus = %Corpus{
        index: %{},
        index_bytes: "x",
        cases: [
          {"cases/t.json",
           [
             %{
               "id" => "raw-hit",
               "surface" => "json.decode",
               "class" => "valid",
               "input" => %{"raw_file" => "raw/x.raw"},
               "expected" => %{"verdict" => "valid", "value" => 123}
             },
             %{
               "id" => "raw-miss",
               "surface" => "json.decode",
               "class" => "invalid_type",
               "input" => %{"raw_file" => "raw/absent.raw"},
               "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
             }
           ]}
        ],
        data: %{},
        raws: raws,
        case_ids: MapSet.new(["raw-hit", "raw-miss"]),
        identity: "sha-256:x"
      }

      results = Runner.run(corpus) |> hd() |> elem(1)
      by_id = Map.new(results, &{&1.case_id, &1.agree})
      assert by_id["raw-hit"]
      assert by_id["raw-miss"]
    end

    test "schema_file resolves from corpus data (map + tagged); explicit dialect strings" do
      corpus = %Corpus{
        index: %{},
        index_bytes: "x",
        cases: [
          {"cases/t.json",
           [
             %{
               "id" => "sc-file",
               "surface" => "schema.validate_instance",
               "class" => "valid",
               "input" => %{
                 "schema_file" => "schemas/simple.schema.json",
                 "instance" => %{"x" => 1.5, "y" => nil},
                 "dialect" => AgentBlueprintProtocol.Schema.dialect()
               },
               "expected" => %{"verdict" => "valid", "valid" => true}
             },
             %{
               "id" => "sc-tagged",
               "surface" => "schema.validate_instance",
               "class" => "valid",
               "input" => %{
                 "schema_file" => "schemas/tagged.schema.json",
                 "instance" => %{}
               },
               "expected" => %{"verdict" => "valid", "valid" => true}
             }
           ]}
        ],
        data: %{
          "schemas/simple.schema.json" => %{
            "type" => "object",
            "additionalProperties" => false,
            "properties" => %{
              "x" => %{"type" => "number"},
              "y" => %{"type" => "null"}
            }
          },
          "schemas/tagged.schema.json" =>
            {:object,
             [
               {"type", {:string, "object"}},
               {"additionalProperties", {:boolean, false}},
               {"properties", {:object, []}}
             ]}
        },
        raws: %{},
        case_ids: MapSet.new(["sc-file", "sc-tagged"]),
        identity: "sha-256:x"
      }

      results = Runner.run(corpus) |> hd() |> elem(1)
      by_id = Map.new(results, &{&1.case_id, &1.agree})
      assert by_id["sc-file"]
      assert by_id["sc-tagged"]
    end

    test "member_string's miss arm returns nil (used in the digest projections)" do
      assert Builder.member_string({:object, [{"other", {:string, "x"}}]}, "absent") == nil
    end

    test "absent support/context members take their defaults (the nil arms)" do
      cases = [
        %{
          "id" => "neg-no-support",
          "surface" => "negotiation.negotiate",
          "class" => "invalid_type",
          "input" => %{"artifact" => %{"protocol_revision" => 2}},
          "expected" => %{"verdict" => "invalid", "code" => "protocol_revision_unsupported"}
        },
        %{
          "id" => "fc-no-context",
          "surface" => "federation.verify_commitment",
          "class" => "invalid_type",
          "input" => %{
            "envelope" => AgentBlueprintProtocol.FederationFixture.bytes(terminal: true)
          },
          "expected" => %{"verdict" => "invalid", "code" => "signature_key_unsupported"}
        }
      ]

      assert agree?(cases, "neg-no-support")
      assert agree?(cases, "fc-no-context")
    end

    test "malformed nested support/context members deny typed, never crash" do
      # Committed tripwires (live reds were the
      # BadMapError crashes).
      cases = [
        %{
          "id" => "neg-support-list",
          "surface" => "negotiation.negotiate",
          "class" => "invalid_type",
          "input" => %{"artifact" => %{"protocol_revision" => 1}, "support" => []},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        },
        %{
          "id" => "ext-support-list",
          "surface" => "extension.resolve",
          "class" => "invalid_type",
          "input" => %{"artifact" => %{"protocol_revision" => 1}, "support" => "junk"},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        },
        %{
          "id" => "fc-context-list",
          "surface" => "federation.verify_commitment",
          "class" => "invalid_type",
          "input" => %{
            "envelope" => AgentBlueprintProtocol.FederationFixture.bytes(terminal: true),
            "context" => []
          },
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        }
      ]

      for id <- ~w(neg-support-list ext-support-list fc-context-list),
          do: assert(agree?(cases, id))
    end

    test "a codec key with no matching arm denies invalid_type" do
      cases = [
        %{
          "id" => "fed-arm-miss",
          "surface" => "federation.decode",
          "class" => "invalid_type",
          "input" => %{"from_a2a_state" => 5},
          "expected" => %{"verdict" => "invalid", "code" => "invalid_type"}
        }
      ]

      assert agree?(cases, "fed-arm-miss")
    end

    test "an off-lattice ordinal passes through and the algebra denies it" do
      narrow = %{
        "max_attempts" => 3,
        "max_concurrency" => 3,
        "max_cost" => %{"amount" => 3, "currency" => "USD"},
        "max_depth" => 3,
        "max_descendants" => 3,
        "max_elapsed_ms" => 3,
        "max_fan_out" => 3,
        "max_tokens" => 3,
        "classification_ceiling" => %{"ordinal" => "banana", "markers" => []},
        "authority_trait" => "local_policy",
        "approval_trait" => "none",
        "effect_impact_ceiling" => "ordinary",
        "disclosure_ceiling" => "none"
      }

      cases = [
        %{
          "id" => "ba-banana",
          "surface" => "bounds_algebra.intersect",
          "class" => "invalid_constraint",
          "input" => %{"blueprint" => narrow, "deployment" => narrow, "host" => narrow},
          "expected" => %{"verdict" => "invalid", "code" => "bound_value_invalid"}
        }
      ]

      assert agree?(cases, "ba-banana")
    end

    test "the acknowledge posture clamps protected bounds with evidence" do
      narrow = %{
        "max_attempts" => 3,
        "max_concurrency" => 3,
        "max_cost" => %{"amount" => 3, "currency" => "USD"},
        "max_depth" => 3,
        "max_descendants" => 3,
        "max_elapsed_ms" => 3,
        "max_fan_out" => 3,
        "max_tokens" => 3,
        "classification_ceiling" => %{"ordinal" => "internal", "markers" => []},
        "authority_trait" => "local_policy",
        "approval_trait" => "none",
        "effect_impact_ceiling" => "ordinary",
        "disclosure_ceiling" => "none"
      }

      cases = [
        %{
          "id" => "ba-ack",
          "surface" => "bounds_algebra.intersect",
          "class" => "bound_widening_protected",
          "input" => %{
            "blueprint" => narrow,
            "deployment" => narrow,
            "host" =>
              Map.put(narrow, "classification_ceiling", %{"ordinal" => "public", "markers" => []}),
            "protected_clamp" => "acknowledge"
          },
          "expected" => %{"verdict" => "valid", "clamp_count" => 1}
        }
      ]

      assert agree?(cases, "ba-ack")
    end

    test "a non-base64 expected value falls back to inequality" do
      cases = [
        %{
          "id" => "cmp-fallback",
          "surface" => "base64url.decode",
          "class" => "valid",
          "input" => %{"base64url" => "QQ"},
          "expected" => %{"verdict" => "valid", "decoded" => "!!!not-base64!!!"}
        }
      ]

      refute agree?(cases, "cmp-fallback")
    end
  end

  defp put_in_receipt(envelope_value, name, value) do
    {:object, members} = envelope_value

    {:object,
     Enum.map(members, fn
       {"evidence_receipt", {:object, receipt}} ->
         inner = Enum.map(receipt, fn {n, v} -> {n, if(n == name, do: value, else: v)} end)
         {"evidence_receipt", {:object, inner}}

       other ->
         other
     end)}
  end

  defp put_in_receipt_inner(envelope_value, name, value) do
    {:object, members} = envelope_value

    {:object,
     Enum.map(members, fn
       {"evidence_receipt", {:object, receipt}} ->
         inner =
           Enum.map(receipt, fn
             {"jws", {:object, jws_members}} ->
               {"jws",
                {:object,
                 Enum.map(jws_members, fn {n, v} ->
                   {n, if(n == name, do: {:string, value}, else: v)}
                 end)}}

             {n, v} ->
               {n, v}
           end)

         {"evidence_receipt", {:object, inner}}

       other ->
         other
     end)}
  end

  defp commitment_of(envelope_value) do
    {:ok, digest} =
      AgentBlueprintProtocol.Federation.terminal_commitment(%AgentBlueprintProtocol.Federation{
        value: envelope_value
      })

    {:string, AgentBlueprintProtocol.Digest.to_tagged(digest)}
  end

  defp drop_receipt_signature(envelope_value) do
    {:object, members} = envelope_value

    {:object,
     Enum.map(members, fn
       {"evidence_receipt", {:object, receipt}} ->
         {"evidence_receipt", {:object, Enum.reject(receipt, fn {n, _} -> n == "signature" end)}}

       other ->
         other
     end)}
  end

  defp bp_digest_projection,
    do: Builder.member_string(BlueprintFixture.fixture_value([]), "content_digest")

  defp dep_digest_projection,
    do: Builder.member_string(DeploymentFixture.fixture_value([]), "deployment_digest")

  defp tagged_to_plain({:object, members}),
    do: members |> Enum.map(fn {k, v} -> {k, tagged_to_plain(v)} end) |> Map.new()

  defp tagged_to_plain({:array, items}), do: Enum.map(items, &tagged_to_plain/1)
  defp tagged_to_plain({:string, s}), do: s
  defp tagged_to_plain({:integer, n}), do: n
  defp tagged_to_plain({:float, n}), do: n
  defp tagged_to_plain({:boolean, b}), do: b
  defp tagged_to_plain(:null), do: nil

  defp tagged_to_plain(value) when is_map(value),
    do: value |> Enum.map(fn {k, v} -> {k, tagged_to_plain(v)} end) |> Map.new()

  defp tagged_to_plain(value) when is_list(value), do: Enum.map(value, &tagged_to_plain/1)
  defp tagged_to_plain(value), do: value

  describe "the report: refuses vacuous green" do
    test "zero executed results never agree" do
      report = Report.build(corpus_with([]), [])
      refute report.agreement
      assert report.exit_status == 1
      assert report.total == 0
    end

    test "agreement requires every case to agree" do
      results = [
        {"cases/test.json", [%{case_id: "a", agree: true}, %{case_id: "b", agree: false}]}
      ]

      report = Report.build(corpus_with([]), results)

      refute report.agreement
      assert %{total: 2, agreed: 1, disagreed: 1} = report
    end

    test "deterministic JCS bytes, bound to the corpus identity" do
      cases = [
        %{
          "id" => "b64-valid",
          "surface" => "base64url.decode",
          "class" => "valid",
          "input" => %{"base64url" => "QQ"},
          "expected" => %{"verdict" => "valid", "decoded" => "QQ"}
        }
      ]

      corpus = corpus_with(cases)
      results = Runner.run(corpus)
      report = Report.build(corpus, results)
      assert report.agreement and report.exit_status == 0

      {:ok, bytes} = Report.to_bytes(corpus, results)
      assert is_binary(bytes)
      assert bytes =~ "test"

      other = %{corpus | identity: "sha-256:different"}
      {:ok, other_bytes} = Report.to_bytes(other, results)
      assert bytes != other_bytes
    end
  end

  describe "the CLI: --corpus required, exit-status contract" do
    @describetag :tmp_dir

    test "no arguments is a usage error (exit 2)" do
      assert Cli.run([]) == 2
    end

    test "an unknown flag is a usage error (exit 2)" do
      assert Cli.run(["--wat"]) == 2
    end

    test "a floor-valid corpus directory verifies green through the real path (exit 0)", %{
      tmp_dir: dir
    } do
      map = Builder.build(agreeable_minimal())
      write_corpus(dir, map)

      assert ExUnit.CaptureIO.capture_io(fn ->
               send(self(), {:exit, Cli.run(["--corpus", dir])})
             end) =~ "agreement"

      assert_received {:exit, 0}
    end

    test "an over-ceiling corpus file denies value-free at read (exit 2, security lens fix)", %{
      tmp_dir: dir
    } do
      map = Builder.build(agreeable_minimal())
      write_corpus(dir, map)
      # One file over the profile byte ceiling: the read is capped BEFORE
      # bytes are resident (Bounds is the single resource regime).
      File.write!(Path.join(dir, "cases/huge.json"), String.duplicate("A", 5_000_001))

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          send(self(), {:exit, Cli.run(["--corpus", dir])})
        end)

      refute output =~ Path.join(dir, "cases/huge.json")
      assert_received {:exit, 2}
    end

    test "a corrupt corpus directory denies at load (exit 2)", %{tmp_dir: dir} do
      map =
        Builder.build(Builder.minimal_cases())

      write_corpus(dir, Map.delete(map, "cases/json-decode.json"))

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          send(self(), {:exit, Cli.run(["--corpus", dir])})
        end)

      _ = output
      assert_received {:exit, 2}
    end

    test "the REAL escript drives Cli.Main.main end-to-end (exit 0 over the shipped corpus)" do
      # The halt shim is excluded from the coverage CENSUS (executing it
      # in-process would halt the test VM); this test closes the substance
      # gap — the built binary's actual entrypoint, driven through the
      # default path, asserting the exit contract in-suite (the derisk of
      # the carried acknowledgment).
      root = File.cwd!()
      escript = Path.join(root, "agent_blueprint_protocol_conformance")

      {build_out, build_status} =
        System.cmd("mix", ["escript.build"], cd: root, stderr_to_stdout: true)

      assert build_status == 0, "escript build failed:\n#{build_out}"

      on_exit(fn -> File.rm(escript) end)

      {run_out, run_status} =
        System.cmd(escript, ["--corpus", "priv/conformance"], cd: root, stderr_to_stdout: true)

      assert run_out =~ "\"agreement\":true"
      assert run_status == 0
    end
  end

  defp write_corpus(dir, map) do
    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    for {path, bytes} <- map do
      target = Path.join(dir, path)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, bytes)
    end
  end
end
