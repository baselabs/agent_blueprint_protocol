import { spawnSync } from 'node:child_process';
import { readFileSync,lstatSync } from 'node:fs';
import assert from 'node:assert/strict';
const git=args=>{const r=spawnSync('git',args,{maxBuffer:20_000_000});assert.equal(r.status,0);return r.stdout;};
const entries=git(['ls-files','--stage','-z']).toString().split('\0').filter(Boolean);
const lower=new Set();
for(const entry of entries){const [record,path]=entry.split('\t');const [mode,oid]=record.split(' ');assert.notEqual(mode,'120000','symlink: '+path);assert.ok(path.length<240,'long path: '+path);assert.ok(!lower.has(path.toLowerCase()),'case collision: '+path);lower.add(path.toLowerCase());for(const part of path.split('/')){assert.ok(!/[<>:"|?*]|[. ]$/.test(part),'invalid path: '+path);assert.ok(!/^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)/i.test(part),'reserved path: '+path);}assert.ok(lstatSync(path).isFile(),'not regular: '+path);if(process.argv.includes('--paths-only'))continue;const expected=git(['cat-file','blob',oid]);assert.ok(readFileSync(path).equals(expected),'checkout byte drift: '+path);}
console.log('checkout: '+entries.length+(process.argv.includes('--paths-only')?' platform-safe paths (byte comparison omitted)':' byte-identical, platform-safe paths'));
