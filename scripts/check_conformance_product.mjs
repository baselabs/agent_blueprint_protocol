import { readFileSync,mkdtempSync,rmSync,cpSync,writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import {canonical} from '../verifier/results.ts';
import {hash,toTagged} from '../verifier/digest.ts';
import {validateInstance,dialect} from '../verifier/schema.ts';
import {tagged} from '../verifier/plain.ts';
import {documentDigest} from '../verifier/harness.ts';
const scratch=mkdtempSync(join(tmpdir(),'abp-conformance-'));
const certified=readFileSync('spec/conformance/certified-results.json');
function run(args,expected=0){const r=spawnSync(process.execPath,args,{encoding:'utf8',maxBuffer:10_000_000,timeout:15000});assert.equal(r.status,expected,r.stderr);return r;}
try {
  for(const [label,command] of [['escript',['escript','agent_blueprint_protocol_conformance','--serve','--corpus','priv/conformance']],['kit',[process.execPath,'dist/kit/cli.mjs','--serve','--corpus','priv/conformance']]]) {
    const output=join(scratch,label+'.json');
    run(['dist/kit/cli.mjs','conformance','run','--corpus','priv/conformance','--results',output,'--',...command]);
    assert.deepEqual(readFileSync(output),certified,label+' results differ');
  }
  const outcomes={echo:15,duplicate:11,missing:12,extra:13,reordered:14,malformed:15,oversized:16,wrong:19,slow:17,early:18,mismatch:10,projection:19,unclosed:17,inherited:17};
  for(const [stub,status] of Object.entries(outcomes)){const started=Date.now();run(['dist/kit/cli.mjs','conformance','run','--corpus','priv/conformance','--results',join(scratch,'negative.json'),'--timeout-ms','1000','--',process.execPath,'test/external/'+stub+'.mjs'],status);if(stub==='inherited')assert.ok(Date.now()-started<6000,'inherited stdout exceeded shutdown deadline');}
  const claim=join(scratch,'claim.json'),result=join(scratch,'claim-results.json');
  const identity=['--claim',claim,'--implementation','example-verifier','--implementation-version','1','--source','https://example.com/source','--platform','example-platform','--date','2026-11-10'];
  const adapter=[process.execPath,'dist/kit/cli.mjs','--serve','--corpus','priv/conformance'];
  run(['dist/kit/cli.mjs','conformance','run','--corpus','priv/conformance','--results',result,...identity,'--',...adapter]);
  const document=JSON.parse(readFileSync(claim,'utf8'));
  assert.equal(document.results_digest,documentDigest(readFileSync(result,'utf8')));
  assert.equal(validateInstance(tagged(JSON.parse(readFileSync('spec/conformance/claim.schema.json','utf8'))),tagged(document),dialect()).ok,true);
  const prior=join(scratch,'prior');cpSync('priv/conformance',prior,{recursive:true});
  const index=JSON.parse(readFileSync(join(prior,'index.json'),'utf8'));delete index.corpus_digest;index.bool_extra=!index.bool_extra;index.corpus_digest=toTagged(hash('corpus_index',Buffer.from(canonical(index))));
  writeFileSync(join(prior,'index.json'),canonical(index));
  const priorAdapter=[process.execPath,'dist/kit/cli.mjs','--serve','--corpus',prior];
  run(['dist/kit/cli.mjs','conformance','run','--corpus',prior,'--results',result,...identity,'--',...priorAdapter],2);
  run(['dist/kit/cli.mjs','conformance','run','--corpus',prior,'--results',result,...identity,'--prior-corpus-digest',index.corpus_digest,'--',...priorAdapter],2);
  run(['dist/kit/cli.mjs','conformance','run','--corpus',join(scratch,'absent'),'--',...adapter],2);
  assert.deepEqual(readFileSync('dist/release-history.json'),readFileSync('priv/release-history.json'));
  assert.deepEqual(readFileSync('dist/package/dist/release-history.json'),readFileSync('priv/release-history.json'));
  run(['dist/kit/cli.mjs','conformance','run','--corpus','priv/conformance','--results',result,...identity,'--prior-corpus-digest',document.corpus_digest,'--',...adapter]);
  run(['scripts/check_reconcile_mutations.mjs']);
  console.log('conformance product: schemas, both adapters, certified results, and 14 adapter denials passed');
}finally{rmSync(scratch,{recursive:true,force:true});}
