import { readFileSync,existsSync,mkdtempSync,mkdirSync,writeFileSync,rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const git=args=>{const r=spawnSync('git',args,{maxBuffer:20_000_000});if(r.status!==0)throw Error('release promotion: git reference unavailable');return r.stdout;};
const hash=bytes=>createHash('sha1').update('blob '+bytes.length+'\0').update(bytes).digest('hex');
const paths=()=>git(['ls-files','--cached','--others','--exclude-standard','-z']).toString().split('\0').filter(Boolean);
// The final release adds its own dated entry directly above the candidate's
// entry; every earlier entry, the candidate's included, stays byte-identical.
function changelogPromotes(a,b,rc,final){
  const escape=s=>s.replaceAll('.','\\.');
  const entry=b.match(new RegExp('^## \\['+escape(final)+'\\] — \\d{4}-\\d{2}-\\d{2}\\n[\\s\\S]*?(?=^## \\[)','m'));
  if(!entry)return false;
  const at=b.indexOf(entry[0]);
  return b.slice(0,at)+b.slice(at+entry[0].length)===a&&b.indexOf('## ['+rc+']')===at+entry[0].length;
}
// This classifier owns both the promotion diff policy and the candidate
// tree check. A frozen file cannot shed a candidate version at promotion.
function promotionRule(path){
  // Namespace pages identify stable registrations rather than releases.
  if(path.startsWith('site/extensions/'))return 'frozen';
  if(['mix.exs','package.json','package-lock.json','verifier/README.md'].includes(path)||['documentation/','docs/','site/'].some(dir=>path.startsWith(dir)))return 'version';
  if(path==='priv/release-metadata.json')return 'metadata';
  if(path==='priv/release-history.json')return 'history';
  if(path==='CHANGELOG.md')return 'changelog';
  if(path==='README.md')return 'readme';
  if(path==='SECURITY.md')return 'security';
  return 'frozen';
}
function check(changes,rc,final){
  const denied=[];
  for(const [path,before,after] of changes){
    if(before===null||after===null){denied.push(path);continue;}
    const a=before.toString(),b=after.toString();
    switch(promotionRule(path)){
      case 'version':
        if(a.replaceAll(rc,final)!==b)denied.push(path);break;
      case 'metadata':{
        const old=JSON.parse(a),next=JSON.parse(b);old.package_version=final;old.verifier_kit.version=final;
        if(JSON.stringify(old)!==JSON.stringify(next))denied.push(path);break;
      }
      case 'history':{
        const old=JSON.parse(a),next=JSON.parse(b);const row=old.rows.find(x=>x.package_version===rc);
        old.rows.push({...row,package_version:final});
        if(!row||JSON.stringify(old)!==JSON.stringify(next))denied.push(path);break;
      }
      case 'changelog':
        if(!changelogPromotes(a,b,rc,final))denied.push(path);break;
      case 'readme':{
        const normalized=a.replaceAll(rc,final).replaceAll('@agent-blueprint-protocol/verifier@rc','@agent-blueprint-protocol/verifier');
        if(normalized!==b)denied.push(path);break;
      }
      case 'security':{
        const line=final.split('.').slice(0,2).join('.')+'.x';
        const rcRow='| '+rc+' | yes |\n';
        const finalRow='| '+line+' | yes |\n';
        const normalized=a.replace(rcRow,a.includes(finalRow)?'':finalRow);
        if(normalized!==b)denied.push(path);break;
      }
      case 'frozen':denied.push(path);
    }
  }
  if(denied.length)throw Error('release promotion: forbidden differences: '+denied.join(', '));
}
function checkTree(entries,version){
  if(!/^\d+\.\d+\.\d+-/.test(version))return;
  const denied=entries.filter(([path,bytes])=>promotionRule(path)==='frozen'&&bytes.includes(version)).map(([path])=>path);
  if(denied.length)throw Error('release promotion: frozen files name candidate '+version+': '+denied.join(', '));
}
function checkCurrentTree(){
  const version=readFileSync('mix.exs','utf8').match(/@version\s+"([^"]+)"/)[1];
  checkTree(paths().filter(path=>existsSync(path)).map(path=>[path,readFileSync(path)]),version);
}
function seeded(){
  const scratch=mkdtempSync(join(tmpdir(),'abp-promotion-'));
  try {mkdirSync(join(scratch,'lib'));const path='lib/agent_blueprint_protocol.ex',source=readFileSync(path);writeFileSync(join(scratch,path),Buffer.concat([source,Buffer.from('\n# example changed bytes\n')]));
    return [path,source,readFileSync(join(scratch,path))];
  }finally{rmSync(scratch,{recursive:true,force:true});}
}
function selfTest(){
  const rc='1.0.0-rc.1',final='1.0.0';
  check([['verifier/README.md',Buffer.from('npm install @agent-blueprint-protocol/verifier@'+rc),Buffer.from('npm install @agent-blueprint-protocol/verifier@'+final)]],rc,final);
  checkTree([['verifier/README.md',Buffer.from(rc)]],rc);
  assert.equal(promotionRule('site/extensions/example/index.html'),'frozen');
  check([['mix.exs',Buffer.from('@version "'+rc+'"'),Buffer.from('@version "'+final+'"')]],rc,final);
  const readme=Buffer.from('# Example\n\n{:agent_blueprint_protocol, "~> '+rc+'"}\n\nnpm install @agent-blueprint-protocol/verifier@rc\nnpx @agent-blueprint-protocol/verifier@rc --help\n');
  const security=Buffer.from('# Security policy\n\n| Version | Supported |\n| --- | --- |\n| '+rc+' | yes |\n| 1.0.x | yes |\n| 0.8.x | yes |\n');
  const finalReadme=Buffer.from(readme.toString().replaceAll(rc,final).replaceAll('@agent-blueprint-protocol/verifier@rc','@agent-blueprint-protocol/verifier'));
  const finalSecurity=Buffer.from(security.toString().replace('| '+rc+' | yes |\n',''));
  const rcHeading='## ['+rc+']';
  const changelog='# Changelog\n\n'+rcHeading+' — 2026-11-11\n\nCandidate package.\n\n## [0.8.4] — 2026-10-01\n\nEarlier package.\n';
  const finalChangelog=changelog.replace(rcHeading,'## ['+final+'] — 2026-12-01\n\nPromotes '+rc+' unchanged.\n\n'+rcHeading);
  check([['CHANGELOG.md',Buffer.from(changelog),Buffer.from(finalChangelog)]],rc,final);
  assert.throws(()=>check([['CHANGELOG.md',Buffer.from(changelog),Buffer.from(changelog.replace(rcHeading,'## ['+final+']'))]],rc,final),/forbidden differences/);
  assert.throws(()=>check([['CHANGELOG.md',Buffer.from(changelog),Buffer.from(finalChangelog+'edited released text\n')]],rc,final),/forbidden differences/);
  assert.notDeepEqual(readme,finalReadme);
  assert.notDeepEqual(security,finalSecurity);
  assert.notEqual(changelog,finalChangelog);
  check([['README.md',readme,finalReadme],['SECURITY.md',security,finalSecurity]],rc,final);
  for(const [path,before,after] of [['README.md',readme,Buffer.from(finalReadme.toString().replaceAll(final,rc))],['README.md',readme,Buffer.from(finalReadme.toString().replaceAll('@agent-blueprint-protocol/verifier','@agent-blueprint-protocol/verifier@rc'))],['SECURITY.md',security,Buffer.from(finalSecurity.toString().replace('| 1.0.x | yes |\n',''))]])assert.throws(()=>check([[path,before,after]],rc,final),/forbidden differences/);
  for(const [path,before,after] of [['README.md',readme,finalReadme],['SECURITY.md',security,finalSecurity]])assert.throws(()=>check([[path,before,Buffer.concat([after,Buffer.from('extra text')])]],rc,final),/forbidden differences/);
  assert.throws(()=>check([seeded()],rc,final),/forbidden differences/);
  assert.throws(()=>checkTree([['lib/frozen.ex',Buffer.from(rc)]],rc),/frozen files name candidate/);
  checkTree([['documentation/allowed.md',Buffer.from(rc)]],rc);
  checkTree([['test/old_fixture.exs',Buffer.from('0.9.0-rc.1')]],rc);
  console.log('release promotion: permitted version change passed; seeded library change rejected');
}
try {
  const args=process.argv.slice(2);
  if(args.length===1&&args[0]==='--rules'){
    console.log(JSON.stringify(Object.fromEntries(paths().sort().map(path=>[path,promotionRule(path)]))));
  }
  else if(args.length===1&&args[0]==='--prove-source-rejection'){
    const rc=JSON.parse(readFileSync('package.json')).version;check([seeded()],rc,rc.split('-')[0]);
  }
  else if(args.length===0){selfTest();checkCurrentTree();}
  else {
    if(args.length!==2||args[0]!=='--check'||!/^v\d+\.\d+\.\d+-rc\.\d+$/.test(args[1]))throw Error('release promotion: usage --rules or --check <rc-tag>');
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
