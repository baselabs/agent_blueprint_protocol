import { mkdtempSync,readFileSync,writeFileSync,cpSync,rmSync,existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join,resolve,dirname } from 'node:path';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
const npmCli=[join(dirname(process.execPath),'node_modules/npm/bin/npm-cli.js'),resolve(dirname(process.execPath),'../lib/node_modules/npm/bin/npm-cli.js')].find(existsSync);
const root=resolve('.'),scratch=mkdtempSync(join(tmpdir(),'abp-consumer-'));
function command(program,args,cwd=scratch,status=0){const r=spawnSync(program==='npm'&&npmCli?process.execPath:program,program==='npm'&&npmCli?[npmCli,...args]:args,{cwd,encoding:'utf8',maxBuffer:5_000_000});assert.equal(r.status,status,r.stdout+r.stderr);return r;}
try {
  cpSync('.tool-versions',join(scratch,'.tool-versions'));
  const packed=command('npm',['pack','./dist/package','--ignore-scripts','--json','--pack-destination',scratch],root);
  const file=JSON.parse(packed.stdout)[0].filename;
  writeFileSync(join(scratch,'package.json'),'{"private":true,"type":"module"}');
  command('npm',['install','--ignore-scripts','--no-audit','--no-fund',join(scratch,file)]);
  assert.equal(existsSync(join(scratch,'node_modules/@types/node')),false);
  const imported=command(process.execPath,['--input-type=module','-e',"await import('@agent-blueprint-protocol/verifier')"]);assert.equal(imported.stdout,'');assert.equal(imported.stderr,'');
  const mappingIndex=process.argv.indexOf('--mapping');
  if(mappingIndex>=0)writeFileSync(join(scratch,'expected-mapping.json'),process.argv[mappingIndex+1]);
  cpSync('test/typescript/consumer.mjs',join(scratch,'consumer.mjs'));
  process.stdout.write(command(process.execPath,['consumer.mjs',root]).stdout);
  const guide=readFileSync('documentation/typescript.md','utf8');
  const sample=guide.match(/```js\n([\s\S]*?)```/)[1];
  const claimed=sample.match(/console\.log\(.*\); \/\/ (\S+)\n/)[1];
  writeFileSync(join(scratch,'verify.mjs'),sample);
  const example=readFileSync('examples/echo-blueprint.json','utf8');
  writeFileSync(join(scratch,'echo-blueprint.json'),example);
  assert.equal(command(process.execPath,['verify.mjs']).stdout.trim(),claimed);
  const edited=example.replace('"max_attempts":3','"max_attempts":4');assert.notEqual(edited,example);
  writeFileSync(join(scratch,'echo-blueprint.json'),edited);
  assert.notEqual(command(process.execPath,['verify.mjs']).stdout.trim(),claimed);
  const codes=[...readFileSync('verifier/errors.ts','utf8').matchAll(/\| "([^"]+)"/g)].map(x=>x[1]);
  const ex=readFileSync('lib/agent_blueprint_protocol/error.ex','utf8');
  const declared=[...ex.split('@codes [')[1].split('\n  ]')[0].matchAll(/^\s+:([a-z0-9_]+),?$/gm)].map(x=>x[1]);
  const ceilings=ex.match(/@ceiling_keys ~w\(([^)]+)\)/)[1].split(/\s+/).map(x=>'ceiling:'+x);
  assert.deepEqual(codes,[...declared,...ceilings].sort(),'ErrorCode differs from Elixir source');
  if(process.argv[2]==='--error-codes')assert.deepEqual(codes,JSON.parse(process.argv[3]).sort(),'ErrorCode differs from Error.codes/0 and ceiling_keys/0');
  const source="import {decodeBlueprint,type ErrorCode,type Result,type Blueprint} from '@agent-blueprint-protocol/verifier';\nconst result:Result<Blueprint>=decodeBlueprint(new Uint8Array());\nexport function describe(code:ErrorCode):string {switch(code){\n"+codes.map(c=>'case '+JSON.stringify(c)+':return '+JSON.stringify(c)+';').join('\n')+'\ndefault:{const exhaustive:never=code;return exhaustive;} }}\n';
  writeFileSync(join(scratch,'consumer.ts'),source);
  writeFileSync(join(scratch,'tsconfig.json'),JSON.stringify({compilerOptions:{module:'nodenext',moduleResolution:'nodenext',target:'es2023',lib:['es2023'],types:[],strict:true,skipLibCheck:false,noEmit:true},files:['consumer.ts']}));
  const tsc=join(root,'node_modules/typescript/bin/tsc');
  command(process.execPath,[tsc,'-p','tsconfig.json']);
  writeFileSync(join(scratch,'consumer.ts'),source.replace('case '+JSON.stringify(codes[0])+':return '+JSON.stringify(codes[0])+';',''));
  const missing=command(process.execPath,[tsc,'-p','tsconfig.json'],scratch,1);assert.match(missing.stdout,/never/);
  for(const runtime of ['bun','deno']){const r=spawnSync(runtime,['--version'],{encoding:'utf8'});if(r.error?.code==='ENOENT'){console.log(runtime+': unavailable');continue;}const args=runtime==='bun'?['run','consumer.mjs',root]:['run','--allow-read','consumer.mjs',root];process.stdout.write(command(runtime,args).stdout);}
  console.log('consumer: root ESM import, isolated declarations, and exhaustive ErrorCode passed; missing case failed');
}finally{rmSync(scratch,{recursive:true,force:true});}
