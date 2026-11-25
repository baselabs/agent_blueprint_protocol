import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [manifestPath, hex, npm] = process.argv.slice(2);
const { package_checksums: checksums } = JSON.parse(readFileSync(manifestPath, 'utf8'));
const { verifyPackageContents } = await import(pathToFileURL(join(npm, 'dist/verifier/index.js')).href);

for (const [distribution, root] of [['hex', hex], ['npm', npm]]) {
  const checksum = checksums[distribution];
  assert.deepEqual(verifyPackageContents(root, distribution, checksum), {ok: true, value: true});

  const path = join(root, 'README.md');
  const original = readFileSync(path);
  const changed = Buffer.from(original);
  changed[0] ^= 1;
  try {
    writeFileSync(path, changed);
    assert.deepEqual(verifyPackageContents(root, distribution, checksum), {
      ok: false, error: {code: 'digest_mismatch', subject: ['package_checksums', distribution]},
    });
  } finally {
    writeFileSync(path, original);
  }
}

console.log('package contents: both archived checksums agree with the installed verifier');
