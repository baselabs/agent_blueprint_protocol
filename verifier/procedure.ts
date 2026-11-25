// Procedure bindings are an import stage. A denial halts the import.
import { createHash } from 'node:crypto';
import type { Value } from './value.ts';
import { isValue } from './value.ts';
import { tagged, plain } from './plain.ts';
import { encode, verify as canonicalVerify } from './canonical.ts';
import type { Bounds } from './bounds.ts';
import { coerce } from './bounds.ts';
import { field, validate, type Spec, type Kind } from './registry_engine.ts';
import * as deployment from './deployment.ts';
import * as compatibility from './compatibility.ts';
import * as digest from './digest.ts';
import * as portability from './portability.ts';
import * as schemaValidator from './schema.ts';
import { HOST_OWNED } from './reconcile.ts';
import * as json from './decode.ts';
import { PROCEDURE_SCHEMA } from './procedure_schema.ts';

export const NAMESPACE='io.github.baselabs/procedure';
const FORMS=['artifact','build','configuration','service','environment'];
const BASES=['host_computed','operator_attested','host_configured','host_observed','holder_asserted'];
const ASSURANCE:Record<string,string>={host_computed:'measured',operator_attested:'attested',host_configured:'configured',host_observed:'observed',holder_asserted:'asserted'};
export const NOT_VERIFIED=['identity_validity','observer_trust','measurement_freshness','evidence_authenticity','holder_assertion_truth','configuration_execution','service_implementation'];
type Failure={ok:false;e:string;subject:(string|number)[]};
type Result<T>={ok:true;v:T}|Failure;
export interface ProcedureInputs {
  readonly inventory:{readonly builds:readonly compatibility.ObservedIdentity[];readonly instances:readonly Record<string,unknown>[];readonly manifest_digest:string;readonly attempt:string};
  readonly accepted_profiles:readonly string[];
  readonly attempt:string;
  readonly execution_boundary:string;
  readonly phase:'before_send'|'returned';
  readonly children:readonly (string|{readonly value:unknown})[];
  readonly documents:Readonly<Record<string,Value>>;
}
export interface ProcedureCheck {surface:'procedure'|'compatibility';subject:(string|number)[];verified:boolean;detail:any}
export interface ProcedureEvidence {
  protocol_revision:number;blueprint_digest:null;deployment_digest:string;checks:ProcedureCheck[];
  effective_bounds:null;clamps:never[];optional_extensions_retained:never[];not_verified:string[];
}
const failure=(e:string,subject:(string|number)[]=[]):Failure=>({ok:false,e,subject});
class Denial {readonly e:string;readonly subject:(string|number)[];constructor(e:string,subject:(string|number)[]=[]) {this.e=e;this.subject=subject;}}
function requireCheck(test:unknown,e:string,subject:(string|number)[]=[]):asserts test {if(!test)throw new Denial(e,subject);}
function checked<T extends {ok:true}|{ok:false;e:string;subject?:(string|number)[]}>(result:T): asserts result is Extract<T,{ok:true}> {
  if(!result.ok)throw new Denial(result.e,result.subject??[]);
}
function hash(value:unknown):string {
  const bytes=encode(tagged(value));if(!bytes.ok)throw new Denial(bytes.e);
  return 'sha-256:'+createHash('sha256').update(bytes.v).digest('base64url');
}
function digestOk(s:unknown):boolean{return typeof s==='string'&&digest.fromTagged(s).ok;}
const en=(values:string[]):Kind=>({enum:new Set(values)});
const objectKind=(members:Spec[]):Kind=>({object:{members}});
const id=(name:string,required=true):Spec=>field(name,'string',{required,check:v=>v.t==='str'&&Buffer.byteLength(v.v)<=512&&/^[a-z0-9][a-z0-9._/-]*$/.test(v.v)?{ok:true}:{ok:false,e:'invalid_constraint'}});
const dig=(name:string,required=true):Spec=>field(name,'string',{required,check:v=>v.t==='str'?digest.fromTagged(v.v):{ok:false,e:'invalid_type'}});
const arr=(name:string,kind:Kind,minItems:number,maxItems:number,required=true):Spec=>field(name,{array:{kind}},{required,minItems,maxItems});
const integer=(name:string):Spec=>field(name,'integer');
const obj=(name:string,members:Spec[],required=true):Spec=>field(name,objectKind(members),{required});
const timestamp=(name:string,required=true):Spec=>field(name,'string',{required,check:v=>v.t==='str'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(v.v)&&deployment.parseTimestamp(v.v)!==null?{ok:true}:{ok:false,e:'invalid_constraint'}});
function identity(v:Value):{ok:true}|{ok:false;e:string;subject?:(string|number)[]} {
  if(v.t!=='obj')return failure('invalid_type');
  const form=v.v.find(([k])=>k==='form')?.[1];
  const all=[dig('digest',false),id('name',false),dig('enrollment',false),dig('contract',false),dig('published',false)];
  const fields=form?.t==='str'&&FORMS.includes(form.v)?form.v==='build'?[id('name')]:form.v==='service'?[dig('enrollment'),dig('contract'),dig('published',false)]:[dig('digest')]:all;
  return validate([field('form',en(FORMS)),...fields],v);
}
function principal(v:Value):{ok:true}|Failure|{ok:false;e:string;subject?:(string|number)[]} {
  if(v.t!=='obj')return failure('invalid_type');
  const result=validate([dig('key',false),dig('enrollment',false)],v);if(!result.ok)return result;
  if(v.v.length===0)return failure('missing_required_field',['key']);
  return v.v.length===1?{ok:true}:failure('invalid_constraint');
}
function roleTable():Spec[]{return [id('role'),arr('forms',en(FORMS),1,5),arr('bases',en(BASES),1,5),integer('min'),integer('max'),field('schema','any',{required:false}),
  {...arr('exact','string',0,128,false),kind:{array:{...id('item'),name:undefined}}},
  {...arr('covers','string',0,16,false),kind:{array:{...id('item'),name:undefined}}},
  arr('relations',objectKind([id('relation'),id('target_role'),integer('min'),integer('max')]),0,16,false),
  field('evidence',en(['required','optional'])),field('principal',en(['required','optional','forbidden'])),field('validity',en(['required','optional']))];}
