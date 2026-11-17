import {mkdtempSync,rmSync,existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';

const scratch=mkdtempSync(join(tmpdir(),'abp-adapter-startup-'));
try {
  for(const [label,program] of [['missing',join(scratch,'absent')],['unstartable',scratch]]) {
    const results=join(scratch,label+'.json');
    const run=spawnSync(process.execPath,['dist/kit/cli.mjs','conformance','run','--corpus','priv/conformance','--results',results,'--timeout-ms','1000','--',program],{encoding:'utf8',timeout:5000});
    assert.equal(run.status,18,label+' adapter must retain the early_exit contract');
    assert.match(run.stderr,/harness: early_exit: adapter could not be started \([A-Z0-9_]+\)/,label+' adapter must name its startup failure');
    assert.equal(existsSync(results),false,'startup failure must not write results');
  }
  console.log('harness startup: missing and unstartable adapters named; exit 18; no results written');
} finally {rmSync(scratch,{recursive:true,force:true});}
