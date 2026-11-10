import { spawn } from 'node:child_process';
import { readFileSync,writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { load,loadPriorCensus } from './corpus.ts';
import { canonical } from './results.ts';
import { lines,handshake,ExecutionFailure } from './execution.ts';
import { plain } from './plain.ts';

export const OUTCOMES={handshake_mismatch:10,duplicate_id:11,missing_response:12,extra_response:13,reordered_response:14,malformed_line:15,oversized_line:16,response_timeout:17,early_exit:18,disagreement:19} as const;
export function documentDigest(bytes:string):string{return 'sha-256:'+createHash('sha256').update(bytes).digest('base64url');}
export async function runHarness(args:string[],readCorpus:(path:string)=>Map<string,Buffer>,metadata:{corpus_digest:string}):Promise<number> {
  const separator=args.indexOf('--');if(separator<0||separator===args.length-1)return 2;
  const options:Record<string,string>={};
  for(let i=0;i<separator;i+=2){if(!['--corpus','--results','--timeout-ms','--claim','--implementation','--implementation-version','--source','--platform','--date','--prior-corpus-digest'].includes(args[i]!)||!args[i+1]||i+1>=separator||Object.hasOwn(options,args[i]!))return 2;options[args[i]!]=args[i+1]!;}
  const timeout=Number(options['--timeout-ms']??'30000');if(!Number.isInteger(timeout)||timeout<1||timeout>300000)return 2;
  if(!options['--corpus'])return 2;
  let loaded:ReturnType<typeof load>;
  try{loaded=(options['--prior-corpus-digest']?loadPriorCensus:load)(readCorpus(options['--corpus']));}catch{return 2;}
  if(!loaded.ok)return 2;
  const corpus=loaded.v;
  const certified=corpus.identity===metadata.corpus_digest;
  process.stderr.write(`corpus digest ${certified?'matches':'does not match'} the release-certified corpus\n`);
  if(options['--claim']&&(!certified&&options['--prior-corpus-digest']!==corpus.identity))return 2;
  if(options['--prior-corpus-digest']) {
    let history:any;
    for(const path of ['../priv/release-history.json','../release-history.json','./release-history.json']) {
      try{history=JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));break;}
      catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')return 2;}
    }
    if(options['--prior-corpus-digest']!==corpus.identity||!history?.rows?.some((row:any)=>row.corpus_digest===corpus.identity))return 2;
  }
  if(options['--claim']&&['--implementation','--implementation-version','--source','--platform','--date'].some(k=>!options[k]))return 2;
  if(options['--claim']&&(!/^\d{4}-\d{2}-\d{2}$/.test(options['--date']!)||!/^https?:\/\//.test(options['--source']!)))return 2;
  let certifiedRows:Map<string,any>|null=null;
  if(certified){
    let document:any;
    for(const path of ['../spec/conformance/certified-results.json','./spec/conformance/certified-results.json']){
      try{document=JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));break;}
      catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw error;}
    }
    if(!document||document.corpus_digest!==corpus.identity||document.registry_digest!==plain(corpus.index).registry_digest)return 2;
    certifiedRows=new Map(document.results.map((row:any)=>[row.id,row]));
    if(certifiedRows.size!==corpus.caseIds.size)return 2;
  }
  const child=spawn(args[separator+1]!,args.slice(separator+2),{stdio:['pipe','pipe','pipe'],windowsHide:true,detached:process.platform!=='win32'});
  child.stderr.pipe(process.stderr);child.stdin.on('error',()=>{});
  let exitCode:number|null|undefined;
  const exited=new Promise<void>(resolve=>{child.once('error',()=>{exitCode=-1;resolve();});child.once('exit',code=>{exitCode=code;resolve();});});
  const finish=async()=>{
    let timer:ReturnType<typeof setTimeout>|undefined;
    try{await Promise.race([exited,new Promise<never>((_,reject)=>{timer=setTimeout(()=>reject(new ExecutionFailure('response_timeout')),timeout);})]);}
    finally{if(timer)clearTimeout(timer);}
  };
  const reader=lines(child.stdout);
  const rows=corpus.cases.flatMap(f=>f.cases).sort((a,b)=>Buffer.compare(Buffer.from(a.id),Buffer.from(b.id)));
  const results:unknown[]=[];const ids=new Set<string>();
  try {
    child.stdin.write(canonical(handshake(corpus))+'\n');
    const hello=await reader.next(timeout);if(hello===null)throw new ExecutionFailure('early_exit');
    if(canonical(hello)!==canonical(handshake(corpus)))throw new ExecutionFailure('handshake_mismatch');
    const sending=(async()=>{for(const row of rows){if(!child.stdin.write(canonical({id:row.id,surface:row.surface,input:plain(row.input)})+'\n'))await once(child.stdin,'drain');}child.stdin.end();})();
    sending.catch(()=>{});
    let agreement=true;
    for(let i=0;i<rows.length;i++) {
      const response=await reader.next(timeout) as any;
      if(response===null){process.stderr.write('harness response ended before '+rows[i]!.id+'\n');await finish();throw new ExecutionFailure(exitCode===0&&i>0?'missing_response':'early_exit');}
      if(!response||typeof response!=='object'||Object.keys(response).sort().join(',')!=='id,result'||typeof response.id!=='string'||!response.result||typeof response.result!=='object'||Array.isArray(response.result))throw new ExecutionFailure('malformed_line');
      if(ids.has(response.id))throw new ExecutionFailure('duplicate_id');
      if(response.id!==rows[i]!.id)throw new ExecutionFailure('reordered_response');
      ids.add(response.id);
      const expected=plain(rows[i]!.expected);
      const certifiedRow=certifiedRows?.get(rows[i]!.id);
      const exact=!certifiedRows||(certifiedRow?.surface===rows[i]!.surface&&canonical(certifiedRow.result)===canonical(response.result));
      if(!exact||!matches(expected,response.result)){agreement=false;process.stderr.write("harness disagreement: "+rows[i]!.id+"\n");}
      results.push({id:response.id,surface:rows[i]!.surface,result:response.result});
    }
    const extra=await reader.next(timeout);if(extra!==null)throw new ExecutionFailure('extra_response');
    await finish();if(exitCode!==0)throw new ExecutionFailure('early_exit');
    await sending;
    const document=canonical({format:'agent-blueprint-protocol-conformance-results',corpus_digest:corpus.identity,registry_digest:plain(corpus.index).registry_digest,results});
    if(options['--results'])writeFileSync(options['--results'],document);else process.stdout.write(document);
    if(!agreement)throw new ExecutionFailure('disagreement');
    if(options['--claim']) {
      const claim={format:'agent-blueprint-protocol-conformance-claim',implementation:options['--implementation'],version:options['--implementation-version'],source_url:options['--source'],platform:options['--platform'],corpus_digest:corpus.identity,registry_digest:plain(corpus.index).registry_digest,results_digest:documentDigest(document),date:options['--date']};
      writeFileSync(options['--claim'],canonical(claim));
    }
    process.stderr.write('harness: agreement\n');return 0;
  } catch(error) {
    const outcome=error instanceof ExecutionFailure?error.outcome:'early_exit';
    process.stderr.write('harness: '+outcome+'\n');return OUTCOMES[outcome as keyof typeof OUTCOMES]??18;
  } finally {
    // POSIX groups include descendants that can inherit the output pipes.
    // Windows uses the adapter handle: detached groups have no POSIX kill semantics.
    if(process.platform!=='win32'&&child.pid){try{process.kill(-child.pid,'SIGKILL');}catch(error){if(!['ESRCH','EPERM'].includes((error as NodeJS.ErrnoException).code??''))throw error;if(exitCode===undefined)child.kill('SIGKILL');}}
    else if(exitCode===undefined)child.kill('SIGKILL');
    child.stdin.destroy();child.stdout.destroy();child.stderr.destroy();
    let timer:ReturnType<typeof setTimeout>|undefined;
    try{await Promise.race([exited,new Promise<void>(resolve=>{timer=setTimeout(resolve,Math.min(timeout,1000));})]);}
    finally{if(timer)clearTimeout(timer);}
  }
}
function matches(expected:any,actual:any):boolean {
  if(!actual||typeof actual!=='object'||actual.verdict!==expected.verdict)return false;
  return Object.entries(expected).every(([key,value])=>{
    if(!Object.hasOwn(actual,key))return false;
    if(canonical(value)===canonical(actual[key]))return true;
    return ['encoded','canonical','decoded'].includes(key)&&typeof value==='string'&&typeof actual[key]==='string'&&Buffer.from(actual[key],'base64url').equals(Buffer.from(value));
  });
}
