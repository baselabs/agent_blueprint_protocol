import type { Readable } from 'node:stream';
import { decode } from './decode.ts';
import { plain } from './plain.ts';
import { canonical } from './results.ts';
import { memberString,type LoadedCorpus,type CaseObj } from './corpus.ts';
import { project } from './runner.ts';

export const LINE_LIMIT=5_000_000;
export class ExecutionFailure extends Error {
  outcome:string;
  constructor(outcome:string){super(outcome);this.outcome=outcome;}
}
export function lines(stream:Readable):{next:(timeout:number)=>Promise<unknown>} {
  const queue:unknown[]=[];let pending:((x:unknown)=>void)|null=null,buffer=Buffer.alloc(0),ended=false;
  const push=(x:unknown)=>{if(pending){const resolve=pending;pending=null;resolve(x);}else queue.push(x);};
  stream.on('data',(chunk:Buffer)=>{
    buffer=Buffer.concat([buffer,chunk]);
    for(;;){const index=buffer.indexOf(10);if(index<0)break;
      const row=buffer.subarray(0,index);buffer=buffer.subarray(index+1);
      if(row.length+1>LINE_LIMIT){push(new ExecutionFailure('oversized_line'));stream.pause();return;}
      const value=decode(row);push(value.ok?plain(value.v):new ExecutionFailure('malformed_line'));
    }
    if(buffer.length>=LINE_LIMIT){push(new ExecutionFailure('oversized_line'));stream.pause();}
  });
  stream.on('end',()=>{ended=true;if(buffer.length)push(new ExecutionFailure('malformed_line'));push(null);});
  stream.on('error',()=>push(new ExecutionFailure('early_exit')));
  return {next:async(timeout)=>{
    let timer:ReturnType<typeof setTimeout>|undefined;
    const item=queue.length?queue.shift():ended?null:await new Promise(resolve=>{pending=resolve;timer=setTimeout(()=>{pending=null;resolve(new ExecutionFailure('response_timeout'));},timeout);});
    if(timer)clearTimeout(timer);if(item instanceof Error)throw item;return item;
  }};
}
export function handshake(corpus:LoadedCorpus):Record<string,unknown> {
  return {protocol:'agent-blueprint-protocol-conformance-execution',version:1,corpus_digest:corpus.identity,registry_digest:memberString(corpus.index,'registry_digest')};
}
export async function serve(corpus:LoadedCorpus):Promise<number> {
  const reader=lines(process.stdin),hello=handshake(corpus);
  try {
    if(canonical(await reader.next(30_000))!==canonical(hello))return 2;
    process.stdout.write(canonical(hello)+'\n');
    for(;;){const request=await reader.next(30_000) as any;if(request===null)return 0;
      if(!request||Object.keys(request).sort().join(',')!=='id,input,surface'||typeof request.id!=='string'||typeof request.surface!=='string'||!request.input||typeof request.input!=='object'||Array.isArray(request.input))return 2;
      const input=decode(canonical(request.input));if(!input.ok)return 2;
      const row={id:request.id,surface:request.surface,input:input.v,expected:{t:'obj',v:[]}} as unknown as CaseObj;
      process.stdout.write(canonical({id:request.id,result:project(row,corpus.data,corpus.raws)})+'\n');
    }
  }catch{return 2;}
}
