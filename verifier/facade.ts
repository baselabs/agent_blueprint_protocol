import type { ErrorCode } from './errors.ts';
import * as bp from './blueprint.ts';
import * as dep from './deployment.ts';
import * as fed from './federation.ts';
import * as neg from './negotiation.ts';
import * as alg from './bounds_algebra.ts';
import * as sig from './signature.ts';
import * as compat from './compatibility.ts';
import * as imports from './reconcile.ts';
import * as corpus from './corpus.ts';
import * as runner from './runner.ts';
import * as report from './report.ts';
import { resultsDocument,canonical } from './results.ts';
import { tagged,plain,jsonValue } from './plain.ts';
import { rows } from './mapping.ts';
import { toTagged } from './digest.ts';

/** Known output identifiers; future values remain valid strings throughout 1.x. */
export const KNOWN_NOTICES=Object.freeze({clamp_applied:'clamp_applied',extension_deprecated:'extension_deprecated',extension_retired:'extension_retired',extension_unknown_optional_retained:'extension_unknown_optional_retained'} as const);
export type KnownNotice=typeof KNOWN_NOTICES[keyof typeof KNOWN_NOTICES];
export type Notice=KnownNotice|(string & {});
/** Known evidence surfaces, never an exhaustive proof checklist. */
export const KNOWN_EVIDENCE_SURFACES=Object.freeze({canonical:'canonical',digest:'digest',negotiation:'negotiation',structure:'structure',portability:'portability',signatures:'signatures',extensions:'extensions',bind:'bind',bounds:'bounds',compatibility:'compatibility',tenancy:'tenancy',live_policy:'live_policy',authority:'authority',effect_ownership:'effect_ownership',execution:'execution',billing:'billing',evaluation_truth:'evaluation_truth',signature_created_at:'signature_created_at',lifecycle_state:'lifecycle_state',binding_descriptors:'binding_descriptors',binding_staleness:'binding_staleness'} as const);
export type KnownEvidenceSurface=typeof KNOWN_EVIDENCE_SURFACES[keyof typeof KNOWN_EVIDENCE_SURFACES];
export type EvidenceSurface=KnownEvidenceSurface|(string & {});
/** Known binding check kinds; unknown kinds establish no familiar check. */
export const KNOWN_EVIDENCE_CHECK_KINDS=Object.freeze({release_binding:'release_binding',binding_completeness:'binding_completeness',effect_recovery:'effect_recovery',binding_descriptors:'binding_descriptors',binding_staleness:'binding_staleness'} as const);
export type KnownEvidenceCheckKind=typeof KNOWN_EVIDENCE_CHECK_KINDS[keyof typeof KNOWN_EVIDENCE_CHECK_KINDS];
export type EvidenceCheckKind=KnownEvidenceCheckKind|(string & {});
/** Known returned signature identifiers; verification inputs retain their strict types. */
export const KNOWN_SIGNATURE_ALGORITHMS=Object.freeze({ed25519:'Ed25519'} as const);
export type KnownSignatureAlgorithm=typeof KNOWN_SIGNATURE_ALGORITHMS[keyof typeof KNOWN_SIGNATURE_ALGORITHMS];
export type SignatureAlgorithm=KnownSignatureAlgorithm|(string & {});
export const KNOWN_SIGNATURE_PURPOSES=Object.freeze({blueprint:'blueprint',deployment:'deployment',federation_envelope:'federation-envelope'} as const);
export type KnownSignaturePurpose=typeof KNOWN_SIGNATURE_PURPOSES[keyof typeof KNOWN_SIGNATURE_PURPOSES];
export type SignaturePurpose=KnownSignaturePurpose|(string & {});
/** A JSON value without runtime-specific types. */
export type JsonValue=null|boolean|number|string|readonly JsonValue[]|{readonly [key:string]:JsonValue};
/** A closed denial and its value-free member path. */
export interface ProtocolError {readonly code:ErrorCode;readonly subject:readonly (string|number)[]}
/** Every public operation returns a success value or a typed denial. */
export type Result<T>={readonly ok:true;readonly value:T}|{readonly ok:false;readonly error:ProtocolError};
/** Tighten-only decoder ceilings; omission uses the protocol maximum. */
export interface Bounds {readonly bytes?:number;readonly depth?:number;readonly members?:number;readonly items?:number;readonly nodes?:number;readonly string?:number;readonly key?:number;readonly number_lexeme?:number}
/** Names of the eight tighten-only decoder ceilings. */
export type CeilingKey=keyof Bounds;
/** Decode options. */
export interface DecodeOptions {readonly bounds?:Bounds}
/** A read-only artifact view; canonical bytes and digest identify its value. */
export interface Artifact {readonly kind:'blueprint'|'deployment'|'federation';readonly value:{readonly [key:string]:JsonValue};readonly canonicalBytes:Uint8Array;readonly contentDigest:string|null}
/** A decoded Blueprint Core. */
export type Blueprint=Artifact & {readonly kind:'blueprint';readonly contentDigest:string};
/** A decoded Deployment Manifest. */
export type Deployment=Artifact & {readonly kind:'deployment';readonly contentDigest:string};
/** A decoded federation TaskEnvelope. */
export type FederationEnvelope=Artifact & {readonly kind:'federation'};
/** Raw Ed25519 public key supplied by the caller. */
export interface PublicKey {readonly keyId:string;readonly algorithm:'ed25519';readonly key:Uint8Array}
/** Negotiation support with host registrations and held schema documents. Compiled entries preserve their criticality and schema pins. */
export interface Support {readonly revisions:ReadonlySet<number>;readonly coreFields:ReadonlySet<string>;readonly registry:Readonly<Record<string,{readonly owner:string;readonly criticality:'critical'|'optional';readonly state:'reserved'|'active'|'deprecated'|'retired';readonly schemaDigest:string|null;readonly a2aUri:string|null;readonly promotedAtRevision:number|null}>>;readonly schemas:Readonly<Record<string,JsonValue>>}
/** An ordinal classification and its retained regulatory markers. */
export interface Classification {readonly ordinal:'public'|'internal'|'confidential'|'restricted';readonly markers:readonly ('pci'|'phi')[]}
/** An integer count of millionths of one unit of the named ISO 4217 currency. */
export interface Cost {readonly amount:number;readonly currency:string}
/** The closed operational and protected bound vocabulary. */
export interface BoundSet {readonly max_attempts?:number;readonly max_concurrency?:number;readonly max_cost?:Cost;readonly max_depth?:number;readonly max_descendants?:number;readonly max_elapsed_ms?:number;readonly max_fan_out?:number;readonly max_tokens?:number;readonly classification_ceiling?:Classification;readonly disclosure_ceiling?:'none'|'summary'|'detail'|'full';readonly effect_impact_ceiling?:'ordinary'|'money'|'authority'|'secret';readonly authority_trait?:'none'|'local_policy'|'external_authority_required';readonly approval_trait?:'none'|'human_required'|'separated_human_required'}
/** Three bound sources and the protected narrowing posture. */
export interface Sources {readonly blueprint:BoundSet;readonly deployment:BoundSet;readonly host:BoundSet;readonly protectedClamp?:'deny'|'acknowledge'}
/** Descriptor and freshness observations; null leaves a check unverified. */
export interface Observations {readonly now:string|null;readonly maxAttestationAgeMs:number|null;readonly observed:Readonly<Record<string,string>>}
/** Exact observed build identities. */
export interface Observed {readonly identities:readonly {readonly kind:string;readonly name:string;readonly version:string;readonly digest:string}[]}
/** The inputs for the eight-stage non-authorizing import pass. */
export interface Inputs {readonly hostBounds:BoundSet;readonly support:Support;readonly keys:readonly PublicKey[];readonly protectedClamp:'deny'|'acknowledge';readonly observations:Observations}
/** Receiving context for existing federation receipt verification. */
/** Verified signed attributes, including the digest and purpose. */
export interface SignedAttributes {readonly algorithm:SignatureAlgorithm;readonly contentDigest:string;readonly createdAt:string;readonly keyId:string;readonly purpose:SignaturePurpose}
/** Negotiated extension facts. */
export interface Negotiated {readonly protocolRevision:number;readonly criticalExtensions:readonly string[];readonly quarantinedExtensions:readonly string[];readonly optionalRetained:readonly string[];readonly notices:readonly Notice[]}
/** A clamp records the requested and effective values and narrowing source. */
export interface Clamp {readonly field:keyof BoundSet;readonly class:'operational'|'protected';readonly unit:'count'|'millisecond'|'token'|'money'|'ordinal';readonly requested:JsonValue;readonly effective:JsonValue;readonly source:'deployment'|'host';readonly acknowledged:boolean}
/** Pointwise effective bounds and their clamp evidence. */
export interface Intersection {readonly effective:BoundSet;readonly clamps:readonly Clamp[]}
/** One performed or explicitly unverified check. */
export interface Check {readonly surface:EvidenceSurface;readonly subject:readonly (string|number)[];readonly verified:boolean;readonly detail:JsonValue}
/** Typed import evidence; its unverified surfaces never form an empty set. */
export interface Evidence {readonly protocol_revision:number|null;readonly blueprint_digest:string|null;readonly deployment_digest:string|null;readonly checks:readonly Check[];readonly effective_bounds:BoundSet|null;readonly clamps:readonly Clamp[];readonly optional_extensions_retained:readonly string[];readonly not_verified:readonly EvidenceSurface[]}
/** One transport mapping row, returned as inert data. */
export interface MappingRow {readonly index:number;readonly logical_field:string;readonly a2a_location:string;readonly mcp_location:string;readonly verdict:'native'|'partial'|'extension'}
/** An integrity-checked, in-memory corpus handle. */
export interface Corpus {readonly identity:string;readonly totalCases:number}
/** A per-case verdict agreement. */
export interface CaseResult {readonly caseId:string;readonly agree:boolean}
/** An aggregate conformance summary. */
export interface Report {readonly format:'agent-blueprint-protocol-conformance-report';readonly corpus_digest:string;readonly total:number;readonly agreed:number;readonly disagreed:number;readonly agreement:boolean;readonly exit_status:0|1}
/** An identity-free, per-case results document. */
export interface ResultsDocument {readonly format:'agent-blueprint-protocol-conformance-results';readonly corpus_digest:string;readonly registry_digest:string;readonly results:readonly {readonly id:string;readonly surface:string;readonly result:Readonly<Record<string,JsonValue>>}[]}

