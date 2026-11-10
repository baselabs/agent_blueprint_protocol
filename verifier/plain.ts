import type { Value } from './value.ts';

export function tagged(value: unknown, depth = 0): Value {
  if (depth > 64) throw new TypeError('invalid_type');
  if (value === null) return {t:'null'};
  if (typeof value === 'string') return {t:'str', v:value};
  if (typeof value === 'boolean') return {t:'bool', v:value};
  if (typeof value === 'number' && Number.isFinite(value)) return {t:Number.isSafeInteger(value) ? 'int' : 'float', v:value};
  if (Array.isArray(value)) return {t:'arr',v:Array.from(value, x => tagged(x, depth+1))};
  if (value && typeof value === 'object' && [Object.prototype,null].includes(Object.getPrototypeOf(value))) {
    return {t:'obj',v:Object.entries(value).map(([k,v])=>[k,tagged(v,depth+1)])};
  }
  throw new TypeError('invalid_type');
}
export function plain(value: Value): any {
  if (value.t === 'null') return null;
  if (value.t === 'arr') return value.v.map(plain);
  if (value.t === 'obj') return Object.fromEntries(value.v.map(([k,v])=>[k,plain(v)]));
  return value.v;
}
export function jsonValue(value: unknown): any {
  if (value instanceof Set) return [...value].sort();
  if (value instanceof Uint8Array) return Buffer.from(value).toString('base64url');
  if (Array.isArray(value)) return value.map(jsonValue);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,jsonValue(v)]));
  return value;
}
