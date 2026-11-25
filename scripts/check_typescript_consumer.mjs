import { mkdtempSync,mkdirSync,readFileSync,writeFileSync,cpSync,rmSync,existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join,resolve } from 'node:path';
import {capture,stream} from './gate_command.mjs';
import assert from 'node:assert/strict';
import { npmCli } from './npm.mjs';
const npm=npmCli();
const root=resolve('.'),scratch=mkdtempSync(join(tmpdir(),'abp-consumer-'));
function command(program,args,cwd=scratch,status=0,captured=false){const r=(captured?capture:stream)(program==='npm'?process.execPath:program,program==='npm'?[npm,...args]:args,{cwd,encoding:'utf8',maxBuffer:5_000_000});assert.equal(r.status,status);return r;}
try {
  cpSync('.tool-versions',join(scratch,'.tool-versions'));
  const packed=command('npm',['pack','./dist/package','--ignore-scripts','--json','--pack-destination',scratch],root,0,true);
  const file=JSON.parse(packed.stdout)[0].filename;
  writeFileSync(join(scratch,'package.json'),'{"private":true,"type":"module"}');
  command('npm',['install','--ignore-scripts','--no-audit','--no-fund',join(scratch,file)]);
  assert.equal(existsSync(join(scratch,'node_modules/@types/node')),false);
  writeFileSync(join(scratch,'import.mjs'),"await import('@agent-blueprint-protocol/verifier');\n");
  const imported=command(process.execPath,['import.mjs'],scratch,0,true);assert.equal(imported.stdout,'');assert.equal(imported.stderr,'');
  const mappingIndex=process.argv.indexOf('--mapping');
  if(mappingIndex>=0)writeFileSync(join(scratch,'expected-mapping.json'),process.argv[mappingIndex+1]);
  cpSync('test/typescript/consumer.mjs',join(scratch,'consumer.mjs'));
  command(process.execPath,['consumer.mjs',root]);
  cpSync('test/typescript/package_contents.mjs',join(scratch,'package_contents.mjs'));
  command(process.execPath,['package_contents.mjs']);
  const guide=readFileSync('documentation/typescript.md','utf8');
  const sample=guide.match(/```js\n([\s\S]*?)```/)[1];
  const claimed=sample.match(/console\.log\(.*\); \/\/ (\S+)\n/)[1];
  writeFileSync(join(scratch,'verify.mjs'),sample);
  const example=readFileSync('priv/examples/echo-blueprint.json','utf8');
  const examplePath=join(scratch,'node_modules/@agent-blueprint-protocol/verifier/dist/examples/echo-blueprint.json');
  assert.equal(readFileSync(examplePath,'utf8'),example);
  assert.equal(command(process.execPath,['verify.mjs'],scratch,0,true).stdout.trim(),claimed);
  const edited=example.replace('"max_attempts":3','"max_attempts":4');assert.notEqual(edited,example);
  writeFileSync(examplePath,edited);
  assert.notEqual(command(process.execPath,['verify.mjs'],scratch,0,true).stdout.trim(),claimed);
  const codes=[...readFileSync('verifier/errors.ts','utf8').matchAll(/\| "([^"]+)"/g)].map(x=>x[1]);
  const ex=readFileSync('lib/agent_blueprint_protocol/error.ex','utf8');
  const declared=[...ex.split('@codes [')[1].split('\n  ]')[0].matchAll(/^\s+:([a-z0-9_]+),?$/gm)].map(x=>x[1]);
  const ceilings=ex.match(/@ceiling_keys ~w\(([^)]+)\)/)[1].split(/\s+/).map(x=>'ceiling:'+x);
  assert.deepEqual(codes,[...declared,...ceilings].sort(),'ErrorCode differs from Elixir source');
  if(process.argv[2]==='--error-codes')assert.deepEqual(codes,JSON.parse(process.argv[3]).sort(),'ErrorCode differs from Error.codes/0 and ceiling_keys/0');
  const source="import {decodeBlueprint,type ErrorCode,type Result,type Blueprint} from '@agent-blueprint-protocol/verifier';\nconst result:Result<Blueprint>=decodeBlueprint(new Uint8Array());\nexport function describe(code:ErrorCode):string {switch(code){\n"+codes.map(c=>'case '+JSON.stringify(c)+':return '+JSON.stringify(c)+';').join('\n')+'\ndefault:{const exhaustive:never=code;return exhaustive;} }}\n';
  const forward="import {KNOWN_NOTICES,KNOWN_EVIDENCE_SURFACES,KNOWN_EVIDENCE_CHECK_KINDS,KNOWN_SIGNATURE_ALGORITHMS,KNOWN_SIGNATURE_PURPOSES,type Notice,type EvidenceSurface,type EvidenceCheckKind,type SignatureAlgorithm,type SignaturePurpose,type SignedAttributes,type PublicKey,type Support} from '@agent-blueprint-protocol/verifier';\n"+
    "const notice:Notice='future_notice';const surface:EvidenceSurface='future_surface';const kind:EvidenceCheckKind='future_check';const algorithm:SignatureAlgorithm='future_algorithm';const purpose:SignaturePurpose='future_purpose';\n"+
    "const signed:SignedAttributes={algorithm,purpose,contentDigest:'',createdAt:'',keyId:''};\n"+
    "// @ts-expect-error verification input algorithms remain strict\nconst unsupported:PublicKey={algorithm:'future_algorithm',keyId:'',key:new Uint8Array()};\n"+
    "// @ts-expect-error negotiation input lifecycle states remain strict\nconst state:Support['registry'][string]['state']='future_state';\n"+
    "import {procedureSchema,procedureDocumentCommitment,verifyProcedure,type ProcedureInputs,type Deployment,type Evidence} from '@agent-blueprint-protocol/verifier';\n"+
    "declare const procedureDeployment:Deployment;declare const procedureInputs:ProcedureInputs;const procedureResult:Result<Evidence>=verifyProcedure(procedureDeployment,procedureInputs);const procedureCommitment:Result<string>=procedureDocumentCommitment({type:'example.document',nonce:'0'.repeat(64)});procedureSchema();\n"+
    "// @ts-expect-error procedure import phases remain strict\nconst phase:ProcedureInputs['phase']='future_phase';\n"+
    "import {verifyPackageContents,type PackageDistribution} from '@agent-blueprint-protocol/verifier';\n"+
    "const distribution:PackageDistribution='npm';const contentsResult:Result<true>=verifyPackageContents('.',distribution,'checksum');\n"+
    "export function inspectNotice(value:Notice):boolean {switch(value){case KNOWN_NOTICES.extension_deprecated:return true;default:return false;}}\n";
  writeFileSync(join(scratch,'consumer.ts'),source+forward);
  writeFileSync(join(scratch,'tsconfig.json'),JSON.stringify({compilerOptions:{module:'nodenext',moduleResolution:'nodenext',target:'es2022',lib:['es2022'],types:[],strict:true,skipLibCheck:false,noEmit:true},files:['consumer.ts']}));
  for(const compiler of ['typescript-floor','typescript']) {
    const tsc=join(root,'node_modules',compiler,'bin/tsc');
    writeFileSync(join(scratch,'consumer.ts'),source+forward);
    command(process.execPath,[tsc,'-p','tsconfig.json']);
    writeFileSync(join(scratch,'consumer.ts'),(source+forward).replace('case '+JSON.stringify(codes[0])+':return '+JSON.stringify(codes[0])+';',''));
    const missing=command(process.execPath,[tsc,'-p','tsconfig.json'],scratch,compiler==='typescript-floor'?2:1,true);assert.match(missing.stdout,/never/);
    console.log(compiler+': packed declarations, open identifiers, default notice switch, and exhaustive ErrorCode passed; missing case failed');
  }
  for(const runtime of ['bun','deno']){const r=stream(runtime,['--version']);if(r.error?.code==='ENOENT'){console.log(runtime+': unavailable');continue;}const args=runtime==='bun'?['run','consumer.mjs',root]:['run','--allow-read','consumer.mjs',root];command(runtime,args);}
  console.log('consumer: root ESM import, isolated declarations, and exhaustive ErrorCode passed; missing case failed');
}finally{rmSync(scratch,{recursive:true,force:true});}
