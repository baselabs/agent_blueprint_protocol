# Procedure identity for hosts

A procedure declaration commits to the execution-affecting instances and their
relationships. Carry it in the Deployment Manifest's critical
`io.github.baselabs/procedure` extension. Keep `protocol_revision` at 1.
The protocol supplies identity forms and verification rules; your host supplies
the complete role vocabulary and profiles for every procedure it serves.

The registry defines this payload for Deployment Manifests only. Blueprint
payloads in either extension region deny `extension_payload_forbidden` during
negotiation before lifecycle or criticality checks. Its subject is
`["extensions"]`, prefixed with `"blueprint"` during reconcile.

Use `AgentBlueprintProtocol.Procedure.schema/0` (TypeScript `procedureSchema()`)
in negotiation support. Construct the critical body through the existing
`Deployment.from_value/2` `authored_extensions` path. This namespace always
receives the strict portability scan, including when it was authored or its
schema was validated. Recompute and sign the completed Deployment digest.

## Profiles and instances

Inline the complete immutable profile. Accept its plain SHA-256 over JCS digest
in your host policy, rather than trusting its `profile_id`. Changing a role,
schema, evidence requirement or relationship then changes the profile and the
Deployment identity, even if the id stays the same. ABP ships no profiles.

Each declared instance has a unique id, a role, an identity and provenance.
Allowed forms are artifact, build, configuration, service and environment.
Build references name existing revision 1 build entries. Service enrollment
and contract are separate commitments: a release change alters enrollment,
while an unchanged contract keeps the same commitment. Include `published`
only for a digest published by the operator.

Provenance records its basis, optional evidence digest, principal key digest or
principal enrollment commitment, and optional durable validity statement.
These members affect procedure identity. Validity is reported without a clock
comparison. The host judges it, just as it judges signature validity periods.

## Typed, salted host documents

Keep names, endpoints and concrete implementation settings in your host store.
A committed document has a `type` and a fresh 256-bit `nonce`. The nonce is
lowercase hexadecimal (64 characters) or canonical unpadded base64url (43
characters). Use a cryptographic random source and retain the nonce for returned
observations. Separate types are `agent-blueprint-protocol/procedure-configuration`,
`agent-blueprint-protocol/procedure-enrollment`,
`agent-blueprint-protocol/procedure-contract`,
`agent-blueprint-protocol/procedure-environment` and
`agent-blueprint-protocol/procedure-principal-enrollment`.
A contract document describes a service's interface, and an enrollment document records a principal's or a service's enrollment with the host; neither is an agreement between parties, and ABP evaluates neither.

The commitment helper requires tagged JSON and returns SHA-256 over JCS:

```elixir
alias AgentBlueprintProtocol.{Json, Procedure}
{:ok, document} = Json.decode(~s({"type":"agent-blueprint-protocol/procedure-configuration","nonce":"0000000000000000000000000000000000000000000000000000000000000000","revision":1}))
{:ok, digest} = Procedure.document_commitment(document)
true = String.starts_with?(digest, "sha-256:")
{:object, _} = Procedure.schema()
```

The all-zero nonce above is a deterministic example; producers generate their
own fresh nonce. Store documents keyed by their recomputed commitment, and pass
the tagged documents in `Procedure.Inputs.documents`.

After local `$ref` resolution, a configuration schema root must have
`type: object`, `additionalProperties: false`, and every property in `required`.
Configuration schemas require every object member explicitly, including
nullable members. Close each object with `additionalProperties: false`.
Represent decimals as bounded fixed-scale integers. The dialect has no
`pattern` keyword. Put digest and instance references in instance `binds`
relations, rather than strings inside documents. `exact` identifies version
members that must satisfy `Compatibility.exact?/1`. A document that fails its
schema or exactness denies `invalid_constraint` with a document subject.
Missing or incorrectly keyed documents deny `binding_incomplete`.

## Inventory and import points

Build one execution-scoped inventory for every attempt. Its string-keyed map
contains `builds`, `instances`
(the observed procedure records), `manifest_digest` and `attempt`.
Each Elixir build entry is a map with exactly the atom keys `:kind`, `:name`,
`:version` and `:digest`, all binary values. TypeScript uses the string members
`kind`, `name`, `version` and `digest`, all strings. Inventory member names
remain strings in both runtimes. For example:

```elixir
alias AgentBlueprintProtocol.{Compatibility, Deployment, Json}
bytes = File.read!(Application.app_dir(:agent_blueprint_protocol, "priv/examples/echo-deployment.json"))
{:ok, deployment} = Deployment.decode(bytes)
{:ok, {:object, members}} = Json.decode(bytes)
{"build_identities", {:array, entries}} = List.keyfind(members, "build_identities", 0)
builds = Enum.map(entries, fn {:object, pairs} ->
  read = fn key -> {^key, {:string, value}} = List.keyfind(pairs, key, 0); value end
  %{kind: read.("kind"), name: read.("name"), version: read.("version"), digest: read.("digest")}
end)
{:ok, _} = Compatibility.verify(deployment, %Compatibility.Observed{identities: builds})
{:ok, _} = Json.decode(bytes)
```
An observation pairs by instance id, and its identity, provenance and relations
must equal the declaration. Missing, extra and ambiguous observations deny
`binding_incomplete`, including an extra instance under an allowed role.
Covered instances remain attributed through `part_of` and compared transitively;
coverage never exempts an instance from declaration or comparison.

Supply `%Procedure.Inputs{}` with `inventory`, `documents`, `children`,
`accepted_profiles`, `attempt`, `execution_boundary` and `import_point`.
`Procedure.verify/2` is the per-attempt import stage. A denial halts that import.
Pass the same inputs in `Reconcile.Inputs.procedure`; reconcile requires them
when the namespace is critical and runs this stage during binding.
TypeScript uses `verifyProcedure(deployment, inputs)` and `Inputs.procedure`;
its document values are ordinary JSON and its children are Deployment views or
canonical Deployment strings.

Set `import_point` to `:before_send` immediately before sending, using observations from
the selected execution boundary. Set it to `:returned` when importing the
returned run. Rebuild each document from the run's reported values, retaining
the original nonce, and recollect the observations. Bind both inventories to
their actual attempt and Deployment. An inventory copied from another attempt
does not satisfy the binding. The host prevents or detects changes between
measurement and use; ABP reports measurement freshness as unverified.

## Composition and evidence

Construct child manifests first, then ordered composition members referring to
their completed Deployment digests. Supply at most 255 children, 1,024 documents and 256 accepted profile digests.
These host-input limits deny `invalid_type`; unreferenced children are ignored.
Supply each referenced child as canonical
Deployment bytes or a decoded Deployment. Shared children are allowed. The
closure is at most 256 manifests, depth at most 8 including the root, and each
composition has at most 64 members. Every child verifies its own Deployment
digest and conforms to an accepted member profile. Import each member attempt
against its actual member manifest and retain the root as execution provenance.

Evidence records the profile digest, attempt, execution boundary and import point,
per-instance basis and assurance, validity statements, and child digests. It
contains no host-document contents. Identity validity, observer trust,
measurement freshness, evidence authenticity, holder assertion truth,
configuration execution and service implementation remain `not_verified`.
This evidence does not authorize execution or establish those host-owned facts.
