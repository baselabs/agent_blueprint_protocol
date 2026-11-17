import { mkdtempSync,writeFileSync,readFileSync,rmSync } from 'node:fs';
import { join,resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { npmCli } from './npm.mjs';

const npm=npmCli();
function run(scratch,args){
  const result=spawnSync(process.execPath,args,{cwd:scratch,encoding:'utf8',maxBuffer:10_000_000});
  assert.equal(result.status,0,result.stderr);
  return result.stdout;
}
function install(scratch,specifier){
  writeFileSync(join(scratch,'package.json'),'{"private":true,"type":"module"}');
  run(scratch,[npm,'install','--ignore-scripts','--no-audit','--no-fund',specifier]);
  return join(scratch,'node_modules/@agent-blueprint-protocol/verifier');
}

if(process.argv[2]==='--local'){
  // The Elixir consumer driver owns this directory and removes it after replay.
  install(resolve(process.argv[4]),resolve(process.argv[3]));
}else{
  const version=process.argv[2];
  assert.match(version,/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/);
  const scratch=mkdtempSync(join(tmpdir(),'abp-published-'));
  try{
    const pkg=install(scratch,'@agent-blueprint-protocol/verifier@'+version);
    assert.equal(JSON.parse(readFileSync(join(pkg,'package.json'))).version,version);
    const cli=join(pkg,'dist/kit/cli.mjs'),corpus=join(pkg,'dist/corpus');
    const report=JSON.parse(run(scratch,[cli]));
    assert.equal(report.agreement,true);
    const results=join(scratch,'results.json');
    run(scratch,[cli,'conformance','run','--corpus',corpus,'--results',results,'--',process.execPath,cli,'--serve','--corpus',corpus]);
    assert.deepEqual(readFileSync(results),readFileSync(join(pkg,'dist/spec/conformance/certified-results.json')));
    console.log('published package: '+version+' corpus and certified results agree');
  }finally{rmSync(scratch,{recursive:true,force:true});}
}
