import { mkdtempSync,writeFileSync,readFileSync,rmSync,existsSync } from 'node:fs';
import { join,dirname,resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
const version=process.argv[2];assert.match(version,/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/);
const npm=[join(dirname(process.execPath),'node_modules/npm/bin/npm-cli.js'),resolve(dirname(process.execPath),'../lib/node_modules/npm/bin/npm-cli.js')].find(existsSync);assert.ok(npm);
const scratch=mkdtempSync(join(tmpdir(),'abp-published-'));
function run(args){const r=spawnSync(process.execPath,args,{cwd:scratch,encoding:'utf8',maxBuffer:10_000_000});assert.equal(r.status,0,r.stderr);return r.stdout;}
try{
  writeFileSync(join(scratch,'package.json'),'{"private":true,"type":"module"}');
  run([npm,'install','--ignore-scripts','--no-audit','--no-fund','@agent-blueprint-protocol/verifier@'+version]);
  const pkg=join(scratch,'node_modules/@agent-blueprint-protocol/verifier');
  assert.equal(JSON.parse(readFileSync(join(pkg,'package.json'))).version,version);
  const cli=join(pkg,'dist/kit/cli.mjs'),corpus=join(pkg,'dist/corpus');
  const report=JSON.parse(run([cli]));assert.equal(report.agreement,true);
  const results=join(scratch,'results.json');
  run([cli,'conformance','run','--corpus',corpus,'--results',results,'--',process.execPath,cli,'--serve','--corpus',corpus]);
  assert.deepEqual(readFileSync(results),readFileSync(join(pkg,'dist/spec/conformance/certified-results.json')));
  console.log('published package: '+version+' corpus and certified results agree');
}finally{rmSync(scratch,{recursive:true,force:true});}