function instanceTable():Spec[]{return [id('id'),id('role'),field('identity','custom',{check:identity}),
  obj('provenance',[field('basis',en(BASES)),dig('evidence',false),field('principal','custom',{required:false,check:principal}),obj('validity',[timestamp('not_before'),timestamp('not_after',false)],false)]),
  arr('binds',objectKind([id('relation'),id('target')]),0,16,false)];}
export function table():Spec[]{return [obj('profile',[id('profile_id'),arr('roles',objectKind(roleTable()),1,128),obj('composition',[integer('min'),integer('max'),{...arr('member_profiles','string',1,128),kind:{array:{...dig('item'),name:undefined}}}],false)]),
  arr('instances',objectKind(instanceTable()),1,256),obj('composition',[arr('members',objectKind([id('id'),dig('deployment_digest')]),1,64)],false)];}
export function schema():Value{return tagged(PROCEDURE_SCHEMA);}
export function decode(value:Value|string,bounds?:Bounds|Record<string,unknown>):Result<{value:Value}>{
  const normalized=coerce(bounds===undefined?{}:bounds);if(!normalized.ok)return failure(normalized.e);
  if(typeof value==='string'){const parsed=canonicalVerify(value,normalized.v);if(!parsed.ok)return failure(parsed.e);value=parsed.v;}
  const encoded=encode(value,normalized.v);if(!encoded.ok)return failure(encoded.e);
  const valid=validate(table(),value);if(!valid.ok)return failure(valid.e,valid.subject??[]);
  const portable=portability.scan(value);if(!portable.ok)return failure(portable.e);
  return {ok:true,v:{value}};
}
export function documentCommitment(document:Value):Result<string>{
  if(!isValue(document)||document.t!=='obj')return failure('invalid_type',['document']);
  const bytes=encode(document);if(!bytes.ok)return failure(bytes.e);
  const doc=plain(document);
  if(typeof doc.type!=='string'||!doc.type)return failure('invalid_constraint',['type']);
  if(typeof doc.nonce!=='string'||!(/^[0-9a-f]{64}$/.test(doc.nonce)||(/^[A-Za-z0-9_-]{43}$/.test(doc.nonce)&&Buffer.from(doc.nonce,'base64url').toString('base64url')===doc.nonce)))return failure('invalid_constraint',['nonce']);
  return {ok:true,v:'sha-256:'+createHash('sha256').update(bytes.v).digest('base64url')};
}
function unique(xs:unknown[]):boolean{return new Set(xs.map(hash)).size===xs.length;}
function bounds(rule:any,max:number):boolean{return Number.isInteger(rule.min)&&Number.isInteger(rule.max)&&rule.min>=0&&rule.max>=rule.min&&rule.max<=max;}
function acyclic(graph:Map<string,string[]>):boolean {
  const done=new Set<string>(),active=new Set<string>();
  const visit=(node:string):boolean=>{if(active.has(node))return false;if(done.has(node))return true;active.add(node);if(!(graph.get(node)??[]).every(visit))return false;active.delete(node);done.add(node);return true;};
  return [...graph.keys()].every(visit);
}
function totalSchema(s:any):boolean {
  if(!s||typeof s!=='object')return true;
  const object=(Array.isArray(s.type)?s.type.includes('object'):s.type==='object')||['properties','required','additionalProperties'].some(k=>Object.hasOwn(s,k));
  return ((!object)||(s.additionalProperties===false&&JSON.stringify(Object.keys(s.properties??{}).sort())===JSON.stringify([...(s.required??[])].sort())))&&
    Object.values(s.properties??{}).every(totalSchema)&&(s.oneOf??[]).every(totalSchema)&&(!s.items||totalSchema(s.items))&&Object.values(s.$defs??{}).every(totalSchema);
}
function configurationSchema(s:any,root=s):boolean {
  if(s&&typeof s==='object'&&typeof s.$ref==='string') {
    const target=s.$ref.slice(2).split('/').reduce((v:any,k:string)=>v?.[k.replace(/~1/g,'/').replace(/~0/g,'~')],root);
    return configurationSchema(target,root);
  }
  return s?.type==='object'&&s.additionalProperties===false&&JSON.stringify(Object.keys(s.properties??{}).sort())===JSON.stringify([...(s.required??[])].sort());
}
function profileCheck(profile:any,accepted:readonly string[]):void {
  const names=profile.roles.map((r:any)=>r.role);
  requireCheck(unique(names)&&accepted.includes(hash(profile)),'invalid_constraint',['profile']);
  for(const r of profile.roles){
    const path=['profile',r.role];
    requireCheck(bounds(r,256)&&unique(r.forms)&&unique(r.bases),'invalid_constraint',path);
    requireCheck(unique((r.relations??[]).map((x:any)=>x.relation))&&(r.covers??[]).every((x:string)=>names.includes(x)&&x!==r.role)&&unique(r.covers??[])&&unique(r.exact??[]),'invalid_constraint',path);
    for(const relation of r.relations??[])requireCheck(bounds(relation,16)&&names.includes(relation.target_role),'invalid_constraint',[...path,'relations']);
    if(Object.hasOwn(r,'schema')){checked(schemaValidator.parse(tagged(r.schema),schemaValidator.dialect()));requireCheck(totalSchema(r.schema)&&(!r.forms.includes('configuration')||configurationSchema(r.schema)),'invalid_constraint',[...path,'schema']);}
    else requireCheck((r.exact??[]).length===0&&!r.forms.includes('configuration'),'invalid_constraint',[...path,'schema']);
  }
  requireCheck(acyclic(new Map(profile.roles.map((r:any)=>[r.role,r.covers??[]]))),'invalid_constraint',['profile','covers']);
  if(profile.composition)requireCheck(bounds(profile.composition,64)&&unique(profile.composition.member_profiles),'invalid_constraint',['profile','composition']);
}
function declarationCheck(body:any,dep:deployment.Deployment):void {
  const instances=body.instances as any[],roles=new Map<string,any>(body.profile.roles.map((r:any)=>[r.role,r])),ids=new Map<string,any>(instances.map(i=>[i.id,i]));
  const builds=plain(dep.value).build_identities as any[];
  requireCheck(Array.isArray(builds)&&builds.every(b=>b&&typeof b==='object'&&!Array.isArray(b)),'invalid_type',['build_identities']);
  requireCheck(ids.size===instances.length&&unique(instances.map(i=>[i.role,i.identity])),'invalid_constraint',['instances']);
  for(const i of instances){
    const r=roles.get(i.role),p=i.provenance,binds=i.binds??[],path=['instances',i.id];
    requireCheck(r,'invalid_constraint',[...path,'role']);
    requireCheck(r.forms.includes(i.identity.form)&&r.bases.includes(p.basis),'invalid_constraint',path);
    requireCheck(['evidence','principal','validity'].every(k=>r[k]!=='required'||Object.hasOwn(p,k))&&(r.principal!=='forbidden'||!Object.hasOwn(p,'principal')),'invalid_constraint',[...path,'provenance']);
    requireCheck(i.identity.form!=='build'||builds.filter(b=>b.name===i.identity.name).length===1,'invalid_constraint',[...path,'identity']);
    requireCheck(unique(binds),'invalid_constraint',[...path,'binds']);
    for(const b of binds){
      const target=ids.get(b.target),relation=(r.relations??[]).find((r:any)=>r.relation===b.relation);
      const covered=b.relation==='part_of'&&target&&(roles.get(target.role)?.covers??[]).includes(i.role);
      requireCheck(target&&(covered||(relation&&relation.target_role===target.role)),'invalid_constraint',[...path,'binds']);
    }
    requireCheck(![...roles.values()].some(r=>(r.covers??[]).includes(i.role))||binds.some((b:any)=>b.relation==='part_of'&&(roles.get(ids.get(b.target)?.role)?.covers??[]).includes(i.role)),'invalid_constraint',[...path,'binds']);
    for(const relation of r.relations??[]){const n=binds.filter((b:any)=>b.relation===relation.relation).length;requireCheck(n>=relation.min&&n<=relation.max,'invalid_constraint',[...path,'binds']);}
  }
  for(const r of roles.values()){const n=instances.filter(i=>i.role===r.role).length;requireCheck(n>=r.min&&n<=r.max,'invalid_cardinality',['instances',r.role]);}
  requireCheck(acyclic(new Map(instances.map(i=>[i.id,(i.binds??[]).map((b:any)=>b.target)]))),'invalid_constraint',['instances','binds']);
  const members=body.composition?.members??[],r=body.profile.composition;
  requireCheck(unique(members.map((m:any)=>m.id))&&((!r&&members.length===0)||(r&&members.length>=r.min&&members.length<=r.max)),'invalid_constraint',['composition']);
}
function documentsCheck(body:any,documents:Readonly<Record<string,Value>>):void {
  const roles=new Map<string,any>(body.profile.roles.map((r:any)=>[r.role,r]));
  for(const i of body.instances){
    const ident=i.identity;
    const refs:[string,string][]=ident.form==='configuration'||ident.form==='environment'?[[ident.digest,ident.form]]:ident.form==='service'?[[ident.enrollment,'enrollment'],[ident.contract,'contract']]:[];
    if(i.provenance.principal?.enrollment)refs.push([i.provenance.principal.enrollment,'principal-enrollment']);
    for(const [d,type] of refs){
      const path=['documents',d];requireCheck(Object.hasOwn(documents,d),'binding_incomplete',path);
      const computed=documentCommitment(documents[d]!);if(!computed.ok)throw new Denial(computed.e,[...path,...computed.subject]);
      requireCheck(computed.v===d,'binding_incomplete',path);
      const doc=plain(documents[d]!);requireCheck(doc.type==='agent-blueprint-protocol/procedure-'+type,'invalid_constraint',[...path,'type']);
      if(type==='principal-enrollment')continue;
      const role=roles.get(i.role);
      if(Object.hasOwn(role,'schema')){const r=schemaValidator.validateInstance(tagged(role.schema),documents[d]!,schemaValidator.dialect());if(!r.ok)throw new Denial('invalid_constraint',path);}
      for(const name of role.exact??[])requireCheck(compatibility.exact({version:doc[name]}),'invalid_constraint',[...path,name]);
    }
  }
}
function bodyOf(dep:deployment.Deployment):Value {
  const value=plain(dep.value),body=value.extensions?.critical?.[NAMESPACE];
  requireCheck(body!==undefined,'missing_required_field',['extensions','critical',NAMESPACE]);
  return tagged(body);
}
function childrenCheck(dep:deployment.Deployment,body:any,inputs:ProcedureInputs):ProcedureCheck[]{
  // Index content without decoding a Deployment. Only a referenced entry is validated.
  const children=new Map<string,(deployment.Deployment|string)[]>();
  for(const child of inputs.children){
    let value:Value;
    try {
      const parsed=typeof child==='string'?json.decode(child):null;
      const supplied=typeof child==='string'?(parsed?.ok?parsed.v:null):child?.value;
      value=isValue(supplied)?supplied:tagged(supplied);
    }catch{continue;}
    if(value.t!=='obj')continue;
    const key=deployment.contentDigest({value});if(typeof key!=='string')continue;
    children.set(key,[...(children.get(key)??[]),typeof child==='string'?child:{value}]);
  }
  const root=deployment.contentDigest(dep) as string;
  const cache=new Map<string,{profileDigest:string;height:number}>([[root,{profileDigest:hash(body.profile),height:0}]]);
  const walk=(b:any,path:string[],depth:number):ProcedureCheck[]=>{
    const checks:ProcedureCheck[]=[];
    for(const m of b.composition?.members??[]){
      const d=m.deployment_digest;requireCheck(depth<8&&!path.includes(d),'invalid_constraint',['composition']);
      let entry=cache.get(d),nested:ProcedureCheck[]=[];
      if(entry){
        requireCheck(b.profile.composition.member_profiles.includes(entry.profileDigest),'invalid_constraint',['profile']);
        requireCheck(depth+entry.height<=8,'invalid_constraint',['composition']);
      }else{
        const candidates=children.get(d);requireCheck(candidates,'binding_incomplete',['composition',m.id]);
        requireCheck(candidates.length===1,'invalid_constraint',['children']);
        const child=candidates[0]!;
        const encoded=typeof child==='string'?{ok:true as const,v:child}:deployment.canonicalBytes(child);
        checked(encoded);
        const decoded=deployment.decode(encoded.v);
        checked(decoded);
        const parsed=decode(bodyOf(decoded.v));
        checked(parsed);
        const cb=plain(parsed.v.value);profileCheck(cb.profile,b.profile.composition.member_profiles);
        declarationCheck(cb,decoded.v);documentsCheck(cb,inputs.documents);
        entry={profileDigest:hash(cb.profile),height:0};cache.set(d,entry);
        nested=walk(cb,[...path,d],depth+1);
        entry.height=1+Math.max(0,...(cb.composition?.members??[]).map((m:any)=>cache.get(m.deployment_digest)!.height));
      }
      checks.push(check(['composition',path[path.length-1]!,m.id],{deployment_digest:d}),...nested);
    }
    return checks;
  };
  return walk(body,[root],1);
}
function firstDifference(a:any,b:any):string[]{
  if(a&&b&&typeof a==='object'&&typeof b==='object'&&!Array.isArray(a)&&!Array.isArray(b)){
    for(const name of [...new Set([...Object.keys(a),...Object.keys(b)])].sort((a,b)=>Buffer.compare(Buffer.from(a),Buffer.from(b)))){
      if(!Object.hasOwn(a,name)||!Object.hasOwn(b,name))return [name];
      if(hash(a[name])!==hash(b[name]))return [name,...firstDifference(a[name],b[name])];
    }
  }
  return [];
}
function instanceChecked(inst:any,body:any):string[]{
  const role=body.profile.roles.find((r:any)=>r.role===inst.role);
  const documents=['configuration','environment','service'].includes(inst.identity.form)||!!inst.provenance.principal?.enrollment;
  const relations=(role.relations??[]).length>0||(inst.binds??[]).length>0||body.profile.roles.some((r:any)=>(r.covers??[]).includes(inst.role));
  return ['declaration',...(documents?['documents']:[]),'pairing',...(relations?['relations']:[])];
}
function check(subject:(string|number)[],detail:any):ProcedureCheck{return {surface:'procedure',subject,verified:true,detail:{profile_digest:null,attempt:null,execution_boundary:null,phase:null,basis:null,assurance:null,validity:null,deployment_digest:null,checked:[],...detail}};}
export function verify(dep:deployment.Deployment,inputs:ProcedureInputs):Result<ProcedureEvidence>{
  try {
    requireCheck(dep && isValue(dep.value) && inputs && typeof inputs==='object','invalid_type');
    const inventory=inputs.inventory;
    requireCheck(
      inventory && Array.isArray(inventory.builds) &&
      Array.isArray(inventory.instances) && inventory.instances.length<=1024 &&
      Array.from(inventory.instances).every(x=>x && typeof x==='object' && !Array.isArray(x)) &&
      Array.isArray(inputs.children) && inputs.children.length<=255 &&
      inputs.documents && typeof inputs.documents==='object' && !Array.isArray(inputs.documents) &&
      Object.keys(inputs.documents).length<=1024 &&
      Array.isArray(inputs.accepted_profiles) && inputs.accepted_profiles.length<=256 &&
      Array.from(inputs.accepted_profiles).every(digestOk) &&
      [inputs.attempt,inputs.execution_boundary,inventory.manifest_digest,inventory.attempt].every(digestOk) &&
      ['before_send','returned'].includes(inputs.phase),
      'invalid_type',['inputs']
    );
    checked(deployment.verifyContentDigest(dep));
    const decoded=decode(bodyOf(dep));
    checked(decoded);
    const body=plain(decoded.v.value);
    profileCheck(body.profile,inputs.accepted_profiles);
    declarationCheck(body,dep);
    documentsCheck(body,inputs.documents);

    const compatible=compatibility.verify(dep,{identities:[...inventory.builds]});
    checked(compatible);
    const members=childrenCheck(dep,body,inputs);
    const manifest=deployment.contentDigest(dep) as string;
    requireCheck(inventory.manifest_digest===manifest && inventory.attempt===inputs.attempt,
      'binding_incomplete',['inventory']);
    requireCheck(inventory.instances.length===body.instances.length,
      'binding_incomplete',['inventory','instances']);
    for(const inst of body.instances){
      const matches=inventory.instances.filter(observation=>observation.id===inst.id);
      const path=['inventory','instances',inst.id];
      requireCheck(matches.length===1,'binding_incomplete',path);
      requireCheck(hash(matches[0])===hash(inst),'binding_incomplete',[...path,...firstDifference(inst,matches[0])]);
    }

    const instanceChecks=body.instances.map((inst:any)=>check(['instances',inst.id],{
      basis:inst.provenance.basis,
      assurance:ASSURANCE[inst.provenance.basis],
      validity:inst.provenance.validity??null,
      checked:instanceChecked(inst,body),
    }));
    const binding=check([],{
      profile_digest:hash(body.profile),
      attempt:inputs.attempt,
      execution_boundary:inputs.execution_boundary,
      phase:inputs.phase,
    });
    return {ok:true,v:{
      protocol_revision:1,
      blueprint_digest:null,
      deployment_digest:manifest,
      checks:[binding,...instanceChecks,...members,...compatible.checks],
      effective_bounds:null,
      clamps:[],
      optional_extensions_retained:[],
      not_verified:[...HOST_OWNED,...NOT_VERIFIED],
    }};
  }catch(e){
    return e instanceof Denial?failure(e.e,e.subject):failure('invalid_type');
  }
}
