import assert from 'node:assert/strict';
import * as api from '../../dist/verifier/index.js';
const lists = [];
for (const [name, count] of [['blueprintMembers',18], ['deploymentMembers',19], ['federationMembers',23]]) {
  assert.equal(typeof api[name], 'function', name);
  const result = api[name](1);
  assert.equal(result.ok, true);
  assert.equal(result.value.length, count);
  assert.deepEqual(result.value, [...result.value].sort());
  assert.equal(new Set(result.value).size, count);
  for (const revision of [-1,0,2,100]) assert.deepEqual(api[name](revision), {ok:false,error:{code:'protocol_revision_unsupported',subject:['protocol_revision']}});
  for (const revision of [null,true,false,1.5,'1',undefined,[],{},1n,NaN,Infinity]) assert.deepEqual(api[name](revision), {ok:false,error:{code:'invalid_type',subject:[]}});
  result.value.pop();
  assert.equal(api[name](1).value.length, count);
  lists.push(api[name](1).value);
}
console.log(JSON.stringify(lists));
