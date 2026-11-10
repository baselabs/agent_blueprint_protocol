import * as blueprint from './blueprint.ts';
import * as deployment from './deployment.ts';
import * as negotiation from './negotiation.ts';
import * as algebra from './bounds_algebra.ts';
import * as signature from './signature.ts';
import * as digest from './digest.ts';
import { validate } from './registry_engine.ts';
import { member,memberString } from './corpus.ts';
import { plain,jsonValue } from './plain.ts';
import { isValue,type Value } from './value.ts';

type Failure={ok:false;e:string;subject?: (string|number)[]};
export interface Inputs {
  hostBounds:Record<string,unknown>;
  support:negotiation.Support;
  keys:signature.PublicKey[];
  protectedClamp:'deny'|'acknowledge';
  observations:deployment.Observations;
}
export interface Check {surface:string;subject:(string|number)[];verified:boolean;detail:unknown}
export interface Evidence {
  protocol_revision:number;blueprint_digest:string;deployment_digest:string;
  checks:Check[];effective_bounds:Record<string,unknown>;clamps:unknown[];
  optional_extensions_retained:string[];not_verified:string[];
}
const HOST_OWNED=['tenancy','live_policy','authority','effect_ownership','execution','billing','evaluation_truth'];
const CLASSIFICATION=['public','internal','confidential','restricted'];
function failure(e:string,subject:(string|number)[]=[]):Failure{return {ok:false,e,subject};}
function lift(bp:blueprint.Blueprint):Record<string,unknown> {
  const b=plain(bp.value);
  const sites=[b.classification_ceiling,b.output_contract.classification_ceiling,...b.input_ports.map((p:any)=>p.classification_ceiling),...b.output_ports.map((p:any)=>p.classification_ceiling),...b.capability_requirements.map((p:any)=>p.classification_ceiling)];
  const strongest=(values:string[],order:string[])=>order[Math.max(0,...values.map(x=>order.indexOf(x)))];
  return {...b.ceilings,classification_ceiling:{ordinal:strongest(sites,CLASSIFICATION),markers:[]},disclosure_ceiling:'full',approval_trait:strongest(b.capability_requirements.map((x:any)=>x.approval_trait),['none','human_required','separated_human_required']),authority_trait:strongest(b.capability_requirements.map((x:any)=>x.authority_trait),['none','local_policy','external_authority_required']),effect_impact_ceiling:strongest([...b.capability_requirements,...b.effect_intents].map((x:any)=>x.impact_class),['ordinary','money','authority','secret'])};
}
export function reconcile(bp:blueprint.Blueprint,dep:deployment.Deployment,inputs:Inputs):{ok:true;v:Evidence}|Failure {
  if(!bp||!isValue(bp.value))return failure('invalid_type',['blueprint']);
  if(!dep||!isValue(dep.value))return failure('invalid_type',['deployment']);
  if(!inputs||typeof inputs!=='object')return failure('invalid_type',['inputs']);
  for(const key of ['support','observations','hostBounds'] as const)if(!inputs[key]||typeof inputs[key]!=='object')return failure('invalid_type',['inputs',key==='hostBounds'?'host_bounds':key]);
  if(!Array.isArray(inputs.keys))return failure('invalid_type',['inputs','keys']);
  for(let i=0;i<inputs.keys.length;i++)if(!inputs.keys[i]||typeof inputs.keys[i]!=='object')return failure('invalid_type',['inputs','keys',i]);
  if(!['deny','acknowledge'].includes(inputs.protectedClamp))return failure('invalid_type',['inputs','protected_clamp']);
  const checks:Check[]=[];
  const checked=(surface:string,subject:string,verified=true,detail:unknown=null)=>checks.push({surface,subject:[subject],verified,detail});
  const artifacts=[['blueprint',bp,blueprint],['deployment',dep,deployment]] as const;
  // Stage order is part of the verification contract.
  for(const [name,artifact,mod] of artifacts) {
    if(artifact.value.t!=='obj')return failure('invalid_type',[name]);
    const result=mod.canonicalBytes(artifact); // stage: canonical
    if(!result.ok)return failure(result.e,[name]);
    checked('canonical',name);
  }
  for(const [name,artifact,mod] of artifacts) {
    const result=mod.verifyContentDigest(artifact); // stage: digest
    if(!result.ok)return failure(result.e,[name]);
    checked('digest',name,true,mod.contentDigest(artifact));
  }
  const outcomes:negotiation.Outcome[]=[];
  for(const [name,artifact] of artifacts) {
    const result=negotiation.negotiate(artifact.value,inputs.support); // stage: negotiation
    if(!result.ok)return failure(result.e,[name,...(result.e==='protocol_revision_unsupported'?['protocol_revision']:result.e==='required_core_field_unsupported'||result.e==='required_core_field_not_digest_covered'?['required_core_fields']:[])]);
    outcomes.push(result.v);checked('negotiation',name);
  }
  for(const outcome of outcomes) {
    for(const ns of outcome.quarantinedExtensions)checked('extensions',ns,false,'quarantined');
    for(const ns of outcome.optionalRetained)checked('extensions',ns,false,'retained');
  }
  for(const [name,artifact,mod] of artifacts) {
    const result=validate(mod.table(),artifact.value); // stage: structure
    if(!result.ok)return failure(result.e,[name,...(result.subject??[])]);
    checked('structure',name);
  }
  for(let i=0;i<artifacts.length;i++) {
    const [name,artifact,mod]=artifacts[i]!;
    const result=mod.scan(artifact.value,new Set(outcomes[i]!.criticalExtensions)); // stage: portability
    if(!result.ok)return failure(result.e,[name]);
    checked('portability',name);
  }
  for(const [name,artifact,mod] of artifacts) {
    const entries=member(artifact.value,'signatures');
    const signatures=entries?.t==='arr'?entries.v:[];
    for(let i=0;i<signatures.length;i++) {
      const result=signature.verify(signatures[i]!,inputs.keys); // stage: signatures
      if(!result.ok)return failure(result.e,[name,'signatures',i,...(result.subject??[])]);
      if(digest.toTagged(result.v.contentDigest)!==mod.contentDigest(artifact))return failure('digest_mismatch',[name,'signatures',i]);
    }
    checked('signatures',name,signatures.length>0,signatures.length?{key_ids:[...new Set(signatures.map(x=>{const a=signature.attributes(x);if(!a.ok)throw Error('signature invariant');return a.v.keyId;}))]}:'no_signatures_present');
  }
  const binding=deployment.verifyBinding(dep,bp,inputs.observations); // stage: bind
  if(!binding.ok)return failure(binding.e,['deployment',...(binding.subject??[])]);
  const bindings=member(dep.value,'tool_bindings') as Value & {t:'arr'};
  const names=bindings.v.map(x=>memberString(x,'logical_operation')!);
  const staleness=names.length>0&&inputs.observations.now!==null&&inputs.observations.maxAttestationAgeMs!==null;
  const descriptors=names.length>0&&names.every(x=>Object.hasOwn(inputs.observations.observed,x));
  const extra=[['binding_staleness',staleness],['binding_descriptors',descriptors]] as const;
  const skipped=extra.filter(x=>!x[1]).map(x=>x[0]);
  checked('bind','deployment',skipped.length===0,{checked:['release_binding','binding_completeness','effect_recovery',...extra.filter(x=>x[1]).map(x=>x[0])],not_verified:skipped});
  const depBounds=plain(member(dep.value,'host_bounds')!);
  depBounds.classification_ceiling={ordinal:depBounds.classification_ceiling,markers:[]};
  const bounds=algebra.intersect(lift(bp),depBounds,inputs.hostBounds,inputs.protectedClamp); // stage: bounds
  if(!bounds.ok)return failure(bounds.e,bounds.subject??[]);
  checked('bounds','bounds');
  const clamps=jsonValue(bounds.v.clamps.map(c=>({field:c.field,class:c.cls,unit:c.cls==='protected'?'ordinal':c.field==='max_cost'?'money':c.field==='max_elapsed_ms'?'millisecond':c.field==='max_tokens'?'token':'count',requested:c.requested,effective:c.effective,source:c.source,acknowledged:c.acknowledged}))).map((c:any)=>{delete c.cls;return c;});
  for(const clamp of clamps)checked('bounds',clamp.field,true,clamp);
  return {ok:true,v:{protocol_revision:plain(member(bp.value,'protocol_revision')!),blueprint_digest:blueprint.contentDigest(bp) as string,deployment_digest:deployment.contentDigest(dep) as string,checks,effective_bounds:bounds.v.effective,clamps,optional_extensions_retained:[...new Set(outcomes.flatMap(o=>o.optionalRetained))],not_verified:[...new Set([...HOST_OWNED,'signature_created_at','lifecycle_state','key_time_validity','signature_time_validity',...checks.flatMap(c=>c.verified?[]:[c.surface]),...skipped])]}};
}
