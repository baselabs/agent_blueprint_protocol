import { cpSync,mkdtempSync,readFileSync,writeFileSync,rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
const source=readFileSync('verifier/reconcile.ts','utf8');
const markers=[
  '  for(const [name,artifact,mod] of artifacts) {',
  '  for(const [name,artifact,mod] of artifacts) {',
  '  const outcomes:negotiation.Outcome[]=[];',
  '  for(const [name,artifact,mod] of artifacts) {',
  '  for(let i=0;i<artifacts.length;i++) {',
  '  for(const [name,artifact,mod] of artifacts) {',
  '  const binding=deployment.verifyBinding',
  '  const depBounds=plain',
  '  checked(\'bounds\',\'bounds\');'
];
const offsets=[];let cursor=0;for(const marker of markers){const at=source.indexOf(marker,cursor);assert.ok(at>=0,'mutation anchor absent: '+marker);offsets.push(at);cursor=at+marker.length;}
const names=['canonical','digest','negotiation','structure','portability','signatures','bind','bounds'];
const replacements=['','','  const outcomes:negotiation.Outcome[]=artifacts.map(()=>({protocolRevision:1,criticalExtensions:[],quarantinedExtensions:[],optionalRetained:[],notices:[]}));\n','','','','  const skipped:string[]=[];\n','  const bounds={ok:true,v:{effective:{},clamps:[]}};\n'];
const scratch=mkdtempSync(join(tmpdir(),'abp-import-mutations-'));
try {
  cpSync('verifier',join(scratch,'verifier'),{recursive:true});
  // The loader and CLI locate the same immutable release identity.
  cpSync('priv/release-metadata.json',join(scratch,'release-metadata.json'));
  writeFileSync(join(scratch,'package.json'),'{"type":"module"}');
  const variants=names.map((name,i)=>[name+' skipped',source.slice(0,offsets[i])+replacements[i]+source.slice(offsets[i+1])]);
  variants.push(['stage order',source.slice(0,offsets[0])+source.slice(offsets[1],offsets[2])+source.slice(offsets[0],offsets[1])+source.slice(offsets[2])]);
  for(const [name,mutated] of variants){
    writeFileSync(join(scratch,'verifier/reconcile.ts'),mutated);
    const result=spawnSync(process.execPath,[join(scratch,'verifier/cli.ts'),'--corpus',join(process.cwd(),'priv/conformance')],{encoding:'utf8',maxBuffer:5_000_000});
    assert.equal(result.status,1,name+': expected a typed disagreement, received '+result.stderr);
    assert.equal(JSON.parse(result.stdout).agreement,false,name);
    console.log('reconcile mutation rejected: '+name);
  }
}finally{rmSync(scratch,{recursive:true,force:true});}
