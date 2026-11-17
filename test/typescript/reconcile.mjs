import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { KNOWN_EVIDENCE_SURFACES, reconcile, decodeBlueprint, decodeDeployment } from '../../verifier/facade.ts';

test('reconcile reports all three host-owned time facts in the declared order', () => {
  const { cases } = JSON.parse(readFileSync('priv/conformance/cases/reconcile.json', 'utf8'));
  const row = cases.find(row => row.id === 'reconcile-unsigned');
  const blueprint = decodeBlueprint(row.input.blueprint);
  const deployment = decodeDeployment(row.input.deployment);
  assert.equal(blueprint.ok, true);
  assert.equal(deployment.ok, true);
  const host = row.input.inputs;
  const result = reconcile(blueprint.value, deployment.value, {
    hostBounds: host.host_bounds, support: { revisions: new Set([1]), coreFields: new Set(), registry: {}, schemas: {} }, keys: [],
    protectedClamp: host.protected_clamp,
    observations: { now: null, maxAttestationAgeMs: null, observed: {} },
  });
  assert.equal(result.ok, true);
  assert.deepEqual(result.value.not_verified.slice(0, 10), [
    'tenancy', 'live_policy', 'authority', 'effect_ownership', 'execution', 'billing',
    'evaluation_truth', 'signature_created_at', 'lifecycle_state', 'signature_time_validity',
  ]);
  assert.equal(KNOWN_EVIDENCE_SURFACES.signature_time_validity, 'signature_time_validity');
});
