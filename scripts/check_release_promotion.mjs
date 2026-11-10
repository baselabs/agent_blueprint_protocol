import { readFileSync,existsSync,mkdtempSync,mkdirSync,writeFileSync,rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const git=args=>{const r=spawnSync('git',args,{maxBuffer:20_000_000});if(r.status!==0)throw Error('release promotion: git reference unavailable');return r.stdout;};
const hash=bytes=>createHash('sha1').update('blob '+bytes.length+'\0').update(bytes).digest('hex');
const paths=()=>git(['ls-files','--cached','--others','--exclude-standard','-z']).toString().split('\0').filter(Boolean);
function check(changes,rc,final){
  const denied=[];
  for(const [path,before,after] of changes){
    if(before===null||after===null){denied.push(path);continue;}
    const a=before.toString(),b=after.toString();
    if(['mix.exs','package.json','package-lock.json'].includes(path)){
      if(a.replaceAll(rc,final)!==b)denied.push(path);continue;
    }
    if(path==='priv/release-metadata.json'){
      const old=JSON.parse(a),next=JSON.parse(b);old.package_version=final;old.verifier_kit.version=final;
      if(JSON.stringify(old)!==JSON.stringify(next))denied.push(path);continue;
    }
    if(path==='priv/release-history.json'){
      const old=JSON.parse(a),next=JSON.parse(b);const row=old.rows.find(x=>x.package_version===rc);
      old.rows.push({...row,package_version:final});
      if(!row||JSON.stringify(old)!==JSON.stringify(next))denied.push(path);continue;
    }
    if(path==='CHANGELOG.md'){
      const normalized=a.replace('## ['+rc+'] — unreleased','## ['+final+'] — '+(b.match(new RegExp('^## \\['+final.replaceAll('.','\\.')+'\\] — (\\d{4}-\\d{2}-\\d{2})$','m'))?.[1]??'invalid'));
      if(normalized!==b)denied.push(path);continue;
    }
    if(path==='README.md'){
      const normalized=a.replaceAll(rc,final).replaceAll('@agent-blueprint-protocol/verifier@rc','@agent-blueprint-protocol/verifier');
      if(normalized!==b)denied.push(path);continue;
    }
    if(path==='SECURITY.md'){
      const line=final.split('.').slice(0,2).join('.')+'.x';
      const rcRow='| '+rc+' | yes |\n';
      const finalRow='| '+line+' | yes |\n';
      const normalized=a.replace(rcRow,a.includes(finalRow)?'':finalRow).replace('The release candidate is unreleased. ','');
      if(normalized!==b)denied.push(path);continue;
    }
    if(path.startsWith('documentation/')||path.startsWith('docs/')||path.startsWith('site/')){
      if(a.replaceAll(rc,final)!==b)denied.push(path);continue;
    }
    denied.push(path);
  }
  if(denied.length)throw Error('release promotion: forbidden differences: '+denied.join(', '));
}
function seeded(){
  const scratch=mkdtempSync(join(tmpdir(),'abp-promotion-'));
  try {mkdirSync(join(scratch,'lib'));const path='lib/agent_blueprint_protocol.ex',source=readFileSync(path);writeFileSync(join(scratch,path),Buffer.concat([source,Buffer.from('\n# example changed bytes\n')]));
    return [path,source,readFileSync(join(scratch,path))];
  }finally{rmSync(scratch,{recursive:true,force:true});}
}
function selfTest(){
  const rc='1.0.0-rc.1',final='1.0.0';
  check([['mix.exs',Buffer.from('@version "'+rc+'"'),Buffer.from('@version "'+final+'"')]],rc,final);
  const readme=readFileSync('README.md'),security=readFileSync('SECURITY.md');
  const finalReadme=Buffer.from(readme.toString().replaceAll(rc,final).replaceAll('@agent-blueprint-protocol/verifier@rc','@agent-blueprint-protocol/verifier'));
  const finalSecurity=Buffer.from(security.toString().replace('| '+rc+' | yes |\n','').replace('The release candidate is unreleased. ',''));
  check([['README.md',readme,finalReadme],['SECURITY.md',security,finalSecurity]],rc,final);
  for(const [path,before,after] of [['README.md',readme,finalReadme],['SECURITY.md',security,finalSecurity]])assert.throws(()=>check([[path,before,Buffer.concat([after,Buffer.from('extra text')])]],rc,final),/forbidden differences/);
  assert.throws(()=>check([seeded()],rc,final),/forbidden differences/);
  console.log('release promotion: permitted version change passed; seeded library change rejected');
}
try {
  const args=process.argv.slice(2);
  if(args.length===1&&args[0]==='--prove-source-rejection')check([seeded()],'1.0.0-rc.1','1.0.0');
  else if(args.length===0)selfTest();
  else {
    if(args.length!==2||args[0]!=='--check'||!/^v\d+\.\d+\.\d+-rc\.\d+$/.test(args[1]))throw Error('release promotion: usage --check <rc-tag>');
    const tag=args[1],rc=tag.slice(1),final=rc.split('-')[0];
    const tree=git(['ls-tree','-rz',tag]).toString().split('\0').filter(Boolean).map(x=>{const [entry,path]=x.split('\t');return [path,entry.split(' ')[2]];});
    const baseline=new Map(tree),current=new Set(paths()),changes=[];
    for(const path of new Set([...baseline.keys(),...current])){
      const after=current.has(path)&&existsSync(path)?readFileSync(path):null;
      if(after&&hash(after)===baseline.get(path))continue;
      const before=baseline.has(path)?git(['show',tag+':'+path]):null;changes.push([path,before,after]);
    }
    if(JSON.parse(readFileSync('package.json')).version!==final)throw Error('release promotion: candidate tree does not name the final version');
    check(changes,rc,final);console.log('release promotion: candidate differs only in permitted release identity and install pins');
  }
}catch(error){console.error(error.message);process.exitCode=1;}
