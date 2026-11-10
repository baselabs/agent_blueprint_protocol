import { encode } from './canonical.ts';
import { tagged } from './plain.ts';
import { project } from './runner.ts';
import { memberString,type LoadedCorpus } from './corpus.ts';
export function canonical(value:unknown):string {
  const result=encode(tagged(value));if(!result.ok)throw new TypeError(result.e);return result.v;
}
export function resultsDocument(corpus:LoadedCorpus):Record<string,unknown> {
  return {format:'agent-blueprint-protocol-conformance-results',corpus_digest:corpus.identity,registry_digest:memberString(corpus.index,'registry_digest'),results:corpus.cases.flatMap(f=>f.cases).sort((a,b)=>Buffer.compare(Buffer.from(a.id),Buffer.from(b.id))).map(c=>({id:c.id,surface:c.surface,result:project(c,corpus.data,corpus.raws)}))};
}
