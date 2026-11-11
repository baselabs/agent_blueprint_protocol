defmodule AgentBlueprintProtocol.VerificationContractTest do
  use ExUnit.Case, async: true

  alias AgentBlueprintProtocol.{
    Base64Url,
    Blueprint,
    BlueprintFixture,
    Bounds,
    Canonicalization,
    Deployment,
    DeploymentFixture,
    Digest,
    Error,
    Signature
  }

  alias AgentBlueprintProtocol.Signature.{Attributes, PublicKey}

  test "byte helpers return structured failures and decoder ceilings" do
    {public_a, _} = BlueprintFixture.signing_keypair()
    {public_b, _} = BlueprintFixture.signing_keypair()
    assert Digest.equal?(Digest.of(public_a), Digest.of(public_b))

    assert {:error, %Error{code: :invalid_type}} = Digest.of(:invalid)
    assert {:error, %Error{code: :invalid_type}} = Digest.hash(:unknown, "bytes")
    assert {:error, %Error{code: :invalid_type}} = Digest.to_tagged(:invalid)
    assert {:error, %Error{code: :base64url_padded}} = Base64Url.decode("QQ=")

    assert {:error, %Error{code: {:ceiling, :bytes}}} =
             Canonicalization.verify("null", %{bytes: 1})

    assert {:error, %Error{code: {:ceiling, :depth}}} = Bounds.new(%{depth: 0})
  end

  test "artifact negotiation attributes malformed support to support" do
    for artifact <- [%Blueprint{}, %Deployment{}, {:object, []}] do
      assert {:error, %Error{code: :invalid_type, subject: ["support"]}} =
               AgentBlueprintProtocol.negotiate(artifact, nil)
    end
  end

  test "signature verification returns attributes for both registered identifiers" do
    {public, private} = BlueprintFixture.signing_keypair()

    for alg <- ["EdDSA", "Ed25519"] do
      header =
        {:object,
         [
           {"alg", {:string, alg}},
           {"b64", {:boolean, false}},
           {"crit", {:array, [{:string, "b64"}]}},
           {"kid", {:string, "example-signing-key"}}
         ]}

      attrs = BlueprintFixture.signature_attrs(key_id: "example-signing-key")

      shell =
        BlueprintFixture.signature_entry(header: header, attrs: attrs, signature: {:string, "AA"})

      {:object, members} = shell
      {:ok, h} = Canonicalization.encode(header)
      {:ok, a} = Canonicalization.encode(attrs)

      signature =
        :crypto.sign(:eddsa, :none, Base64Url.encode(h) <> "." <> a, [private, :ed25519])

      entry =
        {:object,
         List.keyreplace(
           members,
           "signature",
           0,
           {"signature", {:string, Base64Url.encode(signature)}}
         )}

      assert {:ok, %Attributes{key_id: "example-signing-key", purpose: :blueprint} = verified} =
               Signature.verify(entry, [
                 %PublicKey{key_id: "example-signing-key", algorithm: :ed25519, key: public}
               ])

      assert {:ok, ^verified} = Signature.attributes(entry)
    end
  end

  test "artifact structure denies duplicate signer identities" do
    entry = BlueprintFixture.signature_entry()

    assert {:error, %Error{code: :invalid_constraint, subject: ["signatures"]}} =
             Blueprint.from_value(BlueprintFixture.with_signatures(signatures: [entry, entry]))

    entry = DeploymentFixture.signature_entry()

    assert {:error, %Error{code: :invalid_constraint, subject: ["signatures"]}} =
             Deployment.from_value(DeploymentFixture.with_signatures(signatures: [entry, entry]))
  end

  test "signer uniqueness tolerates malformed hand-built entries until their shape denial" do
    for {artifact, fixture} <- [{Blueprint, BlueprintFixture}, {Deployment, DeploymentFixture}],
        entry <- [{:object, nil}, {:object, [{"signed_attributes", {:object, nil}}]}] do
      value = fixture.fixture_value(extra_members: [{"signatures", {:array, [entry]}}])

      assert {:error, %Error{code: :invalid_type}} =
               AgentBlueprintProtocol.Registry.validate(artifact.table(), value)
    end
  end

  test "unsigned imports and skipped observations are explicitly unverified" do
    {:ok, blueprint} = Blueprint.from_value(BlueprintFixture.fixture_value())
    {:object, bounds} = DeploymentFixture.host_bounds()

    bounds =
      {:object,
       List.keyreplace(bounds, "disclosure_ceiling", 0, {"disclosure_ceiling", {:string, "full"}})}

    {:ok, deployment} =
      Deployment.from_value(
        DeploymentFixture.fixture_value(blueprint: blueprint, host_bounds: bounds)
      )

    {:ok, host_bounds} = AgentBlueprintProtocol.BoundsAlgebra.from_deployment(deployment)

    inputs = %AgentBlueprintProtocol.Reconcile.Inputs{
      host_bounds: host_bounds,
      support: %AgentBlueprintProtocol.Negotiation.Support{revisions: MapSet.new([1])},
      keys: [],
      protected_clamp: :deny,
      observations: %Deployment.Observations{}
    }

    assert {:ok, evidence} = AgentBlueprintProtocol.reconcile(blueprint, deployment, inputs)

    assert Enum.all?(
             Enum.filter(evidence.checks, &(&1.surface == :signatures)),
             &(&1.verified == false and &1.detail == :no_signatures_present)
           )

    assert %{verified: false} = Enum.find(evidence.checks, &(&1.surface == :bind))

    for surface <- [
          :signatures,
          :binding_staleness,
          :binding_descriptors,
          :signature_created_at,
          :lifecycle_state
        ] do
      assert surface in evidence.not_verified
    end
  end

  test "evidence details are typed and schema numeric limits remain reachable" do
    assert {:error, %Error{code: :invalid_type}} =
             AgentBlueprintProtocol.Evidence.build(
               checks: [%{surface: :signatures, subject: [], verified: true, detail: "unchecked"}]
             )

    for detail <- [
          :no_signatures_present,
          :retained,
          :quarantined,
          %AgentBlueprintProtocol.Evidence.Signatures{key_ids: []},
          %AgentBlueprintProtocol.Evidence.Signatures{key_ids: ["example-key", "example-key"]},
          %AgentBlueprintProtocol.Evidence.Signatures{key_ids: [:invalid]},
          %AgentBlueprintProtocol.Evidence.Binding{checked: [], not_verified: []},
          %AgentBlueprintProtocol.Evidence.Binding{
            checked: [:release_binding],
            not_verified: [:binding_staleness]
          }
        ] do
      assert {:error, %Error{code: :invalid_type}} =
               AgentBlueprintProtocol.Evidence.build(
                 checks: [%{surface: :bind, subject: [], verified: true, detail: detail}]
               )
    end

    assert {:ok, _} =
             AgentBlueprintProtocol.Evidence.build(
               checks: [
                 %{
                   surface: :bind,
                   subject: [],
                   verified: true,
                   detail: %AgentBlueprintProtocol.Evidence.Binding{
                     checked: [:release_binding],
                     not_verified: []
                   }
                 }
               ]
             )

    assert {:error, %Error{code: :invalid_constraint}} =
             AgentBlueprintProtocol.Schema.validate_instance(
               {:object, [{"minimum", {:integer, 2}}]},
               {:float, 1.5},
               AgentBlueprintProtocol.Schema.dialect()
             )
  end
end