const handles=new WeakMap<Corpus,corpus.LoadedCorpus>();
function guarded<T>(f:()=>any):Result<T> {try {const r=f();return r?.ok===false?{ok:false,error:{code:r.e as ErrorCode,subject:r.subject??[]}}:{ok:true,value:(r?.ok===true&&Object.hasOwn(r,'v')?r.v:r) as T};}catch{return {ok:false,error:{code:'invalid_type',subject:[]}};}}
function bytes(input:Uint8Array|string):Buffer|string {if(typeof input==='string')return input;if(input instanceof Uint8Array)return Buffer.from(input);throw new TypeError();}
function support(s:Support):neg.Support {return {revisions:new Set(s.revisions),coreFields:new Set(s.coreFields),registry:{...s.registry},schemas:Object.fromEntries(Object.entries(s.schemas).map(([k,v])=>[k,tagged(v)]))};}
function artifact(kind:Artifact['kind'],result:any,mod:any):any {if(!result.ok)return result;const encoded=mod.canonicalBytes(result.v);if(!encoded.ok)return encoded;return {ok:true,v:{kind,value:plain(result.v.value),canonicalBytes:Buffer.from(encoded.v),contentDigest:kind==='federation'?null:mod.contentDigest(result.v)}};}
/** Decode canonical Blueprint bytes under optional tightened ceilings. */
export function decodeBlueprint(input:Uint8Array|string,options:DecodeOptions={}):Result<Blueprint>{return guarded(()=>artifact('blueprint',bp.decode(bytes(input),options.bounds as Record<string,unknown>|undefined),bp));}
/** Decode canonical Deployment bytes under optional tightened ceilings. */
export function decodeDeployment(input:Uint8Array|string,options:DecodeOptions={}):Result<Deployment>{return guarded(()=>artifact('deployment',dep.decode(bytes(input),options.bounds as Record<string,unknown>|undefined),dep));}
/** Decode a canonical federation TaskEnvelope. */
export function decodeFederationEnvelope(input:Uint8Array|string,options:DecodeOptions={}):Result<FederationEnvelope>{return guarded(()=>artifact('federation',fed.decode(bytes(input),options.bounds as Record<string,unknown>|undefined),fed));}
/** Encode an artifact view's value as canonical UTF-8 bytes. */
export function canonicalBytes(value:Artifact):Result<Uint8Array>{return guarded(()=>Buffer.from(canonical(value.value)));}
/** Negotiate revision, required fields, and extensions. */
export function negotiate(value:Blueprint|Deployment,options:Support):Result<Negotiated>{return guarded(()=>neg.negotiate(tagged(value.value),support(options)));}
/** Intersect three total bound sources and record every narrowing. */
export function intersect(options:Sources):Result<Intersection>{return guarded(()=>{const r=alg.intersect(options.blueprint as any,options.deployment as any,options.host as any,options.protectedClamp??'deny');return r.ok?{ok:true,v:{effective:r.v.effective,clamps:r.v.clamps.map(c=>({field:c.field,class:c.cls,unit:c.cls==='protected'?'ordinal':c.field==='max_cost'?'money':c.field==='max_elapsed_ms'?'millisecond':c.field==='max_tokens'?'token':'count',requested:jsonValue(c.requested),effective:jsonValue(c.effective),source:c.source,acknowledged:c.acknowledged}))}}:r;});}
/** Verify exact observed build identities against a Deployment. */
export function verifyCompatibility(value:Deployment,observed:Observed):Result<Evidence>{return guarded(()=>{
  const result=compat.verify({value:tagged(value.value)},observed as any);
  if(!result.ok)return result;
  const entries=value.value.build_identities as readonly {readonly digest:string}[];
  return {ok:true,v:{protocol_revision:value.value.protocol_revision,blueprint_digest:null,deployment_digest:null,effective_bounds:null,clamps:[],optional_extensions_retained:[],checks:entries.map((entry,index)=>({surface:'compatibility',subject:['build_identities',index],verified:true,detail:entry.digest})),not_verified:['tenancy','live_policy','authority','effect_ownership','execution','billing','evaluation_truth']}};
});}
/** Run the eight-stage import pass and return non-authorizing evidence. */
export function reconcile(blueprint:Blueprint,deployment:Deployment,options:Inputs):Result<Evidence>{return guarded(()=>{if(options.observations.now!==null&&dep.parseTimestamp(options.observations.now)===null)return {ok:false,e:"invalid_type"};return imports.reconcile({value:tagged(blueprint.value)},{value:tagged(deployment.value)},{...options,hostBounds:options.hostBounds as any,support:support(options.support),keys:options.keys.map(key=>({keyId:key.keyId,key:key.algorithm==='ed25519'?key.key:new Uint8Array()})),observations:options.observations as dep.Observations});});}
/** Return the 23 transport mapping rows as data. */
export function federationMapping():Result<readonly MappingRow[]>{return guarded(()=>rows.map(row=>({...row})));}
/** Verify a detached signature and return the verified attributes. */
export function verifySignature(entry:JsonValue,keys:readonly PublicKey[]):Result<SignedAttributes>{return guarded(()=>{const r=sig.verify(tagged(entry),keys.map(key=>({keyId:key.keyId,key:key.algorithm==='ed25519'?key.key:new Uint8Array()})));return r.ok?{ok:true,v:{...r.v,contentDigest:toTagged(r.v.contentDigest)}}:r;});}
/** Load and integrity-check a corpus from a path-to-bytes map. */
export function loadCorpus(files:ReadonlyMap<string,Uint8Array>,options:{readonly priorCensus?:boolean}={}):Result<Corpus>{return guarded(()=>{const r=(options.priorCensus?corpus.loadPriorCensus:corpus.load)(new Map([...files].map(([k,v])=>{if(!(v instanceof Uint8Array))throw new TypeError();return [k,Buffer.from(v)];})));if(!r.ok)return r;const handle={identity:r.v.identity,totalCases:r.v.caseIds.size};handles.set(handle,r.v);return {ok:true,v:handle};});}
/** Execute every loaded corpus case. */
export function runCorpus(value:Corpus):Result<readonly (readonly CaseResult[])[]>{return guarded(()=>runner.run(handles.get(value)));}
/** Build the unchanged aggregate report from a corpus run. */
export function buildReport(value:Corpus,results:readonly (readonly CaseResult[])[]):Result<Report>{return guarded(()=>{const r=report.toBytes(value.identity,results as any);return typeof r==='string'?JSON.parse(r):r;});}
/** Build canonical, identity-free per-case results from the implementation. */
export function buildResultsDocument(value:Corpus):Result<ResultsDocument>{return guarded(()=>resultsDocument(handles.get(value)!));}
