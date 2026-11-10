import assert from 'node:assert/strict';
import { readFileSync,readdirSync,existsSync } from 'node:fs';
import { join } from 'node:path';
import * as api from '@agent-blueprint-protocol/verifier';
const root=process.argv[2];
const example=name=>readFileSync(join(root,'examples',name));
const value=r=>{assert.equal(r.ok,true,JSON.stringify(r));return r.value;};
const blueprint=value(api.decodeBlueprint(example('echo-blueprint.json')));
const deployment=value(api.decodeDeployment(example('echo-deployment.json')));
value(api.decodeFederationEnvelope(example('federation-envelope.json')));
value(api.canonicalBytes(blueprint));
const support={revisions:new Set([1]),coreFields:new Set(),registry:{},schemas:{}};
value(api.negotiate(blueprint,support));
for(const path of ['blueprint','deployment','both']) {
  const rows=JSON.parse(readFileSync(join(root,'priv/conformance/cases/negotiation-negotiate.json'))).cases.filter(row=>row.id.startsWith('negotiation-unknown-optional-'+path+'-'));
  for(const row of rows){const outcome=value(api.negotiate({kind:'blueprint',value:row.input.artifact},support));assert.deepEqual(outcome.optionalRetained,[]);assert.deepEqual(outcome.quarantinedExtensions,['com.example.z/y']);}
}
const composed=JSON.parse(readFileSync(join(root,'priv/conformance/cases/reconcile.json'))).cases;
for(const row of composed.filter(row=>/^reconcile-signature-(blueprint|deployment)-/.test(row.id)&&row.expected.subject.length===4)) {
  const side=row.expected.subject[0];const result=(side==='blueprint'?api.decodeBlueprint:api.decodeDeployment)(Buffer.from(row.input[side]));
  assert.equal(result.ok,false,row.id);assert.deepEqual(result.error.subject,row.expected.subject.slice(1),row.id);
}
const bounds={...deployment.value.host_bounds,classification_ceiling:{ordinal:'internal',markers:[]}};
value(api.intersect({blueprint:bounds,deployment:bounds,host:bounds,protectedClamp:'acknowledge'}));
value(api.verifyCompatibility(deployment,{identities:deployment.value.build_identities}));
value(api.reconcile(blueprint,deployment,{hostBounds:bounds,support,keys:[],protectedClamp:'acknowledge',observations:{now:null,maxAttestationAgeMs:null,observed:{}}}));
assert.equal(api.reconcile(blueprint,deployment,{hostBounds:bounds,support,keys:[],protectedClamp:'acknowledge',observations:{now:'invalid',maxAttestationAgeMs:10,observed:{}}}).ok,false);
assert.equal(value(api.federationMapping()).length,23);
if(existsSync('expected-mapping.json'))assert.deepEqual(value(api.federationMapping()),JSON.parse(readFileSync('expected-mapping.json','utf8')));
const signatures=JSON.parse(readFileSync(join(root,'priv/conformance/cases/signature-verify.json'))).cases;
const valid=signatures.find(c=>c.expected.verdict==='valid');
value(api.verifySignature(JSON.parse(valid.input.entry),valid.input.keys.map(k=>({keyId:k.key_id,algorithm:'ed25519',key:Buffer.from(k.key,'base64url')}))));
const files=new Map();function walk(path,prefix=''){for(const entry of readdirSync(path,{withFileTypes:true})){const name=prefix+entry.name;if(entry.isDirectory())walk(join(path,entry.name),name+'/');else files.set(name,readFileSync(join(path,entry.name)));}}
walk(join(root,'priv/conformance'));
const corpus=value(api.loadCorpus(files));
const run=value(api.runCorpus(corpus));assert.equal(value(api.buildReport(corpus,run)).agreement,true);
assert.equal(value(api.buildResultsDocument(corpus)).results.length,corpus.totalCases);
await assert.rejects(import('@agent-blueprint-protocol/verifier/dist/verifier/blueprint.js'),e=>e.code==='ERR_PACKAGE_PATH_NOT_EXPORTED'||/ERR_PACKAGE_PATH_NOT_EXPORTED|Cannot find module/.test(e.message));
const malformed=[undefined,null,true,1,NaN,Infinity,'',[],{},()=>{},Symbol(),new Uint8Array(),{value:null},new Proxy({},{get(){throw Error('access');}})];
const cyclic={};cyclic.value=cyclic;malformed.push(cyclic);
let seed=73;
for(let i=0;i<256;i++) {seed=(Math.imul(seed,1664525)+1013904223)>>>0;const sample=malformed[seed%14];malformed.push(i%3===0?{value:sample,bounds:{depth:sample}}:i%3===1?[sample,{hostBounds:sample}]:String.fromCharCode(seed%65536));}
for(const [name,fn] of Object.entries(api))for(const input of malformed){const r=fn(input,input,input);assert.ok(r&&typeof r.ok==='boolean',name);if(!r.ok)assert.ok(typeof r.error.code==='string'&&Array.isArray(r.error.subject),name);}
console.log('consumer: every facade, corpus, malformed inputs, and deep-import denial passed');
