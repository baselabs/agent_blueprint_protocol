import { createInterface } from 'node:readline';
import { basename } from 'node:path';
import { readFileSync } from 'node:fs';
const mode=basename(process.argv[1],'.mjs');
const certified=['projection','unclosed'].includes(mode)?new Map(JSON.parse(readFileSync('spec/conformance/certified-results.json','utf8')).results.map(row=>[row.id,row.result])):null;
const requests=[];let hello=false;
const write=value=>process.stdout.write(JSON.stringify(value)+'\n');
const input=createInterface({input:process.stdin});
for await(const line of input){const row=JSON.parse(line);if(!hello){hello=true;if(mode==='early')process.exit(7);write(mode==='mismatch'?{...row,version:2}:row);}else requests.push(row);}
if(mode==='slow'){await new Promise(resolve=>setTimeout(resolve,2000));}
if(mode==='oversized'){process.stdout.write(' '.repeat(5_000_001)+'\n');}
else if(mode==='malformed')process.stdout.write('invalid json\n');
else for(let i=0;i<requests.length;i++){
  if(mode==='missing'&&i===requests.length-1)continue;
  const request=requests[i];
  const id=mode==='duplicate'&&i===1?requests[0].id:mode==='reordered'&&i===0?requests[1].id:request.id;
  const result=certified?{...certified.get(request.id),...(mode==='projection'&&i===0?{extra:true}:{})}:{verdict:'invalid',code:'invalid_type'};
  write(mode==='echo'?request:{id,result});
}
if(mode==='extra')write({id:'example-extra',result:{verdict:'invalid',code:'invalid_type'}});

if(mode==='unclosed'){process.stdout.end();setInterval(()=>{},1000);}
