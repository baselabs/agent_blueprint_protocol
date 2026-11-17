import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { flattenedVerify, importJWK } from 'jose';
import { encode } from '../../verifier/canonical.ts';
import { tagged } from '../../verifier/plain.ts';
import { verify } from '../../verifier/signature.ts';

const { cases } = JSON.parse(readFileSync('priv/conformance/cases/signature-verify.json', 'utf8'));
function canonical(value) {
  const result = encode(tagged(value));
  assert.equal(result.ok, true);
  return result.v;
}

for (const [id, alg] of [['signature-algorithm-eddsa', 'EdDSA'], ['signature-algorithm-ed25519', 'Ed25519']]) {
  test(`stock jose verifies the signed corpus fixture with ${alg} and an unencoded detached payload`, async () => {
    const row = cases.find(row => row.id === id);
    assert.ok(row);
    const entry = JSON.parse(row.input.entry);
    assert.deepEqual(entry.protected, { alg, b64: false, crit: ['b64'], kid: entry.signed_attributes.key_id });
    const key = await importJWK({ kty: 'OKP', crv: 'Ed25519', x: row.input.keys[0].key }, alg);
    const payload = canonical(entry.signed_attributes);
    // Reattach the detached JCS payload without encoding it, as RFC 7797 requires.
    const result = await flattenedVerify({
      protected: Buffer.from(canonical(entry.protected)).toString('base64url'),
      payload,
      signature: entry.signature,
    }, key, { algorithms: [alg] });
    assert.equal(new TextDecoder().decode(result.payload), payload);
    assert.equal(result.protectedHeader.alg, alg);
    assert.equal(verify(tagged(entry), row.input.keys.map(key => ({
      keyId: key.key_id, key: Buffer.from(key.key, 'base64url'),
    }))).ok, true);

    await assert.rejects(flattenedVerify({
      protected: Buffer.from(canonical(entry.protected)).toString('base64url'),
      payload: payload.replace('2026', '2025'),
      signature: entry.signature,
    }, key, { algorithms: [alg] }), { code: 'ERR_JWS_SIGNATURE_VERIFICATION_FAILED' });
  });
}

test('every other algorithm string denies signature_algorithm_unsupported', () => {
  const row = cases.find(row => row.id === 'signature-algorithm-ed25519');
  for (const alg of ['', 'none', 'Ed448', 'eddsa', 'ed25519', 'ED25519', 'EdDSA ', ' Ed25519', 'HS256', 'ES256', 'RS256', '__proto__', 'constructor', 'unknown']) {
    const entry = JSON.parse(row.input.entry);
    entry.protected.alg = alg;
    assert.deepEqual(verify(tagged(entry), []), {
      ok: false, e: 'signature_algorithm_unsupported', subject: ['protected'],
    });
  }
});
