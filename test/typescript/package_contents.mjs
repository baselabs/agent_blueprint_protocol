import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { verifyPackageContents } from '@agent-blueprint-protocol/verifier';

const contents = mkdtempSync(join(tmpdir(), 'abp-package-contents-'));
try {
  const hex = 'sha-256:-N1GvPYuKnv6Br--iACuSSCvmVojkp5MQGObQb0b41w';
  const npm = 'sha-256:4M6Z06tLFrxM9rwwrYtoAhLPVXNtiSP3dKOmebaG0yY';
  mkdirSync(join(contents, 'nested'));
  for (const [path, bytes] of [
    ['.sample', Buffer.from([0, 255])], ['nested/z', 'abc'], ['nested/中', ''],
    ['nested/𐀀', 'd'], ['nested/\uE000', 'e'],
  ]) writeFileSync(join(contents, path), bytes);

  assert.equal(verifyPackageContents(contents, 'hex', hex).ok, true);
  assert.equal(verifyPackageContents(contents, 'npm', npm).ok, true);
  const denial = (code, kind = 'npm') => ({ok: false, error: {code, subject: ['package_checksums', kind]}});
  assert.deepEqual(verifyPackageContents(contents, 'npm', hex), denial('digest_mismatch'));

  mkdirSync(join(contents, 'dist'));
  for (const name of ['release-metadata.json', 'release-history.json']) {
    writeFileSync(join(contents, 'dist', name), 'record');
  }
  assert.equal(verifyPackageContents(contents, 'npm', npm).ok, true);
  assert.deepEqual(verifyPackageContents(contents, 'hex', hex), denial('digest_mismatch', 'hex'));
  assert.deepEqual(verifyPackageContents(contents, 'npm', npm + '\n'), denial('digest_encoding_invalid'));
  assert.deepEqual(verifyPackageContents(join(contents, 'missing'), 'npm', npm), denial('invalid_constraint'));

  const file = join(contents, 'nested/z');
  writeFileSync(file, 'abd');
  assert.deepEqual(verifyPackageContents(contents, 'npm', npm), denial('digest_mismatch'));
  rmSync(file);
  assert.deepEqual(verifyPackageContents(contents, 'npm', npm), denial('digest_mismatch'));
  writeFileSync(file, 'abc');
  writeFileSync(join(contents, '.extra'), '');
  assert.deepEqual(verifyPackageContents(contents, 'npm', npm), denial('digest_mismatch'));
  rmSync(join(contents, '.extra'));
  if (process.platform !== 'win32') {
    symlinkSync(file, join(contents, 'linked'));
    assert.deepEqual(verifyPackageContents(contents, 'npm', npm), denial('invalid_constraint'));
  }
} finally {
  rmSync(contents, {recursive:true, force:true});
}
