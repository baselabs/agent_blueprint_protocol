defmodule AgentBlueprintProtocol.ReconcileTest do
  @moduledoc """
  The composed import (the composed-import law): reconcile/3 runs the eight
  stages in the pinned order — canonical → digest → negotiation → structure
  → portability → signatures → bind → bounds — reject-or-annotate, never
  repair. Green end-to-end over the fixture pair; one tamper per stage
  forging the member that stage reads; extension facts and clamp evidence
  land as checks; the signature stage BINDS each entry's signed
  content_digest to the artifact's recomputed digest (a signature over
  another artifact's digest is not evidence here).
  """

  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{
    Blueprint,
    BlueprintFixture,
    BoundsAlgebra,
    Deployment,
    DeploymentFixture,
    Digest,
    Error,
    Evidence,
    Reconcile
  }

  alias AgentBlueprintProtocol.BoundsAlgebra.{BoundSet, ClampEvidence}
  alias AgentBlueprintProtocol.Deployment.Observations
  alias AgentBlueprintProtocol.Negotiation.Support
  alias AgentBlueprintProtocol.Signature.PublicKey

  # RFC 8032 §7.1 TEST 1 (the signature lane's pinned vector).
  @seed Base.decode16!("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
          case: :lower
        )

  defp golden_blueprint(opts \\ []) do
    BlueprintFixture.fixture_value(opts) |> Blueprint.from_value() |> elem(1)
  end

  # The Blueprint derives disclosure :full (no disclosure member — the
  # identity for the meet), so a sub-full deployment/host policy narrows a
  # protected bound on every import (the algebra's documented law). The
  # golden pair widens the deployment's host_bounds to keep :deny green.
  defp wide_host_bounds do
    {:object, members} = DeploymentFixture.host_bounds()

    {:object,
     Enum.map(members, fn
       {"disclosure_ceiling", _} -> {"disclosure_ceiling", {:string, "full"}}
       other -> other
     end)}
  end

  defp golden_deployment(opts \\ []) do
    DeploymentFixture.fixture_value(Keyword.merge([host_bounds: wide_host_bounds()], opts))
    |> Deployment.from_value()
    |> elem(1)
  end

  defp host_bounds(deployment \\ nil) do
    deployment = deployment || golden_deployment()
    {:ok, bounds} = BoundsAlgebra.from_deployment(deployment)
    bounds
  end

  defp inputs(opts \\ []) do
    %Reconcile.Inputs{
      host_bounds: Keyword.get(opts, :host_bounds, host_bounds()),
      support: Keyword.get(opts, :support, %Support{revisions: MapSet.new([1])}),
      keys: Keyword.get(opts, :keys, []),
      protected_clamp: Keyword.get(opts, :protected_clamp, :deny),
      observations: Keyword.get(opts, :observations, default_observations())
    }
  end

  defp default_observations do
    %Observations{
      now: ~U[2026-08-21T00:00:00Z],
      max_attestation_age_ms: 86_400_000,
      observed: %{}
    }
  end

  defp surfaces(%Evidence{} = evidence), do: Enum.map(evidence.checks, & &1.surface)

  # ---- golden green -----------------------------------------------------------------

  test "green end-to-end over the fixture pair: stage checks, retained fact, no clamps, seven atoms" do
    blueprint =
      golden_blueprint(
        extensions:
          BlueprintFixture.extensions(
            optional: %{
              "com.example.commerce/classification-labels" =>
                {:object, [{"labels", {:array, [{:string, "pci"}]}}]}
            }
          )
      )

    deployment = golden_deployment(blueprint: blueprint)

    assert {:ok,
            %Evidence{
              protocol_revision: 1,
              clamps: [],
              effective_bounds: %BoundSet{},
              optional_extensions_retained: ["com.example.commerce/classification-labels"],
              not_verified: not_verified
            } = evidence} = Reconcile.reconcile(blueprint, deployment, inputs())

    assert Enum.take(not_verified, 7) ==
             ~w(tenancy live_policy authority effect_ownership execution billing evaluation_truth)a

    assert surfaces(evidence) == [
             :canonical,
             :canonical,
             :digest,
             :digest,
             :negotiation,
             :negotiation,
             :extensions,
             :structure,
             :structure,
             :portability,
             :portability,
             :signatures,
             :signatures,
             :bind,
             :bounds
           ]

    assert Enum.all?(evidence.checks, & &1.verified)
    assert %Digest{} = evidence.blueprint_digest
    assert %Digest{} = evidence.deployment_digest
  end

  # ---- per-stage tampers (each stage's guard reddens its own tamper) ----------------

  test "canonical tamper: a bignum integer member denies :integer_magnitude at canonical" do
    {:object, ms} = Blueprint.to_value(golden_blueprint())

    forged =
      Enum.map(ms, fn
        {"triggers", _} -> {"triggers", {:integer, 9_223_372_036_854_775_807 * 1024}}
        other -> other
      end)

    assert {:error, %Error{code: :integer_magnitude, subject: ["blueprint"]}} =
             Reconcile.reconcile(
               %Blueprint{value: {:object, forged}},
               golden_deployment(),
               inputs()
             )
  end

  test "canonical tamper: an encode-breaking deployment member denies at canonical" do
    {:object, ms} = DeploymentFixture.fixture_value([])

    forged =
      Enum.map(ms, fn
        {"signer_custody", _} -> {"signer_custody", {:integer, 9_223_372_036_854_775_807 * 1024}}
        other -> other
      end)

    assert {:error, %Error{code: :integer_magnitude, subject: ["deployment"]}} =
             Reconcile.reconcile(
               golden_blueprint(),
               %Deployment{value: {:object, forged}},
               inputs()
             )
  end

  test "digest tamper: a forged declared deployment digest denies :digest_mismatch" do
    deployment =
      DeploymentFixture.fixture_value(
        declared_digest: DeploymentFixture.tagged("forged-deployment")
      )
      |> Deployment.from_value()
      |> elem(1)

    assert {:error, %Error{code: :digest_mismatch, subject: ["deployment"]}} =
             Reconcile.reconcile(golden_blueprint(), deployment, inputs())
  end

  test "canonical tamper: an over-ceiling evidence member denies {:ceiling, :bytes} at canonical only" do
    # Evidence members are digest-EXCLUDED, so only the canonical stage's
    # whole-value encode sees the over-ceiling size — the digest stage's
    # covered-member encode stays under. This is the stage-attribution
    # tamper (the bignum members above are caught identically at digest).
    huge = {:string, String.duplicate("a", 5_100_000)}

    {:object, ms} = DeploymentFixture.fixture_value([])
    forged = Enum.sort([{"attestations", {:array, [huge]}} | ms])

    assert {:error, %Error{code: {:ceiling, :bytes}, subject: ["deployment"]}} =
             Reconcile.reconcile(
               golden_blueprint(),
               %Deployment{value: {:object, forged}},
               inputs()
             )
  end

  test "digest tamper: a forged declared digest denies :digest_mismatch at digest" do
    blueprint =
      BlueprintFixture.fixture_value(
        declared_digest: Digest.to_tagged(Digest.hash(:blueprint_content, "forged"))
      )
      |> Blueprint.from_value()
      |> elem(1)

    assert {:error, %Error{code: :digest_mismatch, subject: ["blueprint"]}} =
             Reconcile.reconcile(blueprint, golden_deployment(), inputs())
  end

  test "negotiation tamper: an unsupported revision set denies at negotiation" do
    inputs = inputs(support: %Support{revisions: MapSet.new([2])})

    assert {:error, %Error{code: :protocol_revision_unsupported, subject: ["blueprint"]}} =
             Reconcile.reconcile(golden_blueprint(), golden_deployment(), inputs)
  end

  test "structure tamper: a malformed signatures entry denies at structure (digest-neutral)" do
    {:object, ms} = Deployment.to_value(golden_deployment())

    forged =
      Enum.map(ms, fn
        member when elem(member, 0) in ~w(deployment_digest signatures attestations) -> member
        other -> other
      end) ++ [{"signatures", {:array, [{:object, [{"junk", {:string, "x"}}]}]}}]

    assert {:error, %Error{code: :signature_malformed, subject: ["deployment"]}} =
             Reconcile.reconcile(
               golden_blueprint(),
               %Deployment{value: {:object, forged}},
               inputs()
             )
  end

  test "portability tamper: a URI in an identity position denies :forbidden_portable_value" do
    {:object, ms} = DeploymentFixture.fixture_value([])

    with_uri =
      Enum.map(ms, fn
        {"scope_projection", _} ->
          {"scope_projection",
           {:object, [{"adapter_identity", {:string, "https://internal.svc/api"}}]}}

        other ->
          other
      end)
      |> DeploymentFixture.with_digest()

    assert {:error, %Error{code: :forbidden_portable_value, subject: ["deployment"]}} =
             Reconcile.reconcile(golden_blueprint(), %Deployment{value: with_uri}, inputs())
  end

  test "signatures tamper: bad signature bytes deny :signature_not_verified" do
    deployment = signed_deployment(forged_signature: true)

    assert {:error, %Error{code: :signature_not_verified, subject: ["signatures", 0]}} =
             Reconcile.reconcile(golden_blueprint(), deployment, inputs(keys: verifiable_keys()))
  end

  test "signatures binding: an honest signature over a DIFFERENT digest denies :digest_mismatch" do
    for artifact <- [:deployment, :blueprint] do
      {blueprint, deployment} =
        case artifact do
          :deployment -> {golden_blueprint(), signed_deployment(foreign_digest: true)}
          :blueprint -> {signed_blueprint(foreign_digest: true), golden_deployment()}
        end

      assert {:error, %Error{code: :digest_mismatch, subject: ["signatures", 0]}} =
               Reconcile.reconcile(blueprint, deployment, inputs(keys: verifiable_keys())),
             "badge attack must deny on the #{artifact} side"
    end
  end

  test "signatures green: honest signatures over the artifacts' own digests verify" do
    assert {:ok, %Evidence{}} =
             Reconcile.reconcile(
               signed_blueprint(),
               signed_deployment(),
               inputs(keys: verifiable_keys())
             )
  end

  test "bind tamper: an observed descriptor mismatch denies :binding_descriptor_mismatch" do
    inputs =
      inputs(
        observations: %Observations{
          now: ~U[2026-08-21T00:00:00Z],
          max_attestation_age_ms: 86_400_000,
          observed: %{"example.demo.read_shape" => DeploymentFixture.tagged("other")}
        }
      )

    assert {:error, %Error{code: :binding_descriptor_mismatch, subject: ["deployment"]}} =
             Reconcile.reconcile(golden_blueprint(), golden_deployment(), inputs)
  end

  test "bounds tamper: a protected narrowing under :deny denies with the clamp triple" do
    host =
      host_bounds()
      |> narrow_to(:classification_ceiling, %{ordinal: :public, markers: MapSet.new()})

    assert {:error,
            %Error{
              code: :protected_bound_clamp_denied,
              detail: %ClampEvidence{field: :classification_ceiling}
            }} =
             Reconcile.reconcile(
               golden_blueprint(),
               golden_deployment(),
               inputs(host_bounds: host)
             )
  end

  test "stage order: a registry defect reports before a scan defect (structure precedes portability)" do
    # The registry half of from_value re-runs at portability, so a registry
    # error is catchable at both stages with an identical observable; the
    # load-bearing contract is the ORDER — the earliest-defect pin. This
    # composite defect (junk signatures entry + URI in an identity position,
    # digest honestly recomputed over both) must report the registry code.
    {:object, ms} = DeploymentFixture.fixture_value([])

    both =
      (Enum.map(ms, fn
         {"scope_projection", _} ->
           {"scope_projection",
            {:object, [{"adapter_identity", {:string, "https://internal.svc/api"}}]}}

         other ->
           other
       end) ++ [{"signatures", {:array, [{:object, [{"junk", {:string, "x"}}]}]}}])
      |> DeploymentFixture.with_digest()

    assert {:error, %Error{code: :signature_malformed, subject: ["deployment"]}} =
             Reconcile.reconcile(golden_blueprint(), %Deployment{value: both}, inputs())
  end

  test "rim: a forged non-object artifact root denies typed at canonical (never raises)" do
    for value <- [{:string, "x"}, {:integer, 7}, {:array, []}, {:object, :junk}] do
      assert {:error, %Error{code: :invalid_type, subject: ["blueprint"]}} =
               Reconcile.reconcile(%Blueprint{value: value}, golden_deployment(), inputs()),
             "blueprint root #{inspect(value)} must deny typed"

      assert {:error, %Error{code: :invalid_type, subject: ["deployment"]}} =
               Reconcile.reconcile(golden_blueprint(), %Deployment{value: value}, inputs()),
             "deployment root #{inspect(value)} must deny typed"
    end
  end

  test "a decode-valid blueprint with long kebab identifiers reconciles green (position modes)" do
    # 43-char separator-bearing identifier: passes scan_identifier (the
    # exemption identifier positions keep at decode) but FAILS scan_value —
    # the portability stage must mirror the per-position modes, not
    # strict-scan everything.
    long_in = String.duplicate("ab-", 14) <> "cd"
    long_out = String.duplicate("cd-", 14) <> "ef"

    blueprint =
      golden_blueprint(
        input_ports: [BlueprintFixture.port(long_in)],
        output_ports: [BlueprintFixture.port("result"), BlueprintFixture.port(long_out)]
      )

    deployment = golden_deployment(blueprint: blueprint)

    assert {:ok, %Evidence{}} = Reconcile.reconcile(blueprint, deployment, inputs())
  end

  test "raw-key entropy in an identifier position denies at portability (exempting mode)" do
    # The strict complement of the kebab green test: scan_identifier still
    # denies raw-key entropy (43+ separator-bearing b64url chars) — the
    # identifier positions keep the EXEMPTION, not immunity.
    raw_key = String.duplicate("AbC", 15) <> "xY"

    {:object, ms} =
      BlueprintFixture.fixture_value(input_ports: [BlueprintFixture.port(raw_key)])

    with_key = BlueprintFixture.with_digest(ms)
    forged_blueprint = %Blueprint{value: with_key}
    deployment = golden_deployment(blueprint: forged_blueprint)

    assert {:error, %Error{code: :forbidden_portable_value, subject: ["blueprint"]}} =
             Reconcile.reconcile(forged_blueprint, deployment, inputs())
  end

  test "a denied member name inside a predicate operand denies at portability (authored scan)" do
    # Predicate operands are arbitrary authored JSON — names denylisted at
    # the authored scan, not keyword-checked by the registry, so this value
    # passes structure and must deny at the portability stage.
    operand = {:object, [{"tenant_id", {:string, "x"}}]}

    predicate =
      {:object,
       [
         {"op", {:string, "eq"}},
         {"path", BlueprintFixture.path(["request"])},
         {"value", operand}
       ]}

    {:object, ms} =
      BlueprintFixture.fixture_value(
        assertions: [
          BlueprintFixture.assertion(kind: "deterministic_predicate", predicate: predicate)
        ]
      )

    with_name = BlueprintFixture.with_digest(ms)
    forged_blueprint = %Blueprint{value: with_name}

    # The deployment binds the forged blueprint's honest recomputed digest
    # (portability is the only stage that denies this value).
    deployment = golden_deployment(blueprint: forged_blueprint)

    assert {:error, %Error{code: :forbidden_portable_value, subject: ["blueprint"]}} =
             Reconcile.reconcile(forged_blueprint, deployment, inputs())
  end

  test "signatures checks carry the entry count as detail" do
    assert {:ok, %Evidence{checks: checks}} =
             Reconcile.reconcile(golden_blueprint(), golden_deployment(), inputs())

    unsigned = Enum.filter(checks, &(&1.surface == :signatures))
    assert Enum.all?(unsigned, &(&1.detail == "no signatures present"))

    assert {:ok, %Evidence{checks: signed_checks}} =
             Reconcile.reconcile(
               signed_blueprint(),
               signed_deployment(),
               inputs(keys: verifiable_keys())
             )

    signed = Enum.filter(signed_checks, &(&1.surface == :signatures))
    assert Enum.all?(signed, &(&1.detail == "1 signature(s) verified"))
  end

  test "a namespace retained by both artifacts appears once in the retained list" do
    ns = "com.example.commerce/classification-labels"
    body = {:object, [{"labels", {:array, [{:string, "pci"}]}}]}

    blueprint =
      golden_blueprint(extensions: BlueprintFixture.extensions(optional: %{ns => body}))

    deployment =
      golden_deployment(
        blueprint: blueprint,
        extensions: DeploymentFixture.extensions(optional: %{ns => body})
      )

    assert {:ok, %Evidence{optional_extensions_retained: retained}} =
             Reconcile.reconcile(blueprint, deployment, inputs())

    assert retained == [ns]
  end

  # ---- facts: quarantine, retention, clamps -----------------------------------------

  test "a quarantined optional extension lands as a verified-false extension check" do
    blueprint =
      golden_blueprint(
        extensions:
          BlueprintFixture.extensions(
            optional: %{"com.unknown/thing" => {:object, [{"x", {:integer, 1}}]}}
          )
      )

    deployment = golden_deployment(blueprint: blueprint)

    assert {:ok, %Evidence{checks: checks}} =
             Reconcile.reconcile(blueprint, deployment, inputs())

    assert %{surface: :extensions, subject: ["com.unknown/thing"], verified: false, detail: nil} in checks
  end

  test "an operational narrowing lands as clamp evidence plus a per-bound bounds check" do
    host = host_bounds() |> narrow_to(:max_tokens, 50_000)

    assert {:ok, %Evidence{clamps: [clamp], effective_bounds: effective} = evidence} =
             Reconcile.reconcile(
               golden_blueprint(),
               golden_deployment(),
               inputs(host_bounds: host)
             )

    assert %ClampEvidence{
             field: :max_tokens,
             class: :operational,
             requested: 100_000,
             effective: 50_000,
             source: :host,
             acknowledged: false
           } = clamp

    assert {:ok, %BoundsAlgebra.Bound{value: 50_000}} = BoundSet.fetch(effective, :max_tokens)

    assert Enum.find(evidence.checks, &(&1.subject == ["max_tokens"])) == %{
             surface: :bounds,
             subject: ["max_tokens"],
             verified: true,
             detail: clamp
           }
  end

  # ---- rim probes -------------------------------------------------------------------

  test "rim: non-struct arguments deny typed naming their position" do
    assert {:error, %Error{code: :invalid_type, subject: ["blueprint"]}} =
             Reconcile.reconcile(:junk, golden_deployment(), inputs())

    assert {:error, %Error{code: :invalid_type, subject: ["deployment"]}} =
             Reconcile.reconcile(golden_blueprint(), :junk, inputs())

    assert {:error, %Error{code: :invalid_type, subject: ["inputs"]}} =
             Reconcile.reconcile(golden_blueprint(), golden_deployment(), :junk)
  end

  test "rim: malformed inputs fields deny typed with their member path" do
    for {forged, subject} <- [
          {%{inputs() | support: :junk}, ["inputs", "support"]},
          {%{inputs() | observations: :junk}, ["inputs", "observations"]},
          {%{inputs() | keys: :junk}, ["inputs", "keys"]},
          {%{inputs() | keys: [:junk]}, ["inputs", "keys", 0]},
          {%{inputs() | protected_clamp: :silent}, ["inputs", "protected_clamp"]},
          {%{inputs() | host_bounds: :junk}, ["inputs", "host_bounds"]}
        ] do
      assert {:error, %Error{code: :invalid_type, subject: ^subject}} =
               Reconcile.reconcile(golden_blueprint(), golden_deployment(), forged),
             "expected typed denial for #{inspect(subject)}"
    end
  end

  # ---- helpers: seeded-key signatures -------------------------------------------------

  defp verifiable_keys,
    do: [%PublicKey{key_id: "reconcile-test-key", algorithm: :ed25519, key: pub()}]

  defp pub, do: elem(:crypto.generate_key(:eddsa, :ed25519, @seed), 0)
  defp priv, do: elem(:crypto.generate_key(:eddsa, :ed25519, @seed), 1)

  # Parseable but wrong: flip the last byte of the 64-byte signature.
  defp tamper_if(<<sig::binary-size(63), last>>, true),
    do: <<sig::binary, Bitwise.bxor(last, 0xFF)>>

  defp tamper_if(sig, _false), do: sig

  defp signed_entry(digest_tagged, opts) do
    header =
      {:object,
       [
         {"alg", {:string, "EdDSA"}},
         {"b64", {:boolean, false}},
         {"crit", {:array, [{:string, "b64"}]}},
         {"kid", {:string, "reconcile-test-key"}}
       ]}

    attrs =
      {:object,
       [
         {"algorithm", {:string, "Ed25519"}},
         {"content_digest", {:string, digest_tagged}},
         {"created_at", {:string, "2026-08-20T00:00:00Z"}},
         {"key_id", {:string, "reconcile-test-key"}},
         {"purpose", {:string, Keyword.get(opts, :purpose, "deployment")}}
       ]}

    {:ok, h} = AgentBlueprintProtocol.Canonicalization.encode(header)
    {:ok, a} = AgentBlueprintProtocol.Canonicalization.encode(attrs)
    signing_input = AgentBlueprintProtocol.Base64Url.encode(h) <> "." <> a

    sig =
      :crypto.sign(:eddsa, :none, signing_input, [priv(), :ed25519])
      |> tamper_if(opts[:forged_signature])
      |> AgentBlueprintProtocol.Base64Url.encode()

    {:object,
     [{"protected", header}, {"signed_attributes", attrs}, {"signature", {:string, sig}}]}
  end

  defp signed_deployment(opts \\ []) do
    base = DeploymentFixture.fixture_value(Keyword.merge([host_bounds: wide_host_bounds()], opts))
    {:ok, dep} = Deployment.from_value(base)

    digest =
      if opts[:foreign_digest] do
        DeploymentFixture.tagged("foreign")
      else
        dep |> Deployment.content_digest() |> Digest.to_tagged()
      end

    entry =
      signed_entry(digest,
        purpose: "deployment",
        forged_signature: Keyword.get(opts, :forged_signature, false)
      )

    {:object, ms} = base

    with_sig =
      Enum.sort([
        {"signatures", {:array, [entry]}} | Enum.reject(ms, fn {n, _} -> n == "signatures" end)
      ])

    {:ok, signed} = Deployment.from_value({:object, with_sig})
    signed
  end

  defp signed_blueprint(opts \\ []) do
    base = BlueprintFixture.fixture_value(opts)
    {:ok, bp} = Blueprint.from_value(base)

    digest =
      if opts[:foreign_digest] do
        DeploymentFixture.tagged("foreign")
      else
        bp |> Blueprint.content_digest() |> Digest.to_tagged()
      end

    entry = signed_entry(digest, purpose: "blueprint")

    {:object, ms} = base

    with_sig =
      Enum.sort([
        {"signatures", {:array, [entry]}} | Enum.reject(ms, fn {n, _} -> n == "signatures" end)
      ])

    {:ok, signed} = Blueprint.from_value({:object, with_sig})
    signed
  end

  defp narrow_to(%BoundSet{} = set, name, value) do
    {:ok, map} = BoundSet.to_map(set)
    {:ok, narrowed} = BoundSet.new(Map.put(map, name, value))
    narrowed
  end
end
