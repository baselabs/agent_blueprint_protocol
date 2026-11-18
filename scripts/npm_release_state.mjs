import {appendFileSync} from 'node:fs';
import {npmIntegrity} from './release_artifact_info.mjs';

// Read only the real public registry. Never print a registry response body.
const [mode, version, archive] = process.argv.slice(2);
if (!['plan', 'read-back'].includes(mode) || !/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(version ?? '') || !archive || process.argv.length !== 5) {
  throw new Error('usage: npm_release_state.mjs plan|read-back VERSION TGZ');
}
const output = process.env.GITHUB_OUTPUT;
if (mode === 'plan' && !output) throw new Error('GITHUB_OUTPUT is required');
const expected = npmIntegrity(archive);
const name = '@agent-blueprint-protocol/verifier';
async function state() {
  let response;
  try {
    response = await fetch(`https://registry.npmjs.org/@agent-blueprint-protocol%2fverifier/${encodeURIComponent(version)}`, {signal: AbortSignal.timeout(30_000)});
  } catch {
    throw new Error(`Could not read npm ${name} ${version}; publication refused`);
  }
  if (response.status === 404) return 'upload';
  if (response.status !== 200) throw new Error(`npm HTTP ${response.status}; unknown release state, publication refused`);
  let release;
  try { release = await response.json(); } catch { throw new Error('npm release metadata is unreadable; publication refused'); }
  if (release.version !== version || release.dist?.integrity !== expected) {
    throw new Error(`npm ${name} ${version}: served bytes differ; nothing was replaced`);
  }
  return 'served';
}
if (mode === 'plan') {
  const npm = await state();
  appendFileSync(output, `npm=${npm}\n`);
  console.log(`npm ${name} ${version}: ${npm}${npm === 'served' ? ' with these bytes; nothing will be uploaded' : ''}`);
} else {
  for (let attempt = 1; ; attempt++) {
    if (await state() === 'served') {
      console.log(`npm ${name} ${version} is served with the built bytes`);
      break;
    }
    if (attempt === 6) {
      throw new Error(`npm ${name} ${version} is not served yet: approve the staged version on npmjs.com, then dispatch Publish again on the same commit; the next run uploads only what is missing.`);
    }
    await new Promise(resolve => setTimeout(resolve, 10_000));
  }
}
