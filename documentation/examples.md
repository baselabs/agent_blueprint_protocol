# The examples gallery

Complete, corpus-verified artifact pairs under `examples/` — every
example is a byte-exact conformance corpus case (the gallery gate
proves it against the corpus on every build; a drifted example reds).

## echo (blueprint + deployment)

The minimal valid pair: `echo-blueprint.json` + `echo-deployment.json`.

### The blueprint, member by member

- `blueprint_id` (`example.demo/echo`) — the producer-qualified
  identity: producer `example.demo`, capability `echo`.
- `capability_requirements` — one requirement: operation family
  `example.demo.read_shape`, kind `read`, impact `ordinary`,
  classification ceiling `internal`, authority and approval traits
  `none`, with argument and result schemas.
- `ceilings` — all eight operational bounds present, none absent
  (absent is an error, never infinity).
- `input_ports` / `output_ports` / `output_contract` — the typed
  surface: a `request` port in, a `result` port out, ceiling `internal`.
- `classification_ceiling` (`internal`) — the artifact-wide
  disclosure ceiling.
- `effect_intents` — one declared effect: `record_summary`, kind
  `mutation`, impact `ordinary`. This is the effect the deployment's
  `effect_owner` binding exists to own.
- `evaluation_assertions` — an output-schema assertion on the `result`
  port.
- `triggers` (`["manual"]`) — how execution starts.
- `producer` — identity, Z-form timestamp, toolchain.
- `protocol_revision` (1), `release_number` (1) — the revision line.
- `extensions` (`{"critical":{},"optional":{}}`) — the empty envelope.
- `required_core_fields` (`[]`) — no extra requirements declared.
- `content_digest` — the release identity over the digest-covered
  members.

### The deployment, member by member

- `protocol_revision` (1) — the revision line, digest-covered.
- `blueprint_release` — the exact binding: the echo blueprint's id,
  release, and content digest. Digest equality only.
- `scope_projection` — the adapter the deployment projects onto.
- `tool_bindings` — the read_shape operation bound to an adapter with
  descriptor and schema digests (rug-pull guards).
- `data_bindings` — the `shape_orders` dataset, classification
  `internal`, freshness `required` within 24h.
- `authority_requirement` / `effect_owner` — the authority profile and
  the effect-owning adapter with host-derived idempotency and
  authoritative recovery.
- `signer_custody` (`host_managed`), `eligibility` (predicate
  expressions), `model_policy`, `host_bounds`, `lifecycle`
  (`active`), `build_identities` (exact version + digest per input),
  `evaluation_binding` (the evaluation corpus by digest),
  `extensions`, `required_core_fields`, `deployment_digest`.

## Verify the pair

The examples ARE corpus cases — digests and all — which is what makes
them honest: what you read is what the corpus executes. The corpus
(including these bytes) verifies on every package build; the
standalone kit attached to each git release tag re-runs it against the
shipped archive.
